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
		filter_CLK: inout std_logic;--filter sampling clock
		alternative_filter_CLK: in std_logic;--alternative input clock (for simulation purpose)
		use_alt_filter_clk: in std_logic;-- '1' uses alternative  clock; '0' uses pll
		instruction_addr: buffer std_logic_vector(31 downto 0)
--		segments: out array7(0 to 7)--signals to control 8 displays of 7 segments
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
		rden_ram: out std_logic;--habilita leitura na ram (cache e periféricos mapeados na ram)
		wren_ram: out std_logic;--habilita escrita na ram (cache e periféricos mapeados na ram)
		wren_filter: out std_logic;--habilita escrita nos coeficientes do filtro
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

component generic_coeffs_mem
	-- 0..P: índices dos coeficientes de x (b)
	-- 1..Q: índices dos coeficientes de y (a)
	generic	(N: natural; P: natural; Q: natural);
	port(	D:	in std_logic_vector(31 downto 0);-- um coeficiente é carregado por vez
			ADDR: in std_logic_vector(N-1 downto 0);--se ALTERAR P, Q PRECISA ALTERAR AQUI
			RST:	in std_logic;--synchronous reset
			RDEN:	in std_logic;--read enable
			WREN:	in std_logic;--write enable
			CLK:	in std_logic;
			Q_coeffs: out std_logic_vector(31 downto 0);--single coefficient reading
			all_coeffs:	out std_logic_vector(32*(P+Q+1)-1 downto 0)-- todos os coeficientes são lidos de uma vez
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
			coeffs:	in std_logic_vector(32*(P+Q+1)-1 downto 0);-- todos os coeficientes são lidos de uma vez
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
--produces 220.5kHz from 5MHz
component pll
	port (areset: in std_logic  := '0';
			inclk0: in std_logic  := '0';
			c0		: out std_logic ;
			locked: out std_logic
	);
end component;

---------------------------------------------------
--produces 5MHz from 50MHz
component pll_5MHz
	port
	(
		areset		: in std_logic  := '0';
		inclk0		: in std_logic  := '0';
		c0				: out std_logic ;
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
		CLK: in std_logic;-- must be filter clock
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
signal CLK: std_logic;--clock for processor and cache
signal CLK5MHz: std_logic;--clock input for PLL
signal CLK220_5kHz: std_logic;--clock output for PLL
signal CLK22_05kHz: std_logic;-- 22.05kHz clock

-----------signals for ROM interfacing---------------------
signal instruction_memory_output: std_logic_vector(31 downto 0);
signal instruction_memory_address: std_logic_vector(4 downto 0);

-----------signals for RAM interfacing---------------------
---processor sees all memory-mapped I/O as part of RAM-----
constant N: integer := 8;-- size in bits of data addresses (each address refers to a 32 bit word)
signal ram_clk: std_logic;--data memory clock signal
signal ram_addr: std_logic_vector(N-1 downto 0);
signal ram_rden: std_logic;
signal ram_wren: std_logic;
signal ram_write_data: std_logic_vector(31 downto 0);
signal ram_Q: std_logic_vector(31 downto 0);

-----------signals for (parallel) cache interfacing--------
signal cache_Q: std_logic_vector(31 downto 0);
signal cache_parallel_write_data: array32 (0 to 2**(N-2)-1);--because N=8 and cache has 64 addresses
signal cache_fill_cache: std_logic;
signal cache_rden: std_logic;
signal cache_wren: std_logic;

-----------signals for FIFO interfacing---------------------
constant F: integer := 2**(6);--fifo depth (twice the cache's size)
signal fifo_clock: std_logic;
signal fifo_input: std_logic_vector (31 downto 0);
signal fifo_output: array32 (0 to (2**(N-3))-1);--because N=8 and cache has 32 addresses 

--signal fifo_valid: std_logic_vector(F-1 downto 0);
signal fifo_invalidate_output: std_logic;

--signals for coefficients memory----------------------------
constant P: natural := 5;
constant Q: natural := 5;
signal coeffs_mem_Q: std_logic_vector(31 downto 0);--signal for single coefficient reading
signal coefficients: std_logic_vector(32*(P+Q+1)-1 downto 0);
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

-----------signals for memory map interfacing--------------
constant ranges: boundaries := 	(--notation: base#value#
											(16#00#,16#0F#),--filter coeffs
											(16#10#,16#1F#),--filter xN
											(16#20#,16#3F#),--cache
											(16#40#,16#7F#),--inner_product
											(16#80#,16#BF#) --VMAC
											);
signal all_periphs_output: array32 (3 downto 0);
signal all_periphs_rden: std_logic_vector(3 downto 0);
signal all_periphs_wren: std_logic_vector(3 downto 0);

signal proc_filter_wren: std_logic;
signal filter_wren: std_logic;
signal filter_rst: std_logic := '1';
signal filter_input: std_logic_vector(31 downto 0);
signal filter_output: std_logic_vector(31 downto 0);
signal filter_state: std_logic := '0';--starts in zero, changes to 1 when first rising edge of filter_CLK occurs
signal send_cache_request: std_logic;
signal irq: std_logic;
signal iack: std_logic;

	begin
	
	rom: mini_rom port map(	--CLK => CLK,
									ADDR=> instruction_memory_address,
									Q	 => instruction_memory_output
	);
	
	fifo_input <= data_in;
	fifo: shift_register generic map (N => F, OS => 2**(5))
								port map(CLK => fifo_clock,
											rst => rst,
											D => fifo_input,
--											invalidate_output => fifo_invalidate_output,
											Q => fifo_output);
--											valid => fifo_valid);
	
	--MINHA ESTRATEGIA É EXECUTAR CÁLCULOS NA SUBIDA DE CLK E GRAVAR Na MEMÓRIA NA BORDA DE DESCIDA
	ram_clk <= not CLK;
	cache_parallel_write_data <= fifo_output(0 to 2**(5)-1);--2^5=32 addresses
	cache: parallel_load_cache generic map (N => 5)
									port map(CLK	=> ram_clk,
												ADDR	=> ram_addr(4 downto 0),
												write_data => ram_write_data,
												parallel_write_data => cache_parallel_write_data,
												fill_cache => cache_fill_cache,
												rden	=> cache_rden,
												wren	=> cache_wren,
												Q		=> cache_Q);
												
	memory_management_unit:
	mmu generic map (N => F, F => 2**(5))
	port map(CLK => CLK,
				CLK_fifo => fifo_clock,
				rst => rst,
				receive_cache_request => send_cache_request,
				iack => iack,
				irq => irq,
				invalidate_output => fifo_invalidate_output,
				fill_cache => cache_fill_cache
	);
	
	coeffs_mem: generic_coeffs_mem generic map (N=> 4, P => P,Q => Q)
									port map(D => ram_write_data,
												ADDR	=> ram_addr(3 downto 0),
												RST => rst,
												RDEN	=> coeffs_mem_rden,
												WREN	=> coeffs_mem_wren,
												CLK	=> ram_clk,
												Q_coeffs => coeffs_mem_Q,
												all_coeffs => coefficients
												);
												
	filter_CLK <= alternative_filter_CLK when (use_alt_filter_clk = '1') else CLK22_05kHz;
	IIR_filter: filter 	generic map (P => P, Q => Q)
								port map(input => filter_input,-- input
											RST => filter_rst,--synchronous reset
											WREN => filter_wren,--enables writing on coefficients
											CLK => filter_CLK,--sampling clock
											coeffs => coefficients,-- todos os coeficientes são lidos de uma vez
											output => filter_output											
											);
	filter_input <= data_in;
	data_out <= filter_output;
											
	filter_reset_process: process (filter_CLK,filter_state)
	begin
--		filter_rst <= '1';
		if (filter_CLK'event and filter_CLK = '1') then
			filter_state <= '1';
		end if;
		if (filter_CLK'event and filter_CLK = '0' and filter_state = '1') then
				filter_rst <= '0';
		end if;
	end process filter_reset_process;
											
	wren_control: wren_ctrl port map (input => proc_filter_wren,
												 CLK => filter_CLK,
												 output => filter_wren
												);
	
	-- must be the same frequency as filter clock, but can't be the same polarity
	--otherwise, there would be problems reading filter output while its changing
	filter_xN_CLK <= not filter_CLK;
	xN: filter_xN
	-- 0..P: índices dos x
	-- P+1..P+Q: índices dos y
	generic map (N => 4, P => P, Q => Q)--N: address width in bits (must be >= log2(P+1+Q))
	port map (	D => ram_write_data,-- not used (peripheral supports only read)
			DX => filter_input,--current filter input
			DY => filter_output,--current filter output
			ADDR => ram_addr(3 downto 0),-- input
			CLK => filter_xN_CLK,-- must be the same frequency as filter clock, but can't be the same polarity
			RST => RST,-- input
			WREN => filter_xN_wren,--not used (peripheral supports only read)
			RDEN => filter_xN_rden,-- input
			output => filter_xN_Q-- output
			);
												
	inner_product: inner_product_calculation_unit
	generic map (N => 6)
	port map(D => ram_write_data,--supposed to be normalized
				ADDR => ram_addr(5 downto 0),
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
	generic map (N => 6)
	port map(D => ram_write_data,
				ADDR => ram_addr(5 downto 0),
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

	all_periphs_output	<= (3 => inner_product_result,	2 => cache_Q,	1 => filter_xN_Q,		0 => coeffs_mem_Q);
--for some reason, the following code does not work: compiles but connections are not generated
	all_periphs_rden		<= (3 => inner_product_rden,	2 => cache_rden,	1 => filter_xN_rden,	0 => coeffs_mem_rden);
	all_periphs_wren		<= (3 => inner_product_wren,	2 => cache_wren,	1 => filter_xN_wren,	0 => coeffs_mem_wren);

/*
	inner_product_rden	<= all_periphs_rden(3);
	cache_rden				<= all_periphs_rden(2);
	filter_xN_rden			<= all_periphs_rden(1);
	coeffs_mem_rden		<= all_periphs_rden(0);

	inner_product_wren	<= all_periphs_wren(3);
	cache_wren				<= all_periphs_wren(2);
	filter_xN_wren			<= all_periphs_wren(1);
	coeffs_mem_wren		<= all_periphs_wren(0);
*/
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
			data_out => ram_Q-- data read
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
		wren_filter => proc_filter_wren,
		send_cache_request => send_cache_request,
		Q_ram => ram_Q
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
	
	--produces 5MHz clock (processor and cache) from 50MHz input
/*	clk_5MHz: prescaler
	generic map (factor => 10)
	port map (
	CLK_IN => CLK_IN,
	rst => rst,
	CLK_OUT => CLK5MHz);*/
	clk_5MHz: pll_5MHz
	port map (
	inclk0 => CLK_IN,
	areset => rst,
	c0 => CLK5MHz
	);
	
	--produces 220.5kHz clock
	pll_220_5kHz: pll
	port map (
	inclk0 => CLK5MHz,
	areset => rst,
	c0 => CLK220_5kHz
	);
	
	--produces 22050Hz clock (sampling frequency) from 220.5kMHz input
	clk_22_05kHz: prescaler
	generic map (factor => 10)
	port map (
	CLK_IN => CLK220_5kHz,
	rst => rst,
	CLK_OUT => CLK22_05kHz);
end setup;