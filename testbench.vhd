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
-- "Time" that will elapse between test vectors we submit to the component.
constant TIME_DELTA : time := 44 us;
constant fs : integer := 22050;--frequência de amostragem do filtro

--reset duration must be long enough to be perceived by the slowest clock (fiter clock, both polarities)
constant TIME_RST : time := 33 us;

signal  	CLK_IN:std_logic;--50MHz
signal	rst: std_logic;
signal  	data_in:std_logic_vector(31 downto 0);
signal	data_out:std_logic_vector(31 downto 0);
signal	instruction_addr:std_logic_vector(31 downto 0);
signal	filter_CLK:std_logic;
signal	alternative_filter_CLK: std_logic;-- will simulate 22050 Hz clock
signal	segments: array7(0 to 7);

constant c_WIDTH : natural := 4;
file 		input_file: text;-- open read_mode;--estrutura representando arquivo de entrada de dados
file 		output_file: text;-- open write_mode;--estrutura representando arquivo de saída de dados

signal count: integer := 0;-- para sincronização da apresentação de amostras
constant COUNT_MAX: integer := 
integer(floor(real(real(fs)*real(TIME_DELTA/1 us)/1000000.0)/real(2.0*(1.0-real(fs)*real(TIME_DELTA/1 us)/1000000.0))));

constant FILTER_CLK_SEMIPERIOD: time := 22675737 ps;--maximum precision allowed by vhdl would be fs, but constant wouldnt fit an integer
signal use_alt_filter_clk: std_logic;

begin

	use_alt_filter_clk <= '1';
	DUT: entity work.processor_demo
	port map(CLK_IN 	=> CLK_IN,
				rst	 	=> rst,
				data_in 	=> data_in,
				data_out	=> data_out,
				instruction_addr=>instruction_addr,
				alternative_filter_CLK => alternative_filter_CLK,--alternative input clock (for simulation purpose)
				use_alt_filter_clk => use_alt_filter_clk,-- '1' uses alternative  clock; '0' uses pll
				filter_CLK=>filter_CLK--filter sampling clock
--				segments	=> segments	
	);
	
	-----------------------------------------------------------
	--	this process reads a file vector, loads its vectors,
	--	passes them to the DUT and checks the result.
	-----------------------------------------------------------
	reading_process: process--parses input text file
		variable v_iline: line;
		variable v_space: character;--stores the white space used to separate 2 arguments
		variable v_A: std_logic_vector(31 downto 0);--data to be read
		
	begin
		file_open(input_file,"input_vectors.txt",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
		wait for TIME_RST;--wait until reset finishes
--		wait until filter_CLK ='1';-- waits until the first rising edge after reset
--		wait for (TIME_DELTA/2);-- additional delay (rising edge of sampling will be in the middle of sample)
		wait until filter_CLK ='0';-- waits for first falling EDGE after reset
		
		while not endfile(input_file) loop
			readline(input_file,v_iline);--lê uma linha
			hread(v_iline,v_A);
--			read(v_iline,v_space);
--			hread(v_iline,v_B);
			
			data_in <= v_A;
			
			-- IMPORTANTE: CONVERSÃO DE TEMPO PARA REAL
			-- se TIME_DELTA em ms, use 1000 e 1 ms
			-- se TIME_DELTA em us, use 1000000 e 1 us
			-- se TIME_DELTA em ns, use 1000000000 e 1 ns
			-- se TIME_DELTA em ps, use 1000000000000 e 1 ps
			if (count = COUNT_MAX) then
				wait until filter_CLK ='1';-- waits until the first rising edge occurs
				wait for (TIME_DELTA/2);-- reestabelece o devido dely entre amostras e clock de amostragem
				count <= 0;
			else
				wait for TIME_DELTA;-- usual delay between 2 samples
				count <= count + 1;
			end if;
		end loop;
		
		file_close(input_file);

		wait; --?
	end process;
	
	write_proc: process(data_out)--writes output file every time data_out changes
		variable v_oline: line;
		variable v_B: std_logic_vector(31 downto 0);--data to be written
	begin

		file_open(output_file,"output_vectors.txt",append_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
		v_B := data_out;
--		if (instruction_addr = x"00000038") then--avoids writing ZZ...Z to the output_file
--				write(v_oline, v_B, right, c_WIDTH);
			hwrite(v_oline, v_B);--write values in hex notation
			writeline(output_file, v_oline);
--		end if;
			
		file_close(output_file);

	end process;
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
	filter_clock: process--22050Hz sampling clock
	begin
		alternative_filter_CLK <= '0';
		wait for FILTER_CLK_SEMIPERIOD;
		alternative_filter_CLK <= '1';
		wait for FILTER_CLK_SEMIPERIOD;
	end process filter_clock;
	
	rst <= '1', '0' after TIME_RST;--reset must be long enough to be perceived by the slowest clock (fifo)
	
end architecture test;