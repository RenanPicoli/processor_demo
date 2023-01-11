--------------------------------------------------
--testbench for d-cache
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.all;
---------------------------------------------------

entity tb_d_cache is
end tb_d_cache;

---------------------------------------------------

architecture behv of tb_d_cache is

signal  	CLK_IN:std_logic;--50MHz
signal	CLK: std_logic;
signal	rst: std_logic;

-----------signals for ROM interfacing---------------------
signal rom_clk: std_logic;
signal rom_output: std_logic_vector(31 downto 0);
signal rom_ADDR: std_logic_vector(7 downto 0);

signal instruction_clk: std_logic;
signal instruction_memory_addr: std_logic_vector(7 downto 0);
signal instruction_memory_Q: std_logic_vector(31 downto 0);
signal instruction_memory_wren: std_logic;
signal instruction_memory_rden: std_logic;
signal instruction_memory_write_data: std_logic_vector(31 downto 0);

-----------signals for d_cache interfacing---------------------
signal program_data_Q: std_logic_vector(31 downto 0);
signal program_data_wren: std_logic;
signal program_data_rden: std_logic;
signal program_data_ready: std_logic;

-----------signals for RAM interfacing---------------------
constant N: integer := 9;-- size in bits of data addresses (each address refers to a 32 bit word)
signal ram_clk: std_logic;--data memory clock signal
signal ram_addr: std_logic_vector(N-1 downto 0);
signal ram_rden: std_logic;
signal ram_wren: std_logic;
signal ram_write_data: std_logic_vector(31 downto 0);

signal CLK_uproc: std_logic;--simulates clock inside processor
signal clk_enable: std_logic;--clock enable internal to processor

constant TIME_RST: time := 50 us;

begin
	
	d_cache: entity work.cache
		generic map (REQUESTED_SIZE => 128, MEM_LATENCY=> 1, REGISTER_ADDR=> false)--user requested cache size, in 32 bit words
		port map (
				req_ADDR => ram_addr(7 downto 0),--address of requested data/instruction
				req_rden => program_data_rden,
				req_wren => program_data_wren,
				req_data_in => ram_write_data,
				CLK => CLK,--processor clock for reading instructions, must run even if cache is not ready
				mem_I => instruction_memory_Q,--data coming from SRAM for write
				mem_CLK => rom_clk,--clock for reading embedded RAM
				RST => rst,--reset to prevent reading while sram is written (must be synchronous to sram_CLK)
				mem_ADDR => instruction_memory_addr,--address for write
				req_ready => program_data_ready,--indicates that instruction already contains the requested instruction
				mem_WREN => instruction_memory_wren,
				mem_O		=> instruction_memory_write_data,
				data => program_data_Q--fetched data
		);
		
		ram_addr(7 downto 0) <= x"00", x"F3" after TIME_RST+20 ns, x"32" after 53020 ns, x"F6" after 54770 ns, x"32" after 57770 ns, x"00" after 61270 ns;
		ram_addr(8) <= '1' when (program_data_rden='1' or program_data_wren='1') else '0';
		program_data_wren <= '0', '1' after 57770 ns, '0' after 59520 ns;
		program_data_rden <= '0','1' after TIME_RST+20 ns,'0' after 57770 ns, '1' after 59520 ns, '0' after 61270 ns;
		ram_write_data <= (others => '0'), x"00005827" after 57770 ns, (others => 'X') after 59520 ns;
	
	rom_clk <= CLK_IN;
	program_memory: entity work.mini_rom port map(	CLK	=> rom_clk,	
									RST	=> rst,--asynchronous reset
									--instruction interface (read-only)
									ADDR_A=> rom_ADDR,
									Q_A	=> rom_output,
									--data interface (read-write)
									D_B	=> instruction_memory_write_data,
									ADDR_B=> instruction_memory_addr,
									WREN_B=> instruction_memory_wren,
									Q_B	=> instruction_memory_Q
	);
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
	rst <= '1', '0' after TIME_RST;

	clk_dbg_uproc:	entity work.pll_dbg_uproc
	port map
	(
		areset=> '0',
		inclk0=> CLK_IN,
		c0		=> open,--produces 48MHz for debugging
		c1		=> CLK,--produces CLK=4MHz for processor
--		c2		=> open,--produces 4x the processor frequency, delayed (for 4MHz uproc, produces 16MHz delayed 31.25 ns)
		locked=> open
	);
	
	-------SIMULATES pART OF PROCESSOR----------------
	CLK_uproc <= CLK and clk_enable;
	
	process(rst,program_data_ready,CLK)
	begin
		if(rst='1')then
			clk_enable <= '1';
		elsif(falling_edge(CLK))then
			if(program_data_ready='1')then
				clk_enable <= '1';
			else--if(program_data_ready='0')then
				clk_enable <= '0';
			end if;
		end if;
	end process;

end behv;

---------------------------------------------------------------------------------------------
