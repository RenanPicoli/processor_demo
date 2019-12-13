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
port (in cache_ready: std_logic;
		in fifo_valid:  std_logic_vector(F-1 downto 0);--1 means a valid data
		out fill_cache: std_logic
);
end entity;

architecture bhv of mmu is

signal fifo_ready: std_logic;

begin

fill_cache <= fifo_valid(0) and cache_ready;


end bhv;