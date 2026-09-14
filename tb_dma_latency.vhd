library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dma_latency is
end entity;

architecture test of tb_dma_latency is
    constant MEM_DEPTH : natural := 256;
    constant LATENCY : natural := 3;
    constant TRANSFER_COUNT : natural := 12;
    constant SOURCE_BASE : natural := 8;
    constant DEST_BASE : natural := 100;

    signal clk : std_logic := '0';
    signal mem_clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal addr : std_logic_vector(1 downto 0) := (others => '0');
    signal d : std_logic_vector(31 downto 0) := (others => '0');
    signal q : std_logic_vector(31 downto 0);
    signal wr_en : std_logic := '0';
    signal mem_addr : std_logic_vector(31 downto 0);
    signal mem_data_in : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_data_out : std_logic_vector(31 downto 0);
    signal mem_ready : std_logic := '1';
    signal mem_valid : std_logic := '0';
    signal mem_rden : std_logic;
    signal mem_wren : std_logic;
    signal irq : std_logic;
    signal iack : std_logic := '0';

    type memory_type is array (0 to MEM_DEPTH - 1) of std_logic_vector(31 downto 0);
    impure function initialize_memory return memory_type is
        variable result : memory_type;
    begin
        for index in 0 to MEM_DEPTH - 1 loop
            result(index) := std_logic_vector(to_unsigned(16#1000# + index, 32));
        end loop;
        return result;
    end function;
    signal memory : memory_type := initialize_memory;
    type address_pipeline_type is array (0 to LATENCY) of integer range 0 to MEM_DEPTH - 1;
    signal address_pipeline : address_pipeline_type := (others => 0);
    signal valid_pipeline : std_logic_vector(0 to LATENCY) := (others => '0');
begin
    uut: entity work.dma_controller
        port map (
            reset => reset,
            clk => clk,
            addr => addr,
            D => d,
            Q => q,
            wr_en => wr_en,
            mem_clk => mem_clk,
            mem_addr => mem_addr,
            mem_data_in => mem_data_in,
            mem_data_out => mem_data_out,
            mem_ready => mem_ready,
            mem_valid => mem_valid,
            mem_rden => mem_rden,
            mem_wren => mem_wren,
            irq => irq,
            iack => iack
        );

    clk <= not clk after 125 ns;
    mem_clk <= not mem_clk after 5 ns;

    -- Modelo de memória com resposta atrasada: cada mem_rden aceito é colocado
    -- em um pipeline e reaparece como mem_valid após LATENCY ciclos.
    memory_model: process(mem_clk)
        variable request_address : integer;
    begin
        if rising_edge(mem_clk) then
            if mem_wren = '1' then
                report "WRITE addr=" & integer'image(to_integer(unsigned(mem_addr))) & " data=" & to_hstring(mem_data_out) severity note;
                memory(to_integer(unsigned(mem_addr))) <= mem_data_out;
            end if;

            for index in 1 to LATENCY loop
                address_pipeline(index) <= address_pipeline(index - 1);
                valid_pipeline(index) <= valid_pipeline(index - 1);
            end loop;

            valid_pipeline(0) <= '0';
            if mem_rden = '1' then
                request_address := to_integer(unsigned(mem_addr));
                report "READ addr=" & integer'image(request_address) severity note;
                assert request_address >= SOURCE_BASE and request_address < SOURCE_BASE + TRANSFER_COUNT
                    report "DMA emitiu endereco de leitura inesperado"
                    severity error;
                address_pipeline(0) <= request_address;
                valid_pipeline(0) <= '1';
            end if;
        end if;
    end process;

    mem_valid <= valid_pipeline(LATENCY);
    mem_data_in <= memory(address_pipeline(LATENCY)) when mem_valid = '1' else (others => '0');

    stimulus: process
    begin
        wait for 40 ns;
        reset <= '0';
        wait until rising_edge(clk);

        addr <= "00"; d <= std_logic_vector(to_unsigned(SOURCE_BASE, 32)); wr_en <= '1';
        wait until rising_edge(clk);
        addr <= "01"; d <= std_logic_vector(to_unsigned(DEST_BASE, 32));
        wait until rising_edge(clk);
        addr <= "10"; d <= std_logic_vector(to_unsigned(TRANSFER_COUNT, 32));
        wait until rising_edge(clk);
        addr <= "11"; d <= x"0000000D";
        wait until rising_edge(clk);
        wr_en <= '0';

        -- Verifica que a associação requisição/resposta preserva todos os dados.
        wait until irq = '1' for 20 us;
        assert irq = '1' report "DMA nao sinalizou irq" severity failure;
        wait for 1 ns;

        for index in 0 to TRANSFER_COUNT - 1 loop
            report "indice=" & integer'image(index) & " origem=" & to_hstring(memory(SOURCE_BASE + index)) & " destino=" & to_hstring(memory(DEST_BASE + index)) severity note;
            assert memory(DEST_BASE + index) = memory(SOURCE_BASE + index)
                report "Dados incorretos no destino, indice " & integer'image(index)
                severity failure;
        end loop;

        report "tb_dma_latency: PASS" severity note;
        wait;
    end process;
end architecture;
