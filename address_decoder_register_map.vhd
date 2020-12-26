--------------------------------------------------
--address_decoder_register_map:
--routes rden and wren signals based on given address
--implements a register map (all registers of a peripheral)
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity address_decoder_register_map is
--N: address width in bits
generic	(N: natural);
port(	ADDR: in std_logic_vector(N-1 downto 0);-- input
		RDEN: in std_logic;-- input
		WREN: in std_logic;-- input
		data_in: in array32;-- input: outputs of all peripheral/registers
		WREN_OUT: out std_logic_vector;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);

end address_decoder_register_map;

---------------------------------------------------

architecture behv of address_decoder_register_map is
signal output: std_logic_vector(31 downto 0);-- data read
begin
	-- mux of data read
	process(ADDR,data_in)
	begin
		output <= (others=>'Z');
		-- i-th element of data_in is associated with address i
		for i in data_in'range loop
			if (i = to_integer(unsigned(ADDR))) then
				output <= data_in(i);
			end if;
		end loop;
	end process;
	
	data_out <= output when RDEN='1' else (others=>'Z');
	
	--demux of WREN
	process(ADDR,WREN)
	begin
		-- i-th element of WREN_OUT is associated with address i
		for i in data_in'range loop
			if (i = to_integer(unsigned(ADDR))) then
				WREN_OUT(i) <= WREN;
			else
				WREN_OUT(i) <= '0';
			end if;
		end loop;
	end process;
end behv;

---------------------------------------------------------------------------------------------
