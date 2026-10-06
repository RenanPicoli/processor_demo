library ieee;
use ieee.std_logic_1164.all;
use std.env.all; -- para encerrar a simulação com std.env.stop.

entity tb_cdc_transaction_bridge is
end entity;

architecture sim of tb_cdc_transaction_bridge is
    signal master_clk : std_logic := '0';
    signal dest_clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal master_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal master_write_data : std_logic_vector(31 downto 0) := (others => '0');
    signal master_rden : std_logic := '0';
    signal master_wren : std_logic := '0';
    signal master_ready : std_logic;
    signal master_valid : std_logic;
    signal master_Q : std_logic_vector(31 downto 0);

    signal dest_addr : std_logic_vector(31 downto 0);
    signal dest_write_data : std_logic_vector(31 downto 0);
    signal dest_rden : std_logic;
    signal dest_wren : std_logic;
    signal dest_ready : std_logic := '0';
    signal dest_valid : std_logic;
    signal dest_Q : std_logic_vector(31 downto 0) := (others => '0');
    signal read_delay : natural range 0 to 2 := 0;
    signal read_count : natural := 0;
    signal read_counted : std_logic := '0';
    signal write_count : natural := 0;

begin
    master_clk <= not master_clk after 5 ns;
    dest_clk <= not dest_clk after 25 ns;

    dut : entity work.cdc_transaction_bridge
        generic map (FIFO_DEPTH => 64)
        port map (
            master_clk => master_clk,
            dest_clk => dest_clk,
            rst => rst,
            master_addr => master_addr,
            master_write_data => master_write_data,
            master_rden => master_rden,
            master_wren => master_wren,
            master_ready => master_ready,
            master_valid => master_valid,
            master_Q => master_Q,
            dest_addr => dest_addr,
            dest_write_data => dest_write_data,
            dest_rden => dest_rden,
            dest_wren => dest_wren,
            dest_ready => dest_ready,
            dest_valid => dest_valid,
            dest_Q => dest_Q
        );

    dest_model : process(dest_clk)
    begin
        if rising_edge(dest_clk) then
            dest_valid <= '0';
            if dest_rden = '0' then
                read_counted <= '0';
            elsif read_counted = '0' then
                read_count <= read_count + 1;
                read_counted <= '1';
            end if;
            if dest_wren = '1' then
                dest_ready <= '1';
                assert dest_addr = x"0000_0040" or dest_addr = x"0000_0041"
                    report "endereco de escrita incorreto" severity failure;
                assert dest_write_data = x"1234_5678" or dest_write_data = x"CAFE_BABE"
                    report "dado de escrita incorreto" severity failure;
                write_count <= write_count + 1;
            elsif dest_rden = '1' then
                dest_ready <= '0';
                if read_delay = 2 then
                    if dest_addr = x"0000_0081" then
                        dest_Q <= x"DEAD_BEEF";
                    else
                        dest_Q <= x"CAFE_BABE";
                    end if;
                    dest_valid <= '1';
                    dest_ready <= '1';--ready to accept new commands
                    read_delay <= 0;
                else
                    read_delay <= read_delay + 1;
                end if;
            else
                dest_ready <= '0';
            end if;
        end if;
    end process;

    stimulus : process
        variable response_seen : boolean;
    begin
        wait for 30 ns;
        rst <= '0';

        master_addr <= x"0000_0080";
        master_rden <= '1';
        response_seen := false;
        for i in 0 to 1000 loop
            wait until rising_edge(master_clk);
            if master_valid = '1' then
                response_seen := true;
                exit;
            end if;
        end loop;
        assert response_seen
            report "tempo esgotado aguardando resposta de leitura" severity failure;

        -- assert master_ready = '0'
        --     report "leitura foi liberada antes da resposta" severity failure;

        -- wait until master_ready = '1';
        assert master_Q = x"CAFE_BABE"
            report "dado de leitura incorreto" severity failure;

        -- Changing the address without dropping rden does not start a second
        -- request; the bridge treats the asserted level as the original read.
        master_addr <= x"0000_0081";
        wait for 300 ns;
        assert read_count = 1
            report "rden mantido alto iniciou uma segunda leitura" severity failure;

        master_rden <= '0';
        wait until rising_edge(master_clk);
        master_addr <= x"0000_0080";
        master_rden <= '1';
        response_seen := false;
        for i in 0 to 1000 loop
            wait until rising_edge(master_clk);
            if master_valid = '1' then
                response_seen := true;
                exit;
            end if;
        end loop;
        assert response_seen
            report "tempo esgotado aguardando segunda leitura consecutiva" severity failure;
        assert master_Q = x"CAFE_BABE"
            report "dado da segunda leitura consecutiva incorreto" severity failure;

        master_rden <= '0';
        wait until rising_edge(master_clk);
        master_addr <= x"0000_0081";
        master_rden <= '1';
        response_seen := false;
        for i in 0 to 1000 loop
            wait until rising_edge(master_clk);
            if master_valid = '1' then
                response_seen := true;
                exit;
            end if;
        end loop;
        assert response_seen
            report "tempo esgotado aguardando leitura consecutiva em endereco diferente" severity failure;
        assert master_Q = x"DEAD_BEEF"
            report "dado da leitura em endereco diferente incorreto" severity failure;

        master_rden <= '0';
        wait until rising_edge(master_clk);
        wait for 300 ns;
        assert read_count = 3
            report "contagem incorreta de leituras consecutivas" severity failure;

        master_addr <= x"0000_0040";
        master_write_data <= x"1234_5678";
        master_wren <= '1';
        response_seen := false;
        for i in 0 to 100 loop
            wait until rising_edge(master_clk);
            if master_ready = '1' then
                response_seen := true;
                exit;
            end if;
        end loop;
        assert response_seen
            report "tempo esgotado aguardando aceitacao da primeira escrita" severity failure;

        master_addr <= x"0000_0041";
        master_write_data <= x"CAFE_BABE";
        response_seen := false;
        for i in 0 to 100 loop
            wait until rising_edge(master_clk);
            if master_ready = '1' then
                response_seen := true;
                exit;
            end if;
        end loop;
        assert response_seen
            report "tempo esgotado aguardando aceitacao da segunda escrita" severity failure;

        master_wren <= '0';
        wait for 2000 ns;
        report "contagem de escritas observada: " & natural'image(write_count) severity note;
        assert write_count = 2
            report "escrita nao foi executada exatamente uma vez" severity failure;

        report "tb_cdc_transaction_bridge concluido" severity note;
        stop;
    end process;
end architecture;
