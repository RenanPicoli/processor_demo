--------------------------------------------------
--address_decoder:
--routes rden and wren signals based on given address
--implements a memory map or a register map
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity address_decoder is
--N: address width in bits
--boundaries: upper limits of each end (except the last, which is 2**N-1)
generic	(N: natural; boundaries: array32);
port(	ADDR: in std_logic_vector(N-1 downto 0);-- input
		RDEN: in std_logic;-- input
		WREN: in std_logic;-- input
--		RDEN_OUT: out std_logic_vector;-- output
		data_in: in array32;-- input: outputs of all peripheral/registers
		WREN_OUT: out std_logic_vector;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);

end address_decoder;

---------------------------------------------------

architecture behv of address_decoder is
signal output: std_logic_vector(31 downto 0);-- data read
begin
	-- mux of data read
	process(ADDR)
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
	process(ADDR)
	begin
		WREN_OUT <= (others=>'0');
		-- i-th element of WREN_OUT is associated with address i
		for i in data_in'range loop
			if (i = to_integer(unsigned(ADDR))) then
				WREN_OUT(i) <= WREN;
			end if;
		end loop;
	end process;
end behv;

---------------------------------------------------------------------------------------------
