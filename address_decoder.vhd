--------------------------------------------------
--address_decoder:
--routes rden and wren signals based on given address
--implements a memory map or a register map
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity address_decoder is
--N: address width in bits
--boundaries: upper limits of each end (except the last, which is 2**N-1)
generic	(N: natural; boundaries: array32);
port(	ADDR: in std_logic_vector(N-1 downto 0);-- input
		RDEN: in std_logic;-- input
		WREN: in std_logic;-- input
		WREN_OUT: out std_logic_vector;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);

end address_decoder;

---------------------------------------------------

architecture behv of address_decoder is

begin

end behv;

---------------------------------------------------------------------------------------------
