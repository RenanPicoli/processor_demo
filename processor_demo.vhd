-------------------------------------------------------------
--microprocessor setup for demonstration
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;

-------------------------------------------------------------

entity processor_demo is
port (CLK_IN: in std_logic;--50MHz input
		rst: in std_logic;
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end entity;

architecture setup of processor_demo is

component decimal_converter --NOTE: it needs 24+3 clock cycles to perform continuous conversion
port(	instruction_addr: in std_logic_vector(31 downto 0);
		data_memory_output: in std_logic_vector(31 downto 0);
		mantissa: out array4(0 to 7);--digits encoded in 4 bits 
		en_7seg: out std_logic;--enables the 7 seg display
--		exponent: out array4(0 to 1);--absolute value of the exponent
		
		--signals for the downloaded bcd converter
		clk		:	IN		STD_LOGIC;											--system clock
		reset_n	:	IN		STD_LOGIC;											--active low asynchronus reset
		ena		:	IN		STD_LOGIC;											--latches in new binary number and starts conversion
		busy		:	OUT	STD_LOGIC											--indicates conversion in progress
);
end component;

component controller
port(	mantissa: in array4(0 to 7);--digits encoded in 4 bits 
		en_7seg: in std_logic;--enables the 7 seg display
--		exponent: in array4(0 to 1);--absolute value of the exponent
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end component;

component microprocessor
generic (N: integer);--size in bits of data addresses 
port (CLK: in std_logic;
		rst: in std_logic;
		data_memory_output: buffer std_logic_vector(31 downto 0);
		instruction_addr: out std_logic_vector (31 downto 0);--AKA read address
		-----ROM----------
		ADDR_rom: out std_logic_vector(4 downto 0);--addr é endereço de byte, mas os Lsb são 00
		Q_rom:	in std_logic_vector(31 downto 0);
		-----RAM-----------
		ADDR_ram: out std_logic_vector(N-1 downto 0);--addr é endereço de byte, mas os Lsb são 00
		write_data_ram: out std_logic_vector(31 downto 0);
		fill_cache_ram: out std_logic;
		rden_ram: out std_logic;--habilita leitura
		wren_ram: out std_logic;--habilita escrita
		Q_ram:in std_logic_vector(31 downto 0)
);
end component;

component mini_rom
	port (--CLK: in std_logic;--borda de subida para escrita, se desativado, memória é lida
			ADDR: in std_logic_vector(4 downto 0);--addr é endereço de byte, mas os Lsb são 00
			Q:	out std_logic_vector(31 downto 0)
			);
end component;

-- * implements a FIFO for reading sensor data; and
-- * permits parallel reading of these data.
component shift_register
	generic (N: integer);--number of stages
	port (CLK: in std_logic;
			rst: in std_logic;
			D: in std_logic_vector (31 downto 0);
			Q: out array32 (0 to N-1);
			valid: out std_logic_vector (N-1 downto 0));--for memory manager use
end component;

component parallel_load_cache
	generic (N: integer);--size in bits of address 
	port (CLK: in std_logic;--borda de subida para escrita, memória pode ser lida a qq momento desde que rden=1
			ADDR: in std_logic_vector(N-1 downto 0);--addr é endereço de byte, mas os Lsb são 00
			write_data: in std_logic_vector(31 downto 0);
			parallel_write_data: in array32 (0 to 2**N-1);
			fill_cache: in std_logic;
			rden: in std_logic;--habilita leitura
			wren: in std_logic;--habilita escrita
			Q:	out std_logic_vector(31 downto 0)
			);
end component;

component prescaler
	generic(factor: integer);
	port (CLK_IN: in std_logic;--50MHz input
			rst: in std_logic;--synchronous reset
			CLK_OUT: out std_logic--output clock
	);
end component;

signal data_memory_output: std_logic_vector(31 downto 0);--number
signal instruction_addr: std_logic_vector(31 downto 0);
signal mantissa: array4(0 to 7);--digits encoded in 4 bits 
signal exponent: array4(0 to 1);--absolute value of the exponent

signal busy: std_logic;
signal en_7seg: std_logic;

signal CLK: std_logic;--clock for processor and cache
-----------signals for ROM interfacing---------------------
signal instruction_memory_output: std_logic_vector(31 downto 0);
signal instruction_memory_address: std_logic_vector(4 downto 0);
-----------signals for RAM interfacing---------------------
constant N: integer := 5;
signal ram_clk: std_logic;--data memory clock signal
signal ram_addr: std_logic_vector(N-1 downto 0);
signal ram_write_data: std_logic_vector(31 downto 0);
signal parallel_write_data: array32 (0 to 2**N-1);
signal ram_fill_cache: std_logic;
signal ram_rden: std_logic;
signal ram_wren: std_logic;
signal ram_Q: std_logic_vector(31 downto 0);
-----------signals for FIFO interfacing---------------------
constant F: integer := 2**(N+1);--fifo depth (twice the cache's size)
signal fifo_clock: std_logic;
signal fifo_input: std_logic_vector (31 downto 0);
signal fifo_output: array32 (0 to F-1);
signal fifo_valid: std_logic_vector(F-1 downto 0);

	begin
	
	rom: mini_rom port map(	--CLK => CLK,
									ADDR=> instruction_memory_address,
									Q	 => instruction_memory_output
	);
	
	fifo_input <= x"00000000";
	fifo: shift_register generic map (N => F)
								port map(CLK => fifo_clock,
											rst => rst,
											D => fifo_input,
											Q => fifo_output,
											valid => fifo_valid);
	
	--MINHA ESTRATEGIA É EXECUTAR CÁLCULOS NA SUBIDA DE CLK E GRAVAR Na MEMÓRIA NA BORDA DE DESCIDA
	ram_clk <= not CLK;
	parallel_write_data <= fifo_output(0 to 2**N-1);
	ram: parallel_load_cache generic map (N => N)
									port map(CLK	=> ram_clk,
												ADDR	=> ram_addr,
												write_data => ram_write_data,
												parallel_write_data => parallel_write_data,
												fill_cache => ram_fill_cache,
												rden	=> ram_rden,
												wren	=> ram_wren,
												Q		=> ram_Q);
	
	processor: microprocessor
	generic map (N => N)
	port map (
		CLK => CLK,
		rst => rst,
		data_memory_output => data_memory_output,
		instruction_addr => instruction_addr,
		ADDR_rom => instruction_memory_address,
		Q_rom => instruction_memory_output,
		ADDR_ram => ram_addr,
		write_data_ram => ram_write_data,
		fill_cache_ram => ram_fill_cache,
		rden_ram => ram_rden,
		wren_ram => ram_wren,
		Q_ram => ram_Q
	);

	converter: decimal_converter port map(
		instruction_addr => instruction_addr,
		data_memory_output=>data_memory_output,
		mantissa => mantissa,
		en_7seg => en_7seg,
--		exponent => exponent,
		
		--signals for the downloaded bcd converter
		clk		=> CLK,					--system clock
		reset_n	=> not rst,				--active low asynchronus reset
		ena		=> '1',					--latches in new binary number and starts conversion
		busy		=> busy					--indicates conversion in progress
	);
	
	controller_7seg: controller port map(
		mantissa => mantissa,--digits encoded in 4 bits 
		en_7seg => en_7seg,
--		exponent => exponent,--absolute value of the exponent
		segments => segments--signals to control 8 displays of 7 segments
	);

	--produces 1Hz clock (processor and cache) from 50MHz input
	clk_1Hz: prescaler
	generic map (factor => 25000000)
	port map (
	CLK_IN => CLK_IN,
	rst => rst,
	CLK_OUT => CLK);
	
	--produces 0.25Hz clock (for fifo) from 50MHz input
	clk_250mHz: prescaler
	generic map (factor => 100000000)
	port map (
	CLK_IN => CLK_IN,
	rst => rst,
	CLK_OUT => fifo_clock);
end setup;