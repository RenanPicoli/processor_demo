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

--reset duration must be long enough to be perceived by the slowest clock (filter clock, both polarities)
constant TIME_RST : time := 50 us;

signal  	CLK_IN:std_logic;--50MHz
signal	rst: std_logic;
signal  	data_in:std_logic_vector(31 downto 0) := (others => '0');
signal  	desired:std_logic_vector(31 downto 0) := (others => '0');--desired response (response of unknown system)
signal	data_out:std_logic_vector(31 downto 0);
signal	instruction_addr:std_logic_vector(31 downto 0);

signal	instruction_number: natural := 0;-- number of the instruction being executed

signal	filter_CLK: std_logic := '0';-- to keep in sync with filter clock generated with PLL
--signal	alternative_filter_CLK: std_logic := '0';-- to keep in sync with filter clock generated with PLL

constant c_WIDTH : natural := 4;
file 		input_file: text;-- open read_mode;--estrutura representando arquivo de entrada de dados
file 		desired_file: text;-- open read_mode;--estrutura representando arquivo de entrada de dados
file 		output_file: text;-- open write_mode;--estrutura representando arquivo de saída de dados

constant COUNT_MAX: integer := 
integer(floor(real(real(fs)*real(TIME_DELTA/1 us)/1000000.0)/real(2.0*(1.0-real(fs)*real(TIME_DELTA/1 us)/1000000.0))));

constant FILTER_CLK_SEMIPERIOD: time := 22_675_736.961 ps;--maximum precision allowed by vhdl would be fs, but constant wouldnt fit an integer

begin

	DUT: entity work.processor_demo
	port map(CLK_IN 	=> CLK_IN,
				rst	 	=> rst,
				data_in 	=> data_in,
				desired	=> desired,
				filter_CLK_out=>filter_CLK,--filter clock: used as port so the testbench can synchronize sample presenting
				data_out	=> data_out,
				instruction_addr=>instruction_addr
	);
	
	--calculate number of instruction being executed
	instruction_number <= to_integer(unsigned(instruction_addr));
	
	-----------------------------------------------------------
	--	this process reads a file vector, loads its vectors,
	--	passes them to the DUT and checks the result.
	-----------------------------------------------------------
	reading_process: process--parses input text file
		variable v_space: character;--stores the white space used to separate 2 arguments
		variable v_A: std_logic_vector(31 downto 0);--input of filter
		variable v_B: std_logic_vector(31 downto 0);--desired response
		variable v_iline_A: line;
		variable v_iline_B: line;
		
		variable count: integer := 0;-- para sincronização da apresentação de amostras
		
	begin
		file_open(input_file,"input_vectors.txt",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		file_open(desired_file,"desired_vectors.txt",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
		wait for TIME_RST;--wait until reset finishes
--		wait until filter_CLK ='1';-- waits until the first rising edge after reset
--		wait for (TIME_DELTA/2);-- additional delay (rising edge of sampling will be in the middle of sample)
		wait until filter_CLK ='0';-- waits for first falling EDGE after reset
		
		while not endfile(input_file) loop
			readline(input_file,v_iline_A);--lê uma linha do arquivo de entradas
			hread(v_iline_A,v_A);
--			read(v_iline,v_space);
--			hread(v_iline,v_B);
			
			data_in <= v_A;-- assigns input to filter
			
			readline(desired_file,v_iline_B);--lê uma linha do arquivo de resposta desejada
			hread(v_iline_B,v_B);
			desired <= v_B;-- assigns desired response to the algorithm
			
			-- IMPORTANTE: CONVERSÃO DE TEMPO PARA REAL
			-- se TIME_DELTA em ms, use 1000 e 1 ms
			-- se TIME_DELTA em us, use 1000000 e 1 us
			-- se TIME_DELTA em ns, use 1000000000 e 1 ns
			-- se TIME_DELTA em ps, use 1000000000000 e 1 ps
			if (count = COUNT_MAX) then
				wait until filter_CLK ='1';-- waits until the first rising edge occurs
				wait for (TIME_DELTA/2);-- reestabelece o devido dely entre amostras e clock de amostragem
			else
				if (count = COUNT_MAX + 1) then
					count := 0;--variable assignment takes place immediately
				end if;
				wait for TIME_DELTA;-- usual delay between 2 samples
			end if;
			count := count + 1;--variable assignment takes place immediately
		end loop;
		
		file_close(input_file);

		wait; --?
	end process;
	
	--reads adaptive filter response
	write_proc: process(data_out)--writes output file every time data_out changes
		variable v_oline: line;
		variable v_C: std_logic_vector(31 downto 0);--data to be written
	begin

		file_open(output_file,"output_vectors.txt",append_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
		v_C := data_out;
		hwrite(v_oline, v_C);--write values in hex notation
--		write(v_oline,string'(" "));
--		write(v_oline,time'image(now));
		writeline(output_file, v_oline);
			
		file_close(output_file);

	end process;
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
--	filter_clock: process--22050Hz sampling clock
--	begin
--		alternative_filter_CLK <= '0';
--		wait for FILTER_CLK_SEMIPERIOD;
--		alternative_filter_CLK <= '1';
--		wait for FILTER_CLK_SEMIPERIOD;
--	end process filter_clock;
	
	rst <= '1', '0' after TIME_RST;--reset must be long enough to be perceived by the slowest clock (fifo)
	
end architecture test;