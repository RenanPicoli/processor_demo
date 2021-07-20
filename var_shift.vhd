--------------------------------------------------
--performs variable shift left according to one of its inputs
--also works as integer multiplier by powers of 2
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer

---------------------------------------------------

entity var_shift is
generic	(N: natural; O: natural; S: natural);--N: number of bits in input, O in output; S: number of bits in shift
port(	input:in std_logic_vector(N-1 downto 0);--input vector that will be shifted
		shift:in std_logic_vector(S-1 downto 0);--signed integer: number of shifts to left (if positive)
		overflow: out std_logic;-- '1' if there are ones that were dropped in the output
		output: out std_logic_vector(O-1 downto 0)--
);
end var_shift;

---------------------------------------------------

architecture behv of var_shift is

--the first index of this array is the shift amount (to left)
--second index comprises all possible positions MSB of input could be shifted to
type choices is array (-2**(S-1) to 2**(S-1)-1) of std_logic_vector((O+2**(S-1)-2) downto 0);
signal possible_outputs: choices;

signal output_dropped_bits: std_logic_vector((O+2**(S-1)-2) downto O);
signal tmp: std_logic_vector((O+2**(S-1)-2) downto O);--to generate the OR of all output_dropped_bits bits

signal logic_extended_input: std_logic_vector((O+2**(S-1)-2) downto 0);

begin
	logic_extended_input <= ((O+2**(S-1)-2) downto N =>'0') & input;

	--implements all possible shifts at once, let the user select the appropriate
	
	shifts: for i in -2**(S-1) to 2**(S-1)-1 generate
		possible_outputs(i) <= to_stdlogicvector(to_bitvector(logic_extended_input) srl ((N - O) - i));--shift right logic
	end generate;

	
	--output write
	output <= possible_outputs(to_integer(signed(shift)))(O-1 downto 0);
	output_dropped_bits <= possible_outputs(to_integer(signed(shift)))((O+2**(S-1)-2) downto O);--for debugging ease

	--all output_dropped_bits bits ORed together
	tmp(O) <= output_dropped_bits(O);
	ovf: for i in (O+2**(S-1)-2) downto O+1 generate
		tmp(i) <= tmp(i-1) or output_dropped_bits(i);
	end generate;
	overflow <= tmp(O+2**(S-1)-2);

end behv;

---------------------------------------------------------------------------------------------
