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
generic	(N: natural; S: natural);--N: number of bits in output; S: number of bits in shift
port(	input:in std_logic_vector(N-1 downto 0);--input vector that will be shifted
		shift:in std_logic_vector(S-1 downto 0);--unsigned integer meaning number of shifts to left
		output: out std_logic_vector(N-1 downto 0)--
);
end var_shift;

---------------------------------------------------

architecture behv of var_shift is

signal possible_outputs: array (0 to 2**S-1) of std_logic_vector(N-1 downto 0);

begin
	--implements all possible shifts at once, let the user select the appropriate

	shifts: for i in 0 to 2**S-1 generate
		possible_outputs(i) <=  input rol to_integer(unsigned(shift));
	end generate;

	
	--output write
	int_output <= ((not int_absolute)+'1')when sign='1' else int_absolute;

end behv;

---------------------------------------------------------------------------------------------
