-------------------------------------------------------------
--microprocessor setup for demonstration
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;

---------------------------------------------------

entity processor_demo is
port (CLK_IN: in std_logic;--50MHz input
		rst: in std_logic;
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end entity;

architecture setup of processor_demo is

component decimal_converter --NOTE: it needs 24+3 clock cycles to perform continuous conversion
port(	instruction_addr: in std_logic_vector(31 downto 0);
		data_memory_output: in std_logic_vector(31 downto 0);
		mantissa: out array4(0 to 7);--digits encoded in 4 bits 
		en_7seg: out std_logic;--enables the 7 seg display
--		exponent: out array4(0 to 1);--absolute value of the exponent
		
		--signals for the downloaded bcd converter
		clk		:	IN		STD_LOGIC;											--system clock
		reset_n	:	IN		STD_LOGIC;											--active low asynchronus reset
		ena		:	IN		STD_LOGIC;											--latches in new binary number and starts conversion
		busy		:	OUT	STD_LOGIC											--indicates conversion in progress
);
end component;

component controller
port(	mantissa: in array4(0 to 7);--digits encoded in 4 bits 
		en_7seg: in std_logic;--enables the 7 seg display
--		exponent: in array4(0 to 1);--absolute value of the exponent
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end component;

component microprocessor
port (CLK: in std_logic;
		rst: in std_logic;
		data_memory_output: buffer std_logic_vector(31 downto 0);
		instruction_addr: out std_logic_vector (31 downto 0)--AKA read address
);
end component;

signal data_memory_output: std_logic_vector(31 downto 0);--number
signal instruction_addr: std_logic_vector(31 downto 0);
signal mantissa: array4(0 to 7);--digits encoded in 4 bits 
signal exponent: array4(0 to 1);--absolute value of the exponent

signal busy: std_logic;
signal en_7seg: std_logic;

signal CLK: std_logic := '0';
signal count: std_logic_vector(29 downto 0) := (others=>'0');

	begin
	
	processor: microprocessor port map (
		CLK => CLK,
		rst => rst,
		data_memory_output => data_memory_output,
		instruction_addr => instruction_addr
	);

	converter: decimal_converter port map(
		instruction_addr => instruction_addr,
		data_memory_output=>data_memory_output,
		mantissa => mantissa,
		en_7seg => en_7seg,
--		exponent => exponent,
		
		--signals for the downloaded bcd converter
		clk		=> CLK,					--system clock
		reset_n	=> not rst,				--active low asynchronus reset
		ena		=> '1',					--latches in new binary number and starts conversion
		busy		=> busy					--indicates conversion in progress
	);
	
	controller_7seg: controller port map(
		mantissa => mantissa,--digits encoded in 4 bits 
		en_7seg => en_7seg,
--		exponent => exponent,--absolute value of the exponent
		segments => segments--signals to control 8 displays of 7 segments
	);

	--produces 1Hz clock from 50MHz input
	prescaler: process(CLK_IN,CLK,count)
	begin
		if(CLK_IN'event and CLK_IN='1') then
--			count <= count + 1;
			if (count = 25000000) then
				CLK <= not CLK;
				count <= (others => '0');
			else
				CLK <= CLK;
				count <= count + 1;
			end if;
		end if;

	end process;
end setup;