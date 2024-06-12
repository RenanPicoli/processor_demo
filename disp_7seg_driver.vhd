library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;--array7

-------------------------------------------------------------

entity disp_7seg_driver is
port (CLK: in std_logic;
		D: in std_logic_vector(31 downto 0);
		segments: out array7(7 downto 0)
);
end entity;

architecture bhv of disp_7seg_driver is

	component mem_code_for_7seg
	port(	address	: in std_logic_vector (3 downto 0);
			clock		: in std_logic  := '1';
			q			: out std_logic_vector (6 downto 0)
	);
	end component;

signal disp_7seg_code: array7(7 downto 0);--used if one code is computed at a time

begin

	digit: for i in 0 to 7 generate
	--the statement below consumes much logic because 8 muxes are inferred (16x7bit)
--		segments(i) <= not code_for_7seg(to_integer(unsigned(disp_7seg_DR_out(4*i+3 downto 4*i ))));
		
		--one nibble being translated at a time
		--ROM containing the codes (commands) to each digit
		mem_code_for_7seg_i : mem_code_for_7seg port map (
			address	=> D(4*i+3 downto 4*i),
			clock		=> CLK,
			q			=> disp_7seg_code(i)
		);

		segments(i) <= not disp_7seg_code(i);
	end generate digit;
	
end bhv;