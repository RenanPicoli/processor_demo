--------------------------------------------------
--address_decoder_memory_map:
--routes rden and wren signals to the correct peripheral based on given address
--implements a memory map (all peripheral at the top level)
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
--use ieee.std_logic_arith.all;--relational operator <=

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--boundaries, tuple

---------------------------------------------------

entity address_decoder_memory_map is
--N: word address width in bits
--B boundaries: list of values of the form (starting address,final address) of all peripherals, written as integers,
--list MUST BE "SORTED" (start address(i) < final address(i) < start address (i+1)),
--values OF THE FORM: "(b1 b2..bN 0..0),(b1 b2..bN 1..1)"
generic	(N: natural; B: boundaries);
port(	ADDR: in std_logic_vector(N-1 downto 0);-- input, it is a word address
		RDEN: in std_logic;-- input
		WREN: in std_logic;-- input
		data_in: in array32;-- input: outputs of all peripheral
		RDEN_OUT: out std_logic_vector;-- output
		WREN_OUT: out std_logic_vector;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);

end address_decoder_memory_map;

---------------------------------------------------

architecture behv of address_decoder_memory_map is
signal output: std_logic_vector(31 downto 0);-- data read
begin
	-- mux of data read
	process(ADDR,RDEN,data_in)
	begin
		-- i-th element of data_in is associated with address i
		for i in data_in'range loop
			if ((B(i)(0) <= to_integer(unsigned(ADDR))) and (to_integer(unsigned(ADDR)) <= B(i)(1))) then
				RDEN_OUT(i) <= RDEN;
				output <= data_in(i);
			else
				RDEN_OUT(i) <='0';
			end if;
		end loop;
	end process;
	
	data_out <= output;

	--demux of WREN
	process(ADDR,WREN)
	begin
		-- i-th element of WREN_OUT is associated with element i of boundaries B
		for i in data_in'range loop
			--B(i)(0) is the start address and B(i)(1) is the end address of i-th peripheral
			if ((B(i)(0) <= to_integer(unsigned(ADDR))) and (to_integer(unsigned(ADDR)) <= B(i)(1))) then
				WREN_OUT(i) <= WREN;
			else
				WREN_OUT(i) <='0';
			end if;
		end loop;
	end process;
end behv;

---------------------------------------------------------------------------------------------
