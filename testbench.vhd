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
constant TIME_RST : time := 50 us;
-- internal clock period.
constant TIME_DELTA : time := 20 ns;

signal  	CLK_IN:std_logic;--50MHz
signal	rst: std_logic;
signal	data_out:std_logic_vector(31 downto 0);

--sram interface
signal	ram_CLK: std_logic;--needed for conversion between sram and altsyncram (sram doesn't have clock)
signal	ram_wren: std_logic;--needed for conversion between sram and altsyncram write enable pins
signal	ram_Q: std_logic_vector(15 downto 0);--needed for conversion between sram and altsyncram data output pins

signal 	sram_WE_n: std_logic;--write enable ACTIVE LOW
signal	sram_IO: std_logic_vector(15 downto 0);--sram data; input because we'll only read
signal	sram_ADDR: std_logic_vector(19 downto 0);--ADDR for SRAM
signal	sram_ADDR_shortened: std_logic_vector(15 downto 0);--ADDR for emulated SRAM (tb_sram is smaller than actual SRAM)

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

begin

	I2C_SDAT <= 'H';--pull up resistor on-board

	DUT: entity work.processor_demo
	port map(
		CLK_IN => CLK_IN,--50MHz input
		rst => rst,
		data_out => data_out,--filter output (encoded in IEEE 754 single precision)
		--I2C
		I2C_SDAT => I2C_SDAT,--I2C SDA
		I2C_SCLK => I2C_SCLK,--I2C SCL
		--I2S/codec
		MCLK => MCLK,-- master clock output for audio codec (12MHz)
		AUD_BCLK => AUD_BCLK,--SCK aka BCLK_IN
		AUD_DACDAT => AUD_DACDAT,--DACDAT aka SD
		AUD_DACLRCK => AUD_DACLRCK,--DACLRCK aka WS
		--SRAM
		sram_IO => sram_IO,--sram data; input because we'll only read
		sram_ADDR => sram_ADDR,--ADDR for SRAM
		sram_CE_n => open,--chip enable, active LOW
		sram_OE_n => open,--output enable, active LOW
		sram_WE_n => sram_WE_n,--write enable, active LOW, HIGH enables reading
		sram_UB_n => open,--upper IO byte access, active LOW
		sram_LB_n => open, --lower	IO byte access, active LOW
		--GREEN LEDS
		LEDG => open,
		--RED LEDS
		LEDR => open,
		--GPIO 14 PINS
		EX_IO => EX_IO,
		--GPIO 40 PINS
		GPIO => GPIO
	);
	
	--calculate number of instruction being executed
	instruction_number <= to_integer(unsigned(GPIO(7 downto 0)));--row number of mini_rom, starting from 0
	filter_CLK <= GPIO(14);
	filter_rst <= GPIO(15);
	
	--wren: active HIGH
	--sram_WE_n: active LOW
	ram_wren <= not sram_WE_n;
	sram_ADDR_shortened <= sram_ADDR(19) & sram_ADDR(14 downto 0);
	ram: tb_sram
	port map
	(
		--trick: in real SRAM, bit 19 divides upper and lower halfs, in tb_sram this is done by bit 15
		address	=> sram_ADDR_shortened,
		clock		=> ram_CLK,--because address is updated at rising_edge of CLK_IN in my system
		data		=> (others=>'0'),--data for write, but I will only read
		wren		=> ram_wren,--active HIGH
		q			=> ram_Q
	);
	--this delay should permit our ram to update its response correctly (valid data when CLK_IN goes low)
	ram_CLK <= transport CLK_IN after 1 ns;
	--sram_IO <= transport ram_Q after 9 ns;--emulates delay in sram response (less than 10 ns)
	sram_IO <= ram_Q;
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
	rst <= '1', '0' after TIME_RST;--reset must be long enough to be perceived by the slowest clock (fifo)
	
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