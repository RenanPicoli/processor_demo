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
generic	(INIT: boolean; DATA_WIDTH: natural; ADDR_WIDTH: natural);--data/address widths in bits
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
	type mem is array (natural range <>) of std_logic_vector;--natural has 31 bit, goes from 0 to 2^31-1, at most
	--function for file reading, assumes little-endian
	-- N: width of word in BYTES;
	-- L: desired legnth of array;
	--Don't constrain the length at the return type declaration.
	impure function get_slv_array_from_file(N: natural; L: natural; fname: string) return mem is
		type t_char_file is file of character;
		subtype byte_t is natural range 0 to 255;
		type byte_arr is array (N-1 downto 0) of byte_t;
		
		file F: t_char_file;
		variable result: mem(0 to L-1)(8*N-1 downto 0) := (others=>(others=>'0'));
		variable idx: integer;
		variable char_v : character;
		variable byte_v : byte_t;
		variable word_value_v:  natural;
	begin
		file_open(F, fname);
		idx := 0;-- index word being accessed
		while ((idx < L) and (not endfile(F))) loop
			for i in 0 to N-1 loop--iterates over bytes of a single word
				read(F, char_v);
				byte_v := character'pos(char_v);
				word_value_v := word_value_v + (byte_v*(2**(8*i)));
			end loop;
			
			result(idx) := std_logic_vector(to_unsigned(word_value_v,8*N));
			word_value_v := 0;
			idx := idx+1;
		end loop;
		
		assert (idx < L) report "Binary file does not have enough elements to fill the signal." severity Warning;
		
		file_close(F);
		return result;		 
	end;
	
	function set_initial_value(INIT: boolean; default_value: mem; constant_from_file: mem) return mem is
	begin
		if(INIT)then
			return constant_from_file;
		else
			return default_value;
		end if;
	end;

	--array of latches
	constant ADDR_WIDTH_implemented: natural := 11;--for 1K instructions
--	constant initial_value: mem(0 to 2**ADDR_WIDTH_implemented-1)(DATA_WIDTH-1 downto 0):= set_initial_value(INIT,(2**ADDR_WIDTH_implemented-1 downto 0 => (DATA_WIDTH-1 downto 0 => '1')),
--																										get_slv_array_from_file(DATA_WIDTH/8,2**ADDR_WIDTH_implemented,"../../sram_file_experimental.bin"));
	constant initial_value: mem(0 to 2**ADDR_WIDTH_implemented-1)(DATA_WIDTH-1 downto 0):= set_initial_value(INIT,(2**ADDR_WIDTH_implemented-1 downto 0 => (DATA_WIDTH-1 downto 0 => '1')),
																										get_slv_array_from_file(DATA_WIDTH/8,2**ADDR_WIDTH_implemented,"../../microprocessor/executable.bin"));

	signal sram: mem(0 to 2**ADDR_WIDTH_implemented-1)(DATA_WIDTH-1 downto 0) := initial_value;

	signal sram_IO_instantaneous:	std_logic_vector(DATA_WIDTH-1 downto 0);--sram data; without delay
	constant	sram_delay: time:= 11 ns;
	signal ADDR_uint: natural;
	
begin
	assert (ADDR_WIDTH >= ADDR_WIDTH_implemented) report "Internal parameter ADDR_WIDTH_implemented must be less than or equal to ADDR_WIDTH." severity Error;

	write_proc:process(IO,WE_n,ADDR)
	begin
		if(WE_n='0')then
			sram(to_integer(unsigned(ADDR(ADDR_WIDTH_implemented-1 downto 0)))) <= IO;
		end if;
	end process;
	
	sram_IO_instantaneous <= sram(ADDR_uint) when (WE_n ='1') else
									 (others=>'Z');
	IO <= transport sram_IO_instantaneous after sram_delay;--emulates delay in sram response (less than 10 ns)
--	process(WE_n,sram,ADDR,initial_value)
--	begin
--		if (WE_n ='1') then
----			IO <= transport sram(to_integer(unsigned(ADDR))) after sram_delay;--emulates delay in sram response (less than 10 ns)
			ADDR_uint <= to_integer(unsigned(ADDR(ADDR_WIDTH_implemented-1 downto 0)));
--			IO <= sram(ADDR_uint);-- when (WE_n ='1') else (others=>'Z');--no delay
--		else
--			IO <= (others=>'Z');
--		end if;
--	end process;

end behv;

----------------------------------------------------
