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
port(	D: in std_logic_vector(31 downto 0);-- input
		ADDR: in std_logic_vector(N-1 downto 0);-- input
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		output: out std_logic_vector(31 downto 0)-- output
);

end inner_product_calculation_unit;

---------------------------------------------------

architecture behv of inner_product_calculation_unit is

	component address_decoder_register_map
	--N: address width in bits
	--boundaries: upper limits of each end (except the last, which is 2**N-1)
	generic	(N: natural);
	port(	ADDR: in std_logic_vector(N-1 downto 0);-- input
			RDEN: in std_logic;-- input
			WREN: in std_logic;-- input
			WREN_OUT: out std_logic_vector;-- output
			data_in: in array32;-- input: outputs of all peripheral/registers
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

	component d_flip_flop
		port (D:	in std_logic_vector(31 downto 0);
				rst:	in std_logic;--synchronous reset
				ENA:	in std_logic;--enables writes
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;
	
	signal A: array32((2**(N-2)-1) downto 0);
	signal B: array32((2**(N-2)-1) downto 0);
	signal A_fpu_inner_product_input: array32 (0 to (2**(N-2)-1));-- A input of fpu_inner_product
	signal B_fpu_inner_product_input: array32 (0 to (2**(N-2)-1));-- B input of fpu_inner_product
	signal result: std_logic_vector(31 downto 0);--result of fpu_inner_product
	signal prod: array32 (0 to (2**(N-2)-1));--results of products
	signal ena_reg: std_logic_vector(0  to 2**N-1);--ena input of registers (write enable)
	signal all_registers_output: array32(0 to (2**(N-1)));--16 reg A, 16 reg B, 1 reg result
	signal address_decoder_output: std_logic_vector(31 downto 0);--result of a read will be here
	signal reg_result_out: std_logic_vector(31 downto 0);--result of inner product will be read here

begin

	all_registers_output <= A_fpu_inner_product_input & B_fpu_inner_product_input & reg_result_out;

-------------------------- address decoder ---------------------------------------------------
	decoder: address_decoder_register_map
	generic map(N => N)
	port map(ADDR => ADDR,
				RDEN => RDEN,
				WREN => WREN,
				data_in => all_registers_output,
				WREN_OUT => ena_reg,
				data_out => output
	);

------------------------ ( A(i) ) registers --------------------------------------------------
	A_i: for i in 0 to (2**(N-2)-1) generate-- A(i)
		A(i) <= D;
		d_ff_A: d_flip_flop port map(	D => A(i),
												RST=> RST,--resets all previous history of input signal
												ENA=> ena_reg(i),
												CLK=>CLK,--sampling clock
												Q=> A_fpu_inner_product_input(i)
												);
	end generate;
	
------------------------ ( B(i) ) registers --------------------------------------------------
	B_i: for i in 0 to (2**(N-2)-1) generate-- B(i)
		B(i) <= D;
		d_ff_B: d_flip_flop port map(	D => B(i),
												RST=> RST,--resets all previous history of input signal
												ENA=> ena_reg((2**(N-2))+i),
												CLK=>CLK,--sampling clock
												Q=> B_fpu_inner_product_input(i)
												);
	end generate;
	
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
		d_ff_result: d_flip_flop port map(	D => result,
														RST=> RST,--resets all previous history of input signal
														ENA=> ena_reg((2**(N-1)+1)),
														CLK=>CLK,--sampling clock
														Q=> reg_result_out
														);
---------------------------------------------------------------------------------------------

end behv;

---------------------------------------------------------------------------------------------
