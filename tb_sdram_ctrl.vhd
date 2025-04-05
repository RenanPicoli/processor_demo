library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

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
    signal irq       : std_logic;
    signal iack      : std_logic;
    signal wr_en     : std_logic := '0';

    -- Clock de 10 ns (100 MHz)
    constant clk_period : time := 10 ns;
begin

    -- Geração de clock
    process
    begin
        while now < 1000 us loop
            clk <= '0';
            wait for clk_period / 2;
            clk <= '1';
            wait for clk_period / 2;
        end loop;
        wait;
    end process;
	 
	 rst <= '1','0' after 1 ns;
	 
    uut: entity work.sdram_controller
    port map (
        clk       => clk,
        rst     	=> rst,
        addr      => addr,
        D         => D,
        Q         => Q,
        wr_en     => wr_en,
		  iack		=> '0'
    );
end architecture;