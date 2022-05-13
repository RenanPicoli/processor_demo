--------------------------------------------------
--instruction cache
--by Renan Picoli de Souza
--reads from DE2-115 onboard SRAM
--input is 16 bit wide
--output is 32 bit instruction
--------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;--addition of std_logic_vector
use ieee.numeric_std.all;--to_integer, unsigned
use work.my_types.all;--array32
use ieee.math_real.all;--ceil and log2

entity I_cache is
	generic (REQUESTED_SIZE: natural);--user requested cache size, in 32 bit words
	port (
			req_ADDR: in std_logic_vector(7 downto 0);--address of requested instruction
			CLK: in std_logic;--processor clock for reading instructions
			sram_IO: in std_logic_vector(15 downto 0);--data coming from SRAM for write
			sram_CLK: in std_logic;--clock for reading SRAM
			RST: in std_logic;--reset to prevent reading while sram is written (must be synchronous to sram_CLK)
			sram_ADDR: out std_logic_vector(19 downto 0);--address for write
			req_ready: out std_logic;--indicates that instruction already contains the requested instruction
			instruction: out std_logic_vector(31 downto 0)--fetched instruction
	);
end I_cache;

architecture structure of I_cache is

component sdp_ram
	generic (N: natural; L: natural);--N: data width in bits; L: address width in bits
	port (
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
signal waddr: std_logic_vector(D downto 0);--write address for the sdp_ram, 1 bit wider than raddr
														-- because bit 0 is used to select between upper and lower half
signal full: std_logic;--sdp is full
signal empty: std_logic;--sdp is empty
signal hit: std_logic;--cache hit
signal miss: std_logic;--cache miss
signal offset: std_logic_vector(7 downto D);--aka (current) page address
signal previous_offset: std_logic_vector(7 downto D);--offset during previous RCLK cycle

signal lower_WREN: std_logic;--WREN for the lower half cache
signal upper_WREN: std_logic;--WREN for the upper half cache

begin
	--cache for the lower half of instruction
	cache_lower: sdp_ram
		generic map (N => 16, L=> D)
		port map(
					WDAT	=> sram_IO,
					WCLK	=> sram_CLK,
					WADDR	=> waddr(D downto 1),--bit 0 is used to select between upper and lower half
					WREN	=> lower_WREN,
					RCLK	=> CLK,
					RADDR	=> raddr,
					RDAT	=> instruction(15 downto 0)
		);
		
	--cache for the upper half of instruction
	cache_upper: sdp_ram
		generic map (N => 16, L=> 4)
		port map(
					WDAT	=> sram_IO,
					WCLK	=> sram_CLK,
					WADDR	=> waddr(D downto 1),--bit 0 is used to select between upper and lower half
					WREN	=> upper_WREN,
					RCLK	=> CLK,
					RADDR	=> raddr,
					RDAT	=> instruction(31 downto 16)
		);
		
	--bit 0 is used to select between upper and lower half
	lower_WREN <= (not full) and (not waddr(0));--even address in SRAM refers to lower half
	upper_WREN <= (not full) and waddr(0);--odd address in SRAM refers to upper half
		
	--cache write address generation
	process(sram_CLK,full,WADDR,miss,RST)
	begin
		if(miss='1' or RST='1')then
			waddr <= (others=>'0');
		elsif(rising_edge(sram_CLK) and full='0') then
			waddr <= waddr + '1';
		end if;
	end process;
	
	--cache read address generation
	raddr <= req_ADDR(D-1 downto 0);
	
	offset <= req_ADDR(7 downto D);--current offset (aka page address)
	
	sram_ADDR <= (19 downto 9 => '0')& offset & waddr;--bit 0 must be included
	
	full <= '1' when waddr=(D downto 0=>'1') else '0';
	
	--previous_offset generation
	process(CLK,offset)
	begin
		if(rising_edge(CLK)) then
			previous_offset <= offset;
		end if;
	end process;
	
	hit <= '1' when offset=previous_offset else '0';
	miss <= not hit;
	
	req_ready <= '1' when waddr>raddr else '0';	
end structure;