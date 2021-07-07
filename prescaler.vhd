-------------------------------------------------------------
--clock prescaler
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;

-------------------------------------------------------------

entity prescaler is
generic(factor: integer);
port (CLK_IN: in std_logic;
		rst: in std_logic;--synchronous reset
		CLK_OUT: out std_logic--output clock
);
end entity;

architecture bhv of prescaler is
signal CLK: std_logic := '0';
signal count: std_logic_vector(29 downto 0) := (others=>'0');

begin
	process(rst,CLK_IN,CLK,count)
	begin
		if (rst='1') then
			count <= (others => '0');
		elsif(falling_edge(CLK_IN)) then
			if(count = factor-1)then
				count <= (others => '0');
			else
				count <= count + 1;
			end if;
		end if;
		
		--this implementation does NOT guarantee 50% duty cycle
		if(rising_edge(CLK_IN)) then
			if (count < factor/2) then
				CLK <= '0';
			else			
				CLK <= '1';
			end if;
		end if;
	end process;
	
	CLK_OUT <= CLK;
end bhv;