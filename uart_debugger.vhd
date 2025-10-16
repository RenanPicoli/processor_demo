library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
--use ieee.numeric_std.all;--to_integer, unsigned
use work.my_types.all;--array32, boundaries
use ieee.math_real.all;--ceil and log2

entity uart_debugger is
    port (
		rst: in std_logic;
		------CPU ITFC---------
		clk: in std_logic;--same as CPU clock (might be extended by processor during memory reading/writing)
		dbg_data_0: buffer std_logic_vector(31 downto 0);-- instructions, value for writes, value for reading
		dbg_data_1: buffer std_logic_vector(31 downto 0);-- address for memory access, register for reg_file access
		dbg_data_2: in std_logic_vector(31 downto 0);-- values for reading
		--command ports bellow must be asserted only for 1 clk cycle, together with dbg_irq
		dbg_sr: out std_logic;-- set register enable
		dbg_gr: out std_logic;-- get register enable
		dbg_sm: out std_logic;-- set memory enable
		dbg_gm: out std_logic;-- get memory enable
		dbg_inj: out std_logic;--inject instruction
		dbg_brk: out std_logic;--instruction break
		dbg_nxt: out std_logic;--next instruction
		dbg_cont: out std_logic;--continue instruction
		dbg_irq: buffer std_logic;-- debug irq, must be asserted for 1 clk cycle (which can be extended)
		
		IACK: in std_logic;--interrupt acknowledgement
		next_pc: in std_logic_vector(31 downto 0);-- byte address: monitor PC (pc_in) for breakpoints
		------UART PHY---------
		uart_phy_clk: in std_logic;--bit clock (not transmitted)
		rx: in std_logic;
		tx: out std_logic
	);
end uart_debugger;

architecture Behavioral of uart_debugger is
    -- Declaração do componente UART Core
    component uart_core
        port (
            rst: in std_logic;
            clk: in std_logic;
            D: in std_logic_vector(7 downto 0);
            wren: in std_logic;
            rden: in std_logic;
            Q: out std_logic_vector(7 downto 0);
				--INTERRUPT ACK
				IACK: in std_logic;--resets all flags!
            data_sent: out std_logic;
            data_received: out std_logic;
            stop_error: out std_logic;
            tx: out std_logic;
            rx: in std_logic
        );
    end component;
	
	component dc_fifo
		generic (N: natural; REQUESTED_FIFO_DEPTH: natural);--REQUESTED_FIFO_DEPTH does NOT need to be power of TWO
		port (
				DATA_IN: in std_logic_vector(N-1 downto 0);--for register write
				WCLK: in std_logic;--processor clock for writes
				RCLK: in std_logic;--processor clock for reading
				RST: in std_logic;--asynchronous reset
				WREN: in std_logic;--enables software write
				POP: in std_logic;--aka RDEN
				FULL: buffer std_logic;--'1' indicates that fifo is (almost) full
				EMPTY: buffer std_logic;--'1' indicates that fifo is (almost) empty
				OVF: out std_logic;--'1' indicates that fifo is overflowing (and dropping data)
				DATA_OUT: out std_logic_vector(N-1 downto 0)--oldest data
		);
	end component;
		
    -- Registradores para armazenar dados e status
    signal status_reg: std_logic_vector(31 downto 0); -- 0: data_sent, 1: data_received, 2: stop_error
	
	signal	uart_data_sent: std_logic;
	signal	uart_data_received: std_logic;
	signal	uart_stop_error: std_logic;
	
	signal	uart_wren: std_logic;
	signal	uart_rden: std_logic;
	signal	uart_data_out: std_logic_vector(7 downto 0);
	signal	uart_data_in: std_logic_vector(7 downto 0);
	signal	uart_iack: std_logic;--it is necessary to clear uart_data_received after single byte commands (to avoid repeating forever)
	
	signal	uart_word_sent: std_logic;

	signal status_wren:	std_logic;
	signal status_rden:	std_logic;	
		
	type state is (IDLE,CMD,D0,D1,D2,D3,A3,A2,A1,A0);
	signal dbg_state: state;
	signal next_dbg_state: state;
	
	signal data_received_evt: std_logic;
	signal prev_uart_data_received: std_logic;
	
	--flags to indicate which cmd is being processed
	--valid until the next cmd is latched
	signal get_mem_cmd: std_logic;
	signal set_mem_cmd: std_logic;
	signal get_reg_cmd: std_logic;
	signal set_reg_cmd: std_logic;
	signal set_brk_cmd:	std_logic;
	signal clr_brk_cmd:	std_logic;
	signal clr_all_brk_cmd:	std_logic;
	signal inject_cmd:	std_logic;
	signal next_cmd:	std_logic;
	signal breakpt_cmd:	std_logic;
	signal continue_cmd:std_logic;
	
	signal get_mem_cmd_delayed: std_logic;
	signal dbg_irq_delayed: std_logic;
	
	signal cmd_one_hot: std_logic_vector(10 downto 0);

	constant REQUESTED_SIZE: natural := 128;
	constant REQUESTED_FIFO_DEPTH: natural := 4;
	constant W: natural := 2;--2**W is the number of uart bytes to encode one processor word
	constant D: natural := natural(ceil(log2(real(REQUESTED_SIZE))));--number of bits needed to select all cache locations
	constant SIZE: natural := 2**D;--real cache size in words SHOULD BE A POWER OF 2 to prevent errors;
	signal req_ready: std_logic;--indicates that data already contains the requested data
	signal dc_fifo_wren:	std_logic;-- so that cache is written only when ready
	signal req_wren: std_logic;--write requested
	signal req_ready_sr: std_logic_vector(1 downto 0);
	signal dc_fifo_empty:	std_logic;
	signal dc_fifo_empty_prev:	std_logic;
	signal dc_fifo_full:	std_logic;
	signal dc_fifo_pop:		std_logic;
	signal dc_fifo_ovf:		std_logic;
	signal dc_fifo_data_out:std_logic_vector(31 downto 0);

	constant log2_FIFO_DEPTH: natural := natural(ceil(log2(real(REQUESTED_FIFO_DEPTH))));--number of bits needed to select all fifo locations
	signal write_addr: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- NEXT position to write on
	signal read_addr: std_logic_vector(log2_FIFO_DEPTH-1 downto 0);-- CURRENT position read

	--signal word_idx: natural;--index of the word being written to program memory (0,1,...,2**W-1)
	subtype word_idx_t is natural range 0 to 2**W-1;
	signal word_idx: word_idx_t;--index of the word being written to program memory
	signal full: std_logic;--tdp_ram is full

	signal uart_cache_wren: std_logic;
	signal uart_cache_rden: std_logic;
	signal uart_cache_write_data: std_logic_vector(31 downto 0);
	signal uart_cache_ready: std_logic;
	signal uart_cache_req_addr: std_logic_vector(31 downto 0);
	signal uart_cache_mem_addr: std_logic_vector(7 downto 0);
	
	--signals for setting/clearing the breakpoints
	type reg_array is array (0 to 7) of std_logic_vector(31 downto 0);
	signal breakpoints : reg_array := (others => (others => '0'));
	signal valid_bits  : std_logic_vector(7 downto 0) := (others => '0');
	signal index       : integer range 0 to 8 := 0;
   signal set_bp     : std_logic;
   signal clear_bp   : std_logic_vector(7 downto 0);
	signal clear_all  : std_logic;
   signal bp_valid   : std_logic_vector(7 downto 0);
	signal bp_match	: std_logic;--next_pc matches one of the VALID breakpoints
   signal match   	: std_logic_vector(7 downto 0);
	signal tmp_matches_ored: std_logic_vector(8 downto 0);
	
	--preserving signals during synthesis for debugging
	attribute preserve : boolean;
	attribute preserve of cmd_one_hot: signal is true;
	attribute preserve of uart_cache_write_data: signal is true;
	attribute preserve of uart_data_in: signal is true;
	attribute preserve of uart_data_received: signal is true;
	attribute preserve of prev_uart_data_received: signal is true;
	attribute preserve of data_received_evt: signal is true;
	attribute preserve of dbg_state: signal is true;
	attribute preserve of next_dbg_state: signal is true;
	attribute preserve of bp_match: signal is true;
	attribute preserve of bp_valid: signal is true;
	attribute preserve of breakpoints: signal is true;
	attribute preserve of set_brk_cmd: signal is true;
	attribute preserve of clr_brk_cmd: signal is true;
	attribute preserve of clr_all_brk_cmd: signal is true;
	attribute preserve of index: signal is true;
	
begin
	get_mem_cmd 	<= cmd_one_hot(0);
	set_mem_cmd 	<= cmd_one_hot(1);
	get_reg_cmd 	<= cmd_one_hot(2);
	set_reg_cmd 	<= cmd_one_hot(3);
	inject_cmd		<= cmd_one_hot(4);
	next_cmd 		<= cmd_one_hot(5);
	breakpt_cmd		<= cmd_one_hot(6);
	continue_cmd	<= cmd_one_hot(7);
	set_brk_cmd		<= cmd_one_hot(8);
	clr_brk_cmd		<= cmd_one_hot(9);
	clr_all_brk_cmd<= cmd_one_hot(10);
	

	process(rst,clk,uart_data_out,dbg_state,uart_data_received,dbg_irq)
	begin
		if(rst='1')then
				cmd_one_hot <= 	"00000000000";
		elsif(rising_edge(clk))then
			--this is tested before the conditions for setting cmd_one_hot
			--because cmd_one_hot must be cleared after one command is done
			--sometimes dbg_state keeps at CMD between two consecutive commands, this would cause the first command to repeat forever
			if(dbg_irq='1')then
				cmd_one_hot <= 	"00000000000";
			--these commands don't produce dbg_irq pulse
			elsif((set_brk_cmd='1' and set_bp='1') or (clr_brk_cmd='1' and clear_bp/=x"00") or (clr_all_brk_cmd='1' and clear_all='1'))then
				cmd_one_hot <= 	"00000000000";
			elsif((dbg_state=CMD or dbg_state=IDLE) and uart_data_received='1')then
				if uart_data_out="10000000"  then
					cmd_one_hot <= 	"00010000000";--continue_cmd
				elsif uart_data_out="01000000"  then
					cmd_one_hot <= 	"00001000000";--breakpt_cmd
				elsif uart_data_out="00100000"  then
					cmd_one_hot <= 	"00000100000";--next_cmd
				elsif uart_data_out="00010000"  then
					cmd_one_hot <= 	"00000010000";--inject_cmd
				elsif uart_data_out="00001000" then
					cmd_one_hot <= 	"00000001000";--set_reg_cmd
				elsif uart_data_out="00000100" then
					cmd_one_hot <= 	"00000000100";--get_reg_cmd
				elsif uart_data_out="00000010" then
					cmd_one_hot <= 	"00000000010";--set_mem_cmd
				elsif uart_data_out="00000001" then
					cmd_one_hot <= 	"00000000001";--get_mem_cmd
				elsif uart_data_out="00000110" then
					cmd_one_hot <= 	"10000000000";--clr_all_brk_cmd
				elsif uart_data_out="00000101" then
					cmd_one_hot <= 	"01000000000";--clr_brk_cmd
				elsif uart_data_out="00000011" then
					cmd_one_hot <= 	"00100000000";--set_brk_cmd
				end if;
			end if;
		end if;
	end process;
	
	uart_fsm: process(rst,clk,data_received_evt)
	begin
		if(rst='1')then
			next_dbg_state <= IDLE;
		--state transition when a byte is received
		elsif(rising_edge(clk) and data_received_evt='1')then
			case dbg_state is
				when CMD|IDLE =>
					if (inject_cmd='1' or set_brk_cmd='1') then
						next_dbg_state <= D3;
					elsif (set_mem_cmd='1' or get_mem_cmd='1') then
						next_dbg_state <= A3;
					elsif (next_cmd='1' or breakpt_cmd='1' or continue_cmd='1' or clr_all_brk_cmd='1') then
						next_dbg_state <= CMD;
					else--when set_reg_cmd='1' or get_reg_cmd='1' or clr_brk_cmd='1'
						next_dbg_state <= A0;
					end if;
				when D3 =>
					next_dbg_state <= D2;
				when D2 =>
					next_dbg_state <= D1;
				when D1 =>
					next_dbg_state <= D0;
				when D0 =>
					next_dbg_state <= CMD;
				when A3 =>
					next_dbg_state <= A2;
				when A2 =>
					next_dbg_state <= A1;
				when A1 =>
					next_dbg_state <= A0;
				when A0 =>
					if (set_mem_cmd='1' or set_reg_cmd='1') then
						next_dbg_state <= D3;
					else
						next_dbg_state <= CMD;
					end if;
				when others =>
					next_dbg_state <= CMD;
			end case;
		end if;
	end process;
	
	process(rst,clk)
	begin
		if(rst='1')then
			dbg_state <= IDLE;
		elsif(rising_edge(clk))then
			dbg_state <= next_dbg_state;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,get_reg_cmd)
	begin
		if(rst='1')then
			dbg_gr <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and get_reg_cmd='1' and  dbg_gr='0')then
				dbg_gr <= '1';--cpu receives a instruction to get a register value during one clock cycle
			else
				dbg_gr <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,set_reg_cmd)
	begin
		if(rst='1')then
			dbg_sr <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and set_reg_cmd='1' and  dbg_sr='0')then
				dbg_sr <= '1';--cpu receives a instruction to set a register during one clock cycle
			else
				dbg_sr <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,get_mem_cmd)
	begin
		if(rst='1')then
			dbg_gm <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and get_mem_cmd='1' and  dbg_gm='0')then
				dbg_gm <= '1';--cpu receives a instruction to get a memory value during one clock cycle (might be extended by processor)
			else
				dbg_gm <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,set_mem_cmd)
	begin
		if(rst='1')then
			dbg_sm <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and set_mem_cmd='1' and  dbg_sm='0')then
				dbg_sm <= '1';--cpu receives a instruction to set a register during one clock cycle (might be extended by processor)
			else
				dbg_sm <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,inject_cmd)
	begin
		if(rst='1')then
			dbg_inj <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and inject_cmd='1' and  dbg_inj='0')then
				dbg_inj <= '1';--cpu receives a instruction (might be extended by processor)
			else
				dbg_inj <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,next_cmd)
	begin
		if(rst='1')then
			dbg_nxt <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and next_cmd='1' and  dbg_nxt='0')then
				dbg_nxt <= '1';--cpu executes the next instruction (might be extended by processor)
			else
				dbg_nxt <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,breakpt_cmd, bp_match)
	begin
		if(rst='1')then
			dbg_brk <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			--  first part is to check if there was break command
			-- the second is to check if one the configured breakpoints was reached
			if(((next_dbg_state=CMD and breakpt_cmd='1') or bp_match='1') and  dbg_brk='0')then
				dbg_brk <= '1';--cpu executes the next instruction (might be extended by processor)
			else
				dbg_brk <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,next_dbg_state,continue_cmd)
	begin
		if(rst='1')then
			dbg_cont <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and continue_cmd='1' and  dbg_cont='0')then
				dbg_cont <= '1';--cpu resumes program normal execution
			else
				dbg_cont <= '0';
			end if;
		end if;
	end process;
	
	--dbg_irq <= '1' when (next_dbg_state=CMD and cmd_one_hot/="000000") else '0';
	process(rst,clk,data_received_evt,next_dbg_state,dbg_state,cmd_one_hot,
				breakpt_cmd,next_cmd,continue_cmd,set_mem_cmd,get_mem_cmd,set_reg_cmd,get_reg_cmd,inject_cmd)
	begin
		if(rst='1')then
			dbg_irq <= '0';
		elsif(rising_edge(clk))then
			--dbg_irq must be '1' for only one clock cycle, after receiving the last byte of the command
			if((next_dbg_state=CMD and (breakpt_cmd='1' or continue_cmd='1' or next_cmd='1') and dbg_irq='0') or --single byte commands
				((dbg_state=A0 and next_dbg_state=CMD) and (get_reg_cmd='1' or get_mem_cmd='1') and dbg_irq='0') or -- only opcode and register or address
				((dbg_state=D0 and next_dbg_state=CMD) and (inject_cmd='1' or set_reg_cmd='1' or set_mem_cmd='1') and dbg_irq='0') or--opcode and two values or opcode and instruction
				(bp_match='1' and dbg_irq='0')--next_pc matches one of the valid breakpoints
				)then
				dbg_irq <= '1';
			else
				dbg_irq <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,uart_data_out,data_received_evt,dbg_state,inject_cmd,set_brk_cmd,set_reg_cmd,get_reg_cmd,set_mem_cmd,get_mem_cmd)
	begin
		if(rst='1')then
			dbg_data_0 <= (others=>'0');
		elsif(rising_edge(clk) and data_received_evt='1')then
			if(inject_cmd='1' or set_reg_cmd='1' or set_mem_cmd='1' or set_brk_cmd='1')then
				if(dbg_state=D3)then
					dbg_data_0(31 downto 24) <= uart_data_out;
				elsif(dbg_state=D2)then
					dbg_data_0(23 downto 16) <= uart_data_out;
				elsif(dbg_state=D1)then
					dbg_data_0(15 downto 8)  <= uart_data_out;
				elsif(dbg_state=D0)then
					dbg_data_0(7 downto 0)   <= uart_data_out;
				end if;
			end if;
		end if;
	end process;
	
	process(rst,clk,dbg_state,data_received_evt,inject_cmd,set_reg_cmd,get_reg_cmd,set_mem_cmd,get_mem_cmd,clr_brk_cmd)
	begin
		if(rst='1')then
			dbg_data_1 <= (others=>'0');
		elsif(rising_edge(clk) and data_received_evt='1')then
			if(set_reg_cmd='1' or get_reg_cmd='1' or set_mem_cmd='1' or get_mem_cmd='1' or clr_brk_cmd='1')then
				if(dbg_state=A3)then
					dbg_data_1(31 downto 24) <= uart_data_out;
				elsif(dbg_state=A2)then
					dbg_data_1(23 downto 16) <= uart_data_out;
				elsif(dbg_state=A1)then
					dbg_data_1(15 downto 8)  <= uart_data_out;
				elsif(dbg_state=A0)then
					dbg_data_1(7 downto 0)   <= uart_data_out;
				end if;
			end if;
		end if;
	end process;
	
	--detects a rising_edge on uart_data_received
	process(rst,clk,uart_data_received)
	begin
		if(rst='1')then
			data_received_evt <= '0';
		elsif(rising_edge(clk))then
			data_received_evt <= uart_data_received and (not prev_uart_data_received);
		end if;
	end process;
	
	process(rst,clk,uart_data_received)
	begin
		if(rst='1')then
			prev_uart_data_received <= '0';
		elsif(rising_edge(clk))then
			prev_uart_data_received <= uart_data_received;
		end if;
	end process;

	uart_rden <= '1';
	
	--it is necessary to clear uart_data_received after commands that don't pulse dbg_irq (to avoid repeating forever)
	uart_iack <= '1' when (dbg_irq='1' or set_bp='1' or clear_all='1' or (clear_bp/=x"00")) else '0';
    -- Instanciação do UART Core
    uart_inst: uart_core
        port map (
            rst => rst,
            clk => uart_phy_clk,
            D => uart_data_in,
            wren => uart_wren,
            rden => uart_rden,
            Q => uart_data_out,
				iack => uart_iack,--it is necessary to clear uart_data_received after single byte commands (to avoid repeating forever)
            data_sent => uart_data_sent,
            data_received => uart_data_received,
            stop_error => uart_stop_error,
            tx => tx,
            rx => rx
        );	
	
	process(rst,clk,dbg_state,get_reg_cmd,get_mem_cmd_delayed,dbg_irq,dbg_irq_delayed)
	begin
		if(rst='1')then
			uart_cache_write_data <= (others=>'0');--sends to uart value of register
			uart_cache_wren <= '0';
		elsif(rising_edge(clk))then
			if(get_reg_cmd='1')then
				if(dbg_irq='1')then
					uart_cache_write_data <= dbg_data_2;--sends to dc_fifo value of register
					uart_cache_wren <= '1';
				end if;
			--these signals must be delayed because get_mem takes 2 clock cycles too complete
			elsif(get_mem_cmd_delayed='1')then
				if(dbg_irq_delayed='1')then
					uart_cache_write_data <= dbg_data_2;--sends to dc_fifo value of memory
					uart_cache_wren <= '1';
				end if;
			elsif(uart_cache_wren='1')then
					uart_cache_wren <= '0';
			end if;
		end if;
	end process;
	
	process(rst,clk,get_mem_cmd,dbg_irq)
	begin
		if(rst='1')then
			get_mem_cmd_delayed <= '0';
			dbg_irq_delayed <= '0';
		elsif(rising_edge(clk))then
			get_mem_cmd_delayed <= get_mem_cmd;
			dbg_irq_delayed <= dbg_irq;
		end if;
	end process;
	
		-- stores the writes made to cache
		fifo: dc_fifo	generic map (N=> 32, REQUESTED_FIFO_DEPTH => REQUESTED_FIFO_DEPTH)
						port map(
								DATA_IN => uart_cache_write_data,
								RST => RST,
								WCLK => CLK,
								WREN => uart_cache_wren,
								FULL => dc_fifo_full,
								EMPTY => open,--takes too long to update, synchronized with uart_phy_clk
								OVF => dc_fifo_ovf,
								RCLK => uart_phy_clk,
								POP => dc_fifo_pop,
								DATA_OUT => dc_fifo_data_out);
		
		--should be active only for one uart_phy_clk cycle
		--after a pop, word_idx should update and pop will clear
		process(rst,uart_phy_clk,dc_fifo_empty,word_idx,uart_data_sent)
		begin
			if(rst='1')then
				dc_fifo_pop <='0';
				dc_fifo_empty_prev <='1';
			elsif(rising_edge(uart_phy_clk))then
				--first write, uart_data_sent is zeroed
				if((dc_fifo_empty='0') and (word_idx=2**W-1) and dc_fifo_empty_prev='1' and uart_data_sent='0' and dc_fifo_pop='0')then
					dc_fifo_pop <= '1';
				--other writes
				elsif((dc_fifo_empty='0') and (word_idx=2**W-1) and uart_data_sent='1' and dc_fifo_pop='0')then
					dc_fifo_pop <= '1';
				else
					dc_fifo_pop <= '0';
				end if;
				dc_fifo_empty_prev <= dc_fifo_empty;
			end if;
		end process;
		
		uart_data_in <= dc_fifo_data_out((word_idx+1)*8-1 downto word_idx*8);

		process(RST,uart_phy_clk,dc_fifo_pop,word_idx,uart_data_sent,uart_word_sent)
		begin
			if(RST='1')then
				uart_wren <= '0';
			elsif(rising_edge(uart_phy_clk))then
				if(dc_fifo_pop='1')then
					uart_wren <= '1';--loads uart_core with byte 0 (LSB)
				elsif(uart_data_sent='1' and uart_wren='0' and (word_idx /= 0) and uart_word_sent='0')then
					uart_wren <= '1';--loads uart_core with byte 1, 2 or 3
				else
					uart_wren <= '0';
				end if;
			end if;
		end process;
		
		process(RST,uart_phy_clk,uart_wren,dc_fifo_pop)
		begin
			if(RST='1')then
				word_idx <= 2**W-1;
			elsif(rising_edge(uart_phy_clk))then
				if(word_idx /= 2**W-1 and (uart_wren='1' or dc_fifo_pop='1'))then
					word_idx <= word_idx + 1;
				elsif(word_idx = 2**W-1 and dc_fifo_pop='1')then
					word_idx <= 0;
				end if;
			end if;
		end process;
		
		process(RST,uart_phy_clk,word_idx,dc_fifo_pop)
		begin
			if(RST='1')then
				uart_word_sent <= '0';
			elsif(rising_edge(uart_phy_clk))then
				if(dc_fifo_pop='1')then
					uart_word_sent <= '0';
				elsif(uart_data_sent='1' and (word_idx = 2**W-1))then
					uart_word_sent <= '1';
				end if;
			end if;
		end process;

	--write pointer
	process(RST,CLK,uart_cache_wren,FULL)
	begin
		if(RST='1') then
			write_addr <= (others=>'0');
			--SOFTWARE MUST CHECK the (almost) FULL flag before writing
		elsif (rising_edge(CLK) and uart_cache_wren='1') then-- and FULL='0') then		
			write_addr <= write_addr + '1';
		end if;
	end process;
	
	--read pointer
	process(RST,uart_phy_clk,dc_fifo_pop)
	begin
		if(RST='1') then
			read_addr <= (others=>'1');--read_addr = -1, goes to 0 at first reading
			--SOFTWARE MUST CHECK the (almost) EMPTY flag before reading
		elsif (rising_edge(uart_phy_clk) and dc_fifo_pop='1') then-- and EMPTY='0') then		
			read_addr <= read_addr + '1';
		end if;
	end process;
	
	--reproduces partially the logic of EMPTY output of dc_fifo, but write pointer is not synchronized whth reading clock (uart_phy_clk)
	dc_fifo_empty	<= '1' when (read_addr + 1 = write_addr) else '0';--next position to read is the next to write (contains invalid data)

	process(rst,clk,next_dbg_state,clr_all_brk_cmd)
	begin
		if(rst='1')then
			clear_all <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and clr_all_brk_cmd='1' and  clear_all='0')then
				clear_all <= '1';--clears all breakpoints and valid bits
			else
				clear_all <= '0';
			end if;
		end if;
	end process;

	process(rst,clk,next_dbg_state,dbg_state,set_brk_cmd)
	begin
		if(rst='1')then
			set_bp <= '0';
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and dbg_state=D0 and set_brk_cmd='1' and  set_bp='0')then
				set_bp <= '1';--sets breakpoint specified in dbg_data_0 and valid bits
			else
				set_bp <= '0';
			end if;
		end if;
	end process;

	process(rst,clk,next_dbg_state,dbg_state,clr_brk_cmd,dbg_data_1)
	begin
		if(rst='1')then
			clear_bp <= (others=>'0');
		elsif(rising_edge(clk))then
			--must be '1' for only one clock cycle
			if(next_dbg_state=CMD and dbg_state=A0 and clr_brk_cmd='1' and  clear_bp="00000000")then
				 for i in 0 to 7 loop
					  if i = conv_integer(unsigned(dbg_data_1(7 downto 0))) then
							clear_bp(i) <= '1';--clears breakpoint specified by dbg_data_1(7 downto 0)
						else
							clear_bp(i) <= '0';
					  end if;
				 end loop;
			else
				clear_bp <= (others=>'0');
			end if;
		end if;
	end process;
	
	bkpts: process (clk, rst, clear_all, set_bp, clear_bp, index, data_received_evt, set_brk_cmd, uart_data_out)
	begin
--	  if rst = '1' then
--			breakpoints <= (others => (others => '0'));
--			valid_bits  <= (others => '0');
--			index       <= 0;
--	  elsif rising_edge(clk) then
	  if rising_edge(clk) then
			if clear_all = '1' then
				 breakpoints <= (others => (others => '0'));
				 valid_bits  <= (others => '0');
				 index       <= 0;
			else
				if(data_received_evt='1' and set_brk_cmd='1')then
					if(dbg_state=D3)then
						breakpoints(index)(31 downto 24) <= uart_data_out;
					elsif(dbg_state=D2)then
						breakpoints(index)(23 downto 16) <= uart_data_out;
					elsif(dbg_state=D1)then
						breakpoints(index)(15 downto 8)  <= uart_data_out;
					elsif(dbg_state=D0)then
						breakpoints(index)(7 downto 0)   <= uart_data_out;
					end if;
				end if;
				
				 if set_bp = '1' and index < 8 then
					  valid_bits(index)  <= '1';
				 end if;
				 
				 for i in 0 to 7 loop
					  if clear_bp(i) = '1' then
							breakpoints(i) <= (others => '0');
							valid_bits(i)  <= '0';
					  end if;
				 end loop;
				 
				 -- Atualiza index para apontar ao menor índice livre ou 8 se cheio
				 index <= 8;
				 for i in 0 to 7 loop
					  if valid_bits(i) = '0' then
							index <= i;
							exit;
					  end if;
				 end loop;
			end if;
	  end if;
	end process;

	bp_valid <= valid_bits;
	
	tmp_matches_ored(0) <= '0';
	bp_matches: for i in 0 to 7 generate
		match(i) <= '1' when next_pc=breakpoints(i) and valid_bits(i)='1' else '0';
		tmp_matches_ored(i+1) <= tmp_matches_ored(i) or match(i);
	end generate bp_matches;
	bp_match <= tmp_matches_ored(8);

end Behavioral;