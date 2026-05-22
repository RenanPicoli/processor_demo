library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use std.textio.all;-- to use readline, hread

entity tb_sdram_ctrl is
end entity;

architecture test of tb_sdram_ctrl is
	-- Sinais da SDRAM
	signal clk       : std_logic := '0';
    signal sdram_clk_in: std_logic:= '0';
	signal rst     	: std_logic := '1';
	signal sdram_addr      : std_logic_vector(31 downto 0) := (others => '0');
	signal sdram_D         : std_logic_vector(31 downto 0) := (others => '0');
	signal sdram_Q         : std_logic_vector(31 downto 0);
    signal sdram_wren: std_logic;
    signal sdram_rden: std_logic;
    signal sdram_ready:std_logic;

	-- Interrupção do DMA
	signal dma_addr      : std_logic_vector(1 downto 0) := (others => '0');
	signal dma_D         : std_logic_vector(31 downto 0) := (others => '0');
	signal dma_Q         : std_logic_vector(31 downto 0) := (others => '0');
	signal dma_wren		: std_logic := '0';
	signal dma_mem_ready	: std_logic;
	signal dma_mem_wren		: std_logic := '0';
	signal dma_mem_rden		: std_logic := '0';
	signal dma_mem_addr	: std_logic_vector(31 downto 0);
	signal dma_mem_data_in	: std_logic_vector(31 downto 0);
	signal dma_mem_data_out	: std_logic_vector(31 downto 0) := (others => '0');
	signal irq	: std_logic;
	signal iack	: std_logic;
	signal cpu_addr	: std_logic_vector(31 downto 0) := (others => '0');
	signal cpu_write_data	: std_logic_vector(31 downto 0) := (others => '0');
	signal cpu_Q	: std_logic_vector(31 downto 0) := (others => '0');
	signal cpu_rden	: std_logic := '0';
	signal cpu_wren	: std_logic := '0';
	signal cpu_ready: std_logic := '0';
	-- Simulação de uma memória RAM
	constant ram_depth : natural := 256;
	constant ram_width : natural := 32;
	type ram_type is array (0 to ram_depth-1) of std_logic_vector(ram_width-1 downto 0);
 
	--code from https://vhdlwhiz.com/initialize-ram-from-file/
	impure function init_ram_hex return ram_type is
		-- file text_file : text open read_mode is "ram_content_hex.txt";
		file text_file : text open read_mode is "sdram_img_init.txt";
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
	

	signal ram_addr	: std_logic_vector(31 downto 0);
	signal ram_write_data: std_logic_vector(31 downto 0) := (others => '0');
	signal ram_Q: std_logic_vector(31 downto 0) := (others => '0');
	signal ram_rden	: std_logic;
	signal ram_wren	: std_logic;
	signal ram_ready: std_logic;

	--signals for RAM, must emulate the SDRAM behavior based on A, BA, CAS_N,RAS_N,WE_N
	signal mem_clk	: std_logic;
	signal mem_addr	: std_logic_vector(7 downto 0);
	signal mem_data	: std_logic_vector(31 downto 0) := (others => '0');
	signal mem_rden	: std_logic;
	signal mem_wren	: std_logic;
	
	-- Interface com o chip de SDRAM
	signal A			: std_logic_vector(12 downto 0);
	signal BA			: std_logic_vector(1 downto 0);
	signal DQM			: std_logic_vector(3 downto 0);
	signal DQ			: std_logic_vector(31 downto 0);
	signal CKE			: std_logic;
	signal CLK_OUT		: std_logic;
	signal WE_N			: std_logic;
	signal CAS_N		: std_logic;
	signal RAS_N		: std_logic;
	signal CS_N			: std_logic;
	
    -- VGA signals
    signal PCLK : std_logic := '0';
    signal vga_addr     : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_data_in  : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_Q        : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_wren     : std_logic := '0';
    signal vga_rden     : std_logic := '0';
    signal vga_ready    : std_logic := '0';

    signal SYNC_N, BLANK_N, hsync, vsync : std_logic;
    signal R, G, B : std_logic_vector(7 downto 0);

    -- Clock generation
    constant CLK_PERIOD  : time := 13.3333 ns;  -- 75 MHz
    constant PCLK_PERIOD : time := 40 ns;  -- Same as clk for test
    constant SIM_DURATION: time := 72 ms; -- tempo de ~4 frames
begin
    -- Geração de clock SDRAM ctrl e DMA
    process
    begin
        while now < SIM_DURATION loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;
	 
	rst <= '1','0' after 20 ns;
	sdram_clk_in <= transport clk after CLK_PERIOD - 3 ns;--some repos say DRAM clock must be 3ns ahead of control clock

    sdram_addr <= ram_addr - x"200_0000";
    sdram_wren <= ram_wren when (ram_addr >= x"200_0000" and ram_addr <= x"3FF_FFFF") else '0';
    sdram_rden <= ram_rden when (ram_addr >= x"200_0000" and ram_addr <= x"3FF_FFFF") else '0';
    sdram_D <= ram_write_data when (ram_addr >= x"200_0000" and ram_addr <= x"3FF_FFFF") else (others => '0');
	sdram: entity work.sdram_controller
	generic map (CAS_LATENCY => CAS_latency )
	port map (
		----CPU/DMA itfc-----
		clk	=> clk,
        sdram_clk_in => sdram_clk_in, 
		rst	=> rst,
		addr	=> sdram_addr,
		D		=> sdram_D,
		Q		=> sdram_Q,
		wren	=> sdram_wren,
		rden	=> sdram_rden,
		ready	=> sdram_ready,
		------SDRAM itfc-----
		A		=> A,
		BA		=> BA,
		DQM	    => DQM,
		DQ		=> DQ,
		CKE 	=> CKE,
		sdram_clk_out=> CLK_OUT,
		WE_N	=> WE_N,
		CAS_N	=> CAS_N,
		RAS_N	=> RAS_N,
		CS_N	=> CS_N
    );
    	
	CAS_LAT_PROC: process(rst,mem_clk,mem_data)
	begin
		mem_data_delayed(0) <= mem_data;
		if(rst='1')then
		elsif(rising_edge(mem_clk))then
			mem_rden_delayed(0) <= mem_rden;--reading commando to SDRAM must be sampled
			for i in 0 to CAS_latency-1 loop
				mem_data_delayed(i+1) <= mem_data_delayed(i);
				mem_rden_delayed(i+1) <= mem_rden_delayed(i);				
			end loop;
		end if;
	end process;

    -- Processo para simular memória RAM
	 mem_clk <= CLK_OUT and CKE;
	 mem_addr <= A(7 downto 0);
	 mem_rden <= '1' after 1 ps when (RAS_N = '1' and CAS_N	= '0' and WE_N	= '1') else '0' after 1 ps;--delay just for simulation
	 mem_wren <= '1' after 1 ps when (RAS_N = '1' and CAS_N	= '0' and WE_N	= '0') else '0'after 1 ps ;--delay just for simulation
--	 mem_data <= DQ when mem_wren='1' else (others=>'Z');
	 DQ <= mem_data_delayed(CAS_latency) when mem_rden_delayed(CAS_latency)='1' else (others=>'Z');--taking into account CAS latency
    RAM_PROC: process (mem_clk)
    begin
        if rising_edge(mem_clk) then
            if mem_rden = '1' then
                mem_data <= RAM(conv_integer(mem_addr));
            elsif mem_wren = '1' then--OK
                RAM(conv_integer(mem_addr)) <= DQ;
            end if;
        end if;
    end process;

    -- Instância do DMA
    dma: entity work.dma_controller
    port map (
        clk       => clk,--actually CPU CLOCK
        reset     => rst,
        addr      => dma_addr,
        D         => dma_D,
        Q         => dma_Q,
        wr_en     => dma_wren,
        --interface do DMA com a memória (SDRAM ou VGA)
        mem_clk   => clk,
        mem_addr  => dma_mem_addr,
        mem_data_in  =>  dma_mem_data_in,
        mem_data_out  => dma_mem_data_out,
		mem_ready => dma_mem_ready,
        mem_rden  => dma_mem_rden,
        mem_wren  => dma_mem_wren,
        --interrupção do DMA
        irq       => irq,
		iack	  => iack
    );    

	--decides wether dma or cpu have access to the RAM
	arb: entity work.arbiter
		 port map(
			  clk=> clk,--75MHz, must be fast, it is used for selecting the address decoder "master"
			  rst=> rst,
			  -----
			  cpu_addr=> cpu_addr,
			  cpu_write_data=> cpu_write_data,
			  cpu_rden=> cpu_rden,
			  cpu_wren=> cpu_wren,
			  cpu_ready=> cpu_ready,
			  cpu_Q=> cpu_Q,
			  -----
			  dma_addr=> dma_mem_addr,--address generated by DMA
			  dma_write_data=> dma_mem_data_out,--write_data generated by DMA
			  dma_rden=> dma_mem_rden,
			  dma_wren=> dma_mem_wren,
			  dma_ready=> dma_mem_ready,--ready signal to DMA
			  dma_Q=> dma_mem_data_in,--data from memory to DMA
			  -----
			  mem_addr=> ram_addr,
			  mem_write_data=> ram_write_data,
			  mem_rden=> ram_rden,
			  mem_wren=> ram_wren,
			  mem_ready=> ram_ready,
			  mem_Q=> ram_Q--data read from RAM
		 );
    ram_ready <= vga_ready when (ram_addr >= x"7E" and ram_addr <= x"7F") else
                sdram_ready when (ram_addr >= x"200_0000" and ram_addr <= x"3FF_FFFF") else
                'X';
    ram_Q <= vga_Q when (ram_addr >= x"7E" and ram_addr <= x"7F") else
            sdram_Q when (ram_addr >= x"200_0000" and ram_addr <= x"3FF_FFFF") else
                (others => 'X');
					 
	--controle do VGA pela CPU
	VGA_CFG_PROC : process
	begin
		cpu_addr <= x"0000007F"; -- address of VGA control register
		cpu_wren <= '1';
		cpu_rden <= '0';
		cpu_write_data <= x"00000010";-- start signal for VGA
		wait for CLK_PERIOD+20ns;
		cpu_wren <= '0';
		cpu_rden <= '0';
		cpu_write_data <= (others => '0');
		cpu_addr <= (others => '0');
		wait;
	end process;

    -- Controle do DMA
    process
    begin
        -- Reset do sistema  
		iack <= '0';
        wait for CLK_PERIOD+20ns;

        -- Configuração dos registradores do DMA
        -- wait for CLK_PERIOD/2-20ns+1ns;-- +1ns to make addr/D/wr_en after clock edges
        dma_wren <= '1';
        
        dma_addr <= "00"; dma_D <= x"02000000"; wait for CLK_PERIOD; -- src_addr = 0x02000000
        dma_addr <= "01"; dma_D <= x"0000007E"; wait for CLK_PERIOD; -- dst_addr = 0x0000007E
        dma_addr <= "10"; dma_D <= x"0004B000"; wait for CLK_PERIOD; -- length =  307200 palavras (640*480 pixels)
        dma_addr <= "11"; dma_D <= x"00000065"; wait for CLK_PERIOD; -- CR: Start = 1, SINC = 1, DINC = 0, AUTOSTART=1, SRC_LAT=2

        dma_wren <= '0';

        -- Aguarda a interrupção (fim da transferência)
        wait until irq = '1';
        wait for 250 ns;--ciclo de instrução da CPU não simulada
		iack <= '1';

        -- -- Verifica se os dados foram transferidos corretamente
        -- for i in 0 to 15 loop
        --     assert RAM(i + 208) = std_logic_vector(to_unsigned(i+1, 32))
        --         report "Erro na transferencia! Endereco: " & integer'image(i + 208) & ", valor:" &  to_hstring(RAM(i + 208))
        --         severity error;
        -- end loop;

        -- -- Indica sucesso no teste
        -- report "Teste concluido com sucesso!" severity note;

        wait;
    end process;


    -- Instantiate VGA
    vga_addr <= ram_addr - x"7E";
    vga_wren <= ram_wren when (ram_addr >= x"7E" and ram_addr <= x"7F") else '0';
    vga_rden <= ram_rden when (ram_addr >= x"7E" and ram_addr <= x"7F") else '0';
    vga_data_in <= ram_write_data when (ram_addr >= x"7E" and ram_addr <= x"7F") else (others => '0');
    vga: entity work.vga_controller
        port map (
            clk     => clk,
            rst	    => rst,
            PCLK    => PCLK,
            addr    => vga_addr(5 downto 0),
            data_in => vga_data_in,
            wren    => vga_wren,
            rden    => vga_rden,
            ready   => vga_ready,
            Q       => vga_Q,
            SYNC_N  => SYNC_N,
            BLANK_N => BLANK_N,
            hsync   => hsync,
            vsync   => vsync,
            R       => R,
            G       => G,
            B       => B
        );

    PCLK_process : process
    begin
        while now < SIM_DURATION loop -- tempo de ~4 frames
            PCLK <= '0';
            wait for PCLK_PERIOD / 2;
            PCLK <= '1';
            wait for PCLK_PERIOD / 2;
        end loop;
        wait;
    end process;

end architecture;