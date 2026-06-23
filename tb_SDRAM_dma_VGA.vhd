library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use std.textio.all;-- to use readline, hread
use work.my_types.all;-- array32, boundaries

entity tb_sdram_dma_vga_ctrl is
end entity;

architecture test of tb_sdram_dma_vga_ctrl is
	-- Sinais da SDRAM
	signal sdram_ctrl_clk       : std_logic := '0';
    signal sdram_clk_in: std_logic:= '0';
	signal rst     	: std_logic := '1';
	signal sdram_addr      : std_logic_vector(31 downto 0) := (others => '0');
	signal sdram_D         : std_logic_vector(31 downto 0) := (others => '0');
	signal sdram_ctrl_Q         : std_logic_vector(31 downto 0);
    signal sdram_ctrl_wren: std_logic;
    signal sdram_ctrl_rden: std_logic;
    signal sdram_ctrl_ready:std_logic;

	-----signals between dma and arbiter--------
	signal    dma_ram_addr: std_logic_vector(31 downto 0);
	signal    dma_ram_write_data: std_logic_vector(31 downto 0);
	signal    dma_ram_rden: std_logic;
	signal    dma_ram_wren: std_logic;
	signal    dma_ram_ready: std_logic;
	signal    dma_ram_Q: std_logic_vector(31 downto 0);
	--signals for dma peripheral control
	signal    dma_Q: std_logic_vector(31 downto 0);
	signal    dma_addr: std_logic_vector(31 downto 0);
	signal    dma_rden: std_logic;
	signal    dma_wren: std_logic;
	signal    dma_irq: std_logic;
	signal    dma_iack: std_logic;

	-----signals between cpu and arbiter--------
	signal    cpu_ram_addr: std_logic_vector(31 downto 0);
	signal    cpu_ram_write_data: std_logic_vector(31 downto 0);
	signal    cpu_ram_rden: std_logic;
	signal    cpu_ram_wren: std_logic;
	signal    cpu_ram_ready: std_logic;
	signal    cpu_ram_Q: std_logic_vector(31 downto 0);

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

	signal arbiter_clk_id: std_logic_vector(1 downto 0);-- clock domain identifier for the master that initiates the transaction

	signal ram_clk	: std_logic := '0';
	signal ram_addr	: std_logic_vector(31 downto 0);
	signal ram_next_addr: std_logic_vector(31 downto 0);-- for the address decoder to detect when a new write starts (for multi-clock support)
	signal ram_write_data: std_logic_vector(31 downto 0) := (others => '0');
	signal ram_Q: std_logic_vector(31 downto 0) := (others => '0');
	signal ram_rden	: std_logic;
	signal ram_wren	: std_logic;
	signal ram_ready: std_logic;

	-----------signals for memory map interfacing----------------
	constant ranges: boundaries := 	(--notation: base#value#
												(16#00#,16#07#),-- 0: filter coeffs
												(16#08#,16#0F#),-- 1: filter xN
												(16#10#,16#1F#),-- 2: cache
												(16#20#,16#3F#),-- 3: inner_product
												(16#40#,16#5F#),-- 4: VMAC
												(16#60#,16#67#),-- 5: I2C
												(16#68#,16#6F#),-- 6: I2S
												(16#70#,16#70#),-- 7: current filter output
												(16#71#,16#71#),-- 8: desired response
												(16#72#,16#72#),-- 9: filter status
												(16#73#,16#73#),-- 10: converted_out
												(16#74#,16#74#),-- 11: 7-segments display DR
												(16#75#,16#75#),-- 12: LCD controller
												(16#76#,16#77#),-- 13: general purpose fp32_to_int32
												(16#78#,16#79#),-- 14: UART peripheral (IF AVAILABLE)
												(16#7A#,16#7D#),-- 15: DMA
												(16#7E#,16#7F#),-- 16: VGA
												(16#80#,16#FF#),-- 17: interrupt controller
												(16#100#,16#10F#),-- 18: tmp_vector
												(16#8000#,16#FFFF#),-- 19: instruction memory (aka program_data)
												(16#2000000#,16#3FFFFFF#) --20: SDRAM
												);

	signal all_periphs_output: array32 (ranges'length-1 downto 0);
	signal all_periphs_rden: std_logic_vector(ranges'length-1 downto 0);
	signal all_periphs_wren: std_logic_vector(ranges'length-1 downto 0);
	signal all_periphs_ready: std_logic_vector(ranges'length-1 downto 0);

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
    constant CPU_CLK_PERIOD  : time := 250 ns;  -- 4 MHz
    constant SDRAM_CLK_PERIOD  : time := 13.3333 ns;  -- 75 MHz
    constant PCLK_PERIOD : time := 40 ns;  -- Same as clk for test
    constant SIM_DURATION: time := 72 ms; -- tempo de ~4 frames
begin
    -- Geração de clock SDRAM ctrl e DMA
    process
    begin
        while now < SIM_DURATION loop
            sdram_ctrl_clk <= '0';
            wait for SDRAM_CLK_PERIOD / 2;
            sdram_ctrl_clk <= '1';
            wait for SDRAM_CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Geração de clock CPU
    process
    begin
        while now < SIM_DURATION loop
            ram_clk <= '0';
            wait for CPU_CLK_PERIOD / 2;
            ram_clk <= '1';
            wait for CPU_CLK_PERIOD / 2;
        end loop;
        wait;
    end process;
	 
	rst <= '1','0' after 20 ns;
	sdram_clk_in <= transport sdram_ctrl_clk after SDRAM_CLK_PERIOD - 3 ns;--some repos say DRAM clock must be 3ns ahead of control clock

	sdram_addr <= ram_addr - ranges(20)(0);
	sdram: entity work.sdram_controller
	generic map (CAS_LATENCY => CAS_latency )
	port map (
		----CPU/DMA itfc-----
		clk	=> sdram_ctrl_clk,
        sdram_clk_in => sdram_clk_in, 
		rst	=> rst,
		addr	=> sdram_addr,
		D		=> ram_write_data,
		Q		=> sdram_ctrl_Q,
		wren	=> sdram_ctrl_wren,
		rden	=> sdram_ctrl_rden,
		ready	=> sdram_ctrl_ready,
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
	dma_addr <= ram_addr - ranges(15)(0);
    dma: entity work.dma_controller
    port map (
        clk       => ram_clk,--actually CPU CLOCK
        reset     => rst,
        addr      => dma_addr(1 downto 0),
        D         => ram_write_data,
        Q         => dma_Q,
        wr_en     => dma_wren,
        --interface do DMA com a memória (SDRAM ou VGA)
        mem_clk   => sdram_ctrl_clk, --clock of the memory to which DMA is connected (SDRAM or VGA), used for synchronizing signals
        mem_addr  => dma_ram_addr,
        mem_data_in  =>  dma_ram_Q,
        mem_data_out  => dma_ram_write_data,
		mem_ready => dma_ram_ready,
        mem_rden  => dma_ram_rden,
        mem_wren  => dma_ram_wren,
        --interrupção do DMA
        irq       => dma_irq,
		iack	  => dma_iack
    );    

	--decides wether dma or cpu have access to the RAM
	arb: entity work.arbiter
		generic map (B => ranges, MULTI_CLK=> true)
		 port map(
			  clk=> sdram_ctrl_clk,--75MHz, must be fast, it is used for selecting the address decoder "master"
			  rst=> rst,
			  MASTER_CLK_ID => arbiter_clk_id,
			  CLK_ARR => (0 => ram_clk, 1 => sdram_ctrl_clk),-- array of clocks for peripherals with different clock domains. If MULTI_CLK is false, all values can be set to '0'
			  -----
			  cpu_addr=> cpu_ram_addr,
			  cpu_write_data=> cpu_ram_write_data,
			  cpu_rden=> cpu_ram_rden,
			  cpu_wren=> cpu_ram_wren,
			  cpu_ready=> cpu_ram_ready,
			  cpu_Q=> cpu_ram_Q,
			  -----
			  dma_addr=> dma_ram_addr,--address generated by DMA
			  dma_write_data=> dma_ram_write_data,--write_data generated by DMA
			  dma_rden=> dma_ram_rden,
			  dma_wren=> dma_ram_wren,
			  dma_ready=> dma_ram_ready,--ready signal to DMA
			  dma_Q=> dma_ram_Q,--data from memory to DMA
			  -----
			  mem_addr=> ram_addr,
			--   mem_next_addr=> ram_next_addr, -- for the address decoder to detect when a new write starts (for multi-clock support)
			  mem_write_data=> ram_write_data,
			  mem_rden=> ram_rden,
			  mem_wren=> ram_wren,
			  mem_ready=> ram_ready,
			  mem_Q=> ram_Q--data read from RAM
		 );
	
	all_periphs_ready		<= (20=> sdram_ctrl_ready, 16=> vga_ready, others=>'1');
	all_periphs_output	<= (20=> sdram_ctrl_Q, 16=> vga_Q, 15 => dma_Q,others => (others => '0'));-- just to keep form, only filling the relevant peripherals for this test (SDRAM ctrl and VGA)
	--for some reason, the following code does not work: compiles but connections are not generated
--	all_periphs_rden		<= (3 => inner_product_rden,	2 => cache_rden,	1 => filter_xN_rden,	0 => coeffs_mem_rden);
--	all_periphs_wren		<= (3 => inner_product_wren,	2 => cache_wren,	1 => filter_xN_wren,	0 => coeffs_mem_wren);

	sdram_ctrl_rden			<= all_periphs_rden(20);
	-- program_data_rden			<= all_periphs_rden(19);-- not used, just to keep form
	-- tmp_vector_rden			<= all_periphs_rden(18);-- not used, just to keep form
	-- irq_ctrl_rden				<= all_periphs_rden(17);-- not used, just to keep form
	vga_rden						<= all_periphs_rden(16);
	dma_rden						<= all_periphs_rden(15);-- not used, just to keep form
	-- uart_rden					<= all_periphs_rden(14);
	-- gp_fp32_to_int32_rden	<= all_periphs_rden(13);-- not used, just to keep form
	-- lcd_rden						<= all_periphs_rden(12);-- not used, just to keep form
	-- disp_7seg_DR_rden			<= all_periphs_rden(11);-- not used, just to keep form
	-- converted_out_rden		<= all_periphs_rden(10);-- not used, just to keep form
	-- filter_ctrl_status_rden	<= all_periphs_rden(9);-- not used, just to keep form
	-- d_ff_desired_rden			<= all_periphs_rden(8);-- not used, just to keep form
	-- filter_out_rden			<= all_periphs_rden(7);-- not used, just to keep form
	-- i2s_rden						<= all_periphs_rden(6);
	-- i2c_rden						<= all_periphs_rden(5);
	-- vmac_rden					<=	all_periphs_rden(4);
	-- inner_product_rden		<= all_periphs_rden(3);
	-- cache_rden					<= all_periphs_rden(2);
	-- filter_xN_rden				<= all_periphs_rden(1);
	-- coeffs_mem_rden			<= all_periphs_rden(0);

	sdram_ctrl_wren			<= all_periphs_wren(20);
	-- program_data_wren			<= all_periphs_wren(19);
	-- tmp_vector_wren			<= all_periphs_wren(18);
	-- irq_ctrl_wren				<= all_periphs_wren(17);
	vga_wren						<= all_periphs_wren(16);
	dma_wren						<= all_periphs_wren(15);
--    uart_wren					<= all_periphs_wren(14);
-- 	gp_fp32_to_int32_wren	<= all_periphs_wren(13);
-- 	lcd_wren						<= all_periphs_wren(12);
-- 	disp_7seg_DR_wren			<= all_periphs_wren(11);
-- 	converted_out_wren		<= all_periphs_wren(10);-- not used, just to keep form
-- 	filter_ctrl_status_wren	<= all_periphs_wren(9);
-- 	d_ff_desired_wren			<= all_periphs_wren(8);-- not used, just to keep form
-- 	filter_out_wren			<= all_periphs_wren(7);-- not used, just to keep form
-- 	i2s_wren						<= all_periphs_wren(6);
-- 	i2c_wren						<= all_periphs_wren(5);
-- 	vmac_wren					<= all_periphs_wren(4);
-- 	inner_product_wren		<= all_periphs_wren(3);
-- 	cache_wren					<= all_periphs_wren(2);
-- 	filter_xN_wren				<= all_periphs_wren(1);
-- 	coeffs_mem_wren			<= all_periphs_wren(0);

	memory_map: entity work.address_decoder_memory_map
	--N: word address width in bits
	--B boundaries: list of values of the form (starting address,final address) of all peripherals, written as integers,
	--list MUST BE "SORTED" (start address(i) < final address(i) < start address (i+1)),
	--values OF THE FORM: "(b1 b2..bN 0..0),(b1 b2..bN 1..1)"
	--MULTI_CLK: when true, support multiple peripheral clock domains, otherwise all peripherals are assumed to be in the same clock domain and CLK can be ignored (set to others=>'0')
	generic map (N => 26, B => ranges)
	port map (	ADDR => ram_addr(25 downto 0),-- input, it is a word address
			RDEN => ram_rden,-- input
			WREN => ram_wren,-- input
			-- CLK => (0=> ram_clk, 1=> sdram_ctrl_clk),-- array of clocks for peripherals with different clock domains. If MULTI_CLK is false, all values can be set to '0'
			data_in => all_periphs_output,-- input: outputs of all peripheral
			ready_in => all_periphs_ready,
			RDEN_OUT => all_periphs_rden,-- output
			WREN_OUT => all_periphs_wren,-- output
			ready_out => ram_ready,
			MASTER_CLK_ID => arbiter_clk_id, -- clock of the master that initiates the transaction, used for synchronizing data_out
			-- next_ADDR => ram_next_addr(25 downto 0),-- input, it is a word address, used for detecting when a new write starts (for multi-clock support)
			data_out => ram_Q-- data read
	);
					 
	-- --controle do VGA pela CPU
	-- VGA_CFG_PROC : process
	-- begin
	-- 	cpu_ram_addr <= x"0000007F"; -- address of VGA control register
	-- 	cpu_ram_wren <= '1';
	-- 	cpu_ram_rden <= '0';
	-- 	cpu_ram_write_data <= x"00000010";-- start signal for VGA
	-- 	wait for CPU_CLK_PERIOD+20ns;
	-- 	cpu_ram_wren <= '0';
	-- 	cpu_ram_rden <= '0';
	-- 	cpu_ram_write_data <= (others => '0');
	-- 	cpu_ram_addr <= (others => '0');
	-- 	wait;
	-- end process;

    -- Controle do DMA
    process
    begin
        -- Reset do sistema  
		dma_iack <= '0';	
		cpu_ram_wren <= '0';
		cpu_ram_rden <= '0';
        wait for CPU_CLK_PERIOD+20ns;

		--transferência de dados da SDRAM para o cache mini_ram
        -- Configuração dos registradores do DMA		
		cpu_ram_wren <= '1';
		
        -- src_addr = 0x02000000 
        cpu_ram_addr <= x"0000007A"; cpu_ram_write_data <= x"02000000"; wait for CPU_CLK_PERIOD;
		-- dst_addr = 0x00000010
        cpu_ram_addr <= x"0000007B"; cpu_ram_write_data <= x"00000010"; wait for CPU_CLK_PERIOD;
		-- length =  8 palavras (8 pixels)
        cpu_ram_addr <= x"0000007C"; cpu_ram_write_data <= x"00000008"; wait for CPU_CLK_PERIOD;
		-- CR: Start = 1, SINC = 1, DINC = 1, AUTOSTART=0, SRC_LAT=3
        cpu_ram_addr <= x"0000007D"; cpu_ram_write_data <= x"0000003D"; wait for CPU_CLK_PERIOD;

        cpu_ram_wren <= '0';

        -- Aguarda a interrupção (fim da transferência)
        wait until dma_irq = '1';
        wait for CPU_CLK_PERIOD;--ciclo de instrução da CPU não simulada
		dma_iack <= '1';



		--transferência de dados da SDRAM para o VGA
        -- Configuração dos registradores do DMA		
        cpu_ram_wren <= '1';
        
        cpu_ram_addr <= x"0000007A"; cpu_ram_write_data <= x"02000000"; wait for CPU_CLK_PERIOD; -- src_addr = 0x02000000
        cpu_ram_addr <= x"0000007B"; cpu_ram_write_data <= x"0000007E"; wait for CPU_CLK_PERIOD; -- dst_addr = 0x0000007E
        cpu_ram_addr <= x"0000007C"; cpu_ram_write_data <= x"0004B000"; wait for CPU_CLK_PERIOD; -- length =  307200 palavras (640*480 pixels)
        cpu_ram_addr <= x"0000007D"; cpu_ram_write_data <= x"00000065"; wait for CPU_CLK_PERIOD; -- CR: Start = 1, SINC = 1, DINC = 0, AUTOSTART=1, SRC_LAT=2

        cpu_ram_wren <= '0';

        -- Aguarda a interrupção (fim da transferência)
        wait until dma_irq = '1';
        wait for CPU_CLK_PERIOD;--ciclo de instrução da CPU não simulada
		dma_iack <= '1';

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
	vga_addr <= ram_addr - ranges(16)(0);
    vga: entity work.vga_controller
        port map (
            clk     => sdram_ctrl_clk, -- 75 MHz
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