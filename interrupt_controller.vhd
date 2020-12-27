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
		IACK_OUT: buffer std_logic_vector(L-1 downto 0);--output: all IACK lines going to peripherals
		output: out std_logic_vector(31 downto 0)-- output of register reading
);

end interrupt_controller;

---------------------------------------------------

architecture behv of interrupt_controller is

	component d_flip_flop
		port (D:	in std_logic_vector(31 downto 0);--only bit zeroed have effect, '1' is ignored
				rst:	in std_logic;--synchronous reset
				ENA:	in std_logic:='1';--enables writes
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
				);
	end component;

	signal IRQ_pend: 			std_logic_vector(31 downto 0);-- data to be written: from processor or IRQ lines
	signal IRQ_pend_out:		std_logic_vector(31 downto 0);-- status of all IRQs
	signal previous_IRQ_pend:		std_logic_vector(31 downto 0);-- previous vlue of status of all IRQs
	signal IRQ_IN_extended: std_logic_vector(31 downto 0);-- zero-extension of IRQ lines
	signal irq:					std_logic;
	signal tmp:					std_logic_vector(L-1 downto 0);
	signal cleared: 			std_logic_vector(31 downto 0);-- '1' in positions where the pending bit went from '1' to '0'.
	signal clr_rst:			std_logic := '0';
	signal clr_set:			std_logic := '0';

begin
	
---------------------------------- IRQ pending register ------------------------------------
		-- status ('1' if pending) of all IRQ lines
		irq_pending: d_flip_flop port map(	D => IRQ_pend,
														RST=> RST,--resets all previous history of input signal
														CLK=> CLK,--sampling clock
														Q=> IRQ_pend_out
														);
		
		IRQ_IN_extended <= (31 downto L => '0') & IRQ_IN;
		-- based on IRQ lines and signal WREN, decides what to write in IRQ_pend, BEFORE irq_pend_out UPDATE
		IRQ_pend_write: process(WREN, IRQ_IN_extended, D, CLK)
		begin
			if (WREN='1') then
				IRQ_pend	<= D and IRQ_IN_extended;
			else
				IRQ_pend <= IRQ_IN_extended;
			end if;
		end process;
		
		cleared <= (not IRQ_pend_out) and previous_IRQ_pend;--identifica com '1' as posições que foram de '1' a '0'
		
		process (CLK)
		begin
			if (rising_edge(CLK)) then
				previous_IRQ_pend <= IRQ_pend_out;
			end if;
		end process;
		
		-- AFTER irq_pend_out UPDATE
		--é necessário que o software zere os bits das IRQ atendidas e
		--DEPOIS envie o IACK.
		iack_out_write: for i in 0 to L-1 generate
					IACK_OUT(i) <= IACK_IN and cleared(i);
		end generate;

		-- AFTER irq_pend_out UPDATE
		tmp(0) <= IRQ_pend_out(0);
		irq_out_write: for i in 1 to L-1 generate
				tmp(i) <= tmp(i-1) or IRQ_pend_out(i);
		end generate;		
		irq <= tmp(L-1);
		IRQ_OUT <= irq;
		output <= IRQ_pend_out;
end behv;

---------------------------------------------------------------------------------------------
