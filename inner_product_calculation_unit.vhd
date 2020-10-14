--------------------------------------------------
--inner product calculation unit
--specialized peripheral
--contains fpu_inner_product and its input and output registers
--allows calculation of inner product of vector of up to 32 elements
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity inner_product_calculation_unit is
port(	D: in std_logic_vector(31 downto 0);-- input
		ADDR: in std_logic_vector(6 downto 0);-- input
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		output: out std_logic_vector(31 downto 0)-- output
);

end inner_product_calculation_unit;

---------------------------------------------------

architecture behv of inner_product_calculation_unit is

	-- TODO
--	component address decoder
--	end component;
	
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
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;
	
	signal A: array32(31 downto 0);
	signal B: array32(31 downto 0);
	signal A_fpu_inner_product_input: array32 (0 to 31);-- A input of fpu_inner_product
	signal B_fpu_inner_product_input: array32 (0 to 31);-- B input of fpu_inner_product
	signal result: std_logic_vector(31 downto 0);--connects feedback and feed forward parts
	signal prod: array32 (0 to 32-1);--results of products

begin
------------------------ ( A(i) ) registers --------------------------------------------------
	A_i: for i in 0 to 31 generate-- A(i)
		A(i) <= D;
		d_ff_A: d_flip_flop port map(	D => A(i),
												RST=> RST,--resets all previous history of input signal
												CLK=>CLK,--sampling clock
												Q=> A_fpu_inner_product_input(i)
												);
	end generate;
	
------------------------ ( B(i) ) registers --------------------------------------------------
	B_i: for i in 0 to 31 generate-- B(i)
		B(i) <= D;
		d_ff_B: d_flip_flop port map(	D => B(i),
												RST=> RST,--resets all previous history of input signal
												CLK=>CLK,--sampling clock
												Q=> B_fpu_inner_product_input(i)
												);
	end generate;
	
----------------------- inner product instantiation -------------------------------------------
	inner_product: fpu_inner_product
	generic map (N => 32)
	port map(A => A_fpu_inner_product_input,--supposed to be normalized
				B => B_fpu_inner_product_input,--supposed to be normalized
				-------NEED ADD FLAGS (overflow, underflow, etc)
				--overflow:		out std_logic,
				--underflow:		out std_logic,
				output => result
				);
				
---------------------------------- result register ---------------------------------------------
		d_ff_B: d_flip_flop port map(	D => result,
												RST=> RST,--resets all previous history of input signal
												CLK=>CLK,--sampling clock
												Q=> output
												);
---------------------------------------------------------------------------------------------

end behv;

---------------------------------------------------------------------------------------------
