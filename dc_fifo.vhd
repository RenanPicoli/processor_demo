--------------------------------------------------
--dual clock fifo
--by Renan Picoli de Souza
--8 stages fifo
--32 bit data
--based on the code available at:
-- https://www.ece.ucdavis.edu/~astill/dcfifo.html
--TO-DO implement validity bit
--TO-DO implement IRQ if tries to read from empty fifo
--------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;--addition of std_logic_vector
use ieee.numeric_std.all;--to_integer, unsigned
use work.my_types.all;--array32, array_of_std_logic_vector
use ieee.math_real.all;--ceil and log2

entity dc_fifo is
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
end dc_fifo;


architecture structure of dc_fifo is

	component sync_chain
		generic (N: natural;--bus width in bits
					L: natural);--number of registers in the chain
		port (
				data_in: in std_logic_vector(N-1 downto 0);--data generated at another clock domain
				CLK: in std_logic;--clock of new clock domain
				RST: in std_logic;--asynchronous reset
				data_out: out std_logic_vector(N-1 downto 0)--data synchronized in CLK domain
		);
	end component;
	
	--generic mux
	component mux
		generic(N_BITS_SEL: natural);--number of bits in sel port
		port(	A: in array_of_std_logic_vector;--user must ensure correct sizes
				sel: in std_logic_vector(N_BITS_SEL-1 downto 0);--user must ensure correct sizes
				Q: out std_logic_vector--user must ensure correct sizes
				);
	end component;

constant log2_FIFO_DEPTH: natural := natural(ceil(log2(real(REQUESTED_FIFO_DEPTH))));--number of bits needed to select all fifo locations
constant FIFO_DEPTH: natural := 2**log2_FIFO_DEPTH;--real fifo depth SHOULD BE A POWER OF 2 to prevent errors;

--pop: tells the fifo that data at head was read and can be discarded
--signal head: std_logic_vector(3 downto 0);--points to the position where oldest data should be read, MSB is a overflow bit
--type fifo_word_t is std_logic_vector(N-1 downto 0);
type fifo_t is array (natural range <>) of std_logic_vector(N-1 downto 0);
signal fifo: fifo_t(0 to FIFO_DEPTH-1);
--signal fifo: array_of_std_logic_vector(0 to FIFO_DEPTH-1)(N-1 downto 0);
--signal difference: std_logic_vector(31 downto 0);-- writes - readings
signal write_addr: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- NEXT position to write on
signal read_addr: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- CURRENT position read
signal write_addr_gray: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- write pointer gray coded
signal read_addr_gray: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- read pointer gray coded
signal rd_write_addr: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- write address synchronized to read clock domain
signal wr_read_addr: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- read address synchronized to write clock domain
signal rd_write_addr_gray: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- write address gray coded synchronized to read clock domain
signal wr_read_addr_gray: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- read address gray coded synchronized to write clock domain
signal temp_adder_out: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);--used to determine if fifo is full
signal async_full: std_logic;

constant reserve: std_logic_vector(log2_FIFO_DEPTH-1 downto 0) := (others=>'0');

begin

	--write pointer
	process(RST,WCLK,WREN,FULL)
	begin
		if(RST='1') then
			write_addr <= (others=>'0');
			--SOFTWARE MUST CHECK the (almost) FULL flag before writing
		elsif (rising_edge(WCLK) and WREN='1') then-- and FULL='0') then		
			write_addr <= write_addr + '1';
		end if;
	end process;
	
	--read pointer
	process(RST,RCLK,POP,EMPTY)
	begin
		if(RST='1') then
			read_addr <= (others=>'1');--read_addr = -1, goes to 0 at first reading
			--SOFTWARE MUST CHECK the (almost) EMPTY flag before reading
		elsif (rising_edge(RCLK) and POP='1') then-- and EMPTY='0') then		
			read_addr <= read_addr + '1';
		end if;
	end process;
	
--	difference <= c_writes - c_readings - 1;
	write_addr_gray <= write_addr xor std_logic_vector(unsigned(write_addr) sll 1);
	read_addr_gray  <= read_addr xor std_logic_vector(unsigned(read_addr) sll 1);

	-- converting from gray code to binary
	wr_read_addr(log2_FIFO_DEPTH-1) <= wr_read_addr_gray(log2_FIFO_DEPTH-1);
	wr_gray_to_bin: for i in 0 to log2_FIFO_DEPTH-2 generate
		wr_read_addr(i) <= wr_read_addr(i+1) xor wr_read_addr_gray(i);
	end generate wr_gray_to_bin;

	-- converting from gray code to binary
	rd_write_addr(log2_FIFO_DEPTH-1) <= rd_write_addr_gray(log2_FIFO_DEPTH-1);
	rd_gray_to_bin: for i in 0 to log2_FIFO_DEPTH-2 generate
		rd_write_addr(i) <= rd_write_addr(i+1) xor rd_write_addr_gray(i);
	end generate rd_gray_to_bin;
	
	-- synchronizes write_addr to rising_edge of RCLK, because:
	-- write_addr is generated at WCLK domain
	sync_chain_wr_addr: sync_chain
		generic map (N => log2_FIFO_DEPTH,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => write_addr_gray,--data generated at another clock domain
				CLK => RCLK,--clock of new clock domain
				RST => RST,--asynchronous reset
				data_out => rd_write_addr_gray--data synchronized in CLK domain
		);
		
	-- synchronizes read_addr to rising_edge of WCLK, because:
	-- write_addr is generated at WCLK domain
	sync_chain_rd_addr: sync_chain
		generic map (N => log2_FIFO_DEPTH,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => read_addr_gray,--data generated at another clock domain
				CLK => RCLK,--clock of new clock domain
				RST => RST,--asynchronous reset
				data_out => wr_read_addr_gray--data synchronized in CLK domain
		);	
	
	--head(3) indicates overflow
--	process(RST,difference)
--	begin
--		if (RST='1') then
--			head <= (others=>'1');--if RST then (head = -1)
--		else
--			head(i) <= difference;
--		end if;
--	end process;
	
	--shift register writes
--	process(RST,DATA_IN,WCLK,POP,WREN)
--	begin
--		if(RST='1')then
--			--reset fifo
--			fifo <= (others=>(others=>'0'));
--		elsif(rising_edge(WCLK) and WREN='1') then--rising edge to detect pop assertion (command to shift data) or WREN (async load)
--			fifo <= DATA_IN & fifo(0 to 6);
--		end if;
--	end process;
	process(RST,DATA_IN,WCLK,POP,WREN)
	begin
		if(RST='1')then
			--reset fifo
			fifo <= (others=>(others=>'0'));
		elsif(rising_edge(WCLK) and WREN='1') then--rising edge to detect pop assertion (command to shift data) or WREN (async load)
			fifo(to_integer(unsigned(write_addr))) <= DATA_IN;
		end if;
	end process;
	
	--data_out assertion	
--	DATA_OUT <= fifo(to_integer(unsigned(head(2 downto 0))));
--	process(RST,RCLK,POP)
--	begin
--		if(RST='1') then
--			DATA_OUT <= (others => '0');
--		elsif (rising_edge(RCLK) and POP='1') then
--			DATA_OUT <= fifo(to_integer(unsigned(read_addr)));
--		end if;
--	end process;

	DATA_OUT <= fifo(to_integer(unsigned(read_addr)));
	--using theses muxes only to make a better view in RTL netlist viewer
--	data_out_mux: mux
--					generic map (N_BITS_SEL => log2_FIFO_DEPTH)
--					port map(A => fifo,
--								sel => read_addr,
--								Q => DATA_OUT);
	
--	process (RST,head)
--	begin
--		if(RST='1' or head="1111")then
--			FULL <= '0';
--		elsif (head(3)='1') then
--			FULL <= '1';
--		end if;
--	end process;

   -- Reserve Logic Calculation, if the MSB is 1, hold.
   -- Accordingly assign the wr request output and async full
   temp_adder_out <= rd_write_addr - read_addr + reserve;
   async_full <= temp_adder_out(log2_FIFO_DEPTH-1);
	FULL <= async_full;
	
--	EMPTY		<= '1' when (head="0000" and c_writes=x"00000000") else '0';
	EMPTY		<= '1' when (read_addr + 1 = rd_write_addr) else '0';--next position to read is the next to write (contains invalid data)
--	OVF		<= '1' when (head(3)='1') and (head(2 downto 0)/="000") else '0';
	
end structure;