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

--pipelined, data comes from register external to this component
entity fpu_inner_product is
generic	(N: natural);--number of elements of each vector
port(	CLK: in std_logic;
		RST: in std_logic;
		req_in: in std_logic;
		A:	in array32(N-1 downto 0);-- input
		B:	in array32(N-1 downto 0);-- input
		req_ready: out std_logic;--synchronous to rising_edge(CLK)
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
	
	component d_flip_flop

	port(	D:	in std_logic_vector(31 downto 0);
			RST:	in std_logic;--asynchronous reset
			ENA:	in std_logic:='1';--enables writes
			CLK:	in std_logic;
			Q:	out std_logic_vector(31 downto 0)  
	);

	end component;
	
	signal sum: array32 (0 to N-1);--results of sumations of products
	signal final_sum: std_logic_vector(31 downto 0);--connects feedback and feed forward parts
	signal prod: array32 (0 to N-1);--results of products
	signal dff_prod: array32 (0 to N-1);--results of products
	signal req: std_logic_vector (0 to 3);--req_in is passed between pipeline stages
	signal dff_sum_3: std_logic_vector(31 downto 0);

begin
												
	--3rd stage of pipeline
	dff_output: d_flip_flop port map(D => final_sum,
												RST=> RST,--resets all previous history of input signal
												ENA=> '1',
												CLK=> CLK,--sampling clock
												Q=> output
												);
	
---------- feed-forward ( A(i)*B(i) ) adders --------------------------------------------------
	sum_i: for i in 0 to N-2 generate
		sum_3: if i=N/2-1 generate
			adder: fpu_adder port map(	A => sum(i+1),--supposed to be normalized
												B => dff_prod(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => dff_sum_3
												);
			--2nd stage of pipeline
			dff_sum: d_flip_flop port map(	D => dff_sum_3,
														RST=> RST,--resets all previous history of input signal
														ENA=> '1',
														CLK=> CLK,--sampling clock
														Q=> sum(i)
														);
		end generate;
		sum_others: if i/=N/2-1 generate
			adder: fpu_adder port map(	A => sum(i+1),--supposed to be normalized
												B => dff_prod(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => sum(i)
												);
		end generate;
	end generate;
	final_sum <= sum(0);
	sum(N-1) <= dff_prod(N-1);

---------- feed-forward ( A(i)*B(i) ) multipliers ---------------------------------------------
	mult_i: for i in 0 to N-1 generate
		multiplier: fpu_mult port map(A => A(i),--supposed to be normalized
												B => B(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => prod(i)
												);
												
		--1st stage of pipeline
		dff_mult: d_flip_flop port map(	D => prod(i),
													RST=> RST,--resets all previous history of input signal
													ENA=> '1',
													CLK=> CLK,--sampling clock
													Q=> dff_prod(i)
													);
	end generate;
---------------------------------------------------------------------------------------------

------------------------------ ready generation ---------------------------------------------
-------------------(as many registers as pipeline stages)------------------------------------
	ready_i: for i in 1 to 3 generate
		process(CLK,RST,req)
		begin
			if(RST='1')then
				req(i) <= '1';
			elsif(rising_edge(CLK))then
				req(i) <= req(i-1);
			end if;
		end process;
	end generate;
	req(0) <= req_in;
	req_ready <= req(3);

end behv;

---------------------------------------------------------------------------------------------
