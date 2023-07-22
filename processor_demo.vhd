-------------------------------------------------------------
--microprocessor setup for demonstration
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;
use work.single_precision_type.all;--float

-------------------------------------------------------------

entity processor_demo is
port (CLK_IN: in std_logic;--50MHz input
		rst_n: in std_logic;--active low reset, connected to KEY3
		--SWITCHES for runtime configuration
		SW: in std_logic_vector(17 downto 0);
		--I2C
		I2C_SDAT: inout std_logic;--I2C SDA
		I2C_SCLK: inout std_logic;--I2C SCL
		--I2S/codec
		MCLK: out std_logic;-- master clock output for audio codec (12MHz)
		AUD_BCLK: out std_logic;--SCK aka BCLK_IN
		AUD_DACDAT: out std_logic;--DACDAT aka SD
		AUD_DACLRCK: out std_logic;--DACLRCK aka WS
		--FLASH (data samples)
		flash_IO: in std_logic_vector(7 downto 0);--flash data; input because we'll only read
		flash_ADDR: out std_logic_vector(22 downto 0);--ADDR for flash
		flash_CE_n: out std_logic;--chip enable, active LOW
		flash_OE_n: out std_logic;--output enable, active LOW
		flash_WE_n: out std_logic;--write enable, active LOW, HIGH enables reading
		flash_RST_n: out std_logic;--reset, active LOW
		flash_WP_n: out std_logic; --write protection, active LOW
		flash_RY: in std_logic; --readiness flag, active HIGH, HIGH means busy (writing or erasing)
		--SRAM (instructions)
		sram_IO: inout std_logic_vector(15 downto 0);--sram data; input because we'll only read
		sram_ADDR: buffer std_logic_vector(19 downto 0);--ADDR for SRAM
		sram_CE_n: buffer std_logic;--chip enable, active LOW
		sram_OE_n: buffer std_logic;--output enable, active LOW
		sram_WE_n: buffer std_logic;--write enable, active LOW, HIGH enables reading
		sram_UB_n: buffer std_logic;--upper IO byte access, active LOW
		sram_LB_n: buffer std_logic; --lower	IO byte access, active LOW
		-- 7 segments displays
		segments: out array7(7 downto 0);
		--GREEN LEDS
		LEDG: out std_logic_vector(8 downto 0);
		--RED LEDS
		LEDR: out std_logic_vector(17 downto 0);
		--GPIO 14 PINS
		EX_IO: out std_logic_vector(6 downto 0);
		--GPIO 40 PINS
		GPIO: out std_logic_vector(35 downto 0)
);
end entity;

architecture setup of processor_demo is

component microprocessor
port (CLK_IN: in std_logic;
		rst: in std_logic;
		irq: in std_logic;--interrupt request
		iack: out std_logic;--interrupt acknowledgement
		return_value: out std_logic_vector (31 downto 0);-- output of RV register
		ISR_addr: in std_logic_vector (31 downto 0);--address for interrupt handler, loaded when irq is asserted, it is valid one clock cycle after the IRQ detection
		-----ROM----------
		ADDR_rom: out std_logic_vector(31 downto 0);--addr é endereço de word
		CLK_rom: out std_logic;--clock for mini_rom (is like moving a PC register duplicate to i_cache)
		Q_rom:	in std_logic_vector(31 downto 0);
		i_cache_ready: in std_logic;--indicates i_cache is ready (Q_rom is valid), synchronous to rising_edge(CLK_IN)
		-----RAM-----------
		ADDR_ram: out std_logic_vector(31 downto 0);--WORD ADDRESS
		write_data_ram: out std_logic_vector(31 downto 0);
		rden_ram: out std_logic;--enables read on ram
		wren_ram: out std_logic;--enables write on ram
		d_cache_ready: in std_logic;--indicates d_cache is ready (Q_ram is valid), synchronous to rising_edge(CLK_IN)
		wren_lvec: out std_logic;--enables load vector: loads vector of 8 std_logic_vector in parallel
		lvec_src: out std_logic_vector(2 downto 0);--a single source address for lvec
		lvec_dst_mask: out std_logic_vector(6 downto 0);--mask for destination(s) address(es) for lvec
		vmac_en: out std_logic;--multiply-accumulate enable
		Q_ram:in std_logic_vector(31 downto 0)
);
end component;

component mini_rom
	port (CLK: in std_logic;--borda de subida para escrita, se desativado, memória é lida
			RST: in std_logic;--asynchronous reset
			--interface de instrução (read-only)
			ADDR_A: in std_logic_vector(7 downto 0);--addr é endereço de byte, mas os Lsb são 00
			Q_A:	out std_logic_vector(31 downto 0);
			--interface de dados (read-write)
			D_B:	in std_logic_vector(31 downto 0);
			ADDR_B: in std_logic_vector(7 downto 0);--addr é endereço de byte, mas os Lsb são 00
			WREN_B: std_logic;
			Q_B:	out std_logic_vector(31 downto 0)
			);
end component;

component cache
--REQUESTED_SIZE: user requested cache size, in 32 bit words;
--MEM_LATENCY: latency of program memory in MEM_CLK cycles
--MEM_WIDTH: data width of program memory in bits
	generic (REQUESTED_SIZE: natural; MEM_WIDTH: natural :=32; MEM_LATENCY: natural := 0; REQUESTED_FIFO_DEPTH: natural:= 4; REGISTER_ADDR: boolean);
	port (
			req_ADDR: in std_logic_vector;--address of requested data
			req_rden: in std_logic;--read requested
			req_wren: in std_logic:='0';--write requested
			req_data_in: in std_logic_vector(31 downto 0):=(others=>'0');--data for write request
			CLK: in std_logic;--processor clock for reading/writing data, must run even if cache is not ready
			mem_I: in std_logic_vector(MEM_WIDTH-1 downto 0);--data coming from program memory
			mem_CLK: in std_logic;--clock for reading program memory
			RST: in std_logic;--reset to prevent reading while program memory is written (must be synchronous to mem_CLK)
			mem_ADDR: out std_logic_vector;--address for memory read/write
			mem_WREN: out std_logic:='0';
			req_ready: out std_logic;--indicates that data already contains the requested data
			mem_O: out std_logic_vector(MEM_WIDTH-1 downto 0);--data to be written in program memory
			data: buffer std_logic_vector(31 downto 0)--fetched data
	);
end component;

component mini_ram
	generic (N: integer);--size in bits of address 
	port (CLK: in std_logic;--borda de subida para escrita, memória pode ser lida a qq momento desde que rden=1
			ADDR: in std_logic_vector(N-1 downto 0);--addr é endereço de byte, mas os Lsb são 00
			write_data: in std_logic_vector(31 downto 0);
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

component generic_coeffs_mem
	-- 0..P: índices dos coeficientes de x (b)
	-- 1..Q: índices dos coeficientes de y (a)
	generic	(N: natural; P: natural; Q: natural);--N address width in bits
	port(	D:	in std_logic_vector(31 downto 0);-- um coeficiente é atualizado por vez
			ADDR: in std_logic_vector(N-1 downto 0);--se ALTERAR P, Q PRECISA ALTERAR AQUI
			RST:	in std_logic;--asynchronous reset
			RDEN:	in std_logic;--read enable
			WREN:	in std_logic;--write enable
			CLK:	in std_logic;
--			filter_CLK:	in std_logic;--to synchronize read with filter (coeffs are updated at rising_edge)
--			filter_WREN: in std_logic;--filter write enable, used to check if all_coeffs must be used
			parallel_write_data: in array32 (0 to 2**N-1);
			parallel_wren: in std_logic;
--			parallel_rden: in std_logic;
			parallel_read_data: out array32 (0 to 2**N-1);--used when peripherals other than filter
			Q_coeffs: out std_logic_vector(31 downto 0);--single coefficient reading
			all_coeffs:	out array32((P+Q) downto 0)-- all VALID coefficients are read at once by filter through this port
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
			IACK: in std_logic_vector(1 downto 0);--iack
			IRQ:	out std_logic_vector(1 downto 0);--bit 0: new sample arrived, bit 1: new output is ready
			output: out std_logic_vector(31 downto 0)-- output registered (updated at falling_edge of CLK)
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

component pll_dbg_uproc
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC ;
		c1 	: OUT STD_LOGIC ;
		c2 	: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC 
	);
END component;

---------------------------------------------------

component inner_product_calculation_unit
generic	(N: natural);--N: address width in bits
port(	D: in std_logic_vector(31 downto 0);
		ADDR: in std_logic_vector(N-1 downto 0);
		CLK: in std_logic;
		RST: in std_logic;
		WREN: in std_logic;
		RDEN: in std_logic;
		parallel_write_data: in array32 (0 to 2**(N-2)-1);
		parallel_wren_A: in std_logic;
		parallel_wren_B: in std_logic;
--		parallel_rden_A: in std_logic;--enables parallel read (to shared data bus)
--		parallel_rden_B: in std_logic;--enables parallel read (to shared data bus)
		parallel_read_data_A: out array32 (0 to 2**(N-2)-1);
		parallel_read_data_B: out array32 (0 to 2**(N-2)-1);
		ready: out std_logic;--synchronous to rising_edge(CLK)
		output: out std_logic_vector(31 downto 0)-- output
);
end component;

---------------------------------------------------

component address_decoder_memory_map
--N: word address width in bits
--B boundaries: list of values of the form (starting address,final address) of all peripherals, written as integers,
--list MUST BE "SORTED" (start address(i) < final address(i) < start address (i+1)),
--values OF THE FORM: "(b1 b2..bN 0..0),(b1 b2..bN 1..1)"
generic	(N: natural; B: boundaries);
port(	ADDR: in std_logic_vector(N-1 downto 0);-- input, it is a word address
		RDEN: in std_logic;-- input
		WREN: in std_logic;-- input
		data_in: in array32;-- input: outputs of all peripheral/registers
		ready_in: in std_logic_vector;-- input: ready signals of all peripheral
		RDEN_OUT: out std_logic_vector;-- output
		WREN_OUT: out std_logic_vector;-- output
		ready_out: out std_logic;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);
end component;

---------------------------------------------------

component filter_xN
-- 0..P: índices dos x
-- P+1..P+Q: índices dos y
generic	(N: natural; P: natural; Q: natural);--N: address width in bits (must be >= log2(P+1+Q))
port(	D: in std_logic_vector(31 downto 0);-- not used (peripheral is read-only)
		DX: in std_logic_vector(31 downto 0);--current filter input
		DY: in std_logic_vector(31 downto 0);--current filter output
		ADDR: in std_logic_vector(N-1 downto 0);-- input
		CLK_x: in std_logic;-- must be filter clock (input sampling)
		CLK_y: in std_logic;-- must be not filter clock (output storing)
		RST: in std_logic;-- input
		WREN: in std_logic;--not used (peripheral supports only read)
		RDEN: in std_logic;-- input
		parallel_write_data: in array32 (0 to 2**N-1);--not used
		parallel_wren: in std_logic;--not used
--		parallel_rden: in std_logic;--enables parallel read (to shared data bus)
		parallel_read_data: out array32 (0 to 2**N-1);
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
		parallel_write_data: in array32 (0 to 2**(N-2)-1);
		parallel_wren_A: in std_logic;
		parallel_wren_B: in std_logic;
--		parallel_rden_A: in std_logic;--enables parallel read (to shared data bus)
--		parallel_rden_B: in std_logic;--enables parallel read (to shared data bus)
		parallel_read_data_A: out array32 (0 to 2**(N-2)-1);
		parallel_read_data_B: out array32 (0 to 2**(N-2)-1);
		output: out std_logic_vector(31 downto 0)-- output
);

end component;

---------------------------------------------------
	
component sync_chain
	generic (N: natural;--bus width in bits
				L: natural);--number of registers in the chain
	port (
			data_in: in std_logic_vector(N-1 downto 0);--data generated at another clock domain
			CLK: in std_logic;--clock of new clock domain
			RST: in std_logic;--asynchronous reset
			data_out: out std_logic_vector(N-1 downto 0)--data synchronized in CLK domain
	);
end component;

---------------------------------------------------

component interrupt_controller_vectorized
generic	(L: natural);--L: number of IRQ lines
port(	D: in std_logic_vector(31 downto 0);-- input: data to register write
		ADDR: in std_logic_vector(6 downto 0);--address offset of registers relative to peripheral base address
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		REQ_READY: in  std_logic;--input
		IRQ_IN: in std_logic_vector(L-1 downto 0);--input: all IRQ lines
		IRQ_OUT: out std_logic;--output: IRQ line to cpu
		IACK_IN: in std_logic;--input: IACK line coming from cpu
		IACK_OUT: buffer std_logic_vector(L-1 downto 0);--output: all IACK lines going to peripherals
		ISR_ADDR: out std_logic_vector(31 downto 0);--address of ISR
		output: out std_logic_vector(31 downto 0)-- output of register reading
);

end component;

---------------------------------------------------

component fp32_to_integer
generic	(N: natural);--number of bits in output
port(	fp_in:in std_logic_vector(31 downto 0);--floating point input
		output: out std_logic_vector(N-1 downto 0)-- valid input range [-1,1] maps to output range [-2^(N-1),+(2^(N-1)-1)]
);
end component;

---------------------------------------------------

--to produce audio attenuation and try to avoid clipping
component fpu_divider
port (
	A: in std_logic_vector(31 downto 0);--supposed to be normalized
	B: in std_logic_vector(31 downto 0);--supposed to be normalized
	--FLAGS (overflow, underflow, etc)
	divideByZero:	out std_logic;
	overflow:		out std_logic;
	underflow:		out std_logic;
	result:out std_logic_vector(31 downto 0)
);
end component;

---------------------------------------------------

component i2c_master
	port (
			D: in std_logic_vector(31 downto 0);--for register write
			ADDR: in std_logic_vector(2 downto 0);--address offset of registers relative to peripheral base address
			CLK: in std_logic;--for register read/write, also used to generate SCL
			RST: in std_logic;--reset
			WREN: in std_logic;--enables register write
			RDEN: in std_logic;--enables register read
			IACK: in std_logic;--interrupt acknowledgement
			Q: out std_logic_vector(31 downto 0);--for register read
			IRQ: out std_logic;--interrupt request
			SDA: inout std_logic;--open drain data line
			sda_dbg_p: out natural;--for debug, which statement is driving SDA
			SCL: inout std_logic --open drain clock line
	);
end component;

---------------------------------------------------

component i2s_master_transmitter
	port (
			D: in std_logic_vector(31 downto 0);--for register write
			ADDR: in std_logic_vector(2 downto 0);--address offset of registers relative to peripheral base address
			CLK: in std_logic;--for register read/write, also used to generate SCK
			RST: in std_logic;--reset
			WREN: in std_logic;--enables register write
			RDEN: in std_logic;--enables register read
			IACK: in std_logic;--interrupt acknowledgement
			Q: out std_logic_vector(31 downto 0);--for register read
			IRQ: out std_logic;--interrupt request
			SCK_IN: in std_logic;--clock for SCK generation (must be 256*fs, because SCK_IN is divided by 2 to generate SCK)
			SCK_IN_PLL_LOCKED: in std_logic;--'1' if PLL that provides SCK_IN is locked
			SD: out std_logic;--data line
			WS: buffer std_logic;--left/right clock
			SCK: out std_logic--continuous clock (bit clock); fSCK=128fs
	);
end component;

---------------------------------------------------

--generic mux
component mux
	generic(N_BITS_SEL: natural);--number of bits in sel port
	port(	A: in array_of_std_logic_vector;--user must ensure correct sizes
			sel: in std_logic_vector(N_BITS_SEL-1 downto 0);--user must ensure correct sizes
			Q: out std_logic_vector--user must ensure correct sizes
			);
end component;

--simulates on-board SRAM
component async_sram
generic	(INIT: boolean; DATA_WIDTH: natural; ADDR_WIDTH: natural);--data/address widths in bits
port(	IO:	inout std_logic_vector(DATA_WIDTH-1 downto 0);--data bus
		ADDR:	in std_logic_vector(ADDR_WIDTH-1 downto 0);
		WE_n:	in std_logic;--write enable, active low
		OE_n:	in std_logic;--output enable, active low
		CE_n: in std_logic;--chip enable, active LOW
		UB_n: in std_logic;--upper IO byte access, active LOW
		LB_n: in std_logic --lower IO byte access, active LOW
);

end component;

component mem_code_for_7seg
port(	address	: in std_logic_vector (3 downto 0);
		clock		: in std_logic  := '1';
		q			: out std_logic_vector (6 downto 0)
);
end component;

component LCD_Controller
port (
	clk		: in  std_logic;
	rst		: in  std_logic;
	-- interface with CPU
	D		: in std_logic_vector(31 downto 0);
	wren	: in std_logic;
	Q		: out std_logic_vector(31 downto 0);
	ready	: out std_logic;--check for writes
	  
	  -- LCD control signals
	RS		: out std_logic;
	RW		: out std_logic;
	E		: inout std_logic;
	VO		: out std_logic;
	DB		: inout std_logic_vector(7 downto 0)
);
end component;

signal rst: std_logic;--active high
signal rst_n_sync_CLK_IN: std_logic;--rst_n sync'd to rising_edge of CLK_IN
signal rst_n_sync_sram_CLK: std_logic;--rst_n sync'd to rising_edge of sram_CLK
signal rst_n_sync_uproc: std_logic;--rst_n sync'd to rising_edge of uproc_CLK

--0Y1: will read* byte Y (counting from 0 - LSB) of input vectors
--0Y0: will read* byte Y (counting from 0 - LSB) of desired vectors
--1000: waiting filter_CLK rising edge (since sampling edge is the rising) to read again
--1001: will wait until filter_CLK='0' and the next rising_edge of CLK to read again
-- * : on next rising edge of CLK, flash_ADDR will be updated, at next CLK falling edge IO will be latched
signal flash_reading_state: std_logic_vector(3 downto 0);
signal flash_count: std_logic_vector(19 downto 0);--counter: generates the address for FLASH, 1 bit must be added to obtain address

-----------signals for sram_loader interfacing---------------------
constant sram_loader: boolean := false;
signal sram_filled: std_logic := '0';
signal sram_filled_delayed: std_logic := '0';
signal sram_loader_address: std_logic_vector(7 downto 0);--used to read mini_rom
signal sram_loader_data: std_logic_vector(31 downto 0);--used to read mini_rom
signal sram_loader_counter: std_logic_vector(19 downto 0);--counts from 0 to 1M-1 to generate write addresses
signal sram_loader_counter_delayed: std_logic_vector(19 downto 0);--counts from 0 to 1M-1 to generate write addresses

--on next rising edge of CLK, sram_ADDR will be updated, at next CLK falling edge IO will be latched
signal sram_ADDR_reading: std_logic_vector(19 downto 0);--ADDR for SRAM reading
signal sram_ADDR_lower_half: std_logic_vector(19 downto 0);--address of lower half of next instruction
signal sram_ADDR_upper_half: std_logic_vector(19 downto 0);--address of lower half of next instruction
signal sram_reading_state: std_logic;--'0' means reading enabled, '1' means reading complete
signal sram_CLK: std_logic;--clock for process reading instructions in SRAM, must be 8x CLK, delayed 1/8 CLK cycle
signal sram_CLK_n: std_logic;--sram_CLK inverted
signal count: std_logic_vector(17 downto 0);--counter: generates the address for SRAM, 1 bit must be added to obtain address
signal sram_write_data: std_logic_vector(15 downto 0);--data to be writen in SRAM
signal all_sram_write_data: array_of_std_logic_vector (3 downto 0)(15 downto 0);
signal sram_write_data_sel: std_logic_vector(1 downto 0);

signal sample_number: std_logic_vector(7 downto 0);--used to generate address for data_in_rom_ip and desired_rom_ip
signal desired_sync: std_logic_vector(31 downto 0);--desired response  SYNCCHRONIZED TO ram_CLK

----------adaptive filter algorithm inputs----------------
signal data_in: std_logic_vector(31 downto 0);--data to be filtered (encoded in IEEE 754 single precision)
signal desired: std_logic_vector(31 downto 0);--desired response (encoded in IEEE 754 single precision)
signal expected_output: std_logic_vector(31 downto 0);--expected filter output (encoded in IEEE 754 single precision, generated at modelsim)
signal expected_output_delayed: std_logic_vector(31 downto 0);--expected filter output delayed one filter_CLK clock cycle
signal error_flag: std_logic;-- '1' if expected_output is different from actual filter output

-------------------clocks---------------------------------
--signal rising_CLK_occur: std_logic;--rising edge of CLK occurred after filter_CLK falling edge
signal CLK: std_logic;--clock for processor and cache
signal CLK_n: std_logic;--negated CLK
signal CLK_dbg: std_logic;--clock for debug, check timing analyzer or the pll_dbg wizard
signal CLK_fs: std_logic;-- 11.029kHz clock
signal CLK_fs_dbg: std_logic;-- 110.29kHz clock (10fs)
signal CLK20MHz: std_logic;-- 20MHz clock (for I2S peripheral)
signal CLK12MHz: std_logic;-- 12MHz clock (MCLK for audio codec)

-----------signals for ROM interfacing---------------------
signal rom_clk: std_logic;
signal rom_output: std_logic_vector(31 downto 0);
signal rom_ADDR: std_logic_vector(19 downto 0);

signal instruction_memory_output: std_logic_vector(31 downto 0);
signal instruction_memory_address: std_logic_vector(31 downto 0);
signal instruction_latched: std_logic;
signal instruction_upper_half_latched: std_logic;
signal instruction_lower_half_latched: std_logic;
signal i_cache_ready: std_logic;
signal i_cache_ready_sync: std_logic;--i_cache_ready synchronized to rising_edge(CLK)
signal all_ready: std_logic;--synchronized to rising_edge(CLK)
signal instruction_clk: std_logic;
signal instruction_memory_addr: std_logic_vector(19 downto 0);
signal instruction_memory_Q: std_logic_vector(31 downto 0);
signal instruction_memory_wren: std_logic;
signal instruction_memory_rden: std_logic;
signal instruction_memory_write_data: std_logic_vector(15 downto 0);

-----------signals for d_cache interfacing---------------------
signal program_data_Q: std_logic_vector(31 downto 0);
signal program_data_address: std_logic_vector(18 downto 0);--ram address translated to instruction address
signal program_data_wren: std_logic;
signal program_data_rden: std_logic;
signal program_data_ready: std_logic;

-----------signals for RAM interfacing---------------------
---processor sees all memory-mapped I/O as part of RAM-----
constant N: integer := 9;-- size in bits of data addresses (each address refers to a 32 bit word)
signal ram_clk: std_logic;--data memory clock signal
signal ram_addr: std_logic_vector(31 downto 0);
signal ram_rden: std_logic;
signal ram_wren: std_logic;
signal ram_write_data: std_logic_vector(31 downto 0);
signal d_cache_ready: std_logic;
signal d_cache_ready_sync: std_logic;--d_cache_ready synchronized to rising_edge(CLK)
--signal ram_Q: std_logic_vector(31 downto 0);
signal ram_Q_buffer_in: std_logic_vector(31 downto 0);
signal ram_Q_buffer_out: std_logic_vector(31 downto 0);

-----------signals for (parallel) cache interfacing--------
signal cache_Q: std_logic_vector(31 downto 0);
signal cache_parallel_write_data: array32 (0 to 2**(5)-1);--because cache has 32 addresses
signal cache_fill_cache: std_logic;
signal cache_rden: std_logic;
signal cache_wren: std_logic;

-----------signals for FIFO interfacing---------------------
constant F: integer := 2**(6);--fifo depth (twice the cache's size)
signal fifo_clock: std_logic;
signal fifo_input: std_logic_vector (31 downto 0);
signal fifo_output: array32 (0 to (2**(5))-1);--because cache has 32 addresses 

--signal fifo_valid: std_logic_vector(F-1 downto 0);
signal fifo_invalidate_output: std_logic;

--signals for coefficients memory----------------------------
--constant P: natural := 2;
constant P: natural := 3;
--constant Q: natural := 2;
--constant Q: natural := 0;--forces  FIR filter
constant Q: natural := 4;
signal coeffs_mem_Q: std_logic_vector(31 downto 0);--signal for single coefficient reading
signal coefficients: array32 (P+Q downto 0);
signal coeffs_mem_wren: std_logic;
signal coeffs_mem_rden: std_logic;
--signal coeffs_mem_parallel_rden: std_logic;
signal coeffs_mem_parallel_wren: std_logic;
signal coeffs_mem_vector_bus: array32 (0 to 7);--data bus for parallel write of 8 fp32

--signals for inner_product----------------------------------
signal inner_product_result: std_logic_vector(31 downto 0);
signal inner_product_rden: std_logic;
signal inner_product_wren: std_logic;
signal inner_product_ready:std_logic;
--signal inner_product_parallel_rden_A: std_logic;
signal inner_product_parallel_wren_A: std_logic;
--signal inner_product_parallel_rden_B: std_logic;
signal inner_product_parallel_wren_B: std_logic;
signal inner_product_vector_bus_A: array32 (0 to 7);--data bus for parallel write of 8 fp32
signal inner_product_vector_bus_B: array32 (0 to 7);--data bus for parallel write of 8 fp32

--signals for vmac-------------------------------------------
signal vmac_Q: std_logic_vector(31 downto 0);
signal vmac_rden: std_logic;
signal vmac_wren: std_logic;--enables write on individual registers
signal vmac_en:	std_logic;--enables accumulation
--signal vmac_parallel_rden_A: std_logic;
--signal vmac_parallel_rden_B: std_logic;
signal vmac_parallel_wren_A: std_logic;
signal vmac_parallel_wren_B: std_logic;
signal vmac_vector_bus_A: array32 (0 to 7);--data bus for parallel write of 8 fp32
signal vmac_vector_bus_B: array32 (0 to 7);--data bus for parallel write of 8 fp32

--signals for filter_xN--------------------------------------
signal filter_xN_CLK: std_logic;-- must be the same frequency as filter clock, but can't be the same polarity
signal filter_xN_Q: std_logic_vector(31 downto 0) := (others=>'0');
signal filter_xN_rden: std_logic;
signal filter_xN_wren: std_logic;
--signal filter_xN_parallel_rden: std_logic;
signal filter_xN_parallel_wren: std_logic;
signal filter_xN_vector_bus: array32 (0 to 7);--data bus for parallel write of 8 fp32

--signals for filter_out-------------------------------------
signal filter_out_Q: std_logic_vector(31 downto 0);-- register containing current filter output
signal filter_out_rden: std_logic;-- not used, just to keep form
signal filter_out_wren: std_logic;-- not used, just to keep form

--signals for d_ff_desired-----------------------------------
signal d_ff_desired_Q: std_logic_vector(31 downto 0);-- register containing desired response
signal d_ff_desired_rden: std_logic;-- not used, just to keep form
signal d_ff_desired_wren: std_logic;-- not used, just to keep form

--signals for filter_ctrl_status-----------------------------------
signal filter_enable: std_logic;--bit 0, enables filter_CLK
signal filter_ctrl_status_Q: std_logic_vector(31 downto 0);-- register containing filter status of convergency
signal filter_ctrl_status_rden: std_logic;-- not used, just to keep form
signal filter_ctrl_status_wren: std_logic;

--signals for interrupt controller----------------------------
signal irq_ctrl_Q: std_logic_vector(31 downto 0);-- register containing filter status of convergency
signal irq_ctrl_rden: std_logic;-- not used, just to keep form
signal irq_ctrl_wren: std_logic;
signal irq: std_logic;
signal iack: std_logic;
signal all_irq: std_logic_vector(3 downto 0);
signal all_iack: std_logic_vector(3 downto 0);
signal ISR_ADDR: std_logic_vector(31 downto 0);

--signals for fp32_to_integer----------------------------------
constant audio_resolution: natural := 16;
signal fp_in: std_logic_vector(31 downto 0);
signal fp_in_new_exponent: std_logic_vector(7 downto 0);
signal fpu_denominator: std_logic_vector(31 downto 0);
signal fp32_div0: std_logic;
signal fp32_ovf: std_logic;
signal fp32_undf: std_logic;
signal fp32_to_int_out: std_logic_vector(audio_resolution-1 downto 0);
signal fp32_to_int_out_gain: std_logic_vector(audio_resolution+4 downto 0);--5 bit more than fp32_to_int_out (overflow detection)
signal left_padded_fp32_to_int_out_gain: std_logic_vector(31 downto 0);--fp32_to_int_out_gain left padded with zeroes

--signals for converted_out----------------------------------
signal converted_out_Q: std_logic_vector(31 downto 0);-- register containing current filter output converted to 2's complement
signal converted_out_rden: std_logic;-- not used, just to keep form
signal converted_out_wren: std_logic;-- not used, just to keep form

--signals for I2C----------------------------------
signal i2c_rden: std_logic;
signal i2c_wren: std_logic;
signal i2c_irq: std_logic;
signal i2c_iack: std_logic;
signal i2c_Q: std_logic_vector(31 downto 0);
--signal i2c_sda: std_logic;--open drain data line
--signal i2c_scl: std_logic;--open drain clock line

--signals for I2S----------------------------------
signal i2s_rden: std_logic;
signal i2s_wren: std_logic;
signal i2s_irq: std_logic;
signal i2s_iack: std_logic;
signal i2s_Q: std_logic_vector(31 downto 0);
signal i2s_SD: std_logic;--data line
signal i2s_WS: std_logic;--left/right clock
signal i2s_SCK: std_logic;--continuous clock (bit clock)
signal i2s_SCK_IN_PLL_LOCKED: std_logic;--'1' if PLL that provides SCK_IN is locked

-----------signals for synchronizer chain -------------------
signal filter_irq_sync: std_logic_vector(1 downto 0);--filter_irq synchronized to ram_clk posedge
signal filter_output_sync: std_logic_vector(31 downto 0);--filter output synchronized to ram_CLK negedge

-----------signals for memory map interfacing----------------
constant ranges: boundaries := 	(--notation: base#value#
											(16#00#,16#07#),--filter coeffs
											(16#08#,16#0F#),--filter xN
											(16#10#,16#17#),--cache
											(16#20#,16#3F#),--inner_product
											(16#40#,16#5F#),--VMAC
											(16#60#,16#67#),--I2C
											(16#68#,16#6F#),--I2S
											(16#70#,16#70#),--current filter output
											(16#71#,16#71#),--desired response
											(16#72#,16#72#),--filter status
											(16#73#,16#73#),--converted_out
											(16#74#,16#74#),-- 7-segments display DR
											(16#75#,16#75#),-- LCD controller
											(16#80#,16#FF#),--interrupt controller
											(16#400#,16#7FF#)--instruction memory
											);
signal all_periphs_output: array32 (ranges'length-1 downto 0);
signal all_periphs_rden: std_logic_vector(ranges'length-1 downto 0);
signal all_periphs_wren: std_logic_vector(ranges'length-1 downto 0);
signal all_periphs_ready: std_logic_vector(ranges'length-1 downto 0);

signal filter_CLK: std_logic;
signal filter_CLK_n: std_logic;--filter_CLK inverted
signal filter_CLK_syncd_uproc: std_logic;-- filter_CLK synchronized to uproc_CLK rising edge
signal filter_parallel_wren: std_logic;
signal filter_rst: std_logic := '1';
signal filter_input: std_logic_vector(31 downto 0);
signal filter_output: std_logic_vector(31 downto 0);
signal filter_output_reg: std_logic_vector(31 downto 0);
signal filter_irq: std_logic_vector(1 downto 0);
signal filter_iack: std_logic_vector(1 downto 0);
signal filter_iack_received: std_logic_vector(1 downto 0);
signal filter_iack_received_proc: std_logic_vector(1 downto 0);
signal filter_iack_send_proc: std_logic_vector(1 downto 0);
signal proc_filter_parallel_wren: std_logic;

--signals  for 7-segment register
signal disp_7seg_DR_in: std_logic_vector(31 downto 0);
signal disp_7seg_DR_out: std_logic_vector(31 downto 0);
signal disp_7seg_DR_wren: std_logic;
signal disp_7seg_DR_rden: std_logic;
signal disp_7seg_DR_cnt: std_logic_vector(2 downto 0);--counter for switching between nibbles (0 to 7)
signal disp_7seg_DR_nibble: std_logic_vector(3 downto 0);--used if one nibble is displayed at a time
--signal disp_7seg_DR_code: std_logic_vector(6 downto 0);--used if one code is computed at a time
signal disp_7seg_DR_code: array7(7 downto 0);--used if one code is computed at a time

--signals for LCD controller
signal lcd_Q: std_logic_vector(31 downto 0);
signal lcd_wren: std_logic;
signal lcd_ready: std_logic;

--signals for vector transfers
signal lvec: std_logic;
signal lvec_src: std_logic_vector(2 downto 0);
signal lvec_dst_mask: std_logic_vector(6 downto 0);
signal vector_bus: array32 (0 to 7);--shared data bus for parallel write of 8 fp32
--signal vector_bus_inputs: array_of_std_logic_vector;--shared data bus for parallel write of 8 fp32

signal filter_CLK_state: std_logic := '0';--starts in zero, changes to 1 when first rising edge of filter_CLK occurs
signal send_cache_request: std_logic;
signal mmu_irq: std_logic;
signal mmu_iack: std_logic;

signal sda_dbg_s: natural;--for debug, which statement is driving SDA
	begin

	rst <= not rst_n_sync_uproc;
	
	--debug outputs
	LEDR <= (17 downto 5 =>'0') & fp32_ovf & fp32_undf & fp32_div0 & filter_rst & rst;
	LEDG <= (8 downto 4 =>'0') & "00" & filter_CLK_state & i2s_SCK_IN_PLL_LOCKED;
	EX_IO <= ram_clk & filter_rst & I2C_SDAT & I2C_SCLK & "000";
	GPIO <= (35 downto 16 => '0') & filter_parallel_wren & i2s_irq & AUD_BCLK & AUD_DACDAT & AUD_DACLRCK & filter_irq(0) &
											filter_CLK & CLK & instruction_memory_address(7 downto 0);
	
	CLK_n <= not CLK;
	
	--it is necessary to translate the ram address associated with d_cache (starting at 0x400)
	--to an instruction address (starting at 0)
	program_data_address <= ram_addr(18 downto 0) - ranges(14)(0);
	d_cache: cache
		generic map (REQUESTED_SIZE => 128, MEM_WIDTH=> 16, MEM_LATENCY=> 1, REGISTER_ADDR=> false)--user requested cache size, in 32 bit words
		port map (
				req_ADDR => program_data_address,--address of requested data/instruction
				req_rden => program_data_rden,
				req_wren => program_data_wren,
				req_data_in => ram_write_data,
				CLK => CLK,--processor clock for reading instructions, must run even if cache is not ready
				mem_I => sram_IO,--data coming from SRAM for write
				mem_CLK => sram_CLK,--clock for reading embedded RAM
				RST => rst,--reset to prevent reading while sram is written (must be synchronous to sram_CLK)
				mem_ADDR => instruction_memory_addr,--address for write
				req_ready => program_data_ready,--indicates that instruction already contains the requested instruction
				mem_WREN => instruction_memory_wren,
				mem_O		=> instruction_memory_write_data,
				data => program_data_Q--fetched data
		);
	process(i_cache_ready,d_cache_ready,CLK)
	begin
		if(RST='1')then
			all_ready <= '1';
		elsif(falling_edge(CLK))then--reprocuces delay in clk_enable
			all_ready <= i_cache_ready and d_cache_ready_sync;
		end if;
	end process;
	
	--MINHA ESTRATEGIA É EXECUTAR CÁLCULOS NA SUBIDA DE CLK E GRAVAR NA MEMÓRIA NA BORDA DE DESCIDA
	ram_clk <= CLK;
	mini_ram_cache: mini_ram 	generic map (N => 3)
							port map(CLK	=> ram_clk,
										ADDR	=> ram_addr(2 downto 0),
										write_data => ram_write_data,
										rden	=> cache_rden,
										wren	=> cache_wren,
										Q		=> cache_Q);
	
-----------------FLASH interfacing---------------------
	flash_CE_n <= '0';--chip always enabled
	flash_OE_n <= '0';--output always enabled
	flash_WE_n <= '1';--reading always enabled
	flash_WP_n <= '1';--write protection always disabled
	flash_RST_n <= rst_n;--system reset resets flash to read mode

	flash_reading: process(CLK,filter_rst,flash_reading_state,flash_count,filter_CLK_syncd_uproc,rst)
	begin
		if(rst='1')then
			flash_reading_state <= "1001";
		elsif(filter_CLK_syncd_uproc='1')then
			flash_reading_state <= "1001";
		elsif(rising_edge(CLK) and filter_rst='0') then
			if (flash_reading_state(3)/='1')then--"1000" or "1001"
				flash_reading_state <= flash_reading_state + 1;
			elsif (flash_reading_state="1001") then
				flash_reading_state <= "0000";
			end if;
		end if;
		
		--flash_ADDR will update immediately when flash_reading_state changes
		if (rst='1')then
			flash_ADDR <= (others=>'0');
		elsif (flash_reading_state(3)/='1')then--NOT ("1000" or "1001")
			flash_ADDR <= flash_reading_state(0) & flash_count & flash_reading_state(2 downto 1);--data is launched
		else-- IS "1000" or "1001"			
			flash_ADDR <= (others=>'0');
		end if;
	end process;
	
	--index of sample being fetched
	--generates address for reading FLASH
	--counts from 0 to 1M-1
	fl_counter: process(rst,filter_rst,filter_CLK)
	begin
		if(rst='1' or filter_rst='1')then
			flash_count <= (others=>'0');
		elsif(rising_edge(filter_CLK) and filter_rst='0')then--this ensures, flash_count is updated after used for flash_ADDR
			flash_count <= flash_count + 1;
		end if;
	end process;
	
	process(CLK,rst,flash_ADDR,filter_rst,flash_reading_state)
	begin
		if(rst='1')then
			data_in <= (others=>'0');
			desired <= (others=>'0');
		--flash_ADDR is updated at rising_edge, must wait at least 10 ns to latch valid data
		elsif (falling_edge(CLK) and filter_rst='0' and flash_reading_state(3)='0') then--data is latched
			if(flash_ADDR(22)='0')then--reading input vectors
				if(flash_ADDR(1 downto 0)="00")then--reading byte 0
					data_in(7 downto 0) <= flash_IO;
				elsif(flash_ADDR(1 downto 0)="01")then--reading byte 1
					data_in(15 downto 8) <= flash_IO;
				elsif(flash_ADDR(1 downto 0)="10")then--reading byte 2
					data_in(23 downto 16) <= flash_IO;
				else--reading byte 3
					data_in(31 downto 24) <= flash_IO;
				end if;
			else--reading desired vectors
				if(flash_ADDR(1 downto 0)="00")then--reading byte 0
					desired(7 downto 0) <= flash_IO;
				elsif(flash_ADDR(1 downto 0)="01")then--reading byte 1
					desired(15 downto 8) <= flash_IO;
				elsif(flash_ADDR(1 downto 0)="10")then--reading byte 2
					desired(23 downto 16) <= flash_IO;
				else--reading byte 3
					desired(31 downto 24) <= flash_IO;
				end if;
			end if;
		end if;
	end process;
--------------------------------------------------------
-----------------SRAM interfacing---------------------
	sram_CE_n <= '0';--chip always enabled
	sram_OE_n <= '0';--output always enabled
	sram_UB_n <= '0';--upper byte always enabled
	sram_LB_n <= '0';--lower byte always enabled

	sram_ADDR_lower_half <= instruction_memory_address(18 downto 0) & '0';--address of lower half of instruction
	sram_ADDR_upper_half <= instruction_memory_address(18 downto 0) & '1';--address of upper	half of instruction

	sram_no_loader: if not sram_loader generate
		sram_WE_n <= 	'1' when i_cache_ready='0' else -- instruction fetching has priority over read/write access
							'0' when instruction_memory_wren='1' else-- enables software to update content
							'1';--reading always enabled
		i_cache: cache
			generic map (REQUESTED_SIZE => 1024, MEM_WIDTH=> 16, MEM_LATENCY=> 1, REGISTER_ADDR=> true)--user requested cache size, in 32 bit words
			port map (
					req_ADDR => instruction_memory_address(18 downto 0),--address of requested instruction
					req_rden => '1',
					CLK => instruction_clk,--processor clock for reading instructions, must run even if i_cache is not ready
					mem_I => sram_IO,--data coming from SRAM for write
					mem_CLK => sram_CLK,--clock for reading program memory
					RST => rst,--reset to prevent reading while sram is written (must be synchronous to sram_CLK)
					mem_ADDR => rom_ADDR,--address for reading
					req_ready => i_cache_ready,--indicates that instruction already contains the requested instruction
					data => instruction_memory_output--fetched instruction
			);
			
		sram_ADDR <= rom_ADDR when i_cache_ready='0' else instruction_memory_addr;
		sram_IO <= instruction_memory_write_data when sram_WE_n='0' else (others=>'Z');
		
		--synchronized asynchronous reset
		--asserted asynchronously
		--deasserted synchronously to the rising_edge of uproc_CLK
--		sync_async_reset_cache_ready: sync_chain
--		generic map (N => 1,--bus width in bits
--					L => 2)--number of registers in the chain
--		port map (
--				data_in(0) => '1',--data generated at another clock domain
--				CLK => CLK,--clock of new clock domain				
--				RST => not cache_ready,--asynchronous reset (asserted at rising_edge(sram_CLK), deasserted at rising_edge(CLK))
--				data_out(0) => cache_ready_sync --data synchronized in CLK domain
--		);
		i_cache_ready_sync <= i_cache_ready;
	
		--synchronized asynchronous reset
		--asserted asynchronously
		--deasserted synchronously to the rising_edge of uproc_CLK
		sync_async_reset_uproc: sync_chain
		generic map (N => 1,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in(0) => '1',--data generated at another clock domain
				CLK => CLK,--clock of new clock domain				
				RST => not rst_n,--asynchronous reset
				data_out(0) => rst_n_sync_uproc --data synchronized in CLK domain
		);
	end generate;
	
	sram_with_loader: if sram_loader generate
		program_memory: mini_rom port map(	CLK	=> sram_CLK,	
										RST	=> rst,--asynchronous reset
										--instruction interface (read-only)
										ADDR_A=> sram_loader_address,
										Q_A	=> sram_loader_data,--delayed from sram_loader_address by 1 sram_CLK cycle
										--data interface (read-write)
										D_B	=> (others=>'0'),
										ADDR_B=> (others=>'0'),
										WREN_B=> '0',
										Q_B	=> open
		);
		
		i_cache: cache
			generic map (REQUESTED_SIZE => 1024, MEM_WIDTH=> 16, MEM_LATENCY=> 1, REGISTER_ADDR=> true)--user requested cache size, in 32 bit words
			port map (
					req_ADDR => instruction_memory_address(18 downto 0),--address of requested instruction
					req_rden => '1',
					CLK => instruction_clk,--processor clock for reading instructions, must run even if i_cache is not ready
					mem_I => sram_IO,--data coming from SRAM for write
					mem_CLK => sram_CLK,--clock for reading embedded RAM
					RST => not sram_filled,--reset to prevent reading while sram is written (must be synchronous to sram_CLK)
					mem_ADDR => sram_ADDR_reading,--address for write
					req_ready => i_cache_ready,--indicates that instruction already contains the requested instruction
					data => instruction_memory_output--fetched instruction
			);
		i_cache_ready_sync <= i_cache_ready;
		
		sram_WE_n <= 	'0' when sram_filled_delayed='0' else -- after reset, SRAM must be filled before usage
							'1' when i_cache_ready='0' else -- instruction fetching has priority over read/write access
							'0' when instruction_memory_wren='1' else-- enables software to update content
							'1';--reading always enabled
		--process for reading/writing instructions at SRAM
		sram_reading: process(sram_CLK,sram_IO,CLK,rst_n_sync_sram_CLK,rst_n_sync_uproc,sram_filled_delayed,sram_ADDR_reading,sram_reading_state,instruction_latched,instruction_lower_half_latched,instruction_upper_half_latched,sram_loader_counter,sram_ADDR_lower_half,sram_ADDR_upper_half)
		begin
			if(sram_filled_delayed='0')then--reset is extended to store instructions in SRAM 
				sram_ADDR <= sram_loader_counter_delayed;
			elsif(i_cache_ready='0')then
				sram_ADDR <= sram_ADDR_reading;-- address for i_cache loading
			else
				sram_ADDR <= instruction_memory_addr;-- address for d_cache loading
			end if;
		end process;
		
--		sram_write_data <=sram_loader_data(15 downto 0) when (sram_filled='0' and sram_loader_counter(0)='0' and sram_loader_counter(19 downto 9) = (19 downto 9=>'0')) else
--								sram_loader_data(31 downto 16) when (sram_filled='0' and sram_loader_counter(0)='1' and sram_loader_counter(19 downto 9) = (19 downto 9=>'0')) else
--								(15 downto 0=>'0') when (sram_filled='0' and sram_loader_counter(19 downto 9) /= (19 downto 9=>'0'));
		all_sram_write_data <= (3 => (15 downto 0=>'0'),2=> (15 downto 0=>'0'),
										1=> sram_loader_data(31 downto 16),0=> sram_loader_data(15 downto 0));
		process(sram_CLK,sram_loader_counter)
		begin
			if(rising_edge(sram_CLK))then--delays the sel signal to account for mini_rom latency
				if sram_loader_counter(19 downto 9) /= (19 downto 9=>'0') then
					sram_write_data_sel(1) <= '1';
				else
					sram_write_data_sel(1) <= '0';
				end if;
				sram_write_data_sel(0) <= sram_loader_counter(0);
			end if;
		end process;
		sram_write_data_mux: mux
									generic map (N_BITS_SEL => 2)
									port map(A => all_sram_write_data,
												sel => sram_write_data_sel,
												Q => sram_write_data);
		sram_IO <=	sram_write_data when sram_filled_delayed='0' else
						instruction_memory_write_data when sram_WE_n='0' else
						(others=>'Z');
		sram_loader_address <= sram_loader_counter(8 downto 1);--address for mini_rom
		
		write_loop: process(rst_n_sync_sram_CLK,sram_CLK,sram_loader_counter)
			begin
				if(rst_n_sync_sram_CLK='0')then--using synchronous reset to ensure no problems with reset removal
					sram_loader_counter <= (others=>'0');
					sram_loader_counter_delayed <= (others=>'0');
					sram_filled <= '0';
					sram_filled_delayed <= '0';
				elsif(rising_edge(sram_CLK))then--period is 12.5 ns, enough for writes
					if(sram_loader_counter /= (8 downto 0 =>'1'))then
						sram_loader_counter <= sram_loader_counter + 1;
					else
						sram_filled <= '1';--when sram_loader_counter = xFFFFF
					end if;
					sram_filled_delayed <= sram_filled;
					sram_loader_counter_delayed <= sram_loader_counter;
				end if;
		end process;
		
		--synchronized asynchronous reset
		--asserted asynchronously
		--deasserted synchronously to the rising_edge of uproc_CLK
		sync_async_reset_uproc: sync_chain
		generic map (N => 1,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in(0) => '1',--data generated at another clock domain
				CLK => CLK,--clock of new clock domain				
				RST => not sram_filled,--asynchronous reset
				data_out(0) => rst_n_sync_uproc --data synchronized in CLK domain
		);
		--synchronized asynchronous reset
		--asserted asynchronously
		--deasserted synchronously to the falling_edge of sram_CLK
		sync_async_reset_sram_CLK: sync_chain
		generic map (N => 1,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in(0) => '1',--data generated at another clock domain
				CLK => sram_CLK_n,--clock of new clock domain				
				RST => not rst_n,--asynchronous reset
				data_out(0) => rst_n_sync_sram_CLK --data synchronized in CLK domain
		);
		sram_CLK_n <= not sram_CLK;
	end generate;
	
	instruction_latched <= instruction_lower_half_latched and instruction_upper_half_latched;
--------------------------------------------------------
	filter_CLK_n <= not filter_CLK;
	
	-- synchronizes desired to rising_edge of CLK, because:
	--1: filter_CLK is generated at filter_CLK domain
	--2: this signal is used to reset flash_reading_state (in CLK domain)
	sync_chain_filter_CLK: sync_chain
		generic map (N => 1,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in(0) => filter_CLK,--data generated at another clock domain
				CLK => CLK,--clock of new clock domain				
				RST => rst,--asynchronous reset
				data_out(0) => filter_CLK_syncd_uproc --data synchronized in CLK domain
		);

	-- synchronizes desired to rising_edge of ram_CLK, because:
	--1: desired is generated at filter_CLK domain
	--2: this signal is sampled by processor at rising_edge of CLK
	sync_chain_desired: sync_chain
		generic map (N => 32,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => desired,--data generated at another clock domain
				CLK => ram_CLK,--clock of new clock domain				
				RST => rst,--asynchronous reset
				data_out => desired_sync --data synchronized in CLK domain
		);
		
	--vector_bus multiplexer
	-- index 1 was skipped because refers to filter internal coefficients
	vector_bus <= 	coeffs_mem_vector_bus when (lvec='1' and lvec_src="000") else
						filter_xN_vector_bus when (lvec='1' and lvec_src="010") else
						inner_product_vector_bus_A when (lvec='1' and lvec_src="011") else
						inner_product_vector_bus_B when (lvec='1' and lvec_src="100") else
						vmac_vector_bus_A when (lvec='1' and lvec_src="101") else
						vmac_vector_bus_B when (lvec='1' and lvec_src="110") else
						(others=>(others => '0'));
--	vector_bus <= 	open_drain(coeffs_mem_vector_bus) when (lvec='1' and lvec_src="000") else (others=>(others => 'Z'));
--	vector_bus <= 	open_drain(filter_xN_vector_bus) when (lvec='1' and lvec_src="010") else (others=>(others => 'Z'));
--	vector_bus <= 	open_drain(inner_product_vector_bus_A) when (lvec='1' and lvec_src="011") else (others=>(others => 'Z'));
--	vector_bus <= 	open_drain(inner_product_vector_bus_B) when (lvec='1' and lvec_src="100") else (others=>(others => 'Z'));
--	vector_bus <= 	open_drain(vmac_vector_bus_A) when (lvec='1' and lvec_src="101") else (others=>(others => 'Z'));
--	vector_bus <= 	open_drain(vmac_vector_bus_B) when (lvec='1' and lvec_src="110") else (others=>(others => 'Z'));
	-- index 1 was skipped because refers to filter internal coefficients
--	vector_bus_inputs <= (	0=> coeffs_mem_vector_bus, 2 => filter_xN_vector_bus, 3 => inner_product_vector_bus_A,
--									4=> inner_product_vector_bus_B, 5=> vmac_vector_bus_A, 6=> vmac_vector_bus_B,
--									others=> (others=>(others => '0')));
--	vector_bus_mux: mux
--						generic map (N_BITS_SEL => 4)
--						port map(A => vector_bus_inputs,
--									sel => ((not lvec) & lvec_src),
--									Q => vector_bus);
	
--	coeffs_mem_parallel_rden <= '1' when (lvec='1' and lvec_src="000") else '0';
	coeffs_mem_parallel_wren <= lvec_dst_mask(0);
	coeffs_mem: generic_coeffs_mem generic map (N=> 3, P => P,Q => Q)
									port map(D => ram_write_data,
												ADDR	=> ram_addr(2 downto 0),
												RST => rst,
												RDEN	=> coeffs_mem_rden,
												WREN	=> coeffs_mem_wren,
												CLK	=> ram_clk,
--												filter_CLK => filter_CLK,
--												filter_WREN => filter_parallel_wren,
												parallel_write_data => vector_bus,
--												parallel_rden => coeffs_mem_parallel_rden,
												parallel_wren => coeffs_mem_parallel_wren,
												parallel_read_data => coeffs_mem_vector_bus,
												Q_coeffs => coeffs_mem_Q,
												all_coeffs => coefficients
												);
												
	filter_CLK <= CLK_fs;
	proc_filter_parallel_wren <= lvec_dst_mask(1);
	IIR_filter: filter 	generic map (P => P, Q => Q)
								port map(input => filter_input,-- input
											RST => filter_rst,--synchronous reset
											WREN => filter_parallel_wren,--enables updating all coefficients at once
											CLK => filter_CLK,--sampling clock
											coeffs => coefficients,-- todos os coeficientes são lidos de uma vez
--											iack => filter_iack_received, --necessary complex mechanism to synchronize to filter_CLK (indeed, CLK_fs_dbg), sucetible to failure
											iack => filter_iack,--simpler, but produces CDC
											irq => filter_irq,
											output => filter_output											
											);
	filter_input <= data_in;
	
	process(filter_rst,filter_irq,filter_CLK,CLK_fs_dbg,filter_iack_send_proc)
	begin
		if (filter_rst='1') then
			filter_iack_received <= (others=>'0');
--		elsif(falling_edge(filter_CLK))then
		elsif(falling_edge(CLK_fs_dbg))then
			if (filter_CLK='1') then
				--accepts iack of irq(0) only during filter_CLK positive semicycle
				filter_iack_received(0) <= filter_iack_send_proc(0);
				filter_iack_received(1) <= '0';
			elsif (filter_CLK='0') then
				--accepts iack of irq(1) only during filter_CLK negative semicycle
				filter_iack_received(0) <= '0';
				filter_iack_received(1) <= filter_iack_send_proc(1);
			end if;
		end if;
	end process;
	
	-- synchronizes filter_iack_received to rising_edge of CLK, because:
	--1: filter_iack_received is generated at CLK_fs_dbg domain
	--2: this signal is sampled in filter_iack_send_proc at rising_edge of ram_CLK
	sync_chain_filter_iack_received: sync_chain
		generic map (N => 2,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => filter_iack_received,--data generated at another clock domain
				CLK => CLK,--clock of new clock domain
				RST => rst,--asynchronous reset
				data_out => filter_iack_received_proc --data synchronized in CLK domain
		);
	
	--must extend filter_iack until receives the filter_iack_received_proc='1'
	process(rst,CLK,filter_iack,filter_iack_received_proc)
	begin
		if (rst='1') then
			filter_iack_send_proc <= (others=>'0');
		elsif(rising_edge(CLK))then
			--flag is raised
			if (filter_iack/="00") then
				filter_iack_send_proc <= filter_iack;
			--flag is cleared
			elsif (filter_iack_received_proc/="00") then
				filter_iack_send_proc <= filter_iack_send_proc and (not filter_iack_received_proc);--zeroes the IRQ lineas acked
			end if;
		end if;
	end process;		

	-- synchronizes filter output to rising_edge of CLK, because:
	--1: filter output is generated at filter_CLK domain
	--2: this signal is sampled in filter_out at rising_edge of ram_CLK
	sync_chain_filter_output: sync_chain
		generic map (N => 32,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => filter_output,--data generated at another clock domain
				CLK => ram_clk,--clock of new clock domain
				RST => rst,--asynchronous reset
				data_out => filter_output_sync --data synchronized in CLK domain
		);
		filter_out_Q <= filter_output_sync;
					
	filter_ctrl_status: d_flip_flop
	 port map(	D => ram_write_data,--written by software
					RST=> RST,--resets all previous history of filter output
					ENA=> filter_ctrl_status_wren,
					CLK=>ram_clk,--must be the same as filter_CLK
					Q=> filter_ctrl_status_Q
					);
	filter_enable <= filter_ctrl_status_Q(0);--bit 0 enables filter_CLK
					
	filter_reset_process: process (filter_CLK,RST,filter_CLK_state,filter_enable,i2s_SCK_IN_PLL_LOCKED)
	begin
		if(RST='1')then
			filter_rst <='1';
			filter_CLK_state <= '0';
		else
			if (rising_edge(filter_CLK) and i2s_SCK_IN_PLL_LOCKED='1') then--pll_audio must be locked
				filter_CLK_state <= '1';
			end if;
			if (falling_edge(filter_CLK) and filter_CLK_state = '1' and filter_enable='1' and i2s_SCK_IN_PLL_LOCKED='1') then
					filter_rst <= '0';
			end if;
		end if;
	end process filter_reset_process;

	process(RST,proc_filter_parallel_wren,filter_CLK)
	begin
		if(proc_filter_parallel_wren=	'1')then
			filter_parallel_wren <= '1';
		elsif(rising_edge(filter_CLK))then--next rising_edge of filter means next sample, so filter_parallel_wren must be reset
			filter_parallel_wren <= '0';
		end if;
	end process;
	
	-- must be the clock of filter output updating
	filter_xN_CLK <= not filter_CLK;
--	filter_xN_parallel_rden <= '1' when (lvec='1' and lvec_src="010") else '0';
	filter_xN_parallel_wren <= lvec_dst_mask(2);
	xN: filter_xN
	-- 0..P: índices dos x
	-- P+1..P+Q: índices dos y
	generic map (N => 3, P => P, Q => Q)--N: address width in bits (must be >= log2(P+1+Q))
	port map (	D => ram_write_data,-- not used (peripheral supports only read)
			DX => filter_input,--current filter input
			DY => filter_output,--current filter output
			ADDR => ram_addr(2 downto 0),-- input
			CLK_x => filter_CLK,
--			CLK_y => filter_xN_CLK,-- must be the same frequency as filter clock, but can't be the same polarity
			CLK_y => filter_CLK,--IF using registered filter_output
			RST => filter_rst,
			WREN => filter_xN_wren,--not used (peripheral supports only read)
			RDEN => filter_xN_rden,-- input
			parallel_write_data => vector_bus,
--			parallel_rden => filter_xN_parallel_rden,
			parallel_wren => filter_xN_parallel_wren,
			parallel_read_data => filter_xN_vector_bus,
			output => filter_xN_Q-- output
			);

--	inner_product_parallel_rden_A <= '1' when (lvec='1' and lvec_src="011") else '0';
--	inner_product_parallel_rden_B <= '1' when (lvec='1' and lvec_src="100") else '0';
	inner_product_parallel_wren_A <= lvec_dst_mask(3);
	inner_product_parallel_wren_B <= lvec_dst_mask(4);
	inner_product: inner_product_calculation_unit
	generic map (N => 5)
	port map(D => ram_write_data,--supposed to be normalized
				ADDR => ram_addr(4 downto 0),
				CLK => ram_clk,
				RST => rst,
				WREN => inner_product_wren,
				RDEN => inner_product_rden,
				parallel_write_data => vector_bus,
--				parallel_rden_A => inner_product_parallel_rden_A,
				parallel_wren_A => inner_product_parallel_wren_A,
--				parallel_rden_B => inner_product_parallel_rden_B,
				parallel_wren_B => inner_product_parallel_wren_B,
				parallel_read_data_A => inner_product_vector_bus_A,
				parallel_read_data_B => inner_product_vector_bus_B,
				-------NEED ADD FLAGS (overflow, underflow, etc)
				--overflow:		out std_logic,
				--underflow:		out std_logic,
				ready => inner_product_ready,--synchronous to rising_edge(CLK)
				output => inner_product_result
				);
				
--	vmac_parallel_rden_A <= '1' when (lvec='1' and lvec_src="101") else '0';
--	vmac_parallel_rden_B <= '1' when (lvec='1' and lvec_src="110") else '0';
	vmac_parallel_wren_A <= lvec_dst_mask(5);
	vmac_parallel_wren_B <= lvec_dst_mask(6);
	vmac: vectorial_multiply_accumulator_unit
	generic map (N => 5)
	port map(D => ram_write_data,
				ADDR => ram_addr(4 downto 0),
				CLK => ram_clk,
				RST => rst,
				WREN => vmac_wren,
				RDEN => vmac_rden,
				VMAC_EN => vmac_en,
				parallel_write_data => vector_bus,
--				parallel_rden_A => vmac_parallel_rden_A,
				parallel_wren_A => vmac_parallel_wren_A,
--				parallel_rden_B => vmac_parallel_rden_B,
				parallel_wren_B => vmac_parallel_wren_B,
				parallel_read_data_A => vmac_vector_bus_A,
				parallel_read_data_B => vmac_vector_bus_B,
				-------NEED ADD FLAGS (overflow, underflow, etc)
				--overflow:		out std_logic,
				--underflow:		out std_logic,
				output => vmac_Q
	);
	
	fp32_to_int: fp32_to_integer
	generic map (N=> audio_resolution)
	port map (fp_in => fp_in,
				 output=> fp32_to_int_out);
				 
--	fp32_attenuation: fpu_divider
--	port map(A => filter_output_sync,
--				B => fpu_denominator,
--				overflow	=> fp32_ovf,
--				underflow=> fp32_undf,
--				divideByZero=> fp32_div0,
--				result=> fp_in				
--				);
	fp_in <= filter_output_sync;
	
	--Switches are used to select fp_in division (preventing saturation) and fp32_to_int_out gain
--	process(fp32_to_int_out_gain,fp32_to_int_out,SW)
--	begin
--		if(SW(1 downto 0)="00")then
--			fpu_denominator <= x"3F80_0000";-- +1.0, decreases by 0 dB
--			fp32_to_int_out_gain <= (audio_resolution+4 downto audio_resolution => fp32_to_int_out(audio_resolution-1)) & fp32_to_int_out;--increases 0 dB, sign extension
--		elsif(SW(1 downto 0)="01")then
--			fpu_denominator <= x"4000_0000";-- +2.0, decreases by 6 dB
--			fp32_to_int_out_gain <= std_logic_vector(signed(fp32_to_int_out) * to_signed(2,5));--increases 6 dB
--			--detection of overflow
--			if(fp32_to_int_out_gain(audio_resolution+2 downto audio_resolution-1) /= (3 downto 0 => fp32_to_int_out(audio_resolution-1)))then
--				fp32_to_int_out_gain <= (audio_resolution+4 downto audio_resolution-1 => fp32_to_int_out(audio_resolution-1), others=> not fp32_to_int_out(audio_resolution-1));
--			end if;
--		elsif(SW(1 downto 0)="10")then
--			fpu_denominator <= x"4080_0000";-- +4.0, decreases by 12 dB
--			fp32_to_int_out_gain <= std_logic_vector(signed(fp32_to_int_out) * to_signed(4,5));--increases 12 dB
--			--detection of overflow
--			if(fp32_to_int_out_gain(audio_resolution+2 downto audio_resolution-1) /= (3 downto 0 => fp32_to_int_out(audio_resolution-1)))then
--				fp32_to_int_out_gain <= (audio_resolution+4 downto audio_resolution-1 => fp32_to_int_out(audio_resolution-1), others=> not fp32_to_int_out(audio_resolution-1));
--			end if;
--		else-- SW(1 downto 0)="11"
--			fpu_denominator <= x"4100_0000";-- +8.0, decreases by 18 dB
--			fp32_to_int_out_gain <= std_logic_vector(signed(fp32_to_int_out) * to_signed(8,5));--increases 18 dB
--			--detection of overflow
--			if(fp32_to_int_out_gain(audio_resolution+2 downto audio_resolution-1) /= (3 downto 0 => fp32_to_int_out(audio_resolution-1)))then
--				fp32_to_int_out_gain <= (audio_resolution+4 downto audio_resolution-1 => fp32_to_int_out(audio_resolution-1), others=> not fp32_to_int_out(audio_resolution-1));
--			end if;
--		end if;
--	end process;
	fp32_to_int_out_gain <= (audio_resolution+4 downto audio_resolution=> fp32_to_int_out(audio_resolution-1)) & fp32_to_int_out;

	left_padded_fp32_to_int_out_gain <= (31 downto audio_resolution => '0') & fp32_to_int_out_gain(audio_resolution-1 downto 0);
	converted_output: d_flip_flop
	 port map(	D => left_padded_fp32_to_int_out_gain,
					RST=> RST,--resets all previous history of filter output
					CLK=>ram_clk,--sampling clock, must be much faster than filter_CLK
					Q=> converted_out_Q
	);

	i2c: i2c_master
	port map(D => ram_write_data,
				ADDR => ram_addr(2 downto 0),
				CLK => ram_clk,
				RST => rst,
				WREN => i2c_wren,
				RDEN => i2c_rden,
				IACK => i2c_iack,
				Q => i2c_Q, --for register read
				IRQ => i2c_irq,
				SDA => I2C_SDAT, --open drain data line
				sda_dbg_p => sda_dbg_s,
				SCL => I2C_SCLK --open drain clock line
			);

	
	AUD_BCLK <= i2s_SCK;
	AUD_DACDAT <= i2s_SD;
	AUD_DACLRCK <= i2s_WS;
	i2s: i2s_master_transmitter
	port map (
				D => ram_write_data,
				ADDR => ram_addr(2 downto 0),
				CLK => ram_clk,
				RST => rst,
				WREN => i2s_wren,
				RDEN => i2s_rden,
				IACK => i2s_iack,
				Q => i2s_Q,--for register read
				IRQ => i2s_irq,
				SCK_IN => CLK20MHz,
				SCK_IN_PLL_LOCKED => i2s_SCK_IN_PLL_LOCKED,--'1' if PLL that provides SCK_IN is locked
				SD => i2s_SD, --data line
				WS => i2s_WS, --left/right clock
				SCK => i2s_SCK --continuous clock (bit clock)
		);		
	MCLK <= CLK12MHz;--master clock for audio codec in USB mode
	
	all_periphs_ready		<= (14=> program_data_ready, 12=> lcd_ready, 3=> inner_product_ready, others=>'1');
	all_periphs_output	<= (14=> program_data_Q, 13 => irq_ctrl_Q, 12=> lcd_Q, 11 => disp_7seg_DR_out, 10 => converted_out_Q, 9 => filter_ctrl_status_Q, 8 => desired_sync, 7 => filter_out_Q, 6 => i2s_Q,
									 5 => i2c_Q, 4 => vmac_Q, 3 => inner_product_result,	2 => cache_Q,	1 => filter_xN_Q,	0 => coeffs_mem_Q);
	--for some reason, the following code does not work: compiles but connections are not generated
--	all_periphs_rden		<= (3 => inner_product_rden,	2 => cache_rden,	1 => filter_xN_rden,	0 => coeffs_mem_rden);
--	all_periphs_wren		<= (3 => inner_product_wren,	2 => cache_wren,	1 => filter_xN_wren,	0 => coeffs_mem_wren);

	program_data_rden			<= all_periphs_rden(14);-- not used, just to keep form
	irq_ctrl_rden				<= all_periphs_rden(13);-- not used, just to keep form
--	irq_ctrl_rden				<= all_periphs_rden(12);-- not used, just to keep form
	disp_7seg_DR_rden			<= all_periphs_rden(11);-- not used, just to keep form
	converted_out_rden		<= all_periphs_rden(10);-- not used, just to keep form
	filter_ctrl_status_rden	<= all_periphs_rden(9);-- not used, just to keep form
	d_ff_desired_rden			<= all_periphs_rden(8);-- not used, just to keep form
	filter_out_rden			<= all_periphs_rden(7);-- not used, just to keep form
	i2s_rden						<= all_periphs_rden(6);
	i2c_rden						<= all_periphs_rden(5);
	vmac_rden					<=	all_periphs_rden(4);
	inner_product_rden		<= all_periphs_rden(3);
	cache_rden					<= all_periphs_rden(2);
	filter_xN_rden				<= all_periphs_rden(1);
	coeffs_mem_rden			<= all_periphs_rden(0);

	program_data_wren			<= all_periphs_wren(14);
	irq_ctrl_wren				<= all_periphs_wren(13);
	lcd_wren						<= all_periphs_wren(12);
	disp_7seg_DR_wren			<= all_periphs_wren(11);
	converted_out_wren		<= all_periphs_wren(10);-- not used, just to keep form
	filter_ctrl_status_wren	<= all_periphs_wren(9);
	d_ff_desired_wren			<= all_periphs_wren(8);-- not used, just to keep form
	filter_out_wren			<= all_periphs_wren(7);-- not used, just to keep form
	i2s_wren						<= all_periphs_wren(6);
	i2c_wren						<= all_periphs_wren(5);
	vmac_wren					<= all_periphs_wren(4);
	inner_product_wren		<= all_periphs_wren(3);
	cache_wren					<= all_periphs_wren(2);
	filter_xN_wren				<= all_periphs_wren(1);
	coeffs_mem_wren			<= all_periphs_wren(0);

	memory_map: address_decoder_memory_map
	--N: word address width in bits
	--B boundaries: list of values of the form (starting address,final address) of all peripherals, written as integers,
	--list MUST BE "SORTED" (start address(i) < final address(i) < start address (i+1)),
	--values OF THE FORM: "(b1 b2..bN 0..0),(b1 b2..bN 1..1)"
	generic map (N => 11, B => ranges)
	port map (	ADDR => ram_addr(10 downto 0),-- input, it is a word address
			RDEN => ram_rden,-- input
			WREN => ram_wren,-- input
			data_in => all_periphs_output,-- input: outputs of all peripheral
			ready_in => all_periphs_ready,
			RDEN_OUT => all_periphs_rden,-- output
			WREN_OUT => all_periphs_wren,-- output
			ready_out => d_cache_ready,
			data_out => ram_Q_buffer_in-- data read
	);
	d_cache_ready_sync <= d_cache_ready;
	
	ram_Q_buffer_out <= ram_Q_buffer_in;
	
	processor: microprocessor
	port map (
		CLK_IN => CLK,
		rst => rst,
		irq => irq,
		iack => iack,
		return_value => open,
		ISR_addr => ISR_ADDR,--address for interrupt handler, loaded when irq is asserted, it is valid one clock cycle after the IRQ detection
		ADDR_rom => instruction_memory_address,
		i_cache_ready => i_cache_ready_sync,--synchronized to rising_edge(CLK)
		CLK_rom => instruction_clk,
		Q_rom => instruction_memory_output,
		ADDR_ram => ram_addr,
		write_data_ram => ram_write_data,
		rden_ram => ram_rden,
		wren_ram => ram_wren,
		d_cache_ready => d_cache_ready_sync,
		vmac_en => vmac_en,
		wren_lvec => lvec,
		lvec_src => lvec_src,
		lvec_dst_mask => lvec_dst_mask,
		Q_ram => ram_Q_buffer_out
	);	

	--patch replacing deffective sync chain
	filter_irq_sync <= filter_irq;
--	-- synchronizes IRQ to rising_edge of CLK, because:
--	-- 1: filter_irq is generated at filter_CLK domain
--	-- 2: this signal is sampled in irq_ctrl at falling_edge of CLK
--	sync_chain_filter_IRQ: sync_chain
--		generic map (N => 1,--bus width in bits
--					L => 2)--number of registers in the chain
--		port map (
--				data_in => (others=> filter_irq),--data generated at another clock domain
--				CLK => ram_clk,--clock of new clock domain
--				data_out => filter_irq_sync --data synchronized in CLK domain
--		);
		
	--filter_irq_sync is synchronized to ram_clk rising_edge by a sync chain in this level
	--i2s_irq is synchronized to ram_clk rising_edge inside I2S peripheral
	--aparently, i2c_irq is synchronized to ram_clk rising_edge because I2C clocks are created dividing ram_clk
--	all_irq	<= (3 => filter_irq_sync(1), 2 => i2s_irq, 1 => i2c_irq, 0 => filter_irq_sync(0));
	all_irq	<= (3 => filter_irq_sync(1), 2 => '0', 1 => i2c_irq, 0 => filter_irq_sync(0));
	i2s_iack	<= all_iack(2);										 
	i2c_iack	<= all_iack(1);
	filter_iack	<= all_iack(3) & all_iack(0);
	irq_ctrl: interrupt_controller_vectorized
	generic map (L => 4)--L: number of IRQ lines
	port map (	D => ram_write_data,-- input: data to register write
			ADDR => ram_addr(6 downto 0),
			CLK => ram_clk,-- input
			RST => RST,-- input
			WREN => irq_ctrl_wren,-- input
			RDEN => irq_ctrl_rden,-- input
			REQ_READY => all_ready,--synchronized to rising_edge(CLK)
			IRQ_IN => all_irq,--input: all IRQ lines
			IRQ_OUT => irq,--output: IRQ line to cpu
			IACK_IN => iack,--input: IACK line coming from cpu
			IACK_OUT => all_iack,--output: all IACK lines going to peripherals
			ISR_ADDR => ISR_ADDR,
			output => irq_ctrl_Q -- output of register reading
	);
	
	disp_7seg_DR_in <= ram_write_data;
	disp_7seg_DR: d_flip_flop port map(
		D => disp_7seg_DR_in,
		CLK => ram_clk,
		RST => RST,
		ENA => disp_7seg_DR_wren,
		Q => disp_7seg_DR_out
	);
	
		disp_7seg_drive: for i in 0 to 7 generate
		--the statement below consumes much logic because 8 muxes are inferred (16x7bit)
--		segments(i) <= not code_for_7seg(to_integer(unsigned(disp_7seg_DR_out(4*i+3 downto 4*i ))));
		
		--one nibble being translated at a time
		--ROM containing the codes (commands) to each digit
		mem_code_for_7seg_i : mem_code_for_7seg port map (
			address	=> disp_7seg_DR_out(4*i+3 downto 4*i),
			clock		=> ram_clk,
			q			=> disp_7seg_DR_code(i)
		);

		segments(i) <= not disp_7seg_DR_code(i);
--		segments(i) <= (6 downto 4 => '1') & disp_7seg_DR_out(4*i+3 downto 4*i);
	end generate disp_7seg_drive;
	
	lcd_ctrl: LCD_Controller port map (
		clk => ram_clk,
		rst => rst,
		-- interface with CPU
		D => ram_write_data,
		wren => lcd_wren,
		Q => lcd_Q,
		ready => lcd_ready,
		  
		  -- LCD control signals
		RS => open,--RS,
		RW => open,--RW,
		E => open,--E,
		VO => open,--VO,
		DB => open--DB
	);
	
	clk_dbg_uproc:	pll_dbg_uproc
	port map
	(
		areset=> '0',
		inclk0=> CLK_IN,
		c0		=> CLK_dbg,--produces 48MHz for debugging
		c1		=> CLK,--produces CLK=4MHz for processor
		c2		=> sram_CLK,--produces 4x the processor frequency, delayed (for 4MHz uproc, produces 16MHz delayed 31.25 ns)
		locked=> open
	);

	--produces 12MHz (MCLK) from 50MHz input
	clk_12MHz: pll_12MHz
	port map (
	inclk0 => CLK_IN,
	areset => '0',
	c0 => CLK12MHz
	);

	--produces 44118Hz (fs) and 20 MHz (for BCLK_IN) from 12MHz input
	clk_fs_sckin: pll_audio
	port map (
	inclk0 => CLK12MHz,
	areset => '0',
	c0 => CLK_fs,
	c1 => CLK20MHz,
	c2 => CLK_fs_dbg,--10x fs
	locked => i2s_SCK_IN_PLL_LOCKED
	);
	
	-- this instruction ROM is meant to be used only in simulation
	-- synthesis translate_off
	sram_sim: async_sram
	generic map (INIT => true, DATA_WIDTH => 16, ADDR_WIDTH => 20)
	port map(
		IO => sram_IO,
		ADDR=> sram_ADDR,
		CE_n=> sram_CE_n,
		OE_n=> sram_OE_n,
		WE_n=> sram_WE_n,
		UB_n=> sram_UB_n,
		LB_n=> sram_LB_n
	);
	-- synthesis translate_on
end setup;