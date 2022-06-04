--------------------------------------------------
--implementation of filter
--Implements IIR filter, if you want FIR filter, set all a coefficients to zero
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity filter is
-- 0..P: índices dos coeficientes de x (b)
-- 1..Q: índices dos coeficientes de y (a)
generic	(P: natural; Q: natural);
port(	input:	in std_logic_vector(31 downto 0);-- input
		RST:	in std_logic;--asynchronous reset
		WREN:	in std_logic;--enables writing on coefficients
		CLK:	in std_logic;--sampling clock
		coeffs:	in array32((P+Q) downto 0);-- todos os coeficientes são lidos de uma vez
		IACK: in std_logic_vector(1 downto 0);--iack
		IRQ:	out std_logic_vector(1 downto 0);--bit 0: new sample arrived, bit 1: new output is ready
		output: out std_logic_vector(31 downto 0)-- output registered (updated at falling_edge of CLK)
);

end filter;

---------------------------------------------------

architecture behv of filter is
	
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
	
	component d_flip_flop--delays
		port (D:	in std_logic_vector(31 downto 0);
				RST: in std_logic;
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;
	
	signal x: array32 (0 to P):= (others=>(others=>'0'));--x(i) <= x[n-i]
	signal y: array32 (0 to Q):= (others=>(others=>'0'));--y(i) <= y[n-i]
	signal sum_feed_forward: array32 (0 to P);--results of sumations in feed forward part
	signal sum_feedback: array32 (0 to Q);--results of sumations in feedback part
	signal feedback_feed_forward: std_logic_vector(31 downto 0);--connects feedback and feed forward parts
	signal prod_feed_forward: array32 (0 to P);--results of products in feed forward part
	signal prod_feedback: array32 (0 to Q);--results of products in feedback part
	signal a: array32 (1 to Q) := (others=>(others=>'0'));--"a" coefficients (feedback part)
	signal b: array32 (0 to P) := (others=>(others=>'0'));--"b" coefficients (feed forward part)
	signal d_ff_y_CLK: std_logic;-- necessary delay between sampling x and y (since changing x will change y)
										  -- it's necessary necessary defining a signal instead of using not CLK because of modelsim (VHDL wouldn't complain)
	signal output_signal: std_logic_vector(31 downto 0);
begin					   
---------- x signal flip flops --------------------------------------------------------------
	--samples input
	d_ff_x0: d_flip_flop port map(	D => input,
												RST=> RST,--resets all previous history of input signal
												CLK=>CLK,--sampling clock
												Q=> x(0)
												);
	
	x_i: for i in 1 to P generate-- x[n-i]
		d_ff_x: d_flip_flop port map(	D => x(i-1),
												RST=> RST,--resets all previous history of input signal
												CLK=>CLK,--sampling clock
												Q=> x(i)
												);
	end generate;
	
---------- y signal flip flops --------------------------------------------------------------
	d_ff_y_CLK <= not CLK;-- necessary delay between sampling x and y (since changing x will change y)
								 -- it's necessary defining a signal instead of using not CLK because of modelsim (VHDL wouldn't complain) 
--	d_ff_y0: d_flip_flop port map(	D => sum_feedback(0),
--												RST=> RST,--resets all previous history of output signal
--												CLK=> d_ff_y_CLK,--sampling clock
--												Q=> y(0)
--												);
	d_ff_y0: d_flip_flop port map(	D => sum_feedback(0),
												RST=> RST,--resets all previous history of output signal
												CLK=> d_ff_y_CLK,--sampling clock
												Q=> y(0)
												);
												
												
	y_j: for j in 1 to Q generate-- y[n-j]
		d_ff_y: d_flip_flop port map(	D => y(j-1),
												RST=> RST,--resets all previous history of output signal
												CLK=> CLK,--sampling clock
												Q=> y(j)
												);
	end generate;
--	output <= sum_feedback(0);
	output <= y(0);
	
---------- feed-forward (bi*x[n-i]) adders --------------------------------------------------
	sum_i: for i in 0 to P-1 generate
		adder: fpu_adder port map(	A => sum_feed_forward(i+1),--supposed to be normalized
											B => prod_feed_forward(i),--supposed to be normalized
											-------NEED ADD FLAGS (overflow, underflow, etc)
											--overflow:		out std_logic,
											--underflow:		out std_logic,
											result => sum_feed_forward(i)
											);
	end generate;
	feedback_feed_forward <= sum_feed_forward(0);
	sum_feed_forward(P) <= prod_feed_forward(P);

---------- feedback (aj*y[n-j]) adders ------------------------------------------------------
	sum_j: for j in 0 to Q-1 generate
		adder: fpu_adder port map(	A => sum_feedback(j+1),--supposed to be normalized
											B => prod_feedback(j),--supposed to be normalized
											-------NEED ADD FLAGS (overflow, underflow, etc)
											--overflow:		out std_logic,
											--underflow:		out std_logic,
											result => sum_feedback(j)
											);
	end generate;
	sum_feedback(Q) <= prod_feedback(Q);
	prod_feedback(0) <= feedback_feed_forward;

---------- feed-forward (bi*x[n-i]) multipliers ---------------------------------------------
	mult_i: for i in 0 to P generate
		multiplier: fpu_mult port map(A => x(i),--supposed to be normalized
												B => b(i),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => prod_feed_forward(i)
												);
	end generate;

---------- feedback (aj*y[n-j]) multipliers -------------------------------------------------
	mult_j: for j in 1 to Q generate
		multiplier: fpu_mult port map(A => y(j),--supposed to be normalized
												B => a(j),--supposed to be normalized
												-------NEED ADD FLAGS (overflow, underflow, etc)
												--overflow:		out std_logic,
												--underflow:		out std_logic,
												result => prod_feedback(j)
												);
	end generate;
---------------------------------------------------------------------------------------------

	-- updating coefficients
   coeff_update: process(CLK,RST)
   begin
	if (RST='1') then--asynchronous reset
		b<= (others=>(others=>'0'));
		a<= (others=>(others=>'0'));
	elsif (rising_edge(CLK)) then
		if (WREN ='1') then--if the filter is allowed to update its coefficients
			coeffs_b: for i in 0 to P loop--coeficientes de x (b)
				b(i) <= coeffs(i);
			end loop;
			
			coeffs_a: for j in 1 to Q loop--coeficientes de y (a)
				a(j) <= coeffs(j+P);
--				a(j) <= (others=>'0');--forces FIR
			end loop;
		end if;
	end if;
   end process;	

	---------------IRQ--------------------------------
	---------new sample arrived-----------------------
	irq_0: process(CLK,IACK,RST)
	begin
		if(RST='1') then
			IRQ(0) <= '0';
		elsif (IACK(0) ='1') then
			IRQ(0) <= '0';
		elsif rising_edge(CLK) then
			IRQ(0) <= '1';
		end if;
	end process;	
	---------new output is ready-----------------------
	irq_1: process(CLK,IACK,RST)
	begin
		if(RST='1') then
			IRQ(1) <= '0';
		elsif (IACK(1) ='1') then
			IRQ(1) <= '0';
		elsif falling_edge(CLK) then
			IRQ(1) <= '1';
		end if;
	end process;	

end behv;

---------------------------------------------------------------------------------------------