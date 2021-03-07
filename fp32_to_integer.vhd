--------------------------------------------------
--converts floating point to signed integer (as it would be after converted by an AD)
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32
use work.single_prec_type.all;--defines floating point single precision fields and constants

---------------------------------------------------

entity fp32_to_integer is
generic	(N: natural);--number of bits in output
port(	fp_in:in std_logic_vector(31 downto 0);--floating point input
		output: out std_logic_vector(N-1 downto 0)-- output in range [-2^(N-1),+(2^(N-1)-1)]
);
end fp32_to_integer;

---------------------------------------------------

architecture behv of filter is

begin	

end behv;

---------------------------------------------------------------------------------------------
