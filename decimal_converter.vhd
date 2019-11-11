------------------------------------------------------------------------------------------------
--Circuit for conversion from single precision floating point to scientific notation (base 10)
--Reads the instruction address of processor,
--in specific (hardcoded 0xA) instruction, reads data_memory_output,
--then it performs the conversion and writes
--mantissa3[3...0],...,mantissa0[3...0],negative,exponent1[3...0],exponent0[3...0]
--
--mantissa3 = most significant digit of mantissa (left of decimal point)
--mantissa0 = least significant digit of mantissa (coefficient of 10e-3)
--negative = if set, means negative exponent
--exponent1 = most significant digit of mantissa
--exponent0 = least significant digit of mantissa
------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;--for type array4

entity decimal_converter is

port(	instruction_addr: in std_logic_vector(31 downto 0);
		data_memory_output: in std_logic_vector(31 downto 0);
		mantissa: out array4(0 to 6);--digits encoded in 4 bits 
		negative: out std_logic;
		en_7seg: out std_logic;--enables the 7 seg display
--		exponent: out array4(0 to 1);--absolute value of the exponent
		
		--signals for the digikey's bcd converter
		clk		:	IN		STD_LOGIC;											--system clock
		reset_n	:	IN		STD_LOGIC;											--active low asynchronus reset
		ena		:	IN		STD_LOGIC;											--latches in new binary number and starts conversion
		busy		:	OUT	STD_LOGIC											--indicates conversion in progress
);
end entity;

architecture bhv of decimal_converter is
component binary_to_bcd
	GENERIC(
		bits		:	INTEGER := 10;		--size of the binary input numbers in bits
		digits	:	INTEGER := 3);		--number of BCD digits to convert to
	PORT(
		clk		:	IN		STD_LOGIC;											--system clock
		reset_n	:	IN		STD_LOGIC;											--active low asynchronus reset
		ena		:	IN		STD_LOGIC;											--latches in new binary number and starts conversion
		binary	:	IN		STD_LOGIC_VECTOR(bits-1 DOWNTO 0);			--binary number to convert
		busy		:	OUT	STD_LOGIC;											--indicates conversion in progress
		bcd		:	OUT	STD_LOGIC_VECTOR(digits*4-1 DOWNTO 0));	--resulting BCD number
end component;

signal bcd: std_logic_vector(15 downto 0);

begin

--	bcd_converter: binary_to_bcd
--	generic map (bits => 24, digits => 4)
--	port map(
--		clk		=> clk,
--		reset_n	=> reset_n,
--		ena		=> ena,
--		binary	=> '1' & data_memory_output(22 downto 0),--expanded mantissa
--		busy		=> busy,
--		bcd		=> bcd
--	);

--	mantissa(3) <= bcd(15	downto 12);
--	mantissa(2) <= bcd(11	downto 8	);
--	mantissa(1) <= bcd(7		downto 4	);
--	mantissa(0) <= bcd(3		downto 0	);
	process(instruction_addr)--combinatorial process
	begin
		case instruction_addr is
		when x"00000028" =>--10th instruction
			mantissa(6) <= "000" & data_memory_output(30);
			mantissa(5) <= "000" & data_memory_output(29);
			mantissa(4) <= "000" & data_memory_output(28);
			mantissa(3) <= "000" & data_memory_output(27);
			mantissa(2) <= "000" & data_memory_output(26);
			mantissa(1) <= "000" & data_memory_output(25);
			mantissa(0) <= "000" & data_memory_output(24);
			negative <= data_memory_output(31);
		when others =>
			--mantissa representa agora o endereço da instrução
			mantissa(6) <= instruction_addr(27 downto 24);
			mantissa(5) <= instruction_addr(23 downto 20);
			mantissa(4) <= instruction_addr(19 downto 16);
			mantissa(3) <= instruction_addr(15 downto 12);
			mantissa(2) <= instruction_addr(11 downto 8);
			mantissa(1) <= instruction_addr(7 downto 4);
			mantissa(0) <= instruction_addr(3 downto 0);
		end case;
	end process;
	
--	en_7seg <= 	'1' when instruction_addr=x"00000028" else--10th instruction
--					'0';
	en_7seg <= '1';
	
end bhv;