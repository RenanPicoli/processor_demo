--------------------------------------------------
--converts floating point to signed integer (as it would be after converted by an AD)
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32
use work.single_precision_type.all;--float--defines floating point single precision fields and constants

---------------------------------------------------

entity fp32_to_integer is
generic	(N: natural);--number of bits in output
port(	fp_in:in std_logic_vector(31 downto 0);--floating point input
		output: out std_logic_vector(N-1 downto 0)-- valid input range [-1,1] maps to output range [-2^(N-1),+(2^(N-1)-1)]
);
end fp32_to_integer;

---------------------------------------------------

architecture behv of fp32_to_integer is

--signals of floating point input
signal sign: std_logic;--floating point sign bit, '1' means negative
signal mantissa: std_logic_vector(22 downto 0);--mantissa plus implicit '1'
signal extended_mantissa: std_logic_vector(23 downto 0);--mantissa plus implicit '1'
signal exponent: std_logic_vector(7 downto 0);--BIASED exponent
signal unbiased_exponent: std_logic_vector(7 downto 0);--exponent without bias

--signals of integer output
signal int_absolute: std_logic_vector(N-1 downto 0);
signal int_output: std_logic_vector(N-1 downto 0);

begin
	sign <= fp_in(31);
	exponent <= fp_in(30 downto 23);
	mantissa <= fp_in(22 downto 0);
	unbiased_exponent <= exponent - EXP_BIAS + (N);--also the number of shifts
	extended_mantissa <= '1' & mantissa;
	
	--int_absolute calculation
	--shifts extended_mantissa the number of exponent without bias (*2^(EXP-bias))

	
	--output write
	int_output <= ((not int_absolute)+'1')when sign='1' else int_absolute;

end behv;

---------------------------------------------------------------------------------------------
