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
use ieee.numeric_std.all;--to_unsigned

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
		IRQ_IN: in std_logic_vector(L-1 downto 0);--input: all IRQ lines, sampled internally at rising_edge(CLK)
		IRQ_OUT: out std_logic;--output: IRQ line to cpu
		IACK_IN: in std_logic;--input: IACK line coming from cpu
		IACK_OUT: buffer std_logic_vector(L-1 downto 0);--output: all IACK lines going to peripherals
		ISR_ADDR: out std_logic_vector(31 downto 0);--address of ISR, it is updated the next clock cycle after the IRQ detection
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

	component stack
		generic(L: natural);--log2 of number of stored words
		port (CLK: in std_logic;--active edge: rising_edge
				rst: in std_logic;-- active high asynchronous reset (should be deasserted at rising_edge of CLK)
				--STACK INTERFACE
				pop: in std_logic;
				push: in std_logic;
				addsp: in std_logic;--sp <- sp + imm
				imm: in std_logic_vector(L-1 downto 0);--imm > 0: deletes vars, imm < 0: reserves space for vars
				stack_in: in std_logic_vector(31 downto 0);-- word to be pushed
				sp: buffer std_logic_vector(L-1 downto 0);-- points to last stacked item (address of a 32-bit word)
				stack_out: out std_logic_vector(31 downto 0);--data retrieved from stack
				--MEMORY-MAPPED INTERFACE
				D: in std_logic_vector(31 downto 0);-- data to be written by memory-mapped interface
				WREN: in std_logic;--write enable for memory-mapped interface
				ADDR: in std_logic_vector(L-1 downto 0);-- address to be written by memory-mapped interface
				Q:		out std_logic_vector(31 downto 0)-- data output for memory-mapped interface
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
	signal IRQ_pend_out:			std_logic_vector(31 downto 0);-- IRQ waiting to be transmitted to CPU
	signal IRQ_pend_out_prev:	std_logic_vector(31 downto 0);-- status of all IRQs in previous clock cycle
	signal IRQ_active_out:		std_logic_vector(31 downto 0);-- all IRQ being SERVICED (includes nested interrupts)
	signal IRQ_active_in:		std_logic_vector(31 downto 0);-- signal used to feed IRQ_active_out register
	signal IRQ_curr_out:			std_logic_vector( 4 downto 0);-- number of IRQ CURRENTLY being serviced
	signal IRQ_curr_out_oh:		std_logic_vector(31 downto 0);-- one-hot of the IRQ CURRENTLY being serviced
	signal IRQ_curr_stack_out_oh:std_logic_vector(31 downto 0);-- one-hot of the IRQ CURRENTLY being serviced on top of stack	
	signal tmp_IRQ_curr:			array32(31 downto 0);
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
	
	signal preemption: std_logic;
	signal tmp_preemption: std_logic_vector(31 downto 0);
	
	constant STACK_LEVELS_LOG2: natural := 4;--up to 16 nested interrupts
	
begin
	--L must be limited to 32 
	assertion: assert (L <= 32) report "parameter L must be <= 32" severity Error;
	
---------------------------------- IRQ pending register ------------------------------------
		irq_pend_wren <= address_decoder_wren(0);
		irq_pending_i: for i in 0 to L-1 generate
			irq_pending: process(RST,irq_pend_wren,D,IRQ_pend_out,IRQ_curr_out_oh,IRQ_IN,IACK_OUT,CLK)
			begin
				if(RST='1') then
					IRQ_pend_out(i) <= '0';
					IRQ_pend_out_prev(i) <= '0';
					IRQ_IN_prev(i)  <= '0';
					IACK_OUT_prev(i) <= '0';
				elsif(IRQ_curr_out_oh(i)='1')then					
					IRQ_pend_out(i) <= '0';
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

		irq_stack: stack
			generic map (L => STACK_LEVELS_LOG2)
			port map (CLK => CLK,--active edge: rising_edge
						rst => RST,-- active high asynchronous reset (should be deasserted at rising_edge)
						--STACK INTERFACE
						pop => IACK_IN,
						push => preemption,
						addsp => '0',
						imm => (others=>'0'),--imm > 0: deletes vars, imm < 0: reserves space for vars
						stack_in => IRQ_curr_out_oh,-- word to be pushed
						sp => open,-- points to last stacked item (address of a 32-bit word)
						stack_out => IRQ_curr_stack_out_oh,--data retrieved from stack
						--MEMORY-MAPPED INTERFACE
						D => (others=>'0'),-- data to be written by memory-mapped interface
						WREN => '0',--write enable for memory-mapped interface
						ADDR => (others=>'0'),-- address to be written by memory-mapped interface
						Q    => open-- data output for memory-mapped interface
				);
		
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
	process(IRQ_active_in,CLK,RST)--must be synchronous to rising_edge(CLK)
	begin
		if(RST='1')then
			IRQ_active_out <= (others=>'0');
		elsif(rising_edge(CLK))then
			IRQ_active_out <= IRQ_active_in;
		end if;
	end process;
	ISR_ADDR <= ISR_ADDR_in;
	
	tmp_ISR_ADDR_in(0) <= vector(0) when IRQ_pend_out(0)='1' else (others=>'0');
	tmp_IRQ_curr(0) <= std_logic_vector(to_unsigned(2**0,32)) when IRQ_pend_out(0)='1' else (others=>'0');
	tmp_preemption(0) <= '0'; 
	isr_addr_in_gen: for i in 1 to L-1 generate
		-- a interruption being serviced can be preempted by another of higher priority
		tmp_ISR_ADDR_in(i) <= vector(i) when (IRQ_pend_out(i)='1' and (priorities(i) < priorities(i-1))) else tmp_ISR_ADDR_in(i-1);
		tmp_IRQ_curr(i) <= std_logic_vector(to_unsigned(2**i,32)) when (IRQ_pend_out(i)='1' and (priorities(i) < priorities(i-1))) else tmp_IRQ_curr(i-1);
		
		tmp_preemption(i) <= '1' when ((IRQ_curr_out_oh /= (31 downto 0 =>'0')) and
												(to_integer(unsigned(IRQ_curr_out)) /= i) and
												(IRQ_pend_out(i)='1' and (priorities(i) < priorities(to_integer(unsigned(IRQ_curr_out)))))) else
												tmp_preemption(i-1);
	end generate isr_addr_in_gen;
	ISR_ADDR_in <= tmp_ISR_ADDR_in(L-1);
	IRQ_curr_out_oh <= tmp_IRQ_curr(L-1);
	preemption <= tmp_preemption(L-1);
	
	--DOES NOT CHECK if is a true one-hot, if two bits are high, the MSb takes precendence
	process(IRQ_curr_out_oh)
	begin
		IRQ_curr_out <= (others=>'0');
		for i in 31 downto 0 loop
			if(IRQ_curr_out_oh(i) = '1') then
				IRQ_curr_out <= std_logic_vector(to_unsigned(i,5));
			end if;
		end loop;
	end process;
	
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