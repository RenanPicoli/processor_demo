--------------------------------------------------
--converts floating point to signed integer (as it would be after converted by an AD)
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.single_precision_type.all;--defines floating point single precision fields and constants

---------------------------------------------------

entity fp32_to_integer is
generic	(N: natural);--number of bits in output
port(	fp_in:in std_logic_vector(31 downto 0);--floating point input
		output: out std_logic_vector(N-1 downto 0)-- valid input range [-1,1] maps to output range [-2^(N-1),+(2^(N-1)-1)]
);
end fp32_to_integer;

---------------------------------------------------

architecture behv of fp32_to_integer is

component var_shift
generic	(N: natural; O: natural; S: natural);--N: number of bits in input, O in output; S: number of bits in shift
port(	input:in std_logic_vector(N-1 downto 0);--input vector that will be shifted
		shift:in std_logic_vector(S-1 downto 0);--unsigned integer meaning number of shifts to left
		overflow: out std_logic;-- '1' if there are ones that were dropped in the output
		output: out std_logic_vector(O-1 downto 0)--
);
end component;

--signals of floating point input
signal sign: std_logic;--floating point sign bit, '1' means negative
signal mantissa: std_logic_vector(22 downto 0);--mantissa plus implicit '1'
signal extended_mantissa: std_logic_vector(23 downto 0);--mantissa plus implicit '1'
signal exponent: std_logic_vector(7 downto 0);--BIASED exponent
signal unbiased_exponent: std_logic_vector(7 downto 0);--exponent without bias

--signals of integer output
signal shifted_ext_mantissa: std_logic_vector(N-1 downto 0);
signal int_absolute: std_logic_vector(N-1 downto 0);
signal int_output: std_logic_vector(N-1 downto 0);
signal overflow: std_logic;

begin
	sign <= fp_in(31);
	exponent <= fp_in(30 downto 23);
	mantissa <= fp_in(22 downto 0);
	unbiased_exponent <= exponent - EXP_BIAS;
	extended_mantissa <= '1' & mantissa;
	
	--int_absolute calculation
	--shifts extended_mantissa the number of exponent without bias (*2^(EXP-bias))
	shift: var_shift
	generic map (N => 24, O=> N, S => 8)
	port map (input => extended_mantissa,
				 shift => unbiased_exponent,
				 overflow => overflow,
				 output => shifted_ext_mantissa);
	
	--output write
	int_absolute <= shifted_ext_mantissa(N-1 downto 0);
	process(int_absolute,sign,overflow)
	begin
		if(overflow='0') then
			if(int_absolute=x"8000" and sign='0')then-- this means output would be +1.0, which is not allowed
				int_output <= x"7FFF";
			else-- int_absolute with it's sign form a representable integer
				if (sign='1') then
					int_output <= ((not int_absolute)+'1');
				else-- sign='0'
					int_output <= int_absolute;
				end if;
			end if;
		else-- overflow='1'
			if(sign='1')then--DAC will saturate at (-1)*Vref
				int_output <= x"8000";
			else--DAC will saturate at (+1)*Vref
				int_output <= x"7FFF";
			end if;
		end if;
	end process;
	output <= int_output;

end behv;
