--------------------------------------------------
--hardware implementation of inner product
--specialized hardware, that is why it is not included in fpu
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

--combinatorial, data comes from register external to this component
entity fpu_inner_product is
generic	(N: natural);--number of elements of each vector
port(	A:	in array32(N-1 downto 0);-- input
		B:	in array32(N-1 downto 0);-- input
		output: out std_logic_vector(31 downto 0)-- output
);

end fpu_inner_product;

---------------------------------------------------

architecture behv of fpu_inner_product is
	
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
	
	signal sum: array32 (0 to N-1);--results of sumations of products
	signal final_sum: std_logic_vector(31 downto 0);--connects feedback and feed forward parts
	signal prod: array32 (0 to N-1);--results of products

begin
	
	output <= final_sum;
	
---------- feed-forward ( A(i)*B(i) ) adders --------------------------------------------------
	sum_i: for i in 0 to N-2 generate
		adder: fpu_adder port map(	A => sum(i+1),--supposed to be normalized
											B => prod(i),--supposed to be normalized
											-------NEED ADD FLAGS (overflow, underflow, etc)
											--overflow:		out std_logic,
											--underflow:		out std_logic,
											result => sum(i)
											);
	end generate;
	final_sum <= sum(0);
	sum(N-1) <= prod(N-1);

---------- feed-forward ( A(i)*B(i) ) multipliers ---------------------------------------------
	mult_i: for i in 0 to N-1 generate
		multiplier: fpu_mult port map(A => A(i),--supposed to be normalized
												B => B(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => prod(i)
												);
	end generate;
---------------------------------------------------------------------------------------------

end behv;

---------------------------------------------------------------------------------------------
