--------------------------------------------------
--simple dual port ram
--by Renan Picoli de Souza
--32 bit data
--------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;--addition of std_logic_vector
use ieee.numeric_std.all;--to_integer, unsigned
use work.my_types.all;--array32

entity sdp_ram is
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
end sdp_ram;

architecture structure of sdp_ram is
type memory is array (0 to 2**L-1) of std_logic_vector(N-1 downto 0);
signal ram: memory;

signal RADDR_reg : std_logic_vector(L-1 downto 0);

begin
	--write
	process(RST,WDAT,WCLK,WREN,WADDR)
	begin
--		if(RST='1')then
--			ram <= (others=>(others=>'0'));
--		elsif(rising_edge(WCLK)) then
		if(rising_edge(WCLK)) then
			if (WREN='1') then
				ram(to_integer(unsigned(WADDR))) <= WDAT;
			end if;
		end if;
	end process;
	
	--reading
	process(RCLK,RADDR)
	begin
--		if(RST='1')then
--			RADDR_reg <= (others=>'0');
--		elsif (rising_edge(RCLK)) then
		if (rising_edge(RCLK)) then
			--CDC, but there is no metastability if setup/hold are not violated
			--necessary that RCLK/WCLK be a rational number for timing analysis
--			RADDR_reg <= RADDR;
			RDAT <= ram(to_integer(unsigned(RADDR)));
		end if;
	end process;
--			RDAT <= ram(to_integer(unsigned(RADDR_reg)));
end structure;