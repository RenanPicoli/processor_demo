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
use ieee.math_real.all;--ceil and log2

---------------------------------------------------

entity interrupt_controller_vectorized is
generic	(L: natural);--L: number of IRQ lines
port(	D: in std_logic_vector(31 downto 0);-- input: data to register write
		ADDR: in std_logic_vector(6 downto 0);--address offset of registers relative to peripheral base address
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		IRQ_IN: in std_logic_vector(L-1 downto 0);--input: all IRQ lines
		IRQ_OUT: out std_logic;--output: IRQ line to cpu
		IACK_IN: in std_logic;--input: IACK line coming from cpu
		IACK_OUT: buffer std_logic_vector(L-1 downto 0);--output: all IACK lines going to peripherals
		ISR_ADDR: out std_logic_vector(31 downto 0);--address of ISR
		output: out std_logic_vector(31 downto 0)-- output of register reading
);

end interrupt_controller_vectorized;

---------------------------------------------------

architecture behv of interrupt_controller_vectorized is
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
	
	component sdp_ram
		generic (N: natural; L: natural);--N: data width in bits; L: address width in bits
		port (RST: in std_logic;
				WDAT: in std_logic_vector(N-1 downto 0);--data for write
				WCLK: in std_logic;--processor clock for writes
				WADDR: in std_logic_vector(L-1 downto 0);--address for write
				WREN: in std_logic;--enables software write
				RCLK: in std_logic;--processor clock for reading
				RADDR: in std_logic_vector(L-1 downto 0);--address for write
				RDAT: out std_logic_vector(N-1 downto 0)--oldest data
		);
	end component;

	component d_flip_flop
		port (D:	in std_logic_vector(31 downto 0);
				RST: in std_logic;
				ENA:	in std_logic:='1';--enables writes
				CLK:in std_logic;
				Q:	out std_logic_vector(31 downto 0)  
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
	
	signal all_registers_output: array32 (95 downto 0);
	signal all_periphs_rden: std_logic_vector(95 downto 0);
	signal address_decoder_wren: std_logic_vector(95 downto 0);
	
	------------signals for IRQ control-------------------
	signal IRQ_IN_prev:			std_logic_vector(31 downto 0);--state of IRQ_IN in previous clock cycle
	signal IRQ_pend_out:			std_logic_vector(31 downto 0);-- status of all IRQs
	signal IRQ_pend_out_prev:	std_logic_vector(31 downto 0);-- status of all IRQs in previous clock cycle
	signal IACK_pend_out:		std_logic_vector(31 downto 0);-- where the IACK must be sent when IACK_IN is asserted by processor
	signal IACK_OUT_prev:		std_logic_vector(31 downto 0);-- status of all IACKs in previous clock cycle
	signal IACK_finished:		std_logic_vector(31 downto 0);-- '1' when IACK_OUT is deasserted
	signal irq:						std_logic;
	signal tmp:						std_logic_vector(31 downto 0);

	------------signals for interrupt vector-------------------
	signal vector: array32 (L-1 downto 0);--address of interrupt handler
	signal vector_Q: std_logic_vector(31 downto 0);--address of interrupt handler
	signal vector_WREN: std_logic;
	
  -- priority of each interrupt, in case more than one IRQ is asserted in a single cycle
  -- each array entry is a unsigned integer, the lower the integer, the higher the priority (0 is the highest priority)
  -- it is allowed to have IRQ's with the same priority, the first IRQ will be serviced
	signal priorities:array32 (L-1 downto 0);
	signal priorities_Q:std_logic_vector(31 downto 0);
	signal priorities_WREN: std_logic;
	
	signal ISR_ADDR_in:		std_logic_vector(31 downto 0);--address of next ISR
	signal tmp_ISR_ADDR_in:	array32(L-1 downto 0);--address of next ISR
	
begin
	--L must be limited to 32 
	assertion: assert (L <= 32) report "parameter L must be <= 32" severity Error;
	
---------------------------------- IRQ pending register ------------------------------------
		irq_pend_wren <= address_decoder_wren(0);
		irq_pending_i: for i in 0 to L-1 generate
			irq_pending: process(RST,irq_pend_wren,D,IRQ_pend_out,IRQ_IN,IACK_OUT,CLK)
			begin
				if(RST='1') then
					IRQ_pend_out(i) <= '0';
					IRQ_pend_out_prev(i) <= '0';
					IRQ_IN_prev(i)  <= '0';
					IACK_OUT_prev(i) <= '0';
				elsif(rising_edge(CLK)) then -- MUST be the same active edge of other RAM peripherals
					IRQ_IN_prev(i) <= IRQ_IN(i);
					IRQ_pend_out_prev(i) <= IRQ_pend_out(i);
					IACK_OUT_prev(i) <= IACK_OUT(i);
					
					if (IRQ_IN(i)='1' and IRQ_IN_prev(i)='0') then -- IRQ assertion, capture IRQ_IN rising_edge
						IRQ_pend_out(i) <= '1';
					elsif (irq_pend_wren='1') then --software writes '0' to clear pending bits, '1' has no effect
						IRQ_pend_out(i) <= IRQ_pend_out(i) and D(i);
					end if;
				end if;
			end process;
		end generate irq_pending_i;		
		IRQ_pend_out(31 downto L) <= (others => '0');--unused bits receive '0'
		irq_pend_Q <= IRQ_pend_out;--signal renaming
		
---------------------------------- IACK pending register ------------------------------------
		iack_pend_wren <= address_decoder_wren(1);
		--detects where the IACK must be sent when IACK_IN is asserted by processor
		iack_pending_i: for i in 0 to L-1 generate
			iack_pending: process(RST,IACK_finished,IRQ_pend_out,IRQ_pend_out_prev,CLK)
			begin
				if(RST='1') then
					IACK_pend_out(i) <= '0';
				elsif (IACK_finished(i)='1') then --software sends IACK
					IACK_pend_out(i) <= '0';
				elsif (falling_edge(CLK) and IRQ_pend_out(i)='0' and IRQ_pend_out_prev(i)='1') then -- assertion after falling_edge of IRQ_pend_out
					IACK_pend_out(i) <= '1';
				end if;
			end process;
		end generate iack_pending_i;
		IACK_pend_out(31 downto L) <= (others => '0');--unused bits receive '0'
		iack_pend_Q <= IACK_pend_out;--signal renaming

---------------------------------- IACK finished register ------------------------------------
		iack_finished_wren <= address_decoder_wren(2);
		iack_finished_i: for i in 0 to L-1 generate
			process (RST,IACK_OUT,IACK_OUT_prev,IRQ_pend_out,CLK)
			begin
				if(RST='1') then
					IACK_finished(i) <= '0';
				elsif (IRQ_pend_out(i)='1') then
					IACK_finished(i) <= '0';
				elsif (falling_edge(CLK) and IACK_OUT(i)='0' and IACK_OUT_prev(i)='1') then-- asserts at falling_edge of IACK_OUT
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
		
------------------------------ ISR_ADDR update ----------------------------------------
---------------- determines which interrupt will be serviced --------------------------
	process(IRQ_IN,CLK,RST)--must be synchronous to rising_edge(CLK)
	begin		
		if(RST='1')then
			ISR_ADDR <= (others=>'0');
		elsif(rising_edge(CLK))then
			ISR_ADDR <= ISR_ADDR_in;
		end if;		
	end process;
	
	tmp_ISR_ADDR_in(0) <= vector(0) when IRQ_IN(0)='1' else (others=>'0');
	isr_addr_in_gen: for i in 1 to L-1 generate
		-- a interruption being serviced can be preempted by another of higher priority
		tmp_ISR_ADDR_in(i) <= vector(i) when (IRQ_IN(i)='1' and (priorities(i) < priorities(i-1))) else tmp_ISR_ADDR_in(i-1);
	end generate isr_addr_in_gen;
	ISR_ADDR_in <= tmp_ISR_ADDR_in(L-1);
	
	-------------vector write----------------------------
	vector_gen: for i in 0 to L-1 generate
		process(CLK,address_decoder_wren,D,RST)
		begin
			if(RST='1')then
				vector(i) <= (others=>'0');
			elsif(rising_edge(CLK))then
				if(address_decoder_wren(i+32)='1')then
					vector(i) <= D;
				end if;
			end if;
		end process;
	end generate vector_gen;
	
	-------------priorities write----------------------------
	priorities_gen: for i in 0 to L-1 generate
		process(CLK,address_decoder_wren,D,RST)
		begin
			if(RST='1')then
				priorities(i) <= (others=>'0');
			elsif(rising_edge(CLK))then
				if(address_decoder_wren(i+64)='1')then
					priorities(i) <= D;
				end if;
			end if;
		end process;
	end generate priorities_gen;
		
-------------------------- address decoder ---------------------------------------------------
	--addr 00: irq_pend
	--addr 01: iack_pend
	--addr 10: iack_finished
--	all_registers_output <= (0=> irq_pend_Q,1=> iack_pend_Q,2=> iack_finished_Q);

	all_registers_output(0) <= irq_pend_Q;
	all_registers_output(1) <= iack_pend_Q;
	all_registers_output(2) <= iack_finished_Q;
	all_registers_output_gen: for i in 0 to L-1 generate
				all_registers_output(i+32) <= vector(i);
				all_registers_output(i+64) <= priorities(i);
	end generate all_registers_output_gen;
--	all_registers_output(4) <= vector_Q;
--	all_registers_output(8) <= priorities_Q;
	
	decoder: address_decoder_register_map
	generic map(N => 7)
	port map(ADDR => ADDR,--ADDR => ADDR(6 downto 5) & ADDR(1 downto 0),
				RDEN => RDEN,
				WREN => WREN,
				data_in => all_registers_output,
				WREN_OUT => address_decoder_wren,
				data_out => output
	);
end behv;

---------------------------------------------------------------------------------------------