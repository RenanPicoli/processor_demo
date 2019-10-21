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
port (CLK: in std_logic;
		rst: in std_logic;
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end entity;

architecture setup of processor_demo is
component decimal_converter
port(	instruction_addr: in std_logic_vector(31 downto 0);
		data_memory_output: in std_logic_vector(31 downto 0);
		mantissa: out array4(0 to 3);--digits encoded in 4 bits 
		negative: out std_logic;
		exponent: out array4(0 to 1)--absolute value of the exponent
);
end component;

component controller
port(	mantissa: in array4(0 to 3);--digits encoded in 4 bits 
		negative: in std_logic;
		exponent: in array4(0 to 1);--absolute value of the exponent
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
signal mantissa: array4(0 to 3);--digits encoded in 4 bits 
signal negative: std_logic;
signal exponent: array4(0 to 1);--absolute value of the exponent

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
		negative => negative,
		exponent => exponent
	);
	
	controller_7seg: controller port map(
		mantissa => mantissa,--digits encoded in 4 bits 
		negative => negative,
		exponent => exponent,--absolute value of the exponent
		segments => segments--signals to control 8 displays of 7 segments
	);

end setup;