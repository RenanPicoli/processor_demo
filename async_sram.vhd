--------------------------------------------------
--Objective: simulate behavior of SRAM included in DE2-115
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity async_sram is
generic	(DATA_WIDTH: natural; ADDR_WIDTH: natural);--data/address widths in bits
port(	IO:	inout std_logic_vector(DATA_WIDTH-1 downto 0);--data bus
		ADDR:	in std_logic_vector(ADDR_WIDTH-1 downto 0);
		WE_n:	in std_logic;--write enable, active low
		OE_n:	in std_logic;--output enable, active low
		CE_n: in std_logic;--chip enable, active LOW
		UB_n: in std_logic;--upper IO byte access, active LOW
		LB_n: in std_logic --lower IO byte access, active LOW
);

end async_sram;

---------------------------------------------------

architecture behv of async_sram is

	--array of latches
--	type word_t is std_logic_vector(DATA_WIDTH-1 downto 0);
	type mem is array (0 to 2**ADDR_WIDTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
	signal sram: mem := (others=>(others=>'1'));
	
begin

	write_proc:process(IO,WE_n,ADDR)
	begin
		if(WE_n='0')then
			sram(to_integer(unsigned(ADDR))) <= IO;
		end if;
	end process;
	
	IO <= sram(to_integer(unsigned(ADDR))) when (WE_n ='1') else
			(others=>'Z');

end behv;

----------------------------------------------------
