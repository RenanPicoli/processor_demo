--------------------------------------------------
--filter_xN: fifos dedicated to provide access to filter previous input and output
--specialized peripheral, although very simple
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity filter_xN is
-- 0..P: índices dos x
-- P+1..P+Q: índices dos y
generic	(N: natural; P: natural; Q: natural);--N: address width in bits (must be >= log2(P+1+Q))
port(	D: in std_logic_vector(31 downto 0);-- not used (peripheral is read-only)
		DX: in std_logic_vector(31 downto 0);--current filter input
		DY: in std_logic_vector(31 downto 0);--current filter output
		ADDR: in std_logic_vector(N-1 downto 0);-- input
		CLK_x: in std_logic;-- must be filter clock (input sampling)
		CLK_y: in std_logic;-- must be not filter clock (output storing)
		RST: in std_logic;-- input
		WREN: in std_logic;--not used (peripheral supports only read)
		RDEN: in std_logic;-- input
		output: out std_logic_vector(31 downto 0)-- output
);

end filter_xN;

---------------------------------------------------

architecture behv of filter_xN is

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
	
	signal all_registers_output: array32(0 to P+Q);--P+1 reg x, Q reg y, others will be zeroed in decoder
	signal x_fifo_output: array32(0 to P);--outputs of register holding previous samples
	signal y_fifo_output: array32(0 to Q-1);--outputs of register holding previous filter outputs
	
	-- defined but will not be used since we are only reading registers
	signal ena_reg: std_logic_vector(0 to P+Q);--ena input of registers (write enable)
	
begin
-------------------------- fifo storing previous P+1 sammples --------------------------------
	x_fifo: process(CLK_x,RST,DX)
	begin
		if (RST='1') then
			x_fifo_output <= (others=>(others=>'0'));
		elsif(CLK_x'event and CLK_x='1') then
			x_fifo_output <= DX & x_fifo_output(0 to P-1);--DX já entra na posição 0
		end if;
	end process;
												
-------------------------- fifo storing previous Q outputs ----------------------------------
	y_fifo: process(CLK_y,RST,DY)
	begin
		if (RST='1') then
			y_fifo_output <= (others=>(others=>'0'));
		elsif(CLK_y'event and CLK_y='1') then
			y_fifo_output <= DY & y_fifo_output(0 to Q-2);--DY já entra na posição 0
		end if;
	end process;

	all_registers_output <= x_fifo_output & y_fifo_output;

-------------------------- address decoder ---------------------------------------------------
	decoder: address_decoder_register_map
	generic map(N => N)
	port map(ADDR => ADDR,
				RDEN => RDEN,
				WREN => WREN,-- not used (supports only readings)
				data_in => all_registers_output,
				WREN_OUT => ena_reg,
				data_out => output
	);

end behv;