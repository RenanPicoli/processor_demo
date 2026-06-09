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
--MULTI_CLK: when true, support multiple peripheral clock domains, otherwise all peripherals are assumed to be in the same clock domain and CLK can be ignored (set to others=>'0')
--DOMAINS: per-peripheral clock domain identifiers, same size as B (array(natural range <>) of tuple(0 to 1))
  generic	(N: natural; B: boundaries);--; DOMAINS: tuple (0 to B'length-1) := (others => 0); MULTI_CLK: boolean := false);
  port(	ADDR: in std_logic_vector(N-1 downto 0);-- input, it is a word address
		RDEN: in std_logic;-- input
		WREN: in std_logic;-- input
		-- CLK: in array_of_std_logic := (others => '0');-- input clocks for peripherals
		data_in: in array32;-- input: outputs of all peripheral
		ready_in: in std_logic_vector(B'length-1 downto 0);-- input: ready signals of all peripheral
		RDEN_OUT: out std_logic_vector;-- output
		WREN_OUT: out std_logic_vector;-- output
		ready_out: out std_logic;-- output
		-- MASTER_CLK_ID: in std_logic_vector(1 downto 0);-- identifies the one clock controlling the bus
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
signal sel_periph_index: natural;
--signal ready_out_reg: std_logic_vector(CLK'length-1 downto 0);--one ready_out_reg for each clk possibility

type integer_array is array (natural range <>) of integer;
-- per-peripheral clock domain identifiers for writes: same size as ranges
constant clk_domains: integer_array (0 to 20) := 	(-- 0: CPU clock; 1: SDRAM clk
											0,-- 0: filter coeffs
											0,-- 1: filter xN
											0,-- 2: cache
											0,-- 3: inner_product
											0,-- 4: VMAC
											0,-- 5: I2C
											0,-- 6: I2S
											0,-- 7: current filter output
											0,-- 8: desired response
											0,-- 9: filter status
											0,-- 10: converted_out
											0,-- 11: 7-segments display DR
											0,-- 12: LCD controller
											0,-- 13: general purpose fp32_to_int32
											0,-- 14: UART peripheral (IF AVAILABLE)
											1,-- 15: DMA
											1,-- 16: VGA
											0,-- 17: interrupt controller
											0,-- 18: tmp_vector
											0,-- 19: instruction memory (aka program_data)
											1 --20: SDRAM
											);


begin
--	assert CLK'length = 2 report "Numero de clocks errado: "& integer'image(CLK'length) severity error;
	-- mux of data read
	process(ADDR,RDEN,WREN,data_in)
		variable p: natural;
		variable mask: std_logic_vector(N downto 0);
		variable mask_length: natural;	
		variable upper_lim_slv: std_logic_vector(N-1 downto 0);
		variable lower_lim_slv: std_logic_vector(N-1 downto 0);
	begin
		output <= (others=>'0');
		sel_periph_index <= 0;
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
			--aligned start address is not strict requirement: I can subtract base address and get a zero-base internall address
--			assert ((B(i)(1) < B(i)(0) + 2**p) or p=32) report "Unaligned range:[" & integer'image(B(i)(0)) & ", " & integer'image(B(i)(1)) & "]" severity error;
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
			report "mask_length=" & integer'image(mask_length);
			
			if ((B(i)(0) <= to_integer(unsigned(ADDR))) and (to_integer(unsigned(ADDR)) <= B(i)(1))) then
--			--this is intended to simplify logic, but requires ALIGNED BOUNDARIES
--			if (ADDR(N-1 downto N-mask_length) = lower_lim_slv(N-1 downto N-mask_length)) then
				sel_periph_index <= i;
				RDEN_OUT(i) <= RDEN;
				WREN_OUT(i) <= WREN;
				output <= data_in(i);
--				ready_out <= ready_in(i);
			else
				RDEN_OUT(i) <='0';
				WREN_OUT(i) <='0';
			end if;
		end loop;
		
		
		report "B'length= # of peripherals = " & integer'image(B'length);
	end process;
	
	-- process(RDEN,WREN,sel_periph_index,ready_in)
	-- begin
	-- 	if (RDEN='1') then
	-- 		ready_out <= ready_in(sel_periph_index);
	-- 	elsif (WREN='1') then
	-- 		if (MULTI_CLK) then
	-- 			if (std_logic_vector(to_unsigned(DOMAINS(sel_periph_index), 2)) = MASTER_CLK_ID) then--if the peripheral is in the same clock domain as the bus, use combinational ready signal
	-- 				ready_out <= ready_in(sel_periph_index);
	-- 			else
	-- 				ready_out <= ready_out_reg(DOMAINS(sel_periph_index));-- uses registered value
	-- 			end if;
	-- 		else
	-- 			ready_out <= ready_in(sel_periph_index);
	-- 		end if;
	-- 	else
	-- 		ready_out <= '1';
	-- 	end if;
	-- end process;
	ready_out <= ready_in(sel_periph_index) when (RDEN='1' or WREN='1') else '1';
	
	-- reg_multi_clk: for i in 0 to CLK'length generate
	-- 	reg: process(CLK,RDEN,WREN,sel_periph_index,ready_in)
	-- 	begin
	-- 		report "clock number :" & integer'image(CLK'length);
	-- 		if (WREN='1' and MULTI_CLK and std_logic_vector(to_unsigned(DOMAINS(sel_periph_index), 2)) /= MASTER_CLK_ID) then--for a write to a peripheral in a different clock domain, register the ready signal at the destination clock domain
	-- 			ready_out_reg(i) <= '0';-- start with not ready when a write starts
	-- 		elsif (rising_edge(CLK(i))) then--updated at rising edge of destination clock
	-- 			ready_out_reg(i) <= ready_in(sel_periph_index);
	-- 		end if;
	-- 	end process;
	-- end generate reg_multi_clk;

	data_out <= output;
end behv;

---------------------------------------------------------------------------------------------
