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
--use std.textio.all;--for to_string()

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
		ready_in: in std_logic_vector(B'length-1 downto 0);-- input: ready signals of all peripheral
		RDEN_OUT: out std_logic_vector;-- output
		WREN_OUT: out std_logic_vector;-- output
		ready_out: out std_logic;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);

end address_decoder_memory_map;

---------------------------------------------------

architecture behv of address_decoder_memory_map is

--decompose n in m * 2^p, with n,m,p natural
--returns p, greatest dividing exponent of  n (see: https://mathworld.wolfram.com/GreatestDividingExponent.html)
--n_width is the width in bits of the representantion of n (in this case, address width)
function gde(n: natural; n_width:natural) return natural is
begin
	if(n=0)then
		return n_width;
	elsif(n mod 2 = 0)then
		return (1 + gde(n/2,n_width));
	else
		return 0;
	end if;
end function;

signal output: std_logic_vector(31 downto 0);-- data read
begin
	-- mux of data read
	process(ADDR,RDEN,WREN,data_in)
		variable p: natural;
		variable mask: std_logic_vector(N downto 0);
		variable mask_length: natural;	
		variable upper_lim_slv: std_logic_vector(N-1 downto 0);
		variable lower_lim_slv: std_logic_vector(N-1 downto 0);
	begin
		output <= (others=>'0');
		-- i-th element of data_in is associated with address i
		for i in data_in'range loop
			--decompose B(i)(0) in m * 2^p, m,p natural
			--returns p, greatest dividing exponent of  B(i)(0) (see: https://mathworld.wolfram.com/GreatestDividingExponent.html)
			p := gde(B(i)(0),N);
			report "Range: [" & integer'image(B(i)(0)) & ", " & integer'image(B(i)(1)) & "]; p = " & integer'image(p);
			
			assert (B(i)(0) <= B(i)(1)) report "Range must be ascending!" severity error;
			if(i > 0)then
				assert (B(i-1)(1) < B(i)(0)) report "Ranges overlap!" severity error;
			end if;
			assert (B(i)(1) < B(i)(0) + 2**p) report "Unaligned range:[" & integer'image(B(i)(0)) & ", " & integer'image(B(i)(1)) & "]" severity error;
			mask(N):='1';
			upper_lim_slv := std_logic_vector(to_unsigned(B(i)(1),N));
			lower_lim_slv := std_logic_vector(to_unsigned(B(i)(0),N));
			for j in N-1 downto 0 loop
				if(upper_lim_slv(j)=lower_lim_slv(j) and mask(j+1)='1')then
					mask(j) := '1';
				else
					mask(j) :='0';
				end if;
			end loop;
			report "mask=" & integer'image(to_integer(unsigned(mask(N-1 downto 0))));
			mask_length := N - gde(to_integer(unsigned(mask(N-1 downto 0))),N);--address width minus number of zeros in mask
			
			--if ((B(i)(0) <= to_integer(unsigned(ADDR))) and (to_integer(unsigned(ADDR)) <= B(i)(1))) then
			if (ADDR(N-1 downto N-mask_length) = lower_lim_slv(N-1 downto N-mask_length)) then
				RDEN_OUT(i) <= RDEN;
				WREN_OUT(i) <= WREN;
				output <= data_in(i);
				ready_out <= ready_in(i);
			else
				RDEN_OUT(i) <='0';
				WREN_OUT(i) <='0';
			end if;
		end loop;
	end process;
	
	data_out <= output;
end behv;

---------------------------------------------------------------------------------------------
