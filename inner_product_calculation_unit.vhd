--------------------------------------------------
--inner product calculation unit
--specialized peripheral
--contains fpu_inner_product and its input and output registers
--allows calculation of inner product of vector of up to 16 elements
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity inner_product_calculation_unit is
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
		parallel_rden_A: in std_logic;--enables parallel read (to shared data bus)
		parallel_rden_B: in std_logic;--enables parallel read (to shared data bus)
		parallel_read_data: out array32 (0 to 2**(N-2)-1);
		output: out std_logic_vector(31 downto 0)-- output
);

end inner_product_calculation_unit;

---------------------------------------------------

architecture behv of inner_product_calculation_unit is

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
	
	--combinatorial, data comes from register external to this component
	component fpu_inner_product
	generic	(N: natural);--number of elements of each vector
	port(	A:	in array32(N-1 downto 0);-- input
			B:	in array32(N-1 downto 0);-- input
			output: out std_logic_vector(31 downto 0)-- output
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
	
	signal A_fpu_inner_product_input: array32 (0 to (2**(N-2)-1));-- A input of fpu_inner_product
	signal B_fpu_inner_product_input: array32 (0 to (2**(N-2)-1));-- B input of fpu_inner_product
	signal result: std_logic_vector(31 downto 0);--result of fpu_inner_product
	signal A_rden: std_logic;--rden for single word of A registers
	signal B_rden: std_logic;--rden for single word of B registers
	signal result_rden: std_logic;--rden for result register
	signal A_wren: std_logic;--wren for single word of A registers
	signal B_wren: std_logic;--wren for single word of B registers
	signal result_wren: std_logic;--wren for result register
	signal A_output: std_logic_vector(31 downto 0);
	signal B_output: std_logic_vector(31 downto 0);
	signal reg_result_out: std_logic_vector(31 downto 0);--result of inner product will be read here
	
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

	all_periphs_output <= (0 => A_output, 1 => B_output, 2=> reg_result_out);
	
	A_rden <= all_periphs_rden(0);
	B_rden <= all_periphs_rden(1);
	result_rden <= all_periphs_rden(2);
	
	A_wren <= all_periphs_wren(0);
	B_wren <= all_periphs_wren(1);
	result_wren <= all_periphs_wren(2);

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
	A_plc: parallel_load_cache
		generic map (N => N-2)
		port map(CLK => CLK,
					ADDR=> ADDR(N-3 downto 0),
					RST => RST,
					write_data => D,
					parallel_write_data => parallel_write_data,
					parallel_wren => parallel_wren_A,
					rden => A_rden,
					wren => A_wren,
					parallel_rden => '1',--fpu_inner_product always read parallel output
					parallel_read_data => A_fpu_inner_product_input,
					Q => A_output
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
					parallel_rden => '1',--fpu_inner_product always read parallel output
					parallel_read_data => B_fpu_inner_product_input,
					Q => B_output
		);
	
----------------------- inner product instantiation -------------------------------------------
	inner_product: fpu_inner_product
	generic map (N => 2**(N-2))
	port map(A => A_fpu_inner_product_input,--supposed to be normalized
				B => B_fpu_inner_product_input,--supposed to be normalized
				-------NEED ADD FLAGS (overflow, underflow, etc)
				--overflow:		out std_logic,
				--underflow:		out std_logic,
				output => result
				);
				
---------------------------------- result register ---------------------------------------------
------------------(READ-ONLY, always WRITTEN by fpu_inner_product)------------------------------
	d_ff_result: d_flip_flop port map(	D => result,
													RST=> RST,--resets all previous history of input signal
													ENA=> '1',
													CLK=> CLK,--sampling clock
													Q=> reg_result_out
													);
---------------------------------------------------------------------------------------------

	--parallel_read_data connects to a shared data bus
	--note that if you mistakenly assert both parallel_rden_A AND parallel_rden_B,
	--parallel_rden_A takes precedence
	parallel_read_data <= 	A_fpu_inner_product_input when (parallel_rden_A='1') else
									B_fpu_inner_product_input when (parallel_rden_B='1') else
									(others=>(others=>'Z'));--prevents latch
end behv;

---------------------------------------------------------------------------------------------
