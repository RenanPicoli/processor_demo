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
	port (
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

begin
	--write
	process(WDAT,WCLK,WREN,WADDR)
	begin
		if(rising_edge(WCLK)) then
			if (WREN='1') then
				ram(to_integer(unsigned(WADDR))) <= WDAT;
			end if;
		end if;
	end process;
	
	--reading
	process(RCLK,RADDR)
	begin
		if (rising_edge(RCLK)) then
			--CDC, but there is no metastability if setup/hold are not violated
			--necessary that RCLK/WCLK be a rational number for timing analysis
			RDAT <= ram(to_integer(unsigned(RADDR)));
		end if;
	end process;
end structure;