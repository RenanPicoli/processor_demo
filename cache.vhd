--------------------------------------------------
--cache for data or instruction
--by Renan Picoli de Souza
--reads from DE2-115 embedded RAM
--input is 32 bit wide
--output is 32 bit data
--------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;--addition of std_logic_vector
use ieee.numeric_std.all;--to_integer, unsigned
use work.my_types.all;--array32
use ieee.math_real.all;--ceil and log2

entity cache is
--REQUESTED_SIZE: user requested cache size, in 32 bit words;
--MEM_LATENCY: latency of program memory in MEM_CLK cycles
--MEM_WIDTH: data width of program memory in bits
	generic (REQUESTED_SIZE: natural; MEM_WIDTH: natural :=32; MEM_LATENCY: natural := 0; REQUESTED_FIFO_DEPTH: natural:= 4; REGISTER_ADDR: boolean);
	port (
			req_ADDR: in std_logic_vector(7 downto 0);--address of requested data
			req_rden: in std_logic;--read requested
			req_wren: in std_logic:='0';--write requested
			req_data_in: in std_logic_vector(31 downto 0):=(others=>'0');--data for write request
			CLK: in std_logic;--processor clock for reading/writing data, must run even if cache is not ready
			mem_I: in std_logic_vector(MEM_WIDTH-1 downto 0);--data coming from program memory
			mem_CLK: in std_logic;--clock for reading program memory
			RST: in std_logic;--reset to prevent reading while program memory is written (must be synchronous to mem_CLK)
			mem_ADDR: out std_logic_vector;--address for memory read/write
			mem_WREN: out std_logic:='0';
			req_ready: out std_logic;--indicates that data already contains the requested data
			mem_O: out std_logic_vector(MEM_WIDTH-1 downto 0);--data to be written in program memory
			data: buffer std_logic_vector(31 downto 0)--fetched data
	);
end cache;

architecture structure of cache is

component tdp_ram
	generic (N: natural; L: natural);--N: data width in bits; L: address width in bits
	port (CLK_A: in std_logic;
			WDAT_A: in std_logic_vector(N-1 downto 0);--data for write
			ADDR_A: in std_logic_vector(L-1 downto 0);--address for read/write
			WREN_A: in std_logic;--enables write on port A
			Q_A: out std_logic_vector(N-1 downto 0);
			CLK_B: in std_logic;
			WDAT_B: in std_logic_vector(N-1 downto 0);--data for write
			ADDR_B: in std_logic_vector(L-1 downto 0);--address for read/write
			WREN_B: in std_logic;--enables write on port B
			Q_B: out std_logic_vector(N-1 downto 0)
	);
end component;

component dc_fifo
	generic (N: natural; REQUESTED_FIFO_DEPTH: natural);--REQUESTED_FIFO_DEPTH does NOT need to be power of TWO
	port (
			DATA_IN: in std_logic_vector(N-1 downto 0);--for register write
			WCLK: in std_logic;--processor clock for writes
			RCLK: in std_logic;--processor clock for reading
			RST: in std_logic;--asynchronous reset
			WREN: in std_logic;--enables software write
			POP: in std_logic;--aka RDEN
			FULL: buffer std_logic;--'1' indicates that fifo is (almost) full
			EMPTY: buffer std_logic;--'1' indicates that fifo is (almost) empty
			OVF: out std_logic;--'1' indicates that fifo is overflowing (and dropping data)
			DATA_OUT: out std_logic_vector(N-1 downto 0)--oldest data
	);
end component;

constant W: natural := integer(ceil(log2(real(32)/real(MEM_WIDTH))));--2**W is the number of memory words to store one instruction
constant D: natural := natural(ceil(log2(real(REQUESTED_SIZE))));--number of bits needed to select all cache locations
constant SIZE: natural := 2**D;--real cache size in words SHOULD BE A POWER OF 2 to prevent errors;

signal raddr: std_logic_vector(D-1 downto 0);--read address for the tdp_ram
signal waddr: std_logic_vector(W+D downto 0);--write address for the tdp_ram, W+1 bit wider than raddr
														-- because W LSbit are used to select between subwords of instruction (when memory width is smaller than instruction width)
														-- and 1 bit (overflow) is used to detect full
signal mem_write_ADDR: std_logic_vector(W+D-1 downto 0);--write address coming from fifo
														
type waddr_sr_t is array (natural range <>) of std_logic_vector(W+D downto 0);
signal waddr_sr: waddr_sr_t (MEM_LATENCY+1 downto 0);--waddr passes through a shift register to account for memory latency
signal waddr_delayed: std_logic_vector(W+D downto 0);--waddr delayed to account for memory latency

signal full: std_logic;--tdp_ram is full
signal empty: std_logic;--tdp_ram is empty
signal hit: std_logic;--cache hit
signal miss: std_logic;--cache miss
signal offset: std_logic_vector(MEM_ADDR'length-1 downto D);--aka (current) page address
signal previous_offset: std_logic_vector(MEM_ADDR'length-1 downto D);--offset during previous RCLK cycle
signal req_ADDR_reg: std_logic_vector(7 downto 0);--address of current instruction/data a RDAT
signal req_ready_sr: std_logic_vector(1 downto 0);
signal previous_req_ready_sr: std_logic_vector(1 downto 0);--req_ready_sr from previous cycle

signal req_wren_ready: std_logic;-- so that cache is written only when ready
signal WREN: std_logic_vector(2**W-1 downto 0);--WREN for the subword caches
signal CLK_n: std_logic;--oposite polarity of processor clock, req_ADDR,req_wren are generated at positive edge of CLK, data must be ready before next rising edge

signal dc_fifo_empty:	std_logic;
signal dc_fifo_full:		std_logic;
signal dc_fifo_pop:		std_logic;
signal dc_fifo_ovf:		std_logic;
signal dc_fifo_data_out:std_logic_vector(32+D-1 downto 0);

signal word_idx: natural;--index of the word being written to program memory (0,1,...,2**W-1)

begin

	assert ((2**(ceil(log2(real(32)/real(MEM_WIDTH))))=real(32)/real(MEM_WIDTH)))
	report "Memory width must be the instruction width divided by a power of 2"
	severity error;
	
	CLK_n <= not CLK;
	
	word_i: for i in 0 to 2**W-1 generate
		storage: tdp_ram generic map (N => MEM_WIDTH, L=> D)
		port map(CLK_A	=> mem_CLK,
					WDAT_A=> mem_I,
					ADDR_A=> waddr_delayed(W+D-1 downto W),
					WREN_A=> WREN(i),
					Q_A	=> OPEN,
					CLK_B	=> CLK,
					WDAT_B=> req_data_in((i+1)*MEM_WIDTH-1 downto i*MEM_WIDTH),
					ADDR_B=> raddr,
					WREN_B=> req_wren_ready,
					Q_B	=> data((i+1)*MEM_WIDTH-1 downto i*MEM_WIDTH)
		);
		WREN(i) <= '1' when (full='0' and dc_fifo_empty='1' and waddr_delayed(W-1 downto 0)=i) else '0';
	end generate;
	req_wren_ready <= req_wren and req_ready;
	
	-- stores the writes made to cache
	fifo: dc_fifo	generic map (N=> D+32, REQUESTED_FIFO_DEPTH => REQUESTED_FIFO_DEPTH)
						port map(DATA_IN => raddr & req_data_in,
									RST => RST,
									WCLK => CLK,
									WREN => req_wren_ready,
									FULL => dc_fifo_full,
									EMPTY => dc_fifo_empty,
									OVF => dc_fifo_ovf,
									RCLK => mem_CLK,
									POP => dc_fifo_pop,
									DATA_OUT => dc_fifo_data_out);
									
	mem_write_ADDR <= dc_fifo_data_out(32+D-1 downto 32) & std_logic_vector(to_unsigned(word_idx,W)); 
	mem_O <= dc_fifo_data_out((word_idx+1)*MEM_WIDTH-1 downto word_idx*MEM_WIDTH);
	dc_fifo_pop <= '1' when ((dc_fifo_empty='0') and (word_idx=2**W-1) and full='1') else '0';
	process(RST,mem_CLK,dc_fifo_pop,word_idx)
	begin
		if(RST='1')then
			mem_WREN <= '0';
		elsif(rising_edge(mem_CLK))then
			if(dc_fifo_pop='1')then
				mem_WREN <= '1';
			elsif(word_idx=2**W-1 and dc_fifo_pop='0')then
				mem_WREN <= '0';
			end if;
		end if;
	end process;
	
	process(RST,mem_CLK,mem_WREN,dc_fifo_pop)
	begin
		if(RST='1')then
			word_idx <= 2**W-1;
		elsif(rising_edge(mem_CLK) and (mem_WREN='1' or dc_fifo_pop='1'))then
			if(word_idx /= 2**W-1)then
				word_idx <= word_idx + 1;
			elsif(word_idx = 2**W-1 and dc_fifo_empty='0')then
				word_idx <= 0;
			end if;
		end if;
	end process;
		
	registered_waddr: if REGISTER_ADDR generate--when req_ADDR is the NEXT address 
		--cache write address generation
		process(mem_CLK,WADDR,miss,dc_fifo_empty,RST)
		begin
			if(RST='1')then
				waddr <= (others=>'0');
			elsif(rising_edge(mem_CLK)) then
				if(miss='1')then
					waddr <= (others=>'0');
				elsif(waddr /= ('1' & (W+D-1 downto 0=>'0')) and dc_fifo_empty='1')then
					waddr <= waddr + '1';
				end if;
			end if;
		end process;
	end generate;
		
	unregistered_waddr: if not REGISTER_ADDR generate--when req_ADDR is the CURRENT address
		--cache write address generation
		process(mem_CLK,WADDR,miss,req_ready_sr,dc_fifo_empty,RST)
		begin
			if(RST='1')then
				waddr <= (others=>'0');
			elsif(rising_edge(mem_CLK)) then
				if(req_ready_sr="00" and miss='1')then--condition to start filling cache
					waddr <= (others=>'0');
				elsif(waddr /= ('1' & (W+D-1 downto 0=>'0')) and dc_fifo_empty='1')then
					waddr <= waddr + '1';
				end if;
			end if;
		end process;
	end generate;
	
	process(mem_CLK,WADDR,RST)
	begin
		if(RST='1')then
			waddr_sr(MEM_LATENCY+1 downto 1) <= (others=>(others=>'0'));
		elsif(rising_edge(mem_CLK))then--this is to allow time for current requested address to be read in rising_edge
			waddr_sr(MEM_LATENCY+1 downto 1) <= waddr_sr(MEM_LATENCY downto 0);
		end if;
	end process;
	waddr_sr(0) <= waddr;--no latency added
	waddr_delayed <= waddr_sr(MEM_LATENCY);-- waddr was delayed MEM_LATENCY clocks (of mem_CLK)
	
	registered_raddr: if REGISTER_ADDR generate--when req_ADDR is the NEXT address
		raddr <= req_ADDR(D-1 downto 0) when (req_ready='1') else req_ADDR_reg(D-1 downto 0);
	end generate;
	
	unregistered_raddr: if not REGISTER_ADDR generate--when req_ADDR is the CURRENT address
		raddr <= req_ADDR(D-1 downto 0);
	end generate;
	
	registered_offset: if REGISTER_ADDR generate--when req_ADDR is the NEXT address 
		offset <= (MEM_ADDR'length-1 downto 8 => '0') & req_ADDR_reg(7 downto D);--current offset (aka page address)
	end generate;
	
	unregistered_offset: if not REGISTER_ADDR generate--when req_ADDR is the CURRENT address 
		offset <= (MEM_ADDR'length-1 downto 8 => '0') & req_ADDR(7 downto D);--current offset (aka page address)
	end generate;
	
	mem_ADDR <= offset(MEM_ADDR'length-1-W downto D) & waddr(W+D-1 downto 0) when full='0' else --NOT delayed because this address will be used to read to RAM, bit 0 must be included
					offset(MEM_ADDR'length-1-W downto D) & mem_write_ADDR;
	full <= '1' when waddr_delayed=('1' & (W+D-1 downto 0=>'0')) else '0';--next position to write exceeds ram limits
	
	registered_previous_offset: if REGISTER_ADDR generate
		--previous_offset generation
		--registers address for correct operation of flag req_ready
		process(CLK,offset,req_ready,RST)
		begin
			if(RST='1')then
				previous_offset <= (others=>'0');
				req_ADDR_reg <= (others=>'0');
			elsif(rising_edge(CLK) and (req_rden='1' or req_wren='1')) then
				previous_offset <= offset;
				if(req_ready='1')then
					req_ADDR_reg <= req_ADDR;
				end if;
			end if;
		end process;
	end generate;
	
	unregistered_previous_offset: if not REGISTER_ADDR generate
		--previous_offset generation
		--registers address for correct operation of flag req_ready
		process(CLK,offset,req_ready,miss,RST)
		begin
			if(RST='1')then
				previous_offset <= (others=>'0');
				req_ADDR_reg <= (others=>'0');
			elsif(rising_edge(CLK) and (req_rden='1' or req_wren='1')) then
				if(miss='1') then
					previous_offset <= offset;
				end if;
				if(req_ready='1')then
					req_ADDR_reg <= req_ADDR;
				end if;
			end if;
		end process;
	end generate;
	
	--glitches may happen
	process(req_rden,req_wren,offset,previous_offset)
	begin
		if (req_wren='1' or req_rden='1') then
			if (offset=previous_offset) then
				hit <= '1';
			else
				hit <= '0';
			end if;
		else
			hit <= '1';
		end if;
	end process;
	miss <= not hit;--glitches may happen
	
	registered_ready: if REGISTER_ADDR generate--when req_ADDR is the NEXT address
		process(RST,CLK,waddr,raddr,miss,req_rden,req_wren,full)
		begin
--			if(RST='1' or dc_fifo_full='1' or (waddr_sr(MEM_LATENCY+1)(W+D downto W) <= raddr(D-1 downto 0)))then
			if(RST='1' or dc_fifo_full='1' or full='0')then
				req_ready <= '0';
			elsif(rising_edge(CLK) and (req_wren='1' or req_rden='1'))then--this is to allow time for current requested address to be read in rising_edge
				if(miss='1')then
					req_ready <= '0';
				else
					req_ready <= '1';
				end if;
			end if;
		end process;
	end generate;
	
	unregistered_ready: if not REGISTER_ADDR generate--when req_ADDR is the the CURRENT address	
		process(RST,CLK,waddr,raddr,miss,hit,req_rden,req_wren,full)
		begin
			if(RST='1')then
				req_ready_sr <= "00";
				previous_req_ready_sr <= "00";
			elsif(rising_edge(CLK))then--this is to allow time for current requested address to be read in rising_edge
				previous_req_ready_sr <= req_ready_sr;
				if(req_ready_sr="00" and (req_wren='1' or req_rden='1') and miss='1')then
					req_ready_sr <= "01";
				elsif(req_ready_sr="00" and req_rden='1' and hit='1')then
					req_ready_sr <= "11";
				elsif(req_ready_sr="01" and full='1')then--recovered from a miss
					req_ready_sr <= "11";
				elsif(req_ready_sr="11")then
					req_ready_sr <= "10";
				elsif(req_ready_sr="10")then
					req_ready_sr <= "00";
				end if;
			end if;
		end process;
--		req_ready <= '1' when (req_ready_sr="00" or req_ready_sr="10") else '0';
		req_ready_p: process(req_ready_sr,RST,CLK,req_rden,req_wren,full,miss)
		begin
			if(RST='1')then--req_ready_sr="01" or req_ready_sr="11"
				req_ready <= '1';
			elsif(falling_edge(CLK))then
				if(req_ready_sr="00" and (((req_rden='1' or req_wren='1') and miss='1') or (req_rden='1' and hit='1')))then
					req_ready <= '0';
				elsif((req_ready_sr="11" and full='1') )then
					req_ready <= '1';
				end if;
			end if;
		end process;
	end generate;
end structure;