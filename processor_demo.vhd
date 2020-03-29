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
		data_in: in std_logic_vector(31 downto 0);--data to be filtered (encoded in IEEE 754 single precision)
		data_out: out std_logic_vector(31 downto 0);--filter output (encoded in IEEE 754 single precision)
		instruction_addr: buffer std_logic_vector(31 downto 0);
		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
);
end entity;

architecture setup of processor_demo is

component decimal_converter --NOTE: it needs 24+3 clock cycles to perform continuous conversion
port(	instruction_addr: in std_logic_vector(31 downto 0);
		data_memory_output: in std_logic_vector(31 downto 0);
		mantissa: out array4(0 to 7);--digits encoded in 4 bits 
		en_7seg: out std_logic--enables the 7 seg display
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
port (CLK_IN: in std_logic;
		rst: in std_logic;
		irq: in std_logic;--interrupt request
		iack: out std_logic;--interrupt acknowledgement
		instruction_addr: out std_logic_vector (31 downto 0);--AKA read address
		-----ROM----------
		ADDR_rom: out std_logic_vector(4 downto 0);--addr é endereço de byte, mas os Lsb são 00
		Q_rom:	in std_logic_vector(31 downto 0);
		-----RAM-----------
		ADDR_ram: out std_logic_vector(N-1 downto 0);--addr é endereço de byte, mas os Lsb são 00
		write_data_ram: out std_logic_vector(31 downto 0);
		rden_ram: out std_logic;--habilita leitura
		wren_ram: out std_logic;--habilita escrita
		send_cache_request: out std_logic;
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
	generic (N: integer; OS: integer);--number of stages and number of stages in the output, respectively.
	port (CLK: in std_logic;
			rst: in std_logic;
			D: in std_logic_vector (31 downto 0);
--			invalidate_output: in std_logic;
			Q: out array32 (0 to OS-1));
--			valid: out std_logic_vector (N-1 downto 0));--for memory manager use
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

component mmu
generic (N: integer; F: integer);--total number of fifo stages and fifo output stage depth, respectively
port (
out_fifo_full: 	out std_logic_vector(1 downto 0):= "00";
out_cache_request: out	std_logic:= '0';
out_fifo_out_isempty: out std_logic:= '1';--'1' means fifo output stage is empty
		CLK: in std_logic;--same clock of processor
		CLK_fifo: in std_logic;--fifo clock
		rst: in std_logic;
		receive_cache_request: in std_logic;
--		fifo_valid:  in std_logic_vector(F-1 downto 0);--1 means a valid data
		iack: in std_logic;
		irq: out std_logic;--data sent
		invalidate_output: buffer std_logic;--invalidate memmory positions after parallel transfer
		fill_cache:  out std_logic
);
end component;

component prescaler
	generic(factor: integer);
	port (CLK_IN: in std_logic;--50MHz input
			rst: in std_logic;--synchronous reset
			CLK_OUT: out std_logic--output clock
	);
end component;

--signal instruction_addr: std_logic_vector(31 downto 0);
signal mantissa: array4(0 to 7);--digits encoded in 4 bits 

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
signal fifo_output: array32 (0 to (2**N)-1);
--signal fifo_valid: std_logic_vector(F-1 downto 0);
signal fifo_invalidate_output: std_logic;

signal send_cache_request: std_logic;

signal irq: std_logic;
signal iack: std_logic;

	begin
	
	rom: mini_rom port map(	--CLK => CLK,
									ADDR=> instruction_memory_address,
									Q	 => instruction_memory_output
	);
	
	fifo_input <= data_in;
	fifo: shift_register generic map (N => F, OS => 2**N)
								port map(CLK => fifo_clock,
											rst => rst,
											D => fifo_input,
--											invalidate_output => fifo_invalidate_output,
											Q => fifo_output);
--											valid => fifo_valid);
	
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
												
	memory_management_unit:
	mmu generic map (N => F, F => 2**N)
	port map(CLK => CLK,
				CLK_fifo => fifo_clock,
				rst => rst,
				receive_cache_request => send_cache_request,
--				fifo_valid => fifo_valid(((2**N)-1) downto 0),
				iack => iack,
				irq => irq,
				invalidate_output => fifo_invalidate_output,
				fill_cache => ram_fill_cache
	);
	
	processor: microprocessor
	generic map (N => N)
	port map (
		CLK_IN => CLK,
		rst => rst,
		irq => irq,
		iack => iack,
		instruction_addr => instruction_addr,
		ADDR_rom => instruction_memory_address,
		Q_rom => instruction_memory_output,
		ADDR_ram => ram_addr,
		write_data_ram => ram_write_data,
		rden_ram => ram_rden,
		wren_ram => ram_wren,
		send_cache_request => send_cache_request,
		Q_ram => ram_Q
	);
	
	--32h38=56=4*14=15ª instrução: instrução que faz load do resultado do filtro, CONFERIR em mini_rom.
	data_out <= ram_Q when instruction_addr=x"00000038" else (others=>'Z');

	converter: decimal_converter port map(
		instruction_addr => instruction_addr,
		data_memory_output=>ram_Q,
		mantissa => mantissa,
		en_7seg => en_7seg
	);
	
	controller_7seg: controller port map(
		mantissa => mantissa,--digits encoded in 4 bits 
		en_7seg => en_7seg,
		segments => segments--signals to control 8 displays of 7 segments
	);

	--são 9 instruções para cada dado em cache, clock do processador precisa ser pelo menos 9x mais rápido
	--produces 10MHz clock (processor and cache) from 50MHz input
	clk_10MHz: prescaler
	generic map (factor => 5)
	port map (
	CLK_IN => CLK_IN,
	rst => rst,
	CLK_OUT => CLK);
	
	--produces 500kHz clock (for fifo) from 50MHz input
	clk_500kHz: prescaler
	generic map (factor => 100)
	port map (
	CLK_IN => CLK_IN,
	rst => rst,
	CLK_OUT => fifo_clock);
end setup;