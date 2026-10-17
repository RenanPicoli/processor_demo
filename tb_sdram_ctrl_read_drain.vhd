library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_sdram_ctrl_read_drain is
end entity;

architecture test of tb_sdram_ctrl_read_drain is
    constant CLK_PERIOD : time := 10 ns;
    constant CAS_LATENCY : natural := 2;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal addr : std_logic_vector(31 downto 0) := (others => '0');
    signal data_in : std_logic_vector(31 downto 0) := (others => '0');
    signal data_out : std_logic_vector(31 downto 0);
    signal wren : std_logic := '0';
    signal rden : std_logic := '0';
    signal valid : std_logic;
    signal ready : std_logic;
    signal sdram_a : std_logic_vector(12 downto 0);
    signal sdram_ba : std_logic_vector(1 downto 0);
    signal sdram_dqm : std_logic_vector(3 downto 0);
    signal sdram_dq : std_logic_vector(31 downto 0);
    signal sdram_read_data : std_logic_vector(31 downto 0) := x"1234_5678";
    signal cke : std_logic;
    signal sdram_clk_out : std_logic;
    signal we_n : std_logic;
    signal cas_n : std_logic;
    signal ras_n : std_logic;
    signal cs_n : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;
    sdram_dq <= sdram_read_data;

    dut: entity work.sdram_controller
        generic map (CAS_LATENCY => CAS_LATENCY)
        port map (
            clk => clk,
            sdram_clk_in => clk,
            rst => rst,
            addr => addr,
            D => data_in,
            Q => data_out,
            wren => wren,
            rden => rden,
            valid => valid,
            ready => ready,
            A => sdram_a,
            BA => sdram_ba,
            DQM => sdram_dqm,
            DQ => sdram_dq,
            CKE => cke,
            sdram_clk_out => sdram_clk_out,
            WE_N => we_n,
            CAS_N => cas_n,
            RAS_N => ras_n,
            CS_N => cs_n
        );

    stimulus: process
    begin
        wait for 1 ns;
        rst <= '0';
        wait for 201 us;
        rden <= '1';
        wait until ready = '1' and valid = '1';

        wait until ready = '0' and valid = '1' for 15 us;
        assert ready = '0' and valid = '1' and rden = '1'
            report "SDRAM controller did not drain an active read before refresh"
            severity failure;

        rden <= '0';
        wait for 1 ns;
        assert valid = '1' and data_out = sdram_read_data
            report "SDRAM controller lost pending read data when rden fell at refresh"
            severity failure;

        wait until valid = '0' for 1 us;
        assert valid = '0'
            report "SDRAM controller did not enter refresh after draining reads"
            severity failure;

        wait for 200 ns;
        rden <= '1';
        wait until ready = '1' and valid = '1' for 1 us;
        assert ready = '1' and valid = '1'
            report "SDRAM controller did not resume reads after refresh"
            severity failure;

        for cycle in 1 to CAS_LATENCY + 2 loop
            wait until rising_edge(clk);
        end loop;

        wait until falling_edge(clk);
        rden <= '0';
        wait for 1 ns;
        assert valid = '1' and data_out = sdram_read_data
            report "SDRAM controller hid the final read data when rden fell"
            severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;
        assert valid = '1' and ready = '0' and data_out = sdram_read_data
            report "SDRAM controller dropped valid before draining CAS latency"
            severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;
        assert valid = '1' and ready = '0' and data_out = sdram_read_data
            report "SDRAM controller did not keep valid through the final CAS cycle"
            severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;
        assert valid = '0' and ready = '0'
            report "SDRAM controller did not return to idle after draining read data"
            severity failure;

        report "tb_sdram_ctrl_read_drain: PASS" severity note;
        stop;
    end process;
end architecture;
