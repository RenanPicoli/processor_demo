-------------------------------------------------------------
--component designed to asynchronously set the output and
--synchronously reset this output
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;

-------------------------------------------------------------

entity wren_ctrl is
port (input: in std_logic;--input able of asynchronously setting the output
		CLK: in std_logic;--synchronously resets output
		output: out std_logic := '0'--output clock
);
end entity;

architecture bhv of wren_ctrl is
begin
	process(input,CLK)
	begin
		if (input'event and input='1') then--output is set
			output <= '1';
		elsif (CLK'event and CLK='0') then
			output <= '0';
		end if;
	end process;

end bhv;