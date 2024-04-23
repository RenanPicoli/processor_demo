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
		--LCD
		lcd_data: inout std_logic_vector(7 downto 0);
		lcd_en: inout std_logic;
		lcd_rw: out std_logic;
		lcd_rs: out std_logic;
		lcd_on: out std_logic;
		lcd_blon: out std_logic;--is this really necessary??
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
		ready: out std_logic;--processor is ready (for new IRQs), clk_enable, synchronized to falling edge of CLK_IN
		irq: in std_logic;--interrupt request
		iack: out std_logic;--interrupt acknowledgement
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
		lvec_dst_mask: out std_logic_vector(7 downto 0);--mask for destination(s) address(es) for lvec
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
		c3 	: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC 
	);
END component;

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

component disp_7seg_driver
port (CLK: in std_logic;
		D: in std_logic_vector(31 downto 0);
		segments: out array7(7 downto 0)
);
end component;

--component by Gerry O'Brien
component LCD_DISPLAY_nty
   PORT( 
      rst              	 : in     std_logic;  -- synchronous active low reset
      clk           		 : in     std_logic;  -- Using the CPU 4 MHz Clk, in order to Genreate the 400Hz signal... clk_count_400hz reset count value must be set to:  <= x"0F424"

		-- interface with CPU
		D		: in std_logic_vector(31 downto 0);
      wren	: in std_logic;
		Q		: out std_logic_vector(31 downto 0);
		ready	: out std_logic;--check for writes
      
      lcd_rs             : out    std_logic;
      lcd_e              : out    std_logic;
      lcd_rw             : out    std_logic;
      lcd_on             : out    std_logic;
      lcd_blon           : out    std_logic;      
      
      data_bus        	 : inout  std_logic_vector(7 downto 0)
   );
end component;

signal rst: std_logic;--active high
signal rst_n_sync_CLK_IN: std_logic;--rst_n sync'd to rising_edge of CLK_IN
signal rst_n_sync_sram_CLK: std_logic;--rst_n sync'd to rising_edge of sram_CLK
signal rst_n_sync_uproc: std_logic;--rst_n sync'd to rising_edge of uproc_CLK

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
signal proc_ready: std_logic;--synchronized to falling_edge(CLK)
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

-----------signals for memory map interfacing----------------
constant ranges: boundaries := 	(--notation: base#value#
											(16#00#,16#07#),--filter coeffs
											(16#08#,16#0F#),--filter xN
											(16#10#,16#1F#),--cache
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
											(16#76#,16#77#),-- lcd_en: general purpose fp32_to_int32
											(16#80#,16#FF#),--interrupt controller
											(16#100#,16#10F#),--tmp_vector
											(16#800#,16#FFF#)--instruction memory
											);
signal all_periphs_output: array32 (ranges'length-1 downto 0);
signal all_periphs_rden: std_logic_vector(ranges'length-1 downto 0);
signal all_periphs_wren: std_logic_vector(ranges'length-1 downto 0);
signal all_periphs_ready: std_logic_vector(ranges'length-1 downto 0);

--signals  for 7-segment register
signal disp_7seg_DR_in: std_logic_vector(31 downto 0);
signal disp_7seg_DR_out: std_logic_vector(31 downto 0);
signal disp_7seg_DR_wren: std_logic;
signal disp_7seg_DR_rden: std_logic;
signal disp_7seg_DR_cnt: std_logic_vector(2 downto 0);--counter for switching between nibbles (0 to 7)
signal disp_7seg_DR_nibble: std_logic_vector(3 downto 0);--used if one nibble is displayed at a time
--signal disp_7seg_DR_code: std_logic_vector(6 downto 0);--used if one code is computed at a time

--signals for LCD controller
signal lcd_clk: std_logic;
signal lcd_Q: std_logic_vector(31 downto 0);
signal lcd_wren: std_logic;
signal lcd_rden: std_logic;
signal lcd_ready: std_logic;

signal irq: std_logic;
signal iack: std_logic;
signal ISR_ADDR: std_logic_vector(31 downto 0);

signal sda_dbg_s: natural;--for debug, which statement is driving SDA
	begin

	rst <= not rst_n_sync_uproc;
	
	--debug outputs
	LEDR <= (17 downto 1 =>'0') & rst;
	LEDG <= (8 downto 0 =>'0');
	EX_IO <= (others => '0');
	GPIO <= (35 downto 9 => '0') & CLK & instruction_memory_address(7 downto 0);
	
	CLK_n <= not CLK;
	
	--it is necessary to translate the ram address associated with d_cache (starting at 0x400)
	--to an instruction address (starting at 0)
	program_data_address <= ram_addr(18 downto 0) - ranges(16)(0);
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
	
	--MINHA ESTRATEGIA É EXECUTAR CÁLCULOS NA SUBIDA DE CLK E GRAVAR NA MEMÓRIA NA BORDA DE DESCIDA
	ram_clk <= CLK;	

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
			generic map (REQUESTED_SIZE => 2048, MEM_WIDTH=> 16, MEM_LATENCY=> 1, REGISTER_ADDR=> true)--user requested cache size, in 32 bit words
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
--------------------------------------------------------

	all_periphs_ready		<= (16=> program_data_ready, 12=> lcd_ready, others=>'1');
	all_periphs_output	<= (16=> program_data_Q, 12=> lcd_Q, 11 => disp_7seg_DR_out, others=>(others=>'0'));

	program_data_rden			<= all_periphs_rden(16);-- not used, just to keep form
	lcd_rden						<= all_periphs_rden(12);-- not used, just to keep form
	disp_7seg_DR_rden			<= all_periphs_rden(11);-- not used, just to keep form


	program_data_wren			<= all_periphs_wren(16);
	lcd_wren						<= all_periphs_wren(12);
	disp_7seg_DR_wren			<= all_periphs_wren(11);

	memory_map: address_decoder_memory_map
	--N: word address width in bits
	--B boundaries: list of values of the form (starting address,final address) of all peripherals, written as integers,
	--list MUST BE "SORTED" (start address(i) < final address(i) < start address (i+1)),
	--values OF THE FORM: "(b1 b2..bN 0..0),(b1 b2..bN 1..1)"
	generic map (N => 12, B => ranges)
	port map (	ADDR => ram_addr(11 downto 0),-- input, it is a word address
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
		ready=> open,
		irq => irq,
		iack => iack,
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
		vmac_en => open,
		wren_lvec => open,
		lvec_src => open,
		lvec_dst_mask => open,
		Q_ram => ram_Q_buffer_out
	);
	
	ISR_ADDR <= (others=>'0');
	irq <='0';
	
	disp_7seg_DR_in <= ram_write_data;
	disp_7seg_DR: d_flip_flop port map(
		D => disp_7seg_DR_in,
		CLK => ram_clk,
		RST => RST,
		ENA => disp_7seg_DR_wren,
		Q => disp_7seg_DR_out
	);

	disp_7seg: disp_7seg_driver port map(
		CLK=> ram_clk,
		D	=> disp_7seg_DR_out,
		segments => segments		
	);

--component by Gerry O'Brien
lcd_ctrl: LCD_DISPLAY_nty
   port map( 
      rst		=> rst,-- synchronous active low reset
      clk		=> ram_clk,
		
		-- interface with CPU
		D			=> ram_write_data,
		wren		=> lcd_wren,
		Q			=> lcd_Q,
		ready		=> lcd_ready,
      
      lcd_rs	=> lcd_rs,
      lcd_e		=> lcd_en,
      lcd_rw	=> lcd_rw,
      lcd_on	=> lcd_on,
      lcd_blon	=> lcd_blon,
      
      
      data_bus	=> lcd_data
   );
		
	clk_dbg_uproc:	pll_dbg_uproc
	port map
	(
		areset=> '0',
		inclk0=> CLK_IN,
		c0		=> CLK_dbg,--produces 48MHz for debugging
		c1		=> CLK,--produces CLK=4MHz for processor
		c2		=> sram_CLK,--produces 4x the processor frequency, delayed (for 4MHz uproc, produces 16MHz delayed 31.25 ns)
		c3		=> lcd_clk,--1MHz for LCD timing and FSM
		locked=> open
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