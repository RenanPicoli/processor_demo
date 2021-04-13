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
	
	signal IRQ_pend_out:		std_logic_vector(31 downto 0);-- status of all IRQs
	signal IACK_pend_out:	std_logic_vector(31 downto 0);-- where the IACK must be sent when IACK_IN is asserted by processor
	signal IACK_finished:	std_logic_vector(31 downto 0);	-- '1' when IACK_OUT is deasserted
	signal irq:					std_logic;
	signal tmp:					std_logic_vector(31 downto 0);

begin
	
---------------------------------- IRQ pending register ------------------------------------
		irq_pending_i: for i in 0 to L-1 generate
			irq_pending: process(RST,WREN,D,IRQ_pend_out,IRQ_IN)
			begin
				if(RST='1') then
					IRQ_pend_out(i) <= '0';
				elsif (WREN='1') then --software writes '0' to clear pending bits, '1' is dont't care
					IRQ_pend_out(i) <= IRQ_pend_out(i) and D(i);
				elsif (rising_edge(IRQ_IN(i))) then -- IRQ assertion
					IRQ_pend_out(i) <= '1';
				end if;
			end process;
		end generate irq_pending_i;		
		IRQ_pend_out(31 downto L) <= (others => '0');--unused bits receive '0'
		
		--detects where the IACK must be sent when IACK_IN is asserted by processor
		iack_pending_i: for i in 0 to L-1 generate
			iack_pending: process(RST,IACK_finished,IRQ_pend_out)
			begin
				if(RST='1') then
					IACK_pend_out(i) <= '0';
				elsif (IACK_finished(i)='1') then --software sends IACK
					IACK_pend_out(i) <= '0';
				elsif (falling_edge(IRQ_pend_out(i))) then -- IRQ assertion
					IACK_pend_out(i) <= '1';
				end if;
			end process;
		end generate iack_pending_i;
		IACK_pend_out(31 downto L) <= (others => '0');--unused bits receive '0'
		
		iack_finished_i: for i in 0 to L-1 generate
			process (RST,IACK_OUT,IRQ_pend_out,CLK)
			begin
				if(RST='1') then
					IACK_finished(i) <= '0';
				elsif (IRQ_pend_out(i)='1') then
					IACK_finished(i) <= '0';
				elsif (falling_edge(IACK_OUT(i))) then-- asserts previous value
					IACK_finished(i) <= '1';
				end if;
			end process;
		end generate iack_finished_i;
		IACK_finished(31 downto L) <= (others => '0');--unused bits receive '0'
		
		-- AFTER irq_pend_out UPDATE
		--é necessário que o software zere os bits das IRQ atendidas e
		--DEPOIS envie o IACK.
		iack_out_write: for i in 0 to L-1 generate
					IACK_OUT(i) <= IACK_IN and IACK_pend_out(i);
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