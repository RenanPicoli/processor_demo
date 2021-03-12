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
generic	(N: natural;O: natural; S: natural);--N: number of bits in input, O in output; S: number of bits in shift
port(	input:in std_logic_vector(N-1 downto 0);--input vector that will be shifted
		shift:in std_logic_vector(S-1 downto 0);--signed integer: number of shifts to left (if positive)
		output: out std_logic_vector(O-1 downto 0)--
);
end var_shift;

---------------------------------------------------

architecture behv of var_shift is

type choices is array (-2**(S-1) to 2**(S-1)-1) of std_logic_vector(O-1 downto 0);
signal possible_outputs: choices;

begin
	--implements all possible shifts at once, let the user select the appropriate

	shifts: for i in -2**(S-1) to 2**(S-1)-1 generate
		possible_outputs(i) <= to_stdlogicvector(to_bitvector(input) srl ((N - O) - i))(O-1 downto 0);--shift right logic
	end generate;

	
	--output write
	output <= possible_outputs(to_integer(signed(shift)));

end behv;

---------------------------------------------------------------------------------------------
