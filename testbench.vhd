--This testbench aims to emulate the behaviour of on-board SRAM

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

--emulates 1/16 of the onboard sram (65536 16bit words)
component tb_sram
	PORT
	(
		address	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
end component;

--simulates on-board SRAM
component async_sram is
generic	(DATA_WIDTH: natural; ADDR_WIDTH: natural);--data/address widths in bits
port(	IO:	inout std_logic_vector(DATA_WIDTH-1 downto 0);--data bus
		ADDR:	in std_logic_vector(ADDR_WIDTH-1 downto 0);
		WE_n:	in std_logic;--write enable, active low
		OE_n:	in std_logic;--output enable, active low
		CE_n: in std_logic;--chip enable, active LOW
		UB_n: in std_logic;--upper IO byte access, active LOW
		LB_n: in std_logic --lower IO byte access, active LOW
);

end component;

component i2c_slave
	port (
			D: in std_logic_vector(31 downto 0);--for register write
			ADDR: in std_logic_vector(1 downto 0);--address offset of registers relative to peripheral base address
			CLK: in std_logic;--for register read/write, also used to generate SCL
			RST: in std_logic;--reset
			WREN: in std_logic;--enables register write
			RDEN: in std_logic;--enables register read
			IACK: in std_logic;--interrupt acknowledgement
			Q: out std_logic_vector(31 downto 0);--for register read
			IRQ: out std_logic;--interrupt request
			SDA: inout std_logic;--open drain data line
			SCL: inout std_logic --open drain clock line
	);
end component;

--reset duration must be long enough to be perceived by the slowest clock (filter clock, both polarities)
constant TIME_RST : time := 50020 ns;
-- internal clock period.
constant TIME_DELTA : time := 20 ns;

signal  	CLK_IN:std_logic;--50MHz
signal	rst: std_logic;
signal	rst_n: std_logic;--negated reset
signal	data_out:std_logic_vector(31 downto 0);

--sram interface
signal	ram_CLK: std_logic;--needed for conversion between sram and altsyncram (sram doesn't have clock)
signal	ram_wren: std_logic;--needed for conversion between sram and altsyncram write enable pins
signal	ram_Q: std_logic_vector(15 downto 0);--needed for conversion between sram and altsyncram data output pins

signal 	flash_CE_n: std_logic;
signal 	flash_OE_n: std_logic;
signal 	flash_WE_n: std_logic;--write enable ACTIVE LOW
signal 	flash_WP_n: std_logic;
signal	flash_IO: std_logic_vector(7 downto 0);--sram data; input because we'll only read
signal	flash_ADDR: std_logic_vector(22 downto 0);--ADDR for FLASH
signal	flash_ADDR_shortened: std_logic_vector(15 downto 0);--ADDR for emulated FLASH (tb_sram is smaller than actual FLASH)

--i2c interface
signal	I2C_SDAT: std_logic;--I2C SDA
signal	I2C_SCLK: std_logic;--I2C SCL

--I2S/codec
signal	MCLK: std_logic;-- master clock output for audio codec (12MHz)
signal	AUD_BCLK: std_logic;--SCK aka BCLK_IN
signal	AUD_DACDAT: std_logic;--DACDAT aka SD
signal	AUD_DACLRCK: std_logic;--DACLRCK aka WS

--GPIO/EX_IO interfaces
signal	GPIO: std_logic_vector(35 downto 0);
signal	EX_IO:std_logic_vector(6 downto 0);

--i2c slave signals
signal D_slv: std_logic_vector(31 downto 0);--for register write
signal ADDR_slv: std_logic_vector(1 downto 0);--address offset of registers relative to peripheral base address
signal WREN_slv: std_logic;--enables register write
signal RDEN_slv: std_logic;--enables register read
constant RW_bit: std_logic:='0';-- 1 read mode; 0 write mode

signal	instruction_number: natural := 0;-- number of the instruction being executed

signal	filter_CLK: std_logic;--filter clock generated with PLL
signal	filter_rst: std_logic;
--signal	alternative_filter_CLK: std_logic := '0';-- to keep in sync with filter clock generated with PLL

signal	sram_IO:		std_logic_vector(15 downto 0);--sram data; input because we'll only read
signal	sram_ADDR:	std_logic_vector(19 downto 0);--ADDR for SRAM
signal	sram_CE_n:	std_logic;--chip enable, active LOW
signal	sram_OE_n:	std_logic;--output enable, active LOW
signal	sram_WE_n:	std_logic;--write enable, active LOW, HIGH enables reading
signal	sram_UB_n:	std_logic;--upper IO byte access, active LOW
signal	sram_LB_n:	std_logic; --lower	IO byte access, active LOW
--signals for verification
signal	expected_output: std_logic_vector(31 downto 0);--filter output calculated by Octave
signal	filter_output: std_logic_vector(31 downto 0);--filter output calculated by hardware
signal	error_flag: std_logic;
file		output_file: text;-- open write_mode;--estrutura representando arquivo de saída de dados da simulacao no Octave

begin

	I2C_SDAT <= 'H';--pull up resistor on-board

	DUT: entity work.processor_demo
	port map(
		CLK_IN => CLK_IN,--50MHz input
		rst_n => rst_n,
		SW => (others=>'0'),
--		data_out => data_out,--filter output (encoded in IEEE 754 single precision)
		--I2C
		I2C_SDAT => I2C_SDAT,--I2C SDA
		I2C_SCLK => I2C_SCLK,--I2C SCL
		--I2S/codec
		MCLK => MCLK,-- master clock output for audio codec (12MHz)
		AUD_BCLK => AUD_BCLK,--SCK aka BCLK_IN
		AUD_DACDAT => AUD_DACDAT,--DACDAT aka SD
		AUD_DACLRCK => AUD_DACLRCK,--DACLRCK aka WS
		--FLASH
		flash_IO => flash_IO,--sram data; input because we'll only read
		flash_ADDR => flash_ADDR,--ADDR for SRAM
		flash_CE_n => open,--chip enable, active LOW
		flash_OE_n => open,--output enable, active LOW
		flash_WE_n => flash_WE_n,--write enable, active LOW, HIGH enables reading
		flash_WP_n => open,--write protection
		flash_RST_n => open, --reset
		flash_RY => '1',
		--SRAM
		sram_ADDR=> sram_ADDR,
		sram_IO	=> sram_IO,
		sram_CE_n=> sram_CE_n,
		sram_OE_n=> sram_OE_n,
		sram_WE_n=> sram_WE_n,
		sram_LB_n=> sram_LB_n,
		sram_UB_n=> sram_UB_n,
 		--GREEN LEDS
		LEDG => open,
		--RED LEDS
		LEDR => open,
		--GPIO 14 PINS
		EX_IO => EX_IO,
		--GPIO 40 PINS
		GPIO => GPIO
	);

	-----------------------------------------------------------
	--	this process reads a file vector, loads its vectors,
	--	and checks the result.
	-----------------------------------------------------------
	reading_process: process--parses input text file
		variable v_space: character;--stores the white space used to separate 2 arguments
		variable v_C: std_logic_vector(31 downto 0);--expected filter output (calculated  by Octave)
		variable v_iline_C: line;
		
		variable count: integer := 0;-- para sincronização da apresentação de amostras
		
	begin
		file_open(output_file,"output_vectors.txt",read_mode);--PRECISA FICAR NA PASTA simulation/modelsim
		
--		wait for TIME_RST+2*FILTER_CLK_SEMIPERIOD;--wait until reset finishes
--		wait until filter_CLK ='1';-- waits until the first rising edge after reset
--		wait for (TIME_DELTA/2);-- additional delay (rising edge of sampling will be in the middle of sample)
--		wait until filter_rst ='0';--wait until filter reset finishes
--		wait until filter_CLK ='0';-- waits for first falling EDGE after reset
		wait until (rising_edge(filter_CLK) and filter_rst='0');--first sample is lacthed by filter
		wait until falling_edge(filter_CLK);--filter_output latency is half cycle
		
		while not endfile(output_file) loop			
			readline(output_file,v_iline_C);--lê uma linha do arquivo de resposta desejada
			hread(v_iline_C,v_C);
			expected_output <= v_C;-- assigns exepcted filter response (calculated by Octave)
			
			-- IMPORTANTE: CONVERSÃO DE TEMPO PARA REAL
			-- se FILTER_CLK_SEMIPERIOD em ms, use 1000 e 1 ms
			-- se FILTER_CLK_SEMIPERIOD em us, use 1000000 e 1 us
			-- se FILTER_CLK_SEMIPERIOD em ns, use 1000000000 e 1 ns
			-- se FILTER_CLK_SEMIPERIOD em ps, use 1000000000000 e 1 ps
--			if (count = COUNT_MAX) then
--				wait until filter_CLK ='1';-- waits until the first rising edge occurs
--				wait for (FILTER_CLK_SEMIPERIOD);-- reestabelece o devido delay entre amostras e clock de amostragem
--			else
--				if (count = COUNT_MAX + 1) then
--					count := 0;--variable assignment takes place immediately
--				end if;
--				wait for 2*FILTER_CLK_SEMIPERIOD;-- usual delay between 2 samples
				wait until falling_edge(filter_CLK);
--			end if;
--			count := count + 1;--variable assignment takes place immediately
		end loop;
		
		file_close(output_file);

		wait; --?
	end process;
	filter_output <= << signal .testbench.DUT.filter_output: std_logic_vector(31 downto 0) >>;--updated at rising_edge(filter_CLK)
	
	verification: process(filter_CLK,filter_rst,filter_output,expected_output)
	begin
		if(filter_rst='1')then--this reset is sync'd with falling_edge(filter_CLK)
			error_flag <= '0';
		elsif(falling_edge(filter_CLK))then
			if (filter_output /= expected_output) then
				error_flag <= '1';
			else
				error_flag <=  '0';
			end if;
		end if;
	end process;
	
	--calculate number of instruction being executed
	instruction_number <= to_integer(unsigned(GPIO(7 downto 0)));--row number of mini_rom, starting from 0
	filter_CLK <= GPIO(9);
	filter_rst <= EX_IO(5);
	
	--wren: active HIGH
	--sram_WE_n: active LOW
	ram_wren <= not flash_WE_n;
	flash_ADDR_shortened <= flash_ADDR(22) & flash_ADDR(15 downto 1);
	ram: tb_sram
	port map
	(
		--trick: in real SRAM, bit 19 divides upper and lower halfs, in tb_sram this is done by bit 15
		address	=> flash_ADDR_shortened,
		clock		=> ram_CLK,--because address is updated at rising_edge of CLK_IN in my system
		data		=> (others=>'0'),--data for write, but I will only read
		wren		=> ram_wren,--active HIGH
		q			=> ram_Q
	);
	--this delay should permit our ram to update its response correctly (valid data when CLK_IN goes low)
	ram_CLK <= transport CLK_IN after 1 ns;
	flash_IO <= ram_Q(7 downto 0) when flash_ADDR(0)='0' else ram_Q(15 downto 8);
	
	rom: async_sram
	generic map (DATA_WIDTH => 16, ADDR_WIDTH => 20)
	port map(
		IO => sram_IO,
		ADDR=> sram_ADDR,
		CE_n=> sram_CE_n,
		OE_n=> sram_OE_n,
		WE_n=> sram_WE_n,
		UB_n=> sram_UB_n,
		LB_n=> sram_LB_n
	);
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
	rst_n <= '0', '1' after TIME_RST;--reset must be long enough to be perceived by the slowest clock (fifo)
	rst <= not rst_n;
	
	slave: i2c_slave
	port map(D 		=> D_slv,
				CLK	=> CLK_IN,
				ADDR 	=> ADDR_slv,
				RST	=>	rst,
				WREN	=> WREN_slv,
				RDEN	=>	RDEN_slv,
				IACK	=> '0',
				Q		=>	open,
				IRQ	=>	open,
				SDA	=>	I2C_SDAT,
				SCL	=>	I2C_SCLK
	);
	
	
	slave_setup:process
	begin
		wait for TIME_RST;--+TIME_DELTA;
		wait until CLK_IN='0';
		--zeroes & WORDS & OADDR & R/W(must store RW bit sent by master; 1 read mode; 0 write mode)
		ADDR_slv <= "00";--CR address
		D_slv <= (31 downto 10 =>'0') & "01" & "0011010" & 'X';--WORDS: 01 (2 words); OADDR: 0011010
		WREN_slv <= '1';
		wait for TIME_DELTA;
		
		ADDR_slv <= "01";--DR address
		--bits 7:0 data received or to be read by master	
		D_slv <= x"0000_00A4";-- data to be read by master
		WREN_slv <= '1';
		wait for TIME_DELTA;

		ADDR_slv<="11";--invalid address
		D_slv<=(others=>'0');
		WREN_slv <= '0';
		wait for TIME_DELTA;
		wait;--process executes once
	end process slave_setup;
	
end architecture test;
