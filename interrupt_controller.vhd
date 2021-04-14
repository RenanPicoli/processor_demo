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

use work.my_types.all;--array32

---------------------------------------------------

entity interrupt_controller is
generic	(L: natural);--L: number of IRQ lines
port(	D: in std_logic_vector(31 downto 0);-- input: data to register write
		ADDR: in std_logic_vector(1 downto 0);--address offset of registers relative to peripheral base address
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
	
	signal irq_pend_Q: std_logic_vector(31 downto 0);
	signal irq_pend_rden: std_logic;
	signal irq_pend_wren: std_logic;-- not used, just to keep form
		
	signal iack_pend_Q: std_logic_vector(31 downto 0);
	signal iack_pend_rden: std_logic;
	signal iack_pend_wren: std_logic;-- not used, just to keep form
		
	signal iack_finished_Q: std_logic_vector(31 downto 0);
	signal iack_finished_rden: std_logic;
	signal iack_finished_wren: std_logic;-- not used, just to keep form
	
	signal all_registers_output: array32 (2 downto 0);
	signal all_periphs_rden: std_logic_vector(2 downto 0);
	signal address_decoder_wren: std_logic_vector(2 downto 0);
	
	------------signals for IRQ control-------------------	
	signal IRQ_pend_out:		std_logic_vector(31 downto 0);-- status of all IRQs
	signal IACK_pend_out:	std_logic_vector(31 downto 0);-- where the IACK must be sent when IACK_IN is asserted by processor
	signal IACK_finished:	std_logic_vector(31 downto 0);	-- '1' when IACK_OUT is deasserted
	signal irq:					std_logic;
	signal tmp:					std_logic_vector(31 downto 0);

begin
	
---------------------------------- IRQ pending register ------------------------------------
		irq_pend_wren <= address_decoder_wren(0);
		irq_pending_i: for i in 0 to L-1 generate
			irq_pending: process(RST,irq_pend_wren,D,IRQ_pend_out,IRQ_IN)
			begin
				if(RST='1') then
					IRQ_pend_out(i) <= '0';
				elsif (irq_pend_wren='1') then --software writes '0' to clear pending bits, '1' is dont't care
					IRQ_pend_out(i) <= IRQ_pend_out(i) and D(i);
				elsif (rising_edge(IRQ_IN(i))) then -- IRQ assertion
					IRQ_pend_out(i) <= '1';
				end if;
			end process;
		end generate irq_pending_i;		
		IRQ_pend_out(31 downto L) <= (others => '0');--unused bits receive '0'
		irq_pend_Q <= IRQ_pend_out;--signal renaming
		
---------------------------------- IACK pending register ------------------------------------
		iack_pend_wren <= address_decoder_wren(1);
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
		iack_pend_Q <= IACK_pend_out;--signal renaming

---------------------------------- IACK finished register ------------------------------------
		iack_finished_wren <= address_decoder_wren(2);
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
		iack_finished_Q <= IACK_finished;--signal renaming
		
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
		
-------------------------- address decoder ---------------------------------------------------
	--addr 00: irq_pend
	--addr 01: iack_pend
	--addr 10: iack_finished
	all_registers_output <= (0=> irq_pend_Q,1=> iack_pend_Q,2=> iack_finished_Q);
	decoder: address_decoder_register_map
	generic map(N => 2)
	port map(ADDR => ADDR,
				RDEN => RDEN,
				WREN => WREN,
				data_in => all_registers_output,
				WREN_OUT => address_decoder_wren,
				data_out => output
	);
end behv;

---------------------------------------------------------------------------------------------