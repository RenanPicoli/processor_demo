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

use work.my_types.all;--for type array4, array7

entity controller is
port(	mantissa: in array4(0 to 7);--digits encoded in 4 bits 
		en_7seg: in std_logic;--enables the 7 seg display
--		exponent: in array4(0 to 1);--absolute value of the exponent
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end entity;

architecture bhv of controller is
	begin
		
		segments(0) <=	not code_for_7seg(to_integer(unsigned(mantissa(0)))) when en_7seg = '1' else "1111111";
		segments(1) <=	not code_for_7seg(to_integer(unsigned(mantissa(1)))) when en_7seg = '1' else "1111111";
		segments(2) <=	not code_for_7seg(to_integer(unsigned(mantissa(2)))) when en_7seg = '1' else "1111111";
		segments(3) <=	not code_for_7seg(to_integer(unsigned(mantissa(3)))) when en_7seg = '1' else "1111111";
		segments(4) <=	not code_for_7seg(to_integer(unsigned(mantissa(4)))) when en_7seg = '1' else "1111111";
		segments(5) <=	not code_for_7seg(to_integer(unsigned(mantissa(5)))) when en_7seg = '1' else "1111111";
		segments(6) <=	not code_for_7seg(to_integer(unsigned(mantissa(6)))) when en_7seg = '1' else "1111111";
		segments(7) <= not code_for_7seg(to_integer(unsigned(mantissa(7)))) when en_7seg = '1' else "1111111";
		
end bhv;