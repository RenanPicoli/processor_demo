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
--		data_out: out std_logic_vector(31 downto 0);--filter output (encoded in IEEE 754 single precision)
		error: out std_logic;--filter output mismatches value obtained in modelsim
		--I2C
		I2C_SDAT: inout std_logic;--I2C SDA
		I2C_SCLK: inout std_logic;--I2C SCL
		sda_dbg_p: out natural;--for debug, which statement is driving SDA
		--I2S/codec
		MCLK: out std_logic;-- master clock output for audio codec (12MHz)
		AUD_BCLK: out std_logic;--SCK aka BCLK_IN
		AUD_DACDAT: out std_logic;--DACDAT aka SD
		AUD_DACLRCK: out std_logic;--DACLRCK aka WS
		--SRAM
		sram_IO: in std_logic_vector(15 downto 0);--sram data; input because we'll only read
		sram_ADDR: out std_logic_vector(19 downto 0);--ADDR for SRAM
		sram_CE_n: out std_logic;--chip enable, active LOW
		sram_OE_n: out std_logic;--output enable, active LOW
		sram_WE_n: out std_logic;--write enable, active LOW, HIGH enables reading
		sram_UB_n: out std_logic;--upper IO byte access, active LOW
		sram_LB_n: out std_logic; --lower	IO byte access, active LOW
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
generic (N: integer);--size in bits of data addresses 
port (CLK_IN: in std_logic;
		rst: in std_logic;
		irq: in std_logic;--interrupt request
		iack: out std_logic;--interrupt acknowledgement
		instruction_addr: out std_logic_vector (31 downto 0);--AKA read address
		-----ROM----------
		ADDR_rom: out std_logic_vector(7 downto 0);--addr é endereço de byte, mas os Lsb são 00
		Q_rom:	in std_logic_vector(31 downto 0);
		-----RAM-----------
		ADDR_ram: out std_logic_vector(N-1 downto 0);--addr é endereço de byte, mas os Lsb são 00
		write_data_ram: out std_logic_vector(31 downto 0);
		rden_ram: out std_logic;--habilita leitura na ram (cache e periféricos mapeados na ram)
		wren_ram: out std_logic;--habilita escrita na ram (cache e periféricos mapeados na ram)
		wren_filter: out std_logic;--habilita escrita nos coeficientes do filtro
		vmac_en: out std_logic;--multiply-accumulate enable
		send_cache_request: out std_logic;
		Q_ram:in std_logic_vector(31 downto 0)
);
end component;

component mini_rom
	port (--CLK: in std_logic;--borda de subida para escrita, se desativado, memória é lida
			ADDR: in std_logic_vector(7 downto 0);--addr é endereço de byte, mas os Lsb são 00
			Q:	out std_logic_vector(31 downto 0)
			);
end component;

-- * implements a FIFO for reading sensor data; and
-- * permits parallel reading of these data.
--component shift_register
--	generic (N: integer; OS: integer);--number of stages and number of stages in the output, respectively.
--	port (CLK: in std_logic;
--			rst: in std_logic;
--			D: in std_logic_vector (31 downto 0);
--			Q: out array32 (0 to OS-1));
--end component;

--component parallel_load_cache
--	generic (N: integer);--size in bits of address 
--	port (CLK: in std_logic;--borda de subida para escrita, memória pode ser lida a qq momento desde que rden=1
--			ADDR: in std_logic_vector(N-1 downto 0);--addr é endereço de byte, mas os Lsb são 00
--			write_data: in std_logic_vector(31 downto 0);
--			parallel_write_data: in array32 (0 to 2**N-1);
--			fill_cache: in std_logic;
--			rden: in std_logic;--habilita leitura
--			wren: in std_logic;--habilita escrita
--			Q:	out std_logic_vector(31 downto 0)
--			);
--end component;

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

--component mmu
--	generic (N: integer; F: integer);--total number of fifo stages and fifo output stage depth, respectively
--	port (
--	out_fifo_full: 	out std_logic_vector(1 downto 0):= "00";
--	out_cache_request: out	std_logic:= '0';
--	out_fifo_out_isempty: out std_logic:= '1';--'1' means fifo output stage is empty
--			CLK: in std_logic;--same clock of processor
--			CLK_fifo: in std_logic;--fifo clock
--			rst: in std_logic;
--			receive_cache_request: in std_logic;
--			iack: in std_logic;
--			irq: out std_logic;--data sent
--			invalidate_output: buffer std_logic;--invalidate memmory positions after parallel transfer
--			fill_cache:  out std_logic
--	);
--end component;

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

component wren_ctrl
	port (input: in std_logic;--input able of asynchronously setting the output
			CLK: in std_logic;--synchronously resets output
			output: inout std_logic := '0'--output clock
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
		locked		: OUT STD_LOGIC 
	);
END component;

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
		RDEN_OUT: out std_logic_vector;-- output
		WREN_OUT: out std_logic_vector;-- output
		data_out: out std_logic_vector(31 downto 0)-- data read
);

end component;

---------------------------------------------------

component filter_xN
-- 0..P: índices dos x
-- P+1..P+Q: índices dos y
generic	(N: natural; P: natural; Q: natural);--N: address width in bits (must be >= log2(P+1+Q))
port(	D: in std_logic_vector(31 downto 0);-- not used (peripheral supports only read)
		DX: in std_logic_vector(31 downto 0);--current filter input
		DY: in std_logic_vector(31 downto 0);--current filter output
		ADDR: in std_logic_vector(N-1 downto 0);-- input
		CLK_x: in std_logic;-- must be filter clock (input sampling)
		CLK_y: in std_logic;-- must be not filter clock (output storing)
		RST: in std_logic;-- input
		WREN: in std_logic;--not used (peripheral supports only read)
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

---------------------------------------------------
	
component sync_chain
	generic (N: natural;--bus width in bits
				L: natural);--number of registers in the chain
	port (
			data_in: in std_logic_vector(N-1 downto 0);--data generated at another clock domain
			CLK: in std_logic;--clock of new clock domain
			data_out: out std_logic_vector(N-1 downto 0)--data synchronized in CLK domain
	);
end component;

---------------------------------------------------

component interrupt_controller
generic	(L: natural);--L: number of IRQ lines
port(	D: in std_logic_vector(31 downto 0);-- input: data to register write
		ADDR: in std_logic_vector(1 downto 0);--address offset of registers relative to peripheral base address
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		IRQ_IN: in std_logic_vector(L-1 downto 0);--input: all IRQ lines
		IRQ_OUT: out std_logic;--output: IRQ line to cpu
		IACK_IN: in std_logic;--input: IACK line coming from cpu
		IACK_OUT: buffer std_logic_vector(L-1 downto 0);--output: all IACK lines going to peripherals
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

component data_in_rom_ip
	port
	(
		address		: in std_logic_vector (7 DOWNTO 0);
		clock		: in std_logic  := '1';
		q		: out std_logic_vector (31 DOWNTO 0)
	);
end component;

component desired_rom_ip
	port
	(
		address		: in std_logic_vector (7 DOWNTO 0);
		clock		: in std_logic  := '1';
		q		: out std_logic_vector (31 DOWNTO 0)
	);
end component;

component output_rom_ip
	port
	(
		address		: in std_logic_vector (7 DOWNTO 0);
		clock		: in std_logic  := '1';
		q		: out std_logic_vector (31 DOWNTO 0)
	);
end component;

--000: will read* lower 16bits of input vectors
--001: will read* lower 16bits of desired vectors
--010: will read* upper 16bits of input vectors
--011: will read* upper 16bits of desired vectors
--100: will wait until filter_CLK falling edge (since sampling edge is the rising) to read again
-- * : on next rising edge of CLK, sram_ADDR will be updated, at next CLK falling edge IO will be latched
signal sram_reading_state: std_logic_vector(2 downto 0);
signal count: std_logic_vector(17 downto 0);--counter: generates the address for SRAM, 1 bit must be added to obtain address

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
signal CLK: std_logic;--clock for processor and cache (50MHz)
signal CLK_dbg: std_logic;--clock for debug, check timing analyzer or the pll_dbg wizard
--signal CLK25MHz: std_logic;--for sram_ADDR counter (25MHz)
signal CLK_fs: std_logic;-- 11.029kHz clock
signal CLK_fs_dbg: std_logic;-- 110.29kHz clock (10fs)
signal CLK16_928571MHz: std_logic;-- 16.928571MHz clock (1536fs, for I2S peripheral)
signal CLK11_285714MHz: std_logic;-- 11.285714MHz clock (1024fs, for I2S peripheral)
signal CLK5_647059MHz: std_logic;-- 5.647059MHz clock (for I2S peripheral)
signal CLK2_8224MHz: std_logic;--2.8224MHz clock (for I2S peripheral, 128fs)
signal CLK12MHz: std_logic;-- 12MHz clock (MCLK for audio codec)

-----------signals for ROM interfacing---------------------
signal instruction_memory_output: std_logic_vector(31 downto 0);
signal instruction_memory_address: std_logic_vector(7 downto 0);

-----------signals for RAM interfacing---------------------
---processor sees all memory-mapped I/O as part of RAM-----
constant N: integer := 7;-- size in bits of data addresses (each address refers to a 32 bit word)
signal ram_clk: std_logic;--data memory clock signal
signal ram_addr: std_logic_vector(N-1 downto 0);
signal ram_rden: std_logic;
signal ram_wren: std_logic;
signal ram_write_data: std_logic_vector(31 downto 0);
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
constant P: natural := 2;
--constant P: natural := 3;
constant Q: natural := 2;
--constant Q: natural := 0;--forces  FIR filter
--constant Q: natural := 4;
signal coeffs_mem_Q: std_logic_vector(31 downto 0);--signal for single coefficient reading
signal coefficients: array32 (P+Q downto 0);
signal coeffs_mem_wren: std_logic;
signal coeffs_mem_rden: std_logic;

--signals for inner_product----------------------------------
signal inner_product_result: std_logic_vector(31 downto 0);
signal inner_product_rden: std_logic;
signal inner_product_wren: std_logic;

--signals for vmac-------------------------------------------
signal vmac_Q: std_logic_vector(31 downto 0);
signal vmac_rden: std_logic;
signal vmac_wren: std_logic;--enables write on individual registers
signal vmac_en:	std_logic;--enables accumulation

--signals for filter_xN--------------------------------------
signal filter_xN_CLK: std_logic;-- must be the same frequency as filter clock, but can't be the same polarity
signal filter_xN_Q: std_logic_vector(31 downto 0) := (others=>'0');
signal filter_xN_rden: std_logic;
signal filter_xN_wren: std_logic;

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
signal all_irq: std_logic_vector(2 downto 0);
signal all_iack: std_logic_vector(2 downto 0);

--signals for fp32_to_integer----------------------------------
constant audio_resolution: natural := 16;
signal fp_in: std_logic_vector(31 downto 0);
signal fp32_to_int_out: std_logic_vector(audio_resolution-1 downto 0);
signal left_padded_fp32_to_int_out: std_logic_vector(31 downto 0);--fp32_to_int_out left padded with zeroes

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
signal filter_irq_sync: std_logic_vector(0 downto 0);--filter_irq synchronized to ram_clk posedge
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
											(16#74#,16#77#),--interrupt controller
											(16#78#,16#78#)--converted_out
											);
signal all_periphs_output: array32 (11 downto 0);
signal all_periphs_rden: std_logic_vector(11 downto 0);
signal all_periphs_wren: std_logic_vector(11 downto 0);

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
signal send_cache_request: std_logic;
signal mmu_irq: std_logic;
signal mmu_iack: std_logic;

signal sda_dbg_s: natural;--for debug, which statement is driving SDA
	begin

	sda_dbg_p <= sda_dbg_s;
	
	--debug outputs
	LEDR <= (17 downto 2 =>'0') & filter_rst & rst;
	LEDG <= (8 downto 4 =>'0') & "00" & filter_CLK_state & i2s_SCK_IN_PLL_LOCKED;
	EX_IO <= ram_clk & filter_rst & I2C_SDAT & I2C_SCLK & sram_reading_state;
	GPIO <= (35 downto 16 => '0') & filter_wren & i2s_irq & AUD_BCLK & AUD_DACDAT & AUD_DACLRCK & filter_irq & filter_CLK & CLK &
											instruction_memory_address;	
	rom: mini_rom port map(	--CLK => CLK,
									ADDR=> instruction_memory_address,
									Q	 => instruction_memory_output
	);
	
	--MINHA ESTRATEGIA É EXECUTAR CÁLCULOS NA SUBIDA DE CLK E GRAVAR NA MEMÓRIA NA BORDA DE DESCIDA
	ram_clk <= not CLK;
	cache: mini_ram 	generic map (N => 3)
							port map(CLK	=> ram_clk,
										ADDR	=> ram_addr(2 downto 0),
										write_data => ram_write_data,
										rden	=> cache_rden,
										wren	=> cache_wren,
										Q		=> cache_Q);
	
-------------------SRAM interfacing---------------------
--	sram_CE_n <= '0';--chip always enabled
--	sram_OE_n <= '0';--output always enabled
--	sram_WE_n <= '1';--reading always enabled
--	sram_UB_n <= '0';--upper byte always enabled
--	sram_LB_n <= '0';--lower byte always enabled
--
--	sram_reading: process(CLK,filter_rst,sram_reading_state,filter_CLK,count,rst)
--	begin
--		if(rst='1')then
--			sram_reading_state <= "101";
--		elsif(filter_CLK='1')then
--			sram_reading_state <= "101";
--		elsif(rising_edge(CLK) and filter_rst='0') then
--			if (sram_reading_state(2)/='1')then--"100" or "101"
--				sram_reading_state <= sram_reading_state + 1;
--			elsif (sram_reading_state="101") then
--				sram_reading_state <= "000";
--			end if;
--		end if;
--		
--		--sram_ADDR will update immediately when sram_reading_state changes
--		if (rst='1')then
--			sram_ADDR <= (others=>'0');
--		elsif (sram_reading_state(2)/='1')then--"100" or "101"
--			sram_ADDR <= sram_reading_state(0) & count & sram_reading_state(1);--data is launched
--		end if;
--	end process;
--	
--	--index of sample being fetched
--	--generates address for reading SRAM
--	--counts from 0 to 256K
--	counter: process(rst,filter_rst,filter_CLK)
--	begin
--		if(rst='1' or filter_rst='1')then
--			count <= (others=>'0');
--		elsif(rising_edge(filter_CLK) and filter_rst='0')then--this ensures, count is updated after used for sram_ADDR
--			count <= count + 1;
--		end if;
--	end process;
--	
--	process(CLK,rst,sram_ADDR,filter_rst,sram_reading_state)
--	begin
--		if(rst='1')then
--			data_in <= (others=>'0');
--			desired <= (others=>'0');
--		--sram_ADDR is updated at rising_edge, must wait at least 10 ns to latch valid data
--		elsif (falling_edge(CLK) and filter_rst='0' and sram_reading_state(2)='0') then--data is latched
--			if(sram_ADDR(19)='0')then--reading input vectors
--				if(sram_ADDR(0)='0')then--reading lower half
--					data_in(15 downto 0) <= sram_IO;
--				else--reading upper half
--					data_in(31 downto 16) <= sram_IO;
--				end if;
--			else--reading desired vectors
--				if(sram_ADDR(0)='0')then--reading lower half
--					desired(15 downto 0) <= sram_IO;
--				else--reading upper half
--					desired(31 downto 16) <= sram_IO;
--				end if;
--			end if;
--		end if;
--	end process;
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
	
	data_in_rom: data_in_rom_ip
		port map
		(
			address	=> sample_number,
			clock		=> filter_CLK_n,
			q			=> data_in
		);

	desired_rom: desired_rom_ip
		port map
		(
			address	=> sample_number,
			clock		=> filter_CLK_n,
			q			=> desired
		);

	output_rom: output_rom_ip
		port map
		(
			address	=> sample_number,
			clock		=> filter_CLK_n,
			q			=> expected_output
		);
		
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
		error <= error_flag;

	-- synchronizes desired to rising_edge of ram_CLK, because:
	--1: desired is generated at filter_CLK domain
	--2: this signal is sampled by processor at rising_edge of CLK
	sync_chain_desired: sync_chain
		generic map (N => 32,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => desired,--data generated at another clock domain
				CLK => ram_CLK,--clock of new clock domain
				data_out => desired_sync --data synchronized in CLK domain
		);
	
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

--	--forces y=x0, for debugging
--	coefficients(0)<=x"3F800000";-- +1.0
--	coefficients(1)<=x"00000000";-- +0.0
--	coefficients(2)<=x"00000000";-- +0.0
--	coefficients(3)<=x"00000000";-- +0.0
--	coefficients(4)<=x"00000000";-- +0.0
--	coefficients(5)<=x"00000000";-- +0.0
--	coefficients(6)<=x"00000000";-- +0.0
--	coefficients(7)<=x"00000000";-- +0.0
												
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
--	data_out <= filter_output;

	-- synchronizes filter output to rising_edge of CLK, because:
	--1: filter output is generated at filter_CLK domain
	--2: this signal is sampled in filter_out at rising_edge of ram_CLK
	sync_chain_filter_output: sync_chain
		generic map (N => 32,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => filter_output,--data generated at another clock domain
				CLK => CLK,--clock of new clock domain
				data_out => filter_output_sync --data synchronized in CLK domain
		);
	
	filter_out: d_flip_flop
	 port map(	D => filter_output_sync,
					RST=> RST,--resets all previous history of filter output
					CLK=>ram_clk,--sampling clock, must be much faster than filter_CLK
					Q=> filter_out_Q
					);
					
--	d_ff_desired: d_flip_flop
--	 port map(	D => desired,
--					RST=> RST,--resets all previous history of filter output
--					CLK=>filter_CLK,--must be the same as filter_CLK
--					Q=> d_ff_desired_Q
--					);
					
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

	process(proc_filter_wren,filter_CLK)
	begin
		if(proc_filter_wren=	'1')then
			filter_wren <= '1';
		elsif(rising_edge(filter_CLK))then--next rising_edge of filter means next sample
			filter_wren <= '0';
		end if;
	end process;
	
	-- must be the clock of filter output updating
	filter_xN_CLK <= not filter_CLK;
	xN: filter_xN
	-- 0..P: índices dos x
	-- P+1..P+Q: índices dos y
	generic map (N => 3, P => P, Q => Q)--N: address width in bits (must be >= log2(P+1+Q))
	port map (	D => ram_write_data,-- not used (peripheral supports only read)
			DX => filter_input,--current filter input
			DY => filter_output,--current filter output
			ADDR => ram_addr(2 downto 0),-- input
			CLK_x => filter_CLK,
			CLK_y => filter_xN_CLK,-- must be the same frequency as filter clock, but can't be the same polarity
			RST => RST,-- input
			WREN => filter_xN_wren,--not used (peripheral supports only read)
			RDEN => filter_xN_rden,-- input
			output => filter_xN_Q-- output
			);
												
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
	
	fp_in <= filter_output_sync;
--fp_in <= data_in;
	fp32_to_int: fp32_to_integer
	generic map (N=> audio_resolution)
	port map (fp_in => fp_in,
				 output=> fp32_to_int_out);
				 

	left_padded_fp32_to_int_out <= (31 downto audio_resolution => '0') & fp32_to_int_out;
	converted_output: d_flip_flop
	 port map(	D => left_padded_fp32_to_int_out,
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
				SCK_IN => CLK16_928571MHz,
				SCK_IN_PLL_LOCKED => i2s_SCK_IN_PLL_LOCKED,--'1' if PLL that provides SCK_IN is locked
				SD => i2s_SD, --data line
				WS => i2s_WS, --left/right clock
				SCK => i2s_SCK --continuous clock (bit clock)
		);		
	MCLK <= CLK12MHz;--master clock for audio codec in USB mode

	all_periphs_output	<= (11 => converted_out_Q, 10 => irq_ctrl_Q, 9 => filter_ctrl_status_Q, 8 => desired_sync, 7 => filter_out_Q, 6 => i2s_Q,
									 5 => i2c_Q, 4 => vmac_Q, 3 => inner_product_result,	2 => cache_Q,	1 => filter_xN_Q,	0 => coeffs_mem_Q);
	--for some reason, the following code does not work: compiles but connections are not generated
--	all_periphs_rden		<= (3 => inner_product_rden,	2 => cache_rden,	1 => filter_xN_rden,	0 => coeffs_mem_rden);
--	all_periphs_wren		<= (3 => inner_product_wren,	2 => cache_wren,	1 => filter_xN_wren,	0 => coeffs_mem_wren);

	converted_out_rden		<= all_periphs_rden(11);-- not used, just to keep form
	irq_ctrl_rden				<= all_periphs_rden(10);-- not used, just to keep form
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

	converted_out_wren		<= all_periphs_wren(11);-- not used, just to keep form
	irq_ctrl_wren				<= all_periphs_wren(10);
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
	generic map (N => N, B => ranges)
	port map (	ADDR => ram_addr,-- input, it is a word address
			RDEN => ram_rden,-- input
			WREN => ram_wren,-- input
			data_in => all_periphs_output,-- input: outputs of all peripheral
			RDEN_OUT => all_periphs_rden,-- output
			WREN_OUT => all_periphs_wren,-- output
			data_out => ram_Q_buffer_in-- data read
	);
	
	ram_Q_buffer_out <= ram_Q_buffer_in;
	
	processor: microprocessor
	generic map (N => N)
	port map (
		CLK_IN => CLK,
		rst => rst,
		irq => irq,
		iack => iack,
		instruction_addr => open,
		ADDR_rom => instruction_memory_address,
		Q_rom => instruction_memory_output,
		ADDR_ram => ram_addr,
		write_data_ram => ram_write_data,
		rden_ram => ram_rden,
		wren_ram => ram_wren,
		wren_filter => proc_filter_wren,
		vmac_en => vmac_en,
		send_cache_request => send_cache_request,
		Q_ram => ram_Q_buffer_out
	);	

	-- synchronizes IRQ to rising_edge of CLK, because:
	--1: filter_irq is generated at filter_CLK domain
	--2: this signal is sampled in irq_ctrl at falling_edge of CLK
	sync_chain_filter_IRQ: sync_chain
		generic map (N => 1,--bus width in bits
					L => 2)--number of registers in the chain
		port map (
				data_in => (others=> filter_irq),--data generated at another clock domain
				CLK => ram_clk,--clock of new clock domain
				data_out => filter_irq_sync --data synchronized in CLK domain
		);
		
	--filter_irq_sync is synchronized to ram_clk rising_edge by a sync chain in this level
	--i2s_irq is synchronized to ram_clk rising_edge inside I2S peripheral
	--aparently, i2c_irq is synchronized to ram_clk rising_edge because I2C clocks are created dividing ram_clk
	all_irq	<= (2 => i2s_irq, 1 => i2c_irq, 0 => filter_irq_sync(0));
	i2s_iack	<= all_iack(2);										 
	i2c_iack	<= all_iack(1);
	filter_iack	<= all_iack(0);
	irq_ctrl: interrupt_controller
	generic map (L => 3)--L: number of IRQ lines
	port map (	D => ram_write_data,-- input: data to register write
			ADDR => ram_addr(1 downto 0),
			CLK => ram_clk,-- input
			RST => RST,-- input
			WREN => irq_ctrl_wren,-- input
			RDEN => irq_ctrl_rden,-- input
			IRQ_IN => all_irq,--input: all IRQ lines
			IRQ_OUT => irq,--output: IRQ line to cpu
			IACK_IN => iack,--input: IACK line coming from cpu
			IACK_OUT => all_iack,--output: all IACK lines going to peripherals
			output => irq_ctrl_Q -- output of register reading
	);
	
	clk_dbg_uproc:	pll_dbg_uproc
	port map
	(
		areset=> '0',
		inclk0=> CLK_IN,
		c0		=> CLK_dbg,
		c1		=> CLK,--produces CLK=4MHz for processor
		locked=> open
	);

--	process(CLK,rst,filter_CLK,filter_rst)
--	begin
--		if(rst='1' or filter_rst='1' or filter_CLK='1')then
--			rising_CLK_occur <= '0';
--		elsif(rising_edge(CLK) and filter_CLK='0')then
--			rising_CLK_occur <='1';
--		end if;
--	end process;
--	
--	process(CLK,rst,filter_CLK,filter_rst,rising_CLK_occur)
--	begin
--		if(rst='1')then
--			CLK25MHz <= '0';
--		elsif(falling_edge(CLK) and filter_rst='0' and filter_CLK='0' and rising_CLK_occur='1')then--this ensures, count is updated after used for sram_ADDR
--			CLK25MHz <= not CLK25MHz;
--		end if;
--	end process;

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
end setup;
