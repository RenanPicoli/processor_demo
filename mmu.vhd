-------------------------------------------------------------
--memory management unit - MMU
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;

-------------------------------------------------------------

entity mmu is
generic (F: integer);--fifo depth
port (CLK: in std_logic;--same clock of processor
		rst: in std_logic;
		receive_cache_request: in std_logic;
		fifo_valid:  in std_logic_vector(F-1 downto 0);--1 means a valid data
		fill_cache:  out std_logic
);
end entity;

architecture bhv of mmu is

signal fifo_ready: std_logic;
signal cache_request: std_logic := '0';

begin

	process(CLK)
	begin
		if(CLK'event and CLK='1') then
			if(rst='0') then
				if (receive_cache_request='1') then
					cache_request <= '1';
				end if;

				fill_cache <= fifo_valid(0) and cache_request;--habilita o carregamento paralelo, mas wren precisa estar ativado.
				
			else--if reset is activated
				cache_request <= '0';
			end if;
		end if;
	end process;
end bhv;