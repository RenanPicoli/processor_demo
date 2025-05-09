library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use std.textio.all;-- to use readline, hread

entity tb_sdram_ctrl is
end entity;

architecture test of tb_sdram_ctrl is
	-- Sinais do DUT (Device Under Test)
	signal clk       : std_logic := '0';
	signal rst     	: std_logic := '1';
	signal addr      : std_logic_vector(31 downto 0) := (others => '0');
	signal D         : std_logic_vector(31 downto 0) := (others => '0');
	signal Q         : std_logic_vector(31 downto 0);

	-- Interrupção do DMA
	signal ready		: std_logic;
	signal wren		: std_logic := '0';
	signal rden		: std_logic := '0';

	-- Clock de 10 ns (100 MHz)
	constant clk_period : time := 10 ns;

	-- Simulação de uma memória RAM
	constant ram_depth : natural := 256;
	constant ram_width : natural := 32;
	type ram_type is array (0 to ram_depth-1) of std_logic_vector(ram_width-1 downto 0);
 
	--code from https://vhdlwhiz.com/initialize-ram-from-file/
	impure function init_ram_hex return ram_type is
		file text_file : text open read_mode is "ram_content_hex.txt";
		variable text_line : line;
		variable ram_content : ram_type;
	begin
		for i in 0 to ram_depth - 1 loop
			readline(text_file, text_line);
			hread(text_line, ram_content(i));
		end loop;

		return ram_content;
	end function;
	signal RAM			: ram_type := init_ram_hex;
	
	constant CAS_latency: natural:= 2;
	type sr_type is array (0 to CAS_latency) of std_logic_vector(ram_width-1 downto 0);
	signal mem_data_delayed	: sr_type;
	signal mem_rden_delayed: std_logic_vector(0 to CAS_latency);
	
	--signals for RAM, must emulate the SDRAM behavior based on A, BA, CAS_N,RAS_N,WE_N
	signal mem_clk		: std_logic;
	signal mem_addr	: std_logic_vector(7 downto 0);
	signal mem_data	: std_logic_vector(31 downto 0) := (others => '0');
	signal mem_rden	: std_logic;
	signal mem_wren	: std_logic;
	
	-- Interface com a SDRAM
	signal A				: std_logic_vector(12 downto 0);
	signal BA			: std_logic_vector(1 downto 0);
	signal DQM			: std_logic_vector(3 downto 0);
	signal DQ			: std_logic_vector(31 downto 0);
	signal CKE			: std_logic;
	signal CLK_OUT		: std_logic;
	signal WE_N			: std_logic;
	signal CAS_N		: std_logic;
	signal RAS_N		: std_logic;
	signal CS_N			: std_logic;
	
begin

    -- Geração de clock
    process
    begin
        while now < 70000 us loop
            clk <= '0';
            wait for clk_period / 2;
            clk <= '1';
            wait for clk_period / 2;
        end loop;
        wait;
    end process;
	 
	 rst <= '1','0' after 1 ns;
	 
	uut: entity work.sdram_controller
	generic map (CAS_LATENCY => CAS_latency )
	port map (
		----CPU/DMA itfc-----
		clk	=> clk,
		rst	=> rst,
		addr	=> addr,
		D		=> D,
		Q		=> Q,
		wren	=> wren,
		rden	=> rden,
		ready	=> ready,
		------SDRAM itfc-----
		A		=> A,
		BA		=> BA,
		DQM	=> DQM,
		DQ		=> DQ,
		CKE	=> CKE,
		CLK_OUT	=> CLK_OUT,
		WE_N	=> WE_N,
		CAS_N	=> CAS_N,
		RAS_N	=> RAS_N,
		CS_N	=> CS_N
    );
	 
	process
	begin
		rden <= '0';
		addr <= (others => '0');
		wait for 195us;
		rden <= '1';--this read MUST be ignored, SDRAM not initialized
		wait for clk_period;
		rden <= '0';
		-------------------
		wait for 54990ns;
		rden <= '1';--reads on offset 0, must activate first
		wait until ready='1';
		wait for clk_period;
		rden <= '0';
		--------------------
		wait for 149855ns;
		rden <= '1';--reads on other offset (row=2), must precharge first, then activate
		addr <= x"0000_0800";
		wait until ready='1';
		wait for clk_period;
		rden <= '0';
		--------------------
		wait for 199845ns;
		rden <= '1';--reads on the same offset (row=2), but will interrupt by reading on offset 0 (row=0)
		addr <= x"0000_0880";
		wait until ready='1';
		wait for clk_period;
		addr <= x"0000_0040";
		wait until ready='1';
		wait for clk_period;
		rden <= '0';
		wait;
	end process;
	
	process(rst,mem_clk,mem_data)
	begin
		mem_data_delayed(0) <= mem_data;
		mem_rden_delayed(0) <= mem_rden;
		if(rst='1')then
		elsif(rising_edge(mem_clk))then
			for i in 0 to CAS_latency-1 loop
				mem_data_delayed(i+1) <= mem_data_delayed(i);
				mem_rden_delayed(i+1) <= mem_rden_delayed(i);				
			end loop;
		end if;
	end process;

    -- Processo para simular memória RAM
	 mem_clk <= CLK_OUT and CKE;
	 mem_addr <= A(7 downto 0);
	 mem_rden <= '1' when (RAS_N = '1' and CAS_N	= '0' and WE_N	= '1') else '0';
	 mem_wren <= '1' when (RAS_N = '1' and CAS_N	= '0' and WE_N	= '0') else '0';
--	 mem_data <= DQ when mem_wren='1' else (others=>'Z');
	 DQ <= mem_data_delayed(cAS_latency) when mem_rden_delayed(CAS_latency)='1' else (others=>'Z');
    process (mem_clk)
    begin
        if rising_edge(mem_clk) then
            if mem_rden = '1' then--NOT OK: take into account CAS latency
                mem_data <= RAM(conv_integer(mem_addr));
            elsif mem_wren = '1' then--OK
                RAM(conv_integer(mem_addr)) <= mem_data;
            end if;
        end if;
    end process;
				
end architecture;