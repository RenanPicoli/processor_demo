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
    signal master_Q : std_logic_vector(31 downto 0);

    signal dest_addr : std_logic_vector(31 downto 0);
    signal dest_write_data : std_logic_vector(31 downto 0);
    signal dest_rden : std_logic;
    signal dest_wren : std_logic;
    signal dest_ready : std_logic := '0';
    signal dest_Q : std_logic_vector(31 downto 0) := (others => '0');
    signal read_delay : natural range 0 to 2 := 0;
    signal write_count : natural := 0;

begin
    master_clk <= not master_clk after 5 ns;
    dest_clk <= not dest_clk after 7 ns;

    dut : entity work.cdc_transaction_bridge
        generic map (FIFO_DEPTH => 4)
        port map (
            master_clk => master_clk,
            dest_clk => dest_clk,
            rst => rst,
            master_addr => master_addr,
            master_write_data => master_write_data,
            master_rden => master_rden,
            master_wren => master_wren,
            master_ready => master_ready,
            master_Q => master_Q,
            dest_addr => dest_addr,
            dest_write_data => dest_write_data,
            dest_rden => dest_rden,
            dest_wren => dest_wren,
            dest_ready => dest_ready,
            dest_Q => dest_Q
        );

    dest_model : process(dest_clk)
    begin
        if rising_edge(dest_clk) then
            dest_ready <= '0';
            if dest_rden = '1' then
                if read_delay = 2 then
                    dest_Q <= x"CAFE_BABE";
                    dest_ready <= '1';
                    read_delay <= 0;
                else
                    read_delay <= read_delay + 1;
                end if;
            elsif dest_wren = '1' then
                assert dest_addr = x"0000_0040"
                    report "endereco de escrita incorreto" severity failure;
                assert dest_write_data = x"1234_5678"
                    report "dado de escrita incorreto" severity failure;
                write_count <= write_count + 1;
            end if;
        end if;
    end process;

    stimulus : process
    begin
        wait for 30 ns;
        rst <= '0';

        master_addr <= x"0000_0080";
        master_rden <= '1';
        wait for 20 ns;
        assert master_ready = '0'
            report "leitura foi liberada antes da resposta" severity failure;

        wait until master_ready = '1';
        assert master_Q = x"CAFE_BABE"
            report "dado de leitura incorreto" severity failure;
        master_rden <= '0';
        wait for 20 ns;

        master_addr <= x"0000_0040";
        master_write_data <= x"1234_5678";
        master_wren <= '1';
        wait until master_ready = '1';
        master_wren <= '0';
        wait for 100 ns;
        report "contagem de escritas observada: " & natural'image(write_count) severity note;
        assert write_count = 1
            report "escrita nao foi executada exatamente uma vez" severity failure;

        report "tb_cdc_transaction_bridge concluido" severity note;
        stop;
    end process;
end architecture;
