library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.my_types.all;

entity tb_dma_minicache_roundtrip is
end entity;

architecture test of tb_dma_minicache_roundtrip is
    -- Teste integrado: CPU configura e transforma dados, enquanto a DMA cruza
    -- os árbitros, decodificadores e a ponte CDC entre os dois domínios.
    constant CPU_CLK_PERIOD : time := 40 ns;
    constant SDRAM_CLK_PERIOD : time := 10 ns;
    constant READ_LATENCY : natural := 2;
    constant TRANSFER_WORDS : natural := 8;
    constant DMA_REG_BASE : natural := 16#7A#;
    constant CACHE_BASE : natural := 16#100#;
    constant SDRAM_BASE : natural := 16#0200_0000#;
    constant SDRAM_DEST_OFFSET : natural := 16#100#;
    constant SDRAM_DEPTH : natural := 512;
    constant TRANSFORM_MASK : std_logic_vector(31 downto 0) := x"A5A5_5A5A";

    constant ADDRESS_RANGES : boundaries := (
        (16#7A#, 16#7D#),
        (16#100#, 16#10F#),
        (16#2000000#, 16#3FFFFFF#)
    );

    constant SOURCE_WORDS : array32(0 to TRANSFER_WORDS-1) := (
        x"0123_4567", x"89AB_CDEF", x"1357_9BDF", x"2468_ACE0",
        x"0F1E_2D3C", x"4B5A_6978", x"55AA_33CC", x"DEAD_BEEF"
    );

    type sdram_words_t is array (0 to SDRAM_DEPTH-1) of std_logic_vector(31 downto 0);
    type read_data_pipe_t is array (0 to READ_LATENCY) of std_logic_vector(31 downto 0);

    impure function initialize_sdram return sdram_words_t is
        variable contents : sdram_words_t := (others => (others => '0'));
    begin
        for index in SOURCE_WORDS'range loop
            contents(index) := SOURCE_WORDS(index);
        end loop;
        return contents;
    end function;

    signal cpu_clk : std_logic := '0';
    signal sdram_clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal cpu_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_write_data : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_rden : std_logic := '0';
    signal cpu_wren : std_logic := '0';
    signal cpu_ready : std_logic;
    signal cpu_valid : std_logic;
    signal cpu_Q : std_logic_vector(31 downto 0);

    signal dma_Q : std_logic_vector(31 downto 0);
    signal dma_register_addr : std_logic_vector(31 downto 0);
    signal dma_mem_addr : std_logic_vector(31 downto 0);
    signal dma_mem_write_data : std_logic_vector(31 downto 0);
    signal dma_mem_data_in : std_logic_vector(31 downto 0);
    signal dma_mem_ready : std_logic;
    signal dma_mem_valid : std_logic;
    signal dma_mem_rden : std_logic;
    signal dma_mem_wren : std_logic;
    signal dma_irq : std_logic;
    signal dma_iack : std_logic := '0';

    signal bridge_master_ready : std_logic;
    signal bridge_master_valid : std_logic;
    signal bridge_master_Q : std_logic_vector(31 downto 0);
    signal bridge_dest_addr : std_logic_vector(31 downto 0);
    signal bridge_dest_write_data : std_logic_vector(31 downto 0);
    signal bridge_dest_rden : std_logic;
    signal bridge_dest_wren : std_logic;

    signal domain0_dma_ready : std_logic;
    signal domain0_dma_valid : std_logic;
    signal domain0_dma_Q : std_logic_vector(31 downto 0);
    signal domain0_addr : std_logic_vector(31 downto 0);
    signal domain0_write_data : std_logic_vector(31 downto 0);
    signal domain0_rden : std_logic;
    signal domain0_wren : std_logic;
    signal domain0_ready : std_logic;
    signal domain0_valid : std_logic;
    signal domain0_Q : std_logic_vector(31 downto 0);
    signal domain0_master_clk_id : std_logic_vector(1 downto 0);

    signal domain1_dma_ready : std_logic;
    signal domain1_dma_valid : std_logic;
    signal domain1_dma_Q : std_logic_vector(31 downto 0);
    signal domain1_addr : std_logic_vector(31 downto 0);
    signal domain1_write_data : std_logic_vector(31 downto 0);
    signal domain1_rden : std_logic;
    signal domain1_wren : std_logic;
    signal domain1_ready : std_logic;
    signal domain1_valid : std_logic;
    signal domain1_Q : std_logic_vector(31 downto 0);
    signal domain1_master_clk_id : std_logic_vector(1 downto 0);

    signal periph0_data : array32(2 downto 0);
    signal periph0_ready : std_logic_vector(2 downto 0) := (others => '1');
    signal periph0_valid : std_logic_vector(2 downto 0) := (others => '0');
    signal periph0_rden : std_logic_vector(2 downto 0);
    signal periph0_wren : std_logic_vector(2 downto 0);
    signal periph1_data : array32(2 downto 0);
    signal periph1_ready : std_logic_vector(2 downto 0) := (others => '1');
    signal periph1_valid : std_logic_vector(2 downto 0) := (others => '0');
    signal periph1_rden : std_logic_vector(2 downto 0);
    signal periph1_wren : std_logic_vector(2 downto 0);

    signal cache_Q : std_logic_vector(31 downto 0);
    signal dma_accesses_cache : std_logic;

    signal sdram_memory : sdram_words_t := initialize_sdram;
    signal sdram_read_data_pipe : read_data_pipe_t := (others => (others => '0'));
    signal sdram_read_valid_pipe : std_logic_vector(0 to READ_LATENCY) := (others => '0');
    signal sdram_Q : std_logic_vector(31 downto 0);
    signal sdram_valid : std_logic;
    signal sdram_read_count : natural := 0;
    signal sdram_write_count : natural := 0;
    signal sdram_write_gaps : natural := 0;
    signal sdram_write_seen : std_logic := '0';
    signal cache_write_count : natural := 0;
    signal cache_read_count : natural := 0;
begin
    cpu_clk <= not cpu_clk after CPU_CLK_PERIOD / 2;
    sdram_clk <= not sdram_clk after SDRAM_CLK_PERIOD / 2;
    dma_register_addr <= std_logic_vector(unsigned(domain0_addr) - to_unsigned(DMA_REG_BASE, 32));

    dma_accesses_cache <= '1'
        when unsigned(dma_mem_addr) >= to_unsigned(CACHE_BASE, 32) and
             unsigned(dma_mem_addr) <= to_unsigned(CACHE_BASE + 15, 32)
        else '0';

    dma_mem_ready <= bridge_master_ready when dma_accesses_cache = '1' else domain1_dma_ready;
    dma_mem_valid <= bridge_master_valid when dma_accesses_cache = '1' else domain1_dma_valid;
    dma_mem_data_in <= bridge_master_Q when dma_accesses_cache = '1' else domain1_dma_Q;

    periph0_data <= (0 => dma_Q, 1 => cache_Q, others => (others => '0'));
    periph0_valid(1) <= '1';
    periph1_data <= (2 => sdram_Q, others => (others => '0'));
    periph1_valid(2) <= sdram_valid;

    -- Usa a mini_ram da integração do processador, para testar a mesma memória
    -- simples usada pela CPU no caminho DMA/mini-cache.
    mini_cache : entity work.mini_ram
        generic map (N => 4)
        port map (
            CLK => cpu_clk,
            ADDR => domain0_addr(3 downto 0),
            write_data => domain0_write_data,
            rden => periph0_rden(1),
            wren => periph0_wren(1),
            Q => cache_Q
        );

    dma : entity work.dma_controller
        generic map (FIFO_LEN => 16, USE_RAM_BLOCKS => true)
        port map (
            reset => rst,
            reset_mem => rst,
            clk => cpu_clk,
            addr => dma_register_addr(1 downto 0),
            D => domain0_write_data,
            Q => dma_Q,
            wr_en => periph0_wren(0),
            mem_clk => sdram_clk,
            mem_addr => dma_mem_addr,
            mem_data_in => dma_mem_data_in,
            mem_data_out => dma_mem_write_data,
            mem_ready => dma_mem_ready,
            mem_valid => dma_mem_valid,
            mem_rden => dma_mem_rden,
            mem_wren => dma_mem_wren,
            irq => dma_irq,
            iack => dma_iack
        );

    dma_cache_bridge : entity work.cdc_transaction_bridge
        generic map (FIFO_DEPTH => 64, DMA_STREAM_MODE => true)
        port map (
            master_clk => sdram_clk,
            dest_clk => cpu_clk,
            rst => rst,
            master_addr => dma_mem_addr,
            master_write_data => dma_mem_write_data,
            master_rden => dma_mem_rden and dma_accesses_cache,
            master_wren => dma_mem_wren and dma_accesses_cache,
            master_ready => bridge_master_ready,
            master_valid => bridge_master_valid,
            master_Q => bridge_master_Q,
            dest_addr => bridge_dest_addr,
            dest_write_data => bridge_dest_write_data,
            dest_rden => bridge_dest_rden,
            dest_wren => bridge_dest_wren,
            dest_ready => domain0_dma_ready,
            dest_valid => domain0_dma_valid,
            dest_Q => domain0_dma_Q
        );

    domain0_arbiter : entity work.arbiter
        generic map (LOCAL_DOMAIN => 0)
        port map (
            clk => cpu_clk,
            rst => rst,
            MASTER_CLK_ID => domain0_master_clk_id,
            cpu_addr => cpu_addr,
            cpu_write_data => cpu_write_data,
            cpu_rden => cpu_rden,
            cpu_wren => cpu_wren,
            cpu_ready => cpu_ready,
            cpu_valid => cpu_valid,
            cpu_Q => cpu_Q,
            dma_addr => bridge_dest_addr,
            dma_write_data => bridge_dest_write_data,
            dma_rden => bridge_dest_rden,
            dma_wren => bridge_dest_wren,
            dma_ready => domain0_dma_ready,
            dma_valid => domain0_dma_valid,
            dma_Q => domain0_dma_Q,
            mem_addr => domain0_addr,
            mem_write_data => domain0_write_data,
            mem_rden => domain0_rden,
            mem_wren => domain0_wren,
            mem_ready => domain0_ready,
            mem_valid => domain0_valid,
            mem_Q => domain0_Q
        );

    domain0_decoder : entity work.address_decoder_memory_map
        generic map (N => 26, B => ADDRESS_RANGES)
        port map (
            ADDR => domain0_addr(25 downto 0),
            RDEN => domain0_rden,
            WREN => domain0_wren,
            data_in => periph0_data,
            ready_in => periph0_ready,
            valid_in => periph0_valid,
            RDEN_OUT => periph0_rden,
            WREN_OUT => periph0_wren,
            ready_out => domain0_ready,
            valid_out => domain0_valid,
            MASTER_CLK_ID => domain0_master_clk_id,
            data_out => domain0_Q
        );

    domain1_arbiter : entity work.arbiter
        generic map (LOCAL_DOMAIN => 1, DMA_STREAM_MODE => true)
        port map (
            clk => sdram_clk,
            rst => rst,
            MASTER_CLK_ID => domain1_master_clk_id,
            cpu_addr => (others => '0'),
            cpu_write_data => (others => '0'),
            cpu_rden => '0',
            cpu_wren => '0',
            cpu_ready => open,
            cpu_valid => open,
            cpu_Q => open,
            dma_addr => dma_mem_addr,
            dma_write_data => dma_mem_write_data,
            dma_rden => dma_mem_rden and not dma_accesses_cache,
            dma_wren => dma_mem_wren and not dma_accesses_cache,
            dma_ready => domain1_dma_ready,
            dma_valid => domain1_dma_valid,
            dma_Q => domain1_dma_Q,
            mem_addr => domain1_addr,
            mem_write_data => domain1_write_data,
            mem_rden => domain1_rden,
            mem_wren => domain1_wren,
            mem_ready => domain1_ready,
            mem_valid => domain1_valid,
            mem_Q => domain1_Q
        );

    domain1_decoder : entity work.address_decoder_memory_map
        generic map (N => 26, B => ADDRESS_RANGES)
        port map (
            ADDR => domain1_addr(25 downto 0),
            RDEN => domain1_rden,
            WREN => domain1_wren,
            data_in => periph1_data,
            ready_in => periph1_ready,
            valid_in => periph1_valid,
            RDEN_OUT => periph1_rden,
            WREN_OUT => periph1_wren,
            ready_out => domain1_ready,
            valid_out => domain1_valid,
            MASTER_CLK_ID => domain1_master_clk_id,
            data_out => domain1_Q
        );

    sdram_Q <= sdram_read_data_pipe(READ_LATENCY);
    sdram_valid <= sdram_read_valid_pipe(READ_LATENCY);

    -- Modelo comportamental na interface pós-decoder: introduz a latência de
    -- leitura e registra escritas sem modelar o controlador/pinos SDRAM físicos.
    sdram_model : process (sdram_clk, rst)
        variable memory_index : natural range 0 to SDRAM_DEPTH-1;
    begin
        if rst = '1' then
            sdram_read_data_pipe <= (others => (others => '0'));
            sdram_read_valid_pipe <= (others => '0');
            sdram_read_count <= 0;
            sdram_write_count <= 0;
            sdram_write_gaps <= 0;
            sdram_write_seen <= '0';
        elsif rising_edge(sdram_clk) then
            sdram_read_data_pipe(0) <= (others => '0');
            sdram_read_valid_pipe(0) <= '0';
            if periph1_rden(2) = '1' and domain1_dma_ready = '1' then
                memory_index := to_integer(unsigned(domain1_addr(8 downto 0)));
                sdram_read_data_pipe(0) <= sdram_memory(memory_index);
                sdram_read_valid_pipe(0) <= '1';
                sdram_read_count <= sdram_read_count + 1;
            end if;

            if periph1_wren(2) = '1' and domain1_dma_ready = '1' then
                memory_index := to_integer(unsigned(domain1_addr(8 downto 0)));
                sdram_memory(memory_index) <= domain1_write_data;
                sdram_write_count <= sdram_write_count + 1;
                sdram_write_seen <= '1';
            elsif sdram_write_seen = '1' and sdram_write_count < TRANSFER_WORDS then
                sdram_write_gaps <= sdram_write_gaps + 1;
            end if;

            for stage in 1 to READ_LATENCY loop
                sdram_read_data_pipe(stage) <= sdram_read_data_pipe(stage-1);
                sdram_read_valid_pipe(stage) <= sdram_read_valid_pipe(stage-1);
            end loop;
        end if;
    end process;

    bridge_activity : process (cpu_clk, rst)
    begin
        if rst = '1' then
            cache_write_count <= 0;
            cache_read_count <= 0;
        elsif rising_edge(cpu_clk) then
            if bridge_dest_wren = '1' and domain0_dma_ready = '1' then
                cache_write_count <= cache_write_count + 1;
            end if;
            if bridge_dest_rden = '1' and domain0_dma_ready = '1' then
                cache_read_count <= cache_read_count + 1;
            end if;
        end if;
    end process;

    stimulus : process
        procedure cpu_access (
            constant address : in std_logic_vector(31 downto 0);
            constant write_enable : in std_logic;
            constant write_value : in std_logic_vector(31 downto 0);
            variable read_value : out std_logic_vector(31 downto 0)
        ) is
        begin
            cpu_addr <= address;
            cpu_write_data <= write_value;
            cpu_rden <= not write_enable;
            cpu_wren <= write_enable;

            for attempt in 0 to 200 loop
                wait until rising_edge(cpu_clk);
                if cpu_ready = '1' then
                    read_value := cpu_Q;
                    cpu_rden <= '0';
                    cpu_wren <= '0';
                    wait until rising_edge(cpu_clk);
                    wait for 1 ns;
                    return;
                end if;
            end loop;

            assert false report "CPU access timed out at address " & to_hstring(address)
                severity failure;
        end procedure;

        procedure configure_dma (
            constant source : in natural;
            constant destination : in natural
        ) is
            variable unused_read_value : std_logic_vector(31 downto 0);
        begin
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE, 32)), '1',
                       std_logic_vector(to_unsigned(source, 32)), unused_read_value);
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE + 1, 32)), '1',
                       std_logic_vector(to_unsigned(destination, 32)), unused_read_value);
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE + 2, 32)), '1',
                       std_logic_vector(to_unsigned(TRANSFER_WORDS, 32)), unused_read_value);
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE + 3, 32)), '1',
                       x"0000_000D", unused_read_value);
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE, 32)), '0',
                       (others => '0'), unused_read_value);
            assert unsigned(unused_read_value) = to_unsigned(source, 32)
                report "DMA source register was not programmed correctly"
                severity failure;
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE + 1, 32)), '0',
                       (others => '0'), unused_read_value);
            assert unsigned(unused_read_value) = to_unsigned(destination, 32)
                report "DMA destination register was not programmed correctly"
                severity failure;
            cpu_access(std_logic_vector(to_unsigned(DMA_REG_BASE + 2, 32)), '0',
                       (others => '0'), unused_read_value);
            assert unsigned(unused_read_value) = to_unsigned(TRANSFER_WORDS, 32)
                report "DMA transfer-count register was not programmed correctly"
                severity failure;
        end procedure;

        variable read_value : std_logic_vector(31 downto 0);
    begin
        wait for 5 * CPU_CLK_PERIOD;
        rst <= '0';
        wait for 2 * CPU_CLK_PERIOD;

        configure_dma(SDRAM_BASE, CACHE_BASE);
        if dma_irq /= '1' then
            wait until dma_irq = '1' for 1 ms;
        end if;
        assert dma_irq = '1'
            report "DMA timed out while copying SDRAM into mini_cache"
            severity failure;
        assert sdram_read_count = TRANSFER_WORDS
            report "DMA did not issue exactly eight SDRAM reads"
            severity failure;
        if cache_write_count /= TRANSFER_WORDS then
            wait until cache_write_count = TRANSFER_WORDS for 100 us;
        end if;
        assert cache_write_count = TRANSFER_WORDS
            report "CDC/arbiter path did not write exactly eight cache words"
            severity failure;

        for index in 0 to TRANSFER_WORDS-1 loop
            cpu_access(std_logic_vector(to_unsigned(CACHE_BASE + index, 32)), '0',
                       (others => '0'), read_value);
            assert read_value = SOURCE_WORDS(index)
                report "Incorrect DMA data in mini_cache at word " & natural'image(index) &
                       ": got " & to_hstring(read_value) &
                       ", expected " & to_hstring(SOURCE_WORDS(index))
                severity failure;

            cpu_access(std_logic_vector(to_unsigned(CACHE_BASE + index, 32)), '1',
                       read_value xor TRANSFORM_MASK, read_value);
        end loop;

        for index in 0 to TRANSFER_WORDS-1 loop
            cpu_access(std_logic_vector(to_unsigned(CACHE_BASE + index, 32)), '0',
                       (others => '0'), read_value);
            assert read_value = (SOURCE_WORDS(index) xor TRANSFORM_MASK)
                report "CPU transformation failed at mini_cache word " & natural'image(index)
                severity failure;
        end loop;

        dma_iack <= '1';
        wait for 2 * CPU_CLK_PERIOD;
        dma_iack <= '0';
        if dma_irq /= '0' then
            wait until dma_irq = '0' for 100 us;
        end if;
        assert dma_irq = '0'
            report "DMA interrupt did not clear before the return transfer"
            severity failure;

        configure_dma(CACHE_BASE, SDRAM_BASE + SDRAM_DEST_OFFSET);
        if dma_irq /= '1' then
            wait until dma_irq = '1' for 1 ms;
        end if;
        assert dma_irq = '1'
            report "DMA timed out while copying transformed cache data to SDRAM"
            severity failure;
        if cache_read_count /= TRANSFER_WORDS then
            wait until cache_read_count = TRANSFER_WORDS for 100 us;
        end if;
        if sdram_write_count /= TRANSFER_WORDS then
            wait until sdram_write_count = TRANSFER_WORDS for 100 us;
        end if;
        assert cache_read_count = TRANSFER_WORDS
            report "CDC/arbiter path did not read exactly eight cache words"
            severity failure;
        assert sdram_write_count = TRANSFER_WORDS
            report "DMA did not issue exactly eight SDRAM writes"
            severity failure;
        assert sdram_write_gaps = 0
            report "DMA inserted idle SDRAM cycles between accepted writes"
            severity failure;

        for index in 0 to TRANSFER_WORDS-1 loop
            assert sdram_memory(SDRAM_DEST_OFFSET + index) =
                   (SOURCE_WORDS(index) xor TRANSFORM_MASK)
                report "Incorrect transformed SDRAM data at destination word " & natural'image(index)
                       & ": got " & to_hstring(sdram_memory(SDRAM_DEST_OFFSET + index)) &
                       ", expected " & to_hstring(SOURCE_WORDS(index) xor TRANSFORM_MASK)
                severity failure;
            assert sdram_memory(index) = SOURCE_WORDS(index)
                report "Source SDRAM data was unexpectedly modified at word " & natural'image(index)
                severity failure;
        end loop;

        report "tb_dma_minicache_roundtrip: PASS (8 SDRAM -> mini_cache -> SDRAM words)"
            severity note;
        stop;
    end process;
end architecture;
