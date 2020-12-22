--------------------------------------------------
--interrupt controller
--specialized peripheral
--combines irq of all peripherals (MMU and filter) in one signal delivered to cpu
--contains one register to store all IRQ pending (one bit for each source)
--software must read this register to determine which ISR to execute
--after this, software will clean the corresponding bit
--after receiving the iack from cpu, controller will send iack to the appropriate peripheral 
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity interrupt_controller is
generic	(L: natural);--L: number of IRQ lines
port(	D: in std_logic_vector(31 downto 0);-- input: data to register write
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		IRQ_IN: in std_logic_vector(L-1 downto 0);--input: all IRQ lines
		IRQ_OUT: out std_logic;--output: IRQ line to cpu
		IACK_IN: in std_logic;--input: IACK line coming from cpu
		IACK_OUT: out std_logic_vector(L-1 downto 0);--output: all IACK lines going to peripherals
		output: out std_logic_vector(31 downto 0)-- output of register reading
);

end interrupt_controller;

---------------------------------------------------

architecture behv of interrupt_controller is

	component d_flip_flop
		port (D:	in std_logic_vector(31 downto 0);--only bit zeroed have effect, '1' is ignored
				rst:	in std_logic;--synchronous reset
				ENA:	in std_logic;--enables writes
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;

	signal IRQ_pend: 			std_logic_vector(31 downto 0);-- data to be written: from processor or IRQ lines
	signal IRQ_IN_extended: std_logic_vector(31 downto 0);-- zero-extension of IRQ lines

begin
	
---------------------------------- IRQ pending register ------------------------------------
		-- status ('1' if pending) of all IRQ lines
		irq_pending: d_flip_flop port map(	D => IRQ_pend,
														RST=> RST,--resets all previous history of input signal
														ENA=> WREN,
														CLK=> CLK,--sampling clock
														Q=> output
														);
		
		IRQ_IN_extended <= (31 downto L => '0') & IRQ_IN;
		-- based on IRQ lines and signal WREN, decides what to write in IRQ_pend
		process(WREN, IRQ_IN)
		begin
			if (WREN='1') then
				IRQ_pend <= D and IRQ_IN_extended;
			else
				IRQ_pend <= IRQ_IN_extended;
			end if;
		end process;
end behv;

---------------------------------------------------------------------------------------------
