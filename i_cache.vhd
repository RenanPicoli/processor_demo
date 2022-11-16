--------------------------------------------------
--instruction cache
--by Renan Picoli de Souza
--reads from DE2-115 embedded RAM
--input is 32 bit wide
--output is 32 bit instruction
--------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;--addition of std_logic_vector
use ieee.numeric_std.all;--to_integer, unsigned
use work.my_types.all;--array32
use ieee.math_real.all;--ceil and log2

entity i_cache is
	generic (REQUESTED_SIZE: natural; MEM_LATENCY: natural := 0);--REQUESTED_SIZE: user requested cache size, in 32 bit words; MEM_LATENCY: latency of program memory in MEM_CLK cycles
	port (
			req_ADDR: in std_logic_vector(7 downto 0);--address of requested instruction
			CLK: in std_logic;--processor clock for reading instructions, must run even if cache is not ready
			mem_IO: in std_logic_vector(31 downto 0);--data coming from embedded RAM for write
			mem_CLK: in std_logic;--clock for reading embedded RAM
			RST: in std_logic;--reset to prevent reading while sram is written (must be synchronous to mem_CLK)
			mem_ADDR: out std_logic_vector(7 downto 0);--address for write
			req_ready: out std_logic;--indicates that instruction already contains the requested instruction
			instruction: out std_logic_vector(31 downto 0)--fetched instruction
	);
end i_cache;

architecture structure of i_cache is

component sdp_ram
	generic (N: natural; L: natural);--N: data width in bits; L: address width in bits
	port (RST: in std_logic;
			WDAT: in std_logic_vector(N-1 downto 0);--data for write
			WCLK: in std_logic;--processor clock for writes
			WADDR: in std_logic_vector(L-1 downto 0);--address for write
			WREN: in std_logic;--enables software write
			RCLK: in std_logic;--processor clock for reading
			RADDR: in std_logic_vector(L-1 downto 0);--address for write
			RDAT: out std_logic_vector(N-1 downto 0)--oldest data
	);
end component;

constant D: natural := natural(ceil(log2(real(REQUESTED_SIZE))));--number of bits needed to select all cache locations
constant SIZE: natural := 2**D;--real cache size in words SHOULD BE A POWER OF 2 to prevent errors;

signal raddr: std_logic_vector(D-1 downto 0);--read address for the sdp_ram
signal waddr: std_logic_vector(D downto 0);--write address for the sdp_ram, 2 bit wider than raddr
														-- because bit 0 is used to select between upper and lower half
														-- and 1 bit (overflow) is used to detect full
														
type waddr_sr_t is array (natural range <>) of std_logic_vector(D downto 0);
signal waddr_sr: waddr_sr_t (MEM_LATENCY+1 downto 0);--waddr passes through a shift register to account for memory latency
signal waddr_delayed: std_logic_vector(D downto 0);--waddr delayed to account for memory latency

signal full: std_logic;--sdp is full
signal empty: std_logic;--sdp is empty
signal hit: std_logic;--cache hit
signal miss: std_logic;--cache miss
signal offset: std_logic_vector(7 downto D);--aka (current) page address
signal previous_offset: std_logic_vector(7 downto D);--offset during previous RCLK cycle
signal req_ADDR_reg: std_logic_vector(7 downto 0);

signal lower_WREN: std_logic;--WREN for the lower half cache
signal upper_WREN: std_logic;--WREN for the upper half cache

begin
	--cache for the lower half of instruction
	cache_lower: sdp_ram
		generic map (N => 32, L=> D)
		port map(RST => RST,
					WDAT	=> mem_IO,
					WCLK	=> mem_CLK,
					WADDR	=> waddr_delayed(D-1 downto 0),
					WREN	=> lower_WREN,
					RCLK	=> CLK,
					RADDR	=> raddr,
					RDAT	=> instruction(31 downto 0)
		);
		
--	--cache for the lower half of instruction
--	cache_lower: sdp_ram
--		generic map (N => 16, L=> D)
--		port map(RST => RST,
--					WDAT	=> mem_IO,
--					WCLK	=> mem_CLK,
--					WADDR	=> waddr(D downto 1),--bit 0 is used to select between upper and lower half
--					WREN	=> lower_WREN,
--					RCLK	=> CLK,
--					RADDR	=> raddr,
--					RDAT	=> instruction(15 downto 0)
--		);
		
	--cache for the upper half of instruction
--	cache_upper: sdp_ram
--		generic map (N => 16, L=> D)
--		port map(RST => RST,
--					WDAT	=> mem_IO,
--					WCLK	=> mem_CLK,
--					WADDR	=> waddr(D downto 1),--bit 0 is used to select between upper and lower half
--					WREN	=> upper_WREN,
--					RCLK	=> CLK,
--					RADDR	=> raddr,
--					RDAT	=> instruction(31 downto 16)
--		);
		
	--bit 0 is used to select between upper and lower half
	lower_WREN <= not full;
--	lower_WREN <= (not full) and (not waddr(0));--even address in SRAM refers to lower half
--	upper_WREN <= (not full) and waddr(0);--odd address in SRAM refers to upper half
		
	--cache write address generation
	process(mem_CLK,full,WADDR,miss,RST)
	begin
		if(miss='1' or RST='1')then
			waddr <= (others=>'0');
		elsif(rising_edge(mem_CLK) and full='0') then
			waddr <= waddr + '1';
		end if;
	end process;
	
	process(mem_CLK,WADDR,miss,RST)
	begin
		if(RST='1')then
			waddr_sr(MEM_LATENCY+1 downto 1) <= (others=>(others=>'0'));
		elsif(rising_edge(mem_CLK))then--this is to allow time for current requested address to be read in rising_edge
			waddr_sr(MEM_LATENCY+1 downto 1) <= waddr_sr(MEM_LATENCY downto 0);
		end if;
	end process;
	waddr_sr(0) <= waddr;--no latency added
	waddr_delayed <= waddr_sr(MEM_LATENCY);-- waddr was delayed MEM_LATENCY clocks (of mem_CLK)
	
	--cache read address generation
	raddr <= req_ADDR(D-1 downto 0) when req_ready='1' else req_ADDR_reg(D-1 downto 0);--not registered here, but raddr is "registered" inside sdp_ram
	
	offset <= req_ADDR_reg(7 downto D);--current offset (aka page address)
	
	mem_ADDR <= (7 downto 8 => '0') & offset & waddr(D-1 downto 0);--bit 0 must be included
	
	full <= '1' when waddr=('1' & (D-1 downto 0=>'0')) else '0';--next position to write exceeds ram limits
	
	--previous_offset generation
	--registers address for correct operation of flag req_ready
	process(CLK,offset,req_ready,RST)
	begin
		if(RST='1')then
			previous_offset <= (others=>'0');
			req_ADDR_reg <= (others=>'0');
		elsif(rising_edge(CLK)) then
			previous_offset <= offset;
			if(req_ready='1')then
				req_ADDR_reg <= req_ADDR;
			end if;
		end if;
	end process;
	
	hit <= '1' when offset=previous_offset else '0';
	miss <= not hit;
	
	process(RST,CLK,waddr,raddr,miss)
	begin
		if(miss='1' or (waddr_sr(MEM_LATENCY+1)(D downto 0) <= raddr(D-1 downto 0)))then
			req_ready<='0';
		elsif(rising_edge(CLK))then--this is to allow time for current requested address to be read in rising_edge
			req_ready <= '1';
		end if;
	end process;	
end structure;