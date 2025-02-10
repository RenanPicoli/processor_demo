-- Code your testbench here
library IEEE;
use IEEE.std_logic_1164.all;
use work.all;--includes uart_core, uart_debugger

entity tb_uart_debugger is
end tb_uart_debugger;

architecture bhv of tb_uart_debugger is
	-------SENDER (shell)---------
	signal	uart_data_sent: std_logic;
	signal	uart_data_received: std_logic;
	signal	uart_stop_error: std_logic;	
	signal	uart_wren: std_logic;
	signal	uart_rden: std_logic;
	signal	uart_data_out: std_logic_vector(7 downto 0);
	signal	uart_data_in: std_logic_vector(7 downto 0);
	signal	tx: std_logic;
	signal	rx: std_logic;
	signal	rst: std_logic;
	signal	iack: std_logic;--resets all flags!
	signal	uart_phy_clk: std_logic;--bit clock (not transmitted)
 
	------CPU DEBUG ITFC (DEBUGGER)---------
	signal proc_clk_out: std_logic;--same as CPU clock (might be extended by processor during memory reading/writing)
	signal proc_dbg_clk: std_logic;--same as CLK (keeps running ehrn cpu is halted or in i-cache miss) but can be extended during d-cache miss
	signal proc_dbg_clk_en: std_logic:='1';--enables proc_dbg_clk to follow CLK
	signal proc_dbg_data_0: std_logic_vector(31 downto 0);-- instructions, value for writes to register or memory
	signal proc_dbg_data_1: std_logic_vector(31 downto 0);--address for memory access, register for reg_file access
	signal proc_dbg_data_2: std_logic_vector(31 downto 0);-- value for reading register or memory
	signal proc_dbg_sr: std_logic;-- set register enable
	signal proc_dbg_gr: std_logic;-- get register enable
	signal proc_dbg_sm: std_logic;-- set memory enable
	signal proc_dbg_gm: std_logic;-- get memory enable
	signal proc_dbg_brk: std_logic;-- instruction break
	signal proc_dbg_inj: std_logic;-- inject instruction
	signal proc_dbg_nxt: std_logic;-- next instruction
	signal proc_dbg_cont: std_logic;-- continue instruction
	signal proc_dbg_irq: std_logic;-- debug irq
	signal proc_dbg_iack: std_logic;--interrupt acknowledgement
	signal proc_next_pc: std_logic_vector(31 downto 0);-- TODO: monitor PC (pc_in) for breakpoints
	signal uart_dbg_tx: std_logic;
	signal uart_dbg_rx: std_logic;
	
	signal CLK: std_logic;
	
begin

	-- Instantiation of UART Core
	uart_sender: entity work.uart_core
		port map (
			rst => rst,
			clk => uart_phy_clk,
			D => uart_data_in,
			wren => uart_wren,
			rden => uart_rden,
			Q => uart_data_out,
			iack => iack,
			data_sent => uart_data_sent,
			data_received => uart_data_received,
			stop_error => uart_stop_error,
			tx => tx,
			rx => rx
		);
	uart_data_in <= x"04", x"02" after 4.1 ms, x"04" after 40 ms, x"02" after 44.1 ms;-- get_register r2 command
	uart_wren <= '0', '1' after 4.048	ms, '0' after 4.1 ms, '1' after 9.022 ms, '0' after 9.074 ms,
						'1' after 44.048	ms, '0' after 44.1 ms, '1' after 49.022 ms, '0' after 49.074 ms;
	uart_rden <= '1';
	iack <= '0';
	--rx <= '1', '0' after 1 ms, '1' after 4800 us;
	--rx <=  '1', '0' after 10 ms, '1' after 11.23 ms, '0' after 11.665ms, '1' after 13.73ms, '0' after 14.153ms, '1' after 14.996ms, '0' after 15.405ms, '1' after 17.9ms;

	dut: entity work.uart_debugger
	port map (
		rst => rst,
		------CPU ITFC---------
		clk => proc_dbg_clk,--must run while processor is halted, but need to be extended by processor during memory reading/writing
		dbg_data_0 => proc_dbg_data_0,-- instructions, value for writes to memory or register
		dbg_data_1 => proc_dbg_data_1,-- address for memory access, register for reg_file access
		dbg_data_2 => proc_dbg_data_2,-- value for reading of register or memory
		--command ports bellow must be asserted only for 1 clk cycle, together with dbg_irq
		dbg_sr => proc_dbg_sr,-- set register enable
		dbg_gr => proc_dbg_gr,-- get register enable
		dbg_sm => proc_dbg_sm,-- set memory enable
		dbg_gm => proc_dbg_gm,-- get memory enable
		dbg_brk=> proc_dbg_brk,--instruction break
		dbg_inj=> proc_dbg_inj,--inject instruction
		dbg_nxt=> proc_dbg_nxt,--next instruction		
		dbg_cont=> proc_dbg_cont,--continue instruction
		dbg_irq => proc_dbg_irq,-- debug irq, must be asserted for 1 clk cycle (which can be extended)
		
		IACK => proc_dbg_iack,--interrupt acknowledgement
		next_pc => proc_next_pc,-- TODO: monitor PC (pc_in) for breakpoints
		------UART PHY---------
		uart_phy_clk=> uart_phy_clk,
		tx => uart_dbg_tx,
		rx => uart_dbg_rx
	);
	uart_dbg_rx <= tx;--connects to sender tx
	rx <= uart_dbg_tx;--connects to sender rx
	proc_dbg_data_2 <= x"0000_003E";--value of r2;
	proc_dbg_clk_en <= '1';--no d-cache miss
	proc_dbg_clk <= CLK and proc_dbg_clk_en;
	proc_next_pc <= (others=>'0');
        
	uart_clock: process
	begin
		uart_phy_clk <='0';
		wait for 26 us;
		uart_phy_clk <='1';
		wait for 26 us;        
	end process uart_clock;
	
	cpu_clock: process
	begin
		CLK <='0';
		wait for 125 ns;
		CLK <='1';
		wait for 125 ns;        
	end process cpu_clock;

	rst<= '1', '0' after 52 us;

end bhv;