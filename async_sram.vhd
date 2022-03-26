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
	signal sram_IO_instantaneous:	std_logic_vector(DATA_WIDTH-1 downto 0);--sram data; without delay
	constant	sram_delay: time:= 10 ns;
	
begin

	write_proc:process(IO,WE_n,ADDR)
	begin
		if(WE_n='0')then
			sram(to_integer(unsigned(ADDR))) <= IO;
		end if;
	end process;
	
--	sram_IO_instantaneous <= sram(to_integer(unsigned(ADDR))) when (WE_n ='1') else
--									 (others=>'Z');
--	IO <= transport sram_IO_instantaneous after sram_delay;--emulates delay in sram response (less than 10 ns)
	process(WE_n,sram,ADDR)
	begin
		if (WE_n ='1') then
--			IO <= transport sram(to_integer(unsigned(ADDR))) after sram_delay;--emulates delay in sram response (less than 10 ns)
			IO <= sram(to_integer(unsigned(ADDR)));--no delay
		else
			IO <= (others=>'Z');
		end if;
	end process;

end behv;

----------------------------------------------------
