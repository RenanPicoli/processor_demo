--------------------------------------------------
--testbench for converts floating point to signed integer converter
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.all;--includes fp32_to_integer
---------------------------------------------------

entity tb_fp32_to_integer is
end tb_fp32_to_integer;

---------------------------------------------------

architecture behv of tb_fp32_to_integer is

constant N: natural:=16;
signal fp_in: std_logic_vector(31 downto 0);--input: fp32
signal output: std_logic_vector(N-1 downto 0);--output: signed integer N bits, 2's complement
signal reconstructed_float: real;--what dac output would be (as a fraction of maximum output)

begin
	
	dut: entity work.fp32_to_integer
	generic map (N => N)
	port map(fp_in => fp_in,
				output => output);
				
	fp_in <= x"BF80_0000",-- -1.0,
				x"3F80_0000" after 1 us,-- +1.0
				x"3F00_0000" after 2 us,-- +0.5
				x"3F7F_FE00" after 3 us,-- 0.999969482421875=1-(2^(-15))
				x"0000_0000" after 4 us,-- +0,
				x"8000_0000" after 5 us,-- -0
				x"3800_0000" after 6 us,-- 0.000030517578125 = 2^(-15)
				x"B800_0000" after 7 us,-- -0.000030517578125 = -2^(-15)
				x"0000_0001" after 8 us,-- 1.40129846432481707092372958329E-45
				x"8000_0001" after 9 us,-- -1.40129846432481707092372958329E-45
				x"C000_0000" after 10 us,-- -2.0
				x"4180_0000" after 11 us,-- 16.0
				x"C180_0000" after 12 us,-- -16.0
            x"3FC0_0000" after 13 us,-- 1.5
            x"BFC0_0000" after 14 us,-- -1.5
            x"3F47_AE14" after 15 us,-- 0.78
            x"BF47_AE14" after 16 us;-- -0.78
				
	reconstructed_float <= real(to_integer(signed(output)))/real(2**(N-1));

end behv;

---------------------------------------------------------------------------------------------
