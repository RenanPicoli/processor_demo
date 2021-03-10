--------------------------------------------------
--testbench for converts floating point to signed integer converter
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.all;--includes fp32_to_integer
use work.my_types.all;--array32
use work.single_precision_type.all;--float--defines floating point single precision fields and constants

---------------------------------------------------

entity tb_fp32_to_integer is
end tb_fp32_to_integer;

---------------------------------------------------

architecture behv of tb_fp32_to_integer is

constant N: natural:=16;
signal fp_in: std_logic_vector(31 downto 0);--input: fp32
signal output: std_logic_vector(N-1 downto 0);--output: signed integer N bits, 2's complement

begin
	
	dut: entity work.fp32_to_integer
	generic map (N => N)
	port map(fp_in => fp_in,
				output => output);
				
	fp_in <= x"3F80_0000", x"BF80_0000" after 1 us;-- 1.0, -1.0
end behv;

---------------------------------------------------------------------------------------------