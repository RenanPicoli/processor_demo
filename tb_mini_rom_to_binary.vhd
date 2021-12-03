--	Generates binary files from mini_rom component for SRAM programming
--	Generates a single file with 1Mx16bit data refering to the instructions in mini_rom.vhd
--	Values are 32 bit wide, but LSB are stored in address 2n, and MSB are stored in addr 2n+1
--	Example: data_in = 0x368F75BF
--	addr[0]= 0x75BF
--	addr[1]= 0x368F
--	This file will fill completely DE2-115 SRAM as I move the assembly to that memory
--	It will be downloaded using DE2 Control Panel

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;--for floor(), ceil()
use work.all;
use std.textio.all;--for file reading
use ieee.std_logic_textio.all;--for reading of std_logic_vectors

use work.my_types.all;


entity testbench is
end testbench;

architecture test of testbench is

signal  	data_in:std_logic_vector(31 downto 0) := (others => '0');
signal	instruction_addr:std_logic_vector(7 downto 0) := (others => '0');
signal	instruction_number: natural := 0;-- number of the instruction being executed

type std_logic_vector_file is file of std_logic_vector(3 downto 0);
file output_file: text;--estrutura representando arquivo de saída de dados

--reset duration must be long enough to be perceived by the slowest clock (filter clock, both polarities)
constant TIME_RST : time := 10 us;

--signal c : natural;

begin

	DUT: entity work.mini_rom
	port map(ADDR 	=> instruction_addr,
				Q	 	=> open
	);
	
	--calculate number of instruction being executed
	instruction_number <= to_integer(unsigned(instruction_addr))/4;
	
	--writes data_in to binary file
	write_proc: process--writing output file every time data_out changes introduces spurious pulses
		variable line_var : line;
		variable digit : natural;
		variable s : string (4 downto 1);
	begin
		file_open(output_file,"sram_assembly.bin",write_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
		data_in <= x"368F75BF";
		
		wait for TIME_RST;
		digit := to_integer(unsigned(data_in(31 downto 24)));
		s(1) := character'val(digit);
		digit := to_integer(unsigned(data_in(23 downto 16)));
		s(2) := character'val(digit);
		digit := to_integer(unsigned(data_in(15 downto 8)));
		s(3) := character'val(digit);
		digit := to_integer(unsigned(data_in(7 downto 0)));
		s(4) := character'val(digit);
		write(line_var, s);         -- write num into line_var
		writeline(output_file, line_var);   -- write line_var into the file
		
		file_close(output_file);
		wait;--suspends the execution
	end process;
	
end architecture test;