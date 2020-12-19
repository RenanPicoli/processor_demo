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
		output: out std_logic_vector(31 downto 0)-- output
);

end vectorial_multiply_accumulator_unit;

---------------------------------------------------

architecture behv of vectorial_multiply_accumulator_unit is

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

	component d_flip_flop
		port (D:	in std_logic_vector(31 downto 0);
				rst:	in std_logic;--synchronous reset
				ENA:	in std_logic;--enables writes
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;
	
	-- 2**(N-2): maximum number of vector components
	signal A_in: 		array32((2**(N-2)-1) downto 0);--A registers input
	signal A_out: 		array32((2**(N-2)-1) downto 0);--A registers output
	signal B_in:		array32((2**(N-2)-1) downto 0);--B registers input
	signal B_out:		array32((2**(N-2)-1) downto 0);--B registers output
	signal lambda_in:	std_logic_vector(31 downto 0)	;--scalar lambda input
	signal lambda_out:std_logic_vector(31 downto 0)	;--scalar lambda input
	
	signal A_fpu_mult_input: array32 (0 to (2**(N-2)-1));-- A input of fpu_mult
	signal B_fpu_mult_product_input: array32 (0 to (2**(N-2)-1));-- B input of fpu_mult
	signal result_fpu_mult_product_output: array32 (0 to (2**(N-2)-1));-- result of fpu_mult
	
	signal A_fpu_adder_input: array32 (0 to (2**(N-2)-1));-- A input of fpu_adder
	signal B_fpu_adder_product_input: array32 (0 to (2**(N-2)-1));-- B input of fpu_adder
	signal result_fpu_adder_product_output: array32 (0 to (2**(N-2)-1));-- result of fpu_adder
	
	signal ena_reg: std_logic_vector(0  to 2**N-1);--ena input of registers (write enable)
	signal all_registers_output: array32(0 to (2**(N-1)));--16 reg A, 16 reg B, 1 reg scalar (0 to 32)
	signal address_decoder_output: std_logic_vector(31 downto 0);--result of a read will be here
	signal address_decoder_wren: std_logic_vector(0  to 2**N-1);--write enable of registers (for individual writes)

begin

	-- there are 3 registers implemented: storing A, B and lambda
	all_registers_output <= A_out & B_out & lambda_out;

-------------------------- address decoder ---------------------------------------------------
	decoder: address_decoder_register_map
	generic map(N => N)
	port map(ADDR => ADDR,
				RDEN => RDEN,
				WREN => WREN,
				data_in => all_registers_output,
				WREN_OUT => address_decoder_wren,
				data_out => output
	);

------------------------ ( A(i) ) registers --------------------------------------------------
	A_i: for i in 0 to (2**(N-2)-1) generate-- A(i)
		A_in(i) <= result_fpu_adder_product_output when VMAC_EN='1' else D;
		ena_reg(i) <= '1' when VMAC_EN='1' else address_decoder_wren(i);
		d_ff_A: d_flip_flop port map(	D => A_in(i),
												RST=> RST,--resets all previous history of input signal
												ENA=> ena_reg(i),
												CLK=>CLK,--sampling clock
												Q=> A_out(i)
												);
	end generate;
	
------------------------ ( B(i) ) registers --------------------------------------------------
	B_i: for i in 0 to (2**(N-2)-1) generate-- B(i)
		B_in(i) <= D;
		d_ff_B: d_flip_flop port map(	D => B_in(i),
												RST=> RST,--resets all previous history of input signal
												ENA=> ena_reg((2**(N-2))+i),
												CLK=>CLK,--sampling clock
												Q=> B_out(i)
												);
	end generate;
	
---------------------------------- lambda register ---------------------------------------------
		lambda_in <= D;
		d_ff_lambda: d_flip_flop port map(	D => lambda_in,
														RST=> RST,--resets all previous history of input signal
														ENA=> ena_reg((2**(N-1)+1)),
														CLK=>CLK,--sampling clock
														Q=> lambda_out
														);
	
-------------------- ( lambda*B(i) ) multipliers ---------------------------------------------
	mult_i: for i in 0 to (2**(N-2)-1) generate-- lambda*B(i)
		multiplier: fpu_mult port map(A => lambda_out,--supposed to be normalized
												B => B_out(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => result_fpu_mult_product_output(i)
												);
	end generate;

	-------------------- ( A(i) + lambda*B(i) ) adders ---------------------------------------------
	add_i: for i in 0 to (2**(N-2)-1) generate
		adder: fpu_adder port map(A => A_out(i),--supposed to be normalized
												B => result_fpu_mult_product_output(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => result_fpu_adder_product_output(i)
												);
	end generate;
---------------------------------------------------------------------------------------------

end behv;

---------------------------------------------------------------------------------------------
