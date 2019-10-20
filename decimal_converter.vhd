------------------------------------------------------------------------------------------------
--Circuit for conversion from single precision floating point to scientific notation (base 10)
--Reads the instruction address of processor,
--in specific (hardcoded 0xA) instruction, reads data_memory_output,
--then it performs the conversion and writes
--mantissa3[3...0],...,mantissa0[3...0],negative,exponent1[3...0],exponent0[3...0]
--
--mantissa3 = most significant digit of mantissa (left of decimal point)
--mantissa0 = least significant digit of mantissa (coefficient of 10e-3)
--negative = if set, means negative exponent
--exponent1 = most significant digit of mantissa
--exponent0 = least significant digit of mantissa
------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;--for type array4

entity decimal_converter is
port(	instruction_addr: in std_logic_vector(31 downto 0);
		data_memory_output: in std_logic_vector(31 downto 0);
		mantissa: out array4(0 to 3);--digits encoded in 4 bits 
		negative: out std_logic;
		exponent: out array4(0 to 1)--absolute value of the exponent
);
end entity;

architecture bhv of decimal_converter is
begin

end bhv;