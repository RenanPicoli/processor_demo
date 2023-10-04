--------------------------------------------------
--interrupt controller with vector of interrupt handler
--specialized peripheral
--combines irq of all peripherals in one signal delivered to cpu
--IRQ_IN is level-triggered, IRQ_OUT is edge-triggered
--contains one register to store all IRQ pending (whose IRQ was not sent to cpu)
--contains one register to store all IRQ started (being service by cpu, even if preempted)
--contains one register to store all IRQ active (one-hot of IRQ being serviced NOW)
--cpu loads ISR_ADDR port to its PC to execute the ISR (first clock after IRQ_OUT assertion)
--during interrupt return, the cpu asserts IACK_IN
--after receiving the iack from cpu, controller will send iack to the appropriate peripheral 
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_unsigned

use work.my_types.all;--array32

---------------------------------------------------

entity interrupt_controller_vectorized is
generic	(L: natural := 2);--L: number of IRQ lines
port(	D: in std_logic_vector(31 downto 0);-- input: data to register write (vector and priorities only)
		ADDR: in std_logic_vector(6 downto 0);--address offset of registers relative to peripheral base address
		CLK: in std_logic;-- input
		RST: in std_logic;-- input
		WREN: in std_logic;-- input
		RDEN: in std_logic;-- input
		REQ_READY: in  std_logic;--input
		IRQ_IN: in std_logic_vector(L-1 downto 0);--input: all IRQ lines, sampled internally at rising_edge(CLK)
		IRQ_OUT: buffer std_logic;--output: IRQ line to cpu
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
	
	signal all_registers_output: array32 (95 downto 0) := (others=>(others=>'0'));
	signal all_periphs_rden: std_logic_vector(95 downto 0);
	signal address_decoder_wren: std_logic_vector(95 downto 0);
	type array2 is array (natural range <>) of std_logic_vector (1 downto 0);
	
	------------signals for IRQ control-------------------
	
	--fsm_state(i): (IRQ_pend(i), IRQ_active(i), IRQ_suspended(i))
	signal fsm_state:				array2(31 downto 0);-- the state of each interrupt is a std_logic(1 downto 0)
	
	signal IRQ_IN_prev:			std_logic_vector(31 downto 0);--state of IRQ_IN in previous clock cycle
	signal IRQ_pend:				std_logic_vector(31 downto 0);-- IRQ waiting to be transmitted to CPU
	signal IRQ_started:			std_logic_vector(31 downto 0);-- Means the IRQ was sent. All IRQ being SERVICED (includes nested interrupts)
--	signal IRQ_suspended:		std_logic_vector(31 downto 0);-- flag indicating that the IRQx was active, but preemption occurred
	signal IRQ_active:			std_logic_vector(31 downto 0);-- one-hot of the ISR being executed NOW
	signal IRQ_status:			std_logic_vector(31 downto 0);-- status register
	signal IRQ_curr_out:			std_logic_vector(31 downto 0);-- number of IRQ CURRENTLY being serviced
	signal IRQ_curr_stack_out_oh:std_logic_vector(31 downto 0);-- one-hot of the IRQ CURRENTLY being serviced on top of stack	
	signal tmp_IRQ_curr:			array32(31 downto 0);
	signal IACK_pend_out:		std_logic_vector(31 downto 0);-- where the IACK must be sent when IACK_IN is asserted by processor
	signal IACK_finished:		std_logic_vector(31 downto 0);-- '1' when IACK_OUT is deasserted
	signal irq:						std_logic;
	signal tmp:						std_logic_vector(31 downto 0);
	signal tmp_IRQ_out:			std_logic_vector(31 downto 0);
	signal IRQ_mask:			std_logic_vector(31 downto 0);-- Interrupt masks
	signal sw_IRQ_reg:			std_logic_vector(31 downto 0);-- written by software, requests the interrupt

	------------signals for interrupt vector-------------------
	signal vector: array32 (L-1 downto 0);--address of interrupt handler
	
  -- priority of each interrupt, in case more than one IRQ is asserted in a single cycle
  -- each array entry is a unsigned integer, the lower the integer, the higher the priority (0 is the highest priority)
  -- it is allowed to have IRQ's with the same priority, the first IRQ will be serviced
	signal priorities:array32 (L-1 downto 0);
	
	signal ISR_ADDR_in:	std_logic_vector(31 downto 0);--address of next ISR
	signal tmp_ISR_ADDR:	array32(L-1 downto 0);--address of next ISR
	
	signal preemption: std_logic_vector(31 downto 0) := (others=>'0');--bit i indicates for IRQi that it was preempted
	signal preemption_evt: std_logic;--flag indicating that an active IRQ was preempted
	signal tmp_preemption_evt: std_logic_vector(31 downto 0);
	signal tmp_preferred: array32(L-1 downto 0) := (others=>(others=>'0'));
	signal req: array32(L-1 downto 0) := (others=>(others=>'0'));
	signal tmp_highest_priority: array32(L-1 downto 0) := (others=>(others=>'1'));
	signal tmp_IRQ_active:	array32(L downto 0);-- one-hot of the ISR being executed NOW
	
	constant STACK_LEVELS_LOG2: natural := 4;--up to 16 nested interrupts
	
begin
	--L must be limited to 32 
	assertion: assert (L <= 32) report "parameter L must be <= 32" severity Error;
	
---------------------------------- FSM ------------------------------------
----------- (separate bits for each state, for clarity sake) --------------
		irq_fsm_i: for i in 0 to L-1 generate
			--fsm_state: (IRQ_pend, IRQ_started)
			IRQ_pend(i)			<= fsm_state(i)(1);
			IRQ_started(i)		<= fsm_state(i)(0);
			
			irq_pending: process(RST,preemption,IRQ_IN,IRQ_OUT,IACK_OUT,IRQ_active,CLK,REQ_READY)
			begin
				if(RST='1') then
					--idle state
					fsm_state(i)	<= "00";
					
					--resets previous history
					IRQ_IN_prev(i)	<= '0';
					
				--next state will be determined
				elsif(rising_edge(CLK)) then -- MUST be the same active edge of other RAM peripherals
					IRQ_IN_prev(i)	<= IRQ_IN(i);
					
					-- idle state
					if (fsm_state(i)="00")then
						if (IRQ_IN(i)='1' and IRQ_IN_prev(i)='0') then-- capture IRQ_IN rising_edge
							fsm_state(i) <= "10";--enters in IRQ_pend state
						end if;
					-- IRQ_pend state
					elsif(fsm_state(i)="10" and REQ_READY='1')then
						if (preemption(i)='0')then
							fsm_state(i) <= "01";--enters in IRQ_started state
						end if;
					--IRQ_started state
					elsif(fsm_state(i)="01" and REQ_READY='1')then
						if(IACK_IN='1' and IRQ_active(i)='1')then-- its ISR finished, cpu sent IACK
							fsm_state(i) <= "00";--enters in idle state
						end if;
					end if;
				end if;
			end process;
		end generate irq_fsm_i;
		
		--unused bits receive '0'
		fsm_state(31 downto L)		<= (others => (others => '0'));
		IRQ_pend(31 downto L)		<= (others => '0');
		IRQ_started(31 downto L)	<= (others => '0');
		IRQ_IN_prev(31 downto L)	<= (others => '0');
		
		arbiter: for i in 0 to L-1 generate
			--if two IRQ's of equal priority arrive in the along the same clock cycle, the IRQ of highest index takes precendence
			req(i) <= (i=> (IRQ_pend(i) or IRQ_started(i)), others=>'0');
			tmp_preferred(i) <= req(to_integer(unsigned(priorities(i))));
			tmp_IRQ_active(i) <= tmp_preferred(i) when (tmp_preferred(i) /= x"0000_0000") else tmp_IRQ_active(i+1);
		end generate arbiter;
		tmp_IRQ_active(L) <= x"0000_0000";
		
		IRQ_active <= tmp_IRQ_active(0);
		
		preemption <= (IRQ_pend or IRQ_started) and (not IRQ_active);
			
		-- AFTER irq_pend_out UPDATE
		--é necessário que o software zere os bits das IRQ atendidas e
		--DEPOIS envie o IACK.
		iack_out_write: for i in 0 to L-1 generate
					IACK_OUT(i) <= IACK_IN and IRQ_active(i);
		end generate;
		
--		IRQ_active <= IRQ_started and (not preemption);
--		IRQ_active <= tmp_preferred(L-1);

		-- AFTER irq_pend_out UPDATE
		tmp(0) <= tmp_IRQ_out(0);
		irq_out_write: for i in 0 to L-1 generate
			tmp_i: if (i /= 0) generate
				tmp(i) <= tmp(i-1) or tmp_IRQ_out(i);
			end generate tmp_i;
			
			process(RST,IRQ_IN,CLK,IRQ_started,IRQ_pend,preemption,REQ_READY)
			begin
				if(RST='1')then
					tmp_IRQ_out(i) <= '0';
				elsif(rising_edge(CLK))then
					if(IRQ_started(i)='1' and REQ_READY='1')then
						tmp_IRQ_out(i) <='0';
					elsif(IRQ_pend(i)='1' and preemption(i)='0')then
						tmp_IRQ_out(i) <='1';
					end if;
				end if;
			end process;
		end generate;
		IRQ_OUT <= tmp(L-1);
		
		tmp_ISR_ADDR(0) <= vector(0) when (tmp_IRQ_out(0)='1') else (others=>'0');		
		ISR_ADDR_write: for i in 1 to L-1 generate
			tmp_ISR_ADDR(i) <= vector(i) when (tmp_IRQ_out(i)='1') else tmp_ISR_ADDR(i-1);
		end generate;
		ISR_ADDR <= tmp_ISR_ADDR(L-1);
	
	--DOES NOT CHECK if is a true one-hot, if two bits are high, the MSb will take precendence
	process(IRQ_active)
	begin
		IRQ_curr_out <= (others=>'0');
		for i in 0 to 31 loop
			if(IRQ_active(i) = '1') then
				IRQ_curr_out <= (31 downto 5=>'0') & std_logic_vector(to_unsigned(i,5));
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
	
	-------------software interrupt write----------------------------
	process(CLK,address_decoder_wren,D,RST)
	begin
		if(RST='1')then
			sw_IRQ_reg <= (others=>'0');
		elsif(rising_edge(CLK))then
			if(address_decoder_wren(5)='1')then
				sw_IRQ_reg <= D;
			end if;
		end if;
	end process;
	
	-------------masks write----------------------------
	process(CLK,address_decoder_wren,D,RST)
	begin
		if(RST='1')then
			IRQ_mask <= (others=>'0');
		elsif(rising_edge(CLK))then
			if(address_decoder_wren(6)='1')then
				IRQ_mask <= D;
			end if;
		end if;
	end process;
		
-------------------------- status register ---------------------------------------------------
	--active
	IRQ_status(0) <= '1' when (IRQ_active /= (31 downto 0=>'0')) else '0';
	IRQ_status(31 downto 1) <= (others=>'0');
		
-------------------------- address decoder ---------------------------------------------------
	--addr 000_0000: irq_pend_Q
	--addr 000_0001: irq_active_out
	--addr 000_0010: IRQ_suspended
	--addr 000_0011: IRQ_status
	--addr 000_0100: IRQ_curr_out
	--addr 000_0101: sw_IRQ_reg
	--addr 000_0110: IRQ_mask
	--addr 010_0000 - 011_1111: vector
	--addr 100_0000 - 101_1111: priorities
	--other addresses: unused (zeroed)

	all_registers_output(0) <= IRQ_pend;
	all_registers_output(1) <= IRQ_active;
	all_registers_output(2) <= IRQ_started;
	all_registers_output(3) <= IRQ_status;
	all_registers_output(4) <= IRQ_curr_out;
	all_registers_output(5) <= sw_IRQ_reg;
	all_registers_output(6) <= IRQ_mask;
	
	all_registers_output_gen: for i in 0 to L-1 generate
				all_registers_output(i+32) <= vector(i);
				all_registers_output(i+64) <= priorities(i);
	end generate all_registers_output_gen;
	
	decoder: address_decoder_register_map
	generic map(N => 7)
	port map(ADDR => ADDR,
				RDEN => RDEN,
				WREN => WREN,
				data_in => all_registers_output,
				WREN_OUT => address_decoder_wren,
				data_out => output
	);
end behv;

---------------------------------------------------------------------------------------------