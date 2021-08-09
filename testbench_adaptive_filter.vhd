--This testbench aims to emulate the the adaptive filter without the processor and unrelated peripherals
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;--for floor(), ceil()
use work.all;
use std.textio.all;--for file reading
use ieee.std_logic_textio.all;--for reading of std_logic_vectors

use work.my_types.all;


entity testbench_af is
end testbench_af;

architecture test of testbench_af is

component generic_coeffs_mem
	-- 0..P: índices dos coeficientes de x (b)
	-- 1..Q: índices dos coeficientes de y (a)
	generic	(N: natural; P: natural; Q: natural);
	port(	D:	in std_logic_vector(31 downto 0);-- um coeficiente é carregado por vez
			ADDR: in std_logic_vector(N-1 downto 0);--se ALTERAR P, Q PRECISA ALTERAR AQUI
			RST:	in std_logic;--asynchronous reset
			RDEN:	in std_logic;--read enable
			WREN:	in std_logic;--write enable
			CLK:	in std_logic;
			Q_coeffs: out std_logic_vector(31 downto 0);--single coefficient reading
			all_coeffs:	out array32((P+Q) downto 0)-- todos os coeficientes VÁLIDOS são lidos de uma vez
	);

end component;

---------------------------------------------------

component filter
	-- 0..P: índices dos coeficientes de x (b)
	-- 1..Q: índices dos coeficientes de y (a)
	generic	(P: natural; Q: natural);
	port(	input:in std_logic_vector(31 downto 0);-- input
			RST:	in std_logic;--synchronous reset
			WREN:	in std_logic;--enables writing on coefficients
			CLK:	in std_logic;--sampling clock
			coeffs:	in array32((P+Q) downto 0);-- todos os coeficientes são lidos de uma vez
			IACK: in std_logic;--iack
			IRQ:	out std_logic;--interrupt request: new sample arrived
			output: out std_logic_vector(31 downto 0)-- output
	);

end component;

---------------------------------------------------

component d_flip_flop
		port (D:	in std_logic_vector(31 downto 0);
				RST: in std_logic;
				ENA:	in std_logic:='1';--enables writes
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;

---------------------------------------------------
--produces 12MHz from 50MHz
component pll_12MHz
	port
	(
		areset		: in std_logic  := '0';
		inclk0		: in std_logic  := '0';
		c0				: out std_logic 
	);
end component;
---------------------------------------------------
--produces fs and 256fs from 12MHz
component pll_audio
	port
	(
		areset		: in std_logic  := '0';
		inclk0		: in std_logic  := '0';
		c0				: out std_logic;
		c1				: out std_logic;
		c2				: out std_logic;
		locked		: out std_logic
	);
end component;

---------------------------------------------------

component inner_product_calculation_unit
generic	(N: natural);--N: address width in bits
port(	D: in std_logic_vector(31 downto 0);-- input
		ADDR: in std_logic_vector(N-1 downto 0);-- input
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		output: out std_logic_vector(31 downto 0)-- output
);
end component;

---------------------------------------------------

component vectorial_multiply_accumulator_unit
generic	(N: natural);--N: address width in bits
port(	D: in std_logic_vector(31 downto 0);-- input
		ADDR: in std_logic_vector(N-1 downto 0);-- input
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		VMAC_EN: in std_logic;-- input: enables accumulation
		output: out std_logic_vector(31 downto 0)-- output
);

end component;

--useful functions
impure function read_mif(constant file_name: in string) return array_of_std_logic_vector is-- Don't constrain the length at the return type declaration.
	file 		input_file: text;-- open read_mode;--estrutura representando arquivo de entrada de dados
	variable result: array_of_std_logic_vector (0 to 255) := (others=>(others=>'0'));
	variable v_space: character;--stores the white space used to separate 2 arguments
	variable v_A: std_logic_vector(31 downto 0);--input of filter
	variable L: line;
	variable v_data_line: line;
	variable word_size: natural;--word size in bits
	variable word_count: natural;--number of words stored
	variable index: natural;-- index of word being stored
	variable S: string(1 to 20);
	variable open_status :FILE_OPEN_STATUS;
begin
	report "Opening " & file_name;
	file_open(open_status,input_file,file_name,read_mode);
	report "open_status = " & FILE_OPEN_STATUS'image(open_status);
	
	--parses header
	readline(input_file,L);--lê uma linha do arquivo de entradas
	report "Tamanho da 1a linha lida = " & natural'image(L'length);
	
	S := (others => ' ');--clears the string
	read(L, S(1 to L'length));
	report "S = " & S;
	
	if(S(1 to 6) = "WIDTH=")then
		report "S(L'length) = " & S(L'length);
		if(S(L'length)=';')then
			word_size := natural'value(S(7 to L'length-1));
		end if;
	end if;	
	report "word_size = " & natural'image(word_size);
	
	readline(input_file,L);--lê uma linha do arquivo de entradas
	S := (others => ' ');--clears the string
	read(L, S(1 to L'length));
	if(S(1 to 6) = "DEPTH=")then
		if(S(L'length)=';')then
			word_count := natural'value(S(7 to L'length-1));
		end if;
	end if;
	report "word_count = " & natural'image(word_count);
	
	--look for "CONTENT BEGIN"
	readline(input_file,L);--lê uma linha do arquivo de entradas
	S := (others => ' ');--clears the string
	read(L, S(1 to L'length));
	while (S(1 to 13) /= "CONTENT BEGIN") loop
		readline(input_file,L);--lê uma linha do arquivo de entradas
		S := (others => ' ');--clears the string
		read(L, S(1 to L'length));
	end loop;
	
	while not endfile(input_file) loop
		readline(input_file,L);--lê uma linha do arquivo de entradas
		S := (others => ' ');--clears the string
		read(L, S(1 to L'length));-- S receives entire line
		if(S(1 to 4) /= "END;")then
			write(v_data_line,string'(S(8 to L'length-1)));
			index := natural'value(S(1 to 6));
			hread(v_data_line,v_A);

	--		hread(v_iline_A,v_A);
	--		read(v_iline,v_space);
	--		hread(v_iline,v_B);
			
			result(index) := v_A;-- assigns input to a memory position
		end if;
	end loop;
	file_close(input_file);
	return result;
end;

--reset duration must be long enough to be perceived by the slowest clock (filter clock, both polarities)
constant TIME_RST : time := 50 us;
-- internal clock period.
constant TIME_DELTA : time := 20 ns;

signal  	CLK_IN:std_logic;--50MHz
signal	rst: std_logic;

-------------------clocks---------------------------------
--signal rising_CLK_occur: std_logic;--rising edge of CLK occurred after filter_CLK falling edge
signal CLK: std_logic;--clock for processor and cache (50MHz)
signal CLK_fs: std_logic;-- 11.029kHz clock
signal CLK_fs_dbg: std_logic;-- 110.29kHz clock
signal CLK16_928571MHz: std_logic;-- 16.928571MHz clock (1536fs, for I2S peripheral)
signal CLK12MHz: std_logic;-- 12MHz clock (MCLK for audio codec)

signal i2s_SCK_IN_PLL_LOCKED: std_logic;--'1' if PLL that provides SCK_IN is locked

signal sample_number: std_logic_vector(7 downto 0);--used to generate address for data_in_rom_ip and desired_rom_ip
signal desired_sync: std_logic_vector(31 downto 0);--desired response  SYNCCHRONIZED TO ram_CLK

----------adaptive filter algorithm inputs----------------
signal data_in: std_logic_vector(31 downto 0);--data to be filtered (encoded in IEEE 754 single precision)
signal desired: std_logic_vector(31 downto 0);--desired response (encoded in IEEE 754 single precision)
signal expected_output: std_logic_vector(31 downto 0);--expected filter output (encoded in IEEE 754 single precision, generated at modelsim)
signal data_in_array: array_of_std_logic_vector (0 to 255);--data to be filtered (encoded in IEEE 754 single precision)
signal desired_array: array_of_std_logic_vector (0 to 255);--desired response (encoded in IEEE 754 single precision)
signal expected_output_array: array_of_std_logic_vector (0 to 255);--expected filter output (encoded in IEEE 754 single precision, generated at modelsim)
signal expected_output_delayed: std_logic_vector(31 downto 0);--expected filter output delayed one filter_CLK clock cycle
signal error_flag: std_logic;-- '1' if expected_output is different from actual filter output

signal filter_CLK: std_logic;
signal filter_CLK_n: std_logic;--filter_CLK inverted
signal proc_filter_wren: std_logic;
signal filter_wren: std_logic;
signal filter_rst: std_logic := '1';
signal filter_input: std_logic_vector(31 downto 0);
signal filter_output: std_logic_vector(31 downto 0);
signal filter_irq: std_logic;
signal filter_iack: std_logic;

signal filter_CLK_state: std_logic := '0';--starts in zero, changes to 1 when first rising edge of filter_CLK occurs

--signals for coefficients memory----------------------------
constant P: natural := 2;
--constant P: natural := 3;
constant Q: natural := 2;
--constant Q: natural := 0;--forces  FIR filter
--constant Q: natural := 4;
signal coeffs_mem_Q: std_logic_vector(31 downto 0);--signal for single coefficient reading
signal coefficients: array32 (P+Q downto 0);
signal coeffs_mem_wren: std_logic;
signal coeffs_mem_rden: std_logic;

-----------signals for RAM interfacing---------------------
---processor sees all memory-mapped I/O as part of RAM-----
constant N: integer := 7;-- size in bits of data addresses (each address refers to a 32 bit word)
signal ram_clk: std_logic;--data memory clock signal
signal ram_addr: std_logic_vector(N-1 downto 0);
signal ram_rden: std_logic;
signal ram_wren: std_logic;
signal ram_write_data: std_logic_vector(31 downto 0);

--signals for inner_product----------------------------------
signal inner_product_result: std_logic_vector(31 downto 0);
signal inner_product_rden: std_logic;
signal inner_product_wren: std_logic;

--signals for vmac-------------------------------------------
signal vmac_Q: std_logic_vector(31 downto 0);
signal vmac_rden: std_logic;
signal vmac_wren: std_logic;--enables write on individual registers
signal vmac_en:	std_logic;--enables accumulation

constant c_WIDTH : natural := 4;
--file 		input_file: text;-- open read_mode;--estrutura representando arquivo de entrada de dados
--file 		desired_file: text;-- open read_mode;--estrutura representando arquivo de entrada de dados
--file 		output_file: text;-- open write_mode;--estrutura representando arquivo de saída de dados

begin	-----------------------------------------------------------
	--	this process reads a file vector, loads its vectors,
	--	passes them to the DUT and checks the result.
	-----------------------------------------------------------
	reading_process: process--parses input text file
		variable v_space: character;--stores the white space used to separate 2 arguments
		variable v_A: std_logic_vector(31 downto 0);--input of filter
		variable v_B: std_logic_vector(31 downto 0);--desired response
		variable v_C: std_logic_vector(31 downto 0);--desired response
		variable v_iline_A: line;
		variable v_iline_B: line;
		variable v_iline_C: line;
		
		variable count: integer := 0;-- para sincronização da apresentação de amostras
		
	begin
--		file_open(input_file,"data_in_rom_ip.mif",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
--		file_open(desired_file,"desired_rom_ip.mif",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
--		file_open(output_file,"output_rom_ip.mif",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
		wait for TIME_RST;--wait until reset finishes
--		wait until filter_CLK ='1';-- waits until the first rising edge after reset
--		wait for (TIME_DELTA/2);-- additional delay (rising edge of sampling will be in the middle of sample)
		wait until filter_CLK ='0';-- waits for first falling EDGE after reset
		
--		data_in_array <= read_mif(input_file);
--		desired_array <= read_mif(desired_array);
--		expected_output_array <= read_mif(output_file);
		
		data_in_array <= read_mif("data_in_rom_ip.mif");--PRECISA FICAR NA PASTA simulation/modelsim
		desired_array <= read_mif("desired_rom_ip.mif");--PRECISA FICAR NA PASTA simulation/modelsim
		expected_output_array <= read_mif("output_rom_ip.mif");--PRECISA FICAR NA PASTA simulation/modelsim
		
--		while not endfile(input_file) loop
--			readline(input_file,v_iline_A);--lê uma linha do arquivo de entradas
--			hread(v_iline_A,v_A);
----			read(v_iline,v_space);
----			hread(v_iline,v_B);
--			
--			data_in <= v_A;-- assigns input to filter
--			
--			readline(desired_file,v_iline_B);--lê uma linha do arquivo de resposta desejada
--			hread(v_iline_B,v_B);
--			desired <= v_B;-- assigns desired response to the algorithm
--			
--			-- IMPORTANTE: CONVERSÃO DE TEMPO PARA REAL
--			-- se TIME_DELTA em ms, use 1000 e 1 ms
--			-- se TIME_DELTA em us, use 1000000 e 1 us
--			-- se TIME_DELTA em ns, use 1000000000 e 1 ns
--			-- se TIME_DELTA em ps, use 1000000000000 e 1 ps
--			if (count = COUNT_MAX) then
--				wait until filter_CLK ='1';-- waits until the first rising edge occurs
--				wait for (TIME_DELTA/2);-- reestabelece o devido delay entre amostras e clock de amostragem
--			else
--				if (count = COUNT_MAX + 1) then
--					count := 0;--variable assignment takes place immediately
--				end if;
--				wait for TIME_DELTA;-- usual delay between 2 samples
--			end if;
--			count := count + 1;--variable assignment takes place immediately
--		end loop;
		
--		file_close(input_file);

		wait; --?
	end process;
	
	data_in <= data_in_array(to_integer(unsigned(sample_number)));
	desired <= desired_array(to_integer(unsigned(sample_number)));
	expected_output <= expected_output_array(to_integer(unsigned(sample_number)));

----------------------------------------------------------
	filter_CLK_n <= not filter_CLK;
	--index of sample being fetched
	--generates address for reading ROM IP's
	--counts from 0 to 255 and then restarts
	counter: process(rst,filter_rst,filter_CLK)
	begin
		if(rst='1' or filter_rst='1')then
			sample_number <= (others=>'0');
		elsif(rising_edge(filter_CLK) and filter_rst='0')then--this ensures, count is updated after used for sram_ADDR
			sample_number <= sample_number + 1;
		end if;
	end process;
		
		process(rst,filter_CLK_n,expected_output)
		begin
			if(rst='1')then
				expected_output_delayed <= (others=>'0');
			elsif(rising_edge(filter_CLK_n))then
				expected_output_delayed <= expected_output;
			end if;
		end process; 
		
		test: process(expected_output_delayed,filter_output,filter_rst,filter_CLK)
		begin
			if(filter_rst='1')then
				error_flag <= '0';
			elsif(rising_edge(filter_CLK)) then
				if (expected_output_delayed /= filter_output) then
					error_flag <= '1';
				else
					error_flag <= '0';
				end if;
			end if;
		end process;
	
	coeffs_mem: generic_coeffs_mem generic map (N=> 3, P => P,Q => Q)
									port map(D => ram_write_data,
												ADDR	=> ram_addr(2 downto 0),
												RST => rst,
												RDEN	=> coeffs_mem_rden,
												WREN	=> coeffs_mem_wren,
												CLK	=> ram_clk,
												Q_coeffs => coeffs_mem_Q,
												all_coeffs => coefficients
												);
		
	filter_CLK <= CLK_fs;
	IIR_filter: filter 	generic map (P => P, Q => Q)
								port map(input => filter_input,-- input
											RST => filter_rst,--synchronous reset
											WREN => filter_wren,--enables writing on coefficients
											CLK => filter_CLK,--sampling clock
											coeffs => coefficients,-- todos os coeficientes são lidos de uma vez
											iack => filter_iack,
											irq => filter_irq,
											output => filter_output											
											);
	filter_input <= data_in;
												
	inner_product: inner_product_calculation_unit
	generic map (N => 5)
	port map(D => ram_write_data,--supposed to be normalized
				ADDR => ram_addr(4 downto 0),
				CLK => ram_clk,
				RST => rst,
				WREN => inner_product_wren,
				RDEN => inner_product_rden,
				-------NEED ADD FLAGS (overflow, underflow, etc)
				--overflow:		out std_logic,
				--underflow:		out std_logic,
				output => inner_product_result
				);
				
	vmac: vectorial_multiply_accumulator_unit
	generic map (N => 5)
	port map(D => ram_write_data,
				ADDR => ram_addr(4 downto 0),
				CLK => ram_clk,
				RST => rst,
				WREN => vmac_wren,
				RDEN => vmac_rden,
				VMAC_EN => vmac_en,
				-------NEED ADD FLAGS (overflow, underflow, etc)
				--overflow:		out std_logic,
				--underflow:		out std_logic,
				output => vmac_Q
	);
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
	rst <= '1', '0' after TIME_RST;--reset must be long enough to be perceived by the slowest clock (fifo)

	--produces 12MHz (MCLK) from 50MHz input
	clk_12MHz: pll_12MHz
	port map (
	inclk0 => CLK_IN,
	areset => rst,
	c0 => CLK12MHz
	);

	--produces 11025Hz (fs) and 16.928571 MHz (1536fs for BCLK_IN) from 12MHz input
	clk_fs_1536fs: pll_audio
	port map (
	inclk0 => CLK12MHz,
	areset => rst,
	c0 => CLK_fs,
	c1 => CLK16_928571MHz,
	c2 => CLK_fs_dbg,--10x fs
	locked => i2s_SCK_IN_PLL_LOCKED
	);
end architecture test;