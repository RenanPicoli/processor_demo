--------------------------------------------------
--vectorial multiply-accumulator unit (VMAC)
--specialized peripheral
--contains fpu_mult and its two input vectors and output vector registers
--allows calculation of a+lambda*b for vetcors a,b of up to 16 elements
--stores the result in a (accumulator)
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity vectorial_multiply_accumulator_unit is
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
		parallel_rden_A: in std_logic;--enables parallel read (to shared data bus)
		parallel_rden_B: in std_logic;--enables parallel read (to shared data bus)
		parallel_read_data: out array32 (0 to 2**(N-2)-1);
		output: out std_logic_vector(31 downto 0)-- output
);

end vectorial_multiply_accumulator_unit;

---------------------------------------------------

architecture behv of vectorial_multiply_accumulator_unit is

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
	
	component fpu_adder
	port (
		A: in std_logic_vector(31 downto 0);--supposed to be normalized
		B: in std_logic_vector(31 downto 0);--supposed to be normalized
		-------NEED ADD FLAGS (overflow, underflow, etc)
		overflow:		out std_logic;
		underflow:		out std_logic;
		result:out std_logic_vector(31 downto 0)
	);
	end component;

	component fpu_mult
	port (
		A: in std_logic_vector(31 downto 0);--supposed to be normalized
		B: in std_logic_vector(31 downto 0);--supposed to be normalized
		-------NEED ADD FLAGS (overflow, underflow, etc)
		overflow:		out std_logic;
		underflow:		out std_logic;
		result:out std_logic_vector(31 downto 0)
	);
	end component;
	
	component parallel_load_cache
	generic (N: integer);--size in bits of address 
	port (CLK: in std_logic;--borda de subida para escrita, memória pode ser lida a qq momento desde que rden=1
			ADDR: in std_logic_vector(N-1 downto 0);--addr is a word (32 bits) address
			RST:	in std_logic;--asynchronous reset
			write_data: in std_logic_vector(31 downto 0);
			parallel_write_data: in array32 (0 to 2**N-1);
			parallel_wren: in std_logic;
			rden: in std_logic;--habilita leitura
			wren: in std_logic;--habilita escrita
			parallel_rden: in std_logic;--enables parallel read (to shared data bus)
			parallel_read_data: out array32 (0 to 2**N-1);
			Q:	out std_logic_vector(31 downto 0)
			);
	end component;
	
	component d_flip_flop

	port(	D:	in std_logic_vector(31 downto 0);
			RST:	in std_logic;--asynchronous reset
			ENA:	in std_logic:='1';--enables writes
			CLK:	in std_logic;
			Q:	out std_logic_vector(31 downto 0)  
	);

	end component;
	
	-- 2**(N-2): maximum number of vector components
	signal lambda_in:	std_logic_vector(31 downto 0)	;--scalar lambda input
	signal lambda_out:std_logic_vector(31 downto 0)	;--scalar lambda input
	
	signal B_fpu_mult_input: array32 (0 to (2**(N-2)-1));-- B input of fpu_mult
	signal result_fpu_mult_output: array32 (0 to (2**(N-2)-1));-- result of fpu_mult
	
	signal A_fpu_adder_input: array32 (0 to (2**(N-2)-1));-- A input of fpu_adder
	signal B_fpu_adder_product_input: array32 (0 to (2**(N-2)-1));-- B input of fpu_adder
	signal result_fpu_adder_output: array32 (0 to (2**(N-2)-1));-- result of fpu_adder
	
	signal A_out: std_logic_vector(31 downto 0);
	signal B_out: std_logic_vector(31 downto 0);
	signal A_rden: std_logic;
	signal B_rden: std_logic;
	signal lambda_rden: std_logic;
	signal A_wren: std_logic;
	signal B_wren: std_logic;
	signal lambda_wren: std_logic;
	
	signal parallel_write_data_A: array32 (0 to 2**(N-2)-1);
	signal parallel_wren_A_or_vmacen: std_logic;
	
	-----------signals for memory map interfacing----------------
	constant ranges: boundaries := 	(--notation: base#value#
												(16#00#,16#07#),--A regs
												(16#08#,16#0F#),--B regs
												(16#10#,16#10#)--result
												);
	signal all_periphs_output: array32 (2 downto 0);
	signal all_periphs_rden: std_logic_vector(2 downto 0);
	signal all_periphs_wren: std_logic_vector(2 downto 0);

begin

	-- there are 3 registers implemented: storing A, B and lambda
	all_periphs_output <= (0 => A_out, 1 => B_out, 2=> lambda_out);
	
	A_rden <= all_periphs_rden(0);
	B_rden <= all_periphs_rden(1);
	lambda_rden <= all_periphs_rden(2);
	
	A_wren <= all_periphs_wren(0);
	B_wren <= all_periphs_wren(1);
	lambda_wren <= all_periphs_wren(2);

-------------------------- address decoder ---------------------------------------------------
	memory_map: address_decoder_memory_map
	--N: word address width in bits
	--B boundaries: list of values of the form (starting address,final address) of all peripherals, written as integers,
	--list MUST BE "SORTED" (start address(i) < final address(i) < start address (i+1)),
	--values OF THE FORM: "(b1 b2..bN 0..0),(b1 b2..bN 1..1)"
	generic map (N => N, B => ranges)
	port map (	ADDR => ADDR,-- input, it is a word address
			RDEN => RDEN,-- input
			WREN => WREN,-- input
			data_in => all_periphs_output,-- input: outputs of all peripheral
			RDEN_OUT => all_periphs_rden,-- output
			WREN_OUT => all_periphs_wren,-- output
			data_out => output-- data read
	);

------------------------ ( A(i) ) registers --------------------------------------------------
	parallel_wren_A_or_vmacen <= parallel_wren_A or VMAC_EN;
	parallel_write_data_A <= result_fpu_adder_output when VMAC_EN='1' else parallel_write_data;
	A_plc: parallel_load_cache
		generic map (N => N-2)
		port map(CLK => CLK,
					ADDR=> ADDR(N-3 downto 0),
					RST => RST,
					write_data => D,
					parallel_write_data => parallel_write_data_A,
					parallel_wren => parallel_wren_A_or_vmacen,
					rden => A_rden,
					wren => A_wren,
					parallel_rden => '1',--fpu_adder always reads parallel output
					parallel_read_data => A_fpu_adder_input,
					Q => A_out
		);
	
------------------------ ( B(i) ) registers --------------------------------------------------
	B_plc: parallel_load_cache
		generic map (N => N-2)
		port map(CLK => CLK,
					ADDR=> ADDR(N-3 downto 0),
					RST => RST,
					write_data => D,
					parallel_write_data => parallel_write_data,
					parallel_wren => parallel_wren_B,
					rden => B_rden,
					wren => B_wren,
					parallel_rden => '1',--fpu_mult always reads parallel output
					parallel_read_data => B_fpu_mult_input,
					Q => B_out
		);
	
---------------------------------- lambda register ---------------------------------------------
	d_ff_lambda: d_flip_flop port map(	D => D,
													RST=> RST,--resets all previous history of input signal
													ENA=> lambda_wren,
													CLK=> CLK,--sampling clock
													Q=> lambda_out
													);
	
-------------------- ( lambda*B(i) ) multipliers ---------------------------------------------
	mult_i: for i in 0 to (2**(N-2)-1) generate-- lambda*B(i)
		multiplier: fpu_mult port map(A => lambda_out,--supposed to be normalized
												B => B_fpu_mult_input(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => result_fpu_mult_output(i)
												);
	end generate;

	-------------------- ( A(i) + lambda*B(i) ) adders ---------------------------------------------
	add_i: for i in 0 to (2**(N-2)-1) generate
		adder: fpu_adder port map(A => A_fpu_adder_input(i),--supposed to be normalized
												B => result_fpu_mult_output(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => result_fpu_adder_output(i)
												);
	end generate;
---------------------------------------------------------------------------------------------

	--parallel_read_data connects to a shared data bus
	--note that if you mistakenly assert both parallel_rden_A AND parallel_rden_B,
	--parallel_rden_A takes precedence
	parallel_read_data <= 	A_fpu_adder_input when (parallel_rden_A='1') else
									B_fpu_mult_input when (parallel_rden_B='1') else
									(others=>(others=>'Z'));--prevents latch
									
end behv;

---------------------------------------------------------------------------------------------
