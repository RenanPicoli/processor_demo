-------------------------------------------------------------
--component designed to asynchronously set the output and
--synchronously reset this output
--output: enables write on filter coefficients
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
		output: inout std_logic := '0'--output (enables write on filter coefficients)
);
end entity;

architecture bhv of wren_ctrl is
signal count: std_logic_vector(0 downto 0) := "0";
signal output_s: std_logic:='0';
signal output_r: std_logic:='0';

begin
	set: process (input, output_r)
	begin
		if (input'event and input='1') then--output is set
			output_s <= '1';
		end if;
		if (output_r = '1') then--output_r exists only to allow reset of output_s
			output_s <= '0';--output is reset
		end if;
	end process set;
	
	count_up: process (CLK, output_r, output_s)
	begin
		if (CLK'event and CLK = '1' and output_s = '1') then
			count <= count + 1;
		end if;
		--if (output_r = '1') then
		if (output_s = '0') then
			count <= "0";
		end if;
	end process count_up;

	reset: process (count, input, CLK)
	begin
		if (CLK'event and CLK='0') then
			if (count = "1") then
				output_r <= '1';--output_r exists only to allow reset of output_s
--				output_s <= '0';
			end if;
		end if;
		if (input='1') then
			output_r <= '0';
		end if;
	end process reset;
	
	output <= output_s;-- and (not output_r);
end bhv;