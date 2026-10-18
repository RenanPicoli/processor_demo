library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.my_types.all;

entity tb_interrupt_controller_vectorized is
end entity;

architecture test of tb_interrupt_controller_vectorized is
	constant CLK_PERIOD: time := 10 ns;
	signal clk: std_logic := '0';
	signal rst: std_logic := '1';
	signal irq_in: std_logic_vector(5 downto 0) := (others => '0');
	signal irq_out: std_logic;
	signal iack_in: std_logic := '0';
	signal iack_out: std_logic_vector(5 downto 0);
	signal addr: std_logic_vector(6 downto 0) := (others => '0');
	signal data: std_logic_vector(31 downto 0) := (others => '0');
	signal wren: std_logic := '0';
	signal isr_addr: std_logic_vector(31 downto 0);
	signal ready: std_logic;
	signal output: std_logic_vector(31 downto 0);

begin
	clk <= not clk after CLK_PERIOD / 2;

	dut: entity work.interrupt_controller_vectorized
		generic map (L => 6)
		port map (
			D => data,
			ADDR => addr,
			CLK => clk,
			RST => rst,
			WREN => wren,
			RDEN => '0',
			PROC_READY => '1',
			IRQ_IN => irq_in,
			IRQ_OUT => irq_out,
			IACK_IN => iack_in,
			IACK_OUT => iack_out,
			ISR_ADDR => isr_addr,
			ready => ready,
			output => output
		);

	test: process
	begin
		wait for 3 * CLK_PERIOD;
		rst <= '0';

		wait until falling_edge(clk);
		wren <= '1';
		addr <= std_logic_vector(to_unsigned(64, addr'length));
		data <= std_logic_vector(to_unsigned(5, data'length));
		wait until rising_edge(clk);
		wait until falling_edge(clk);
		addr <= std_logic_vector(to_unsigned(65, addr'length));
		data <= x"FFFFFFFF";
		wait until rising_edge(clk);
		wait until falling_edge(clk);
		addr <= std_logic_vector(to_unsigned(72, addr'length));
		wait until rising_edge(clk);
		wait until falling_edge(clk);
		addr <= std_logic_vector(to_unsigned(40, addr'length));
		wait until rising_edge(clk);
		wait until falling_edge(clk);
		wren <= '0';
		addr <= (others => '0');
		wait until rising_edge(clk);

		for transfer in 1 to 12 loop
			wait until falling_edge(clk);
			irq_in(5) <= '1';

			wait until irq_out = '1' for 100 ns;
			assert irq_out = '1'
				report "CPU did not receive DMA interrupt on transfer " & integer'image(transfer)
				severity failure;

			wait until falling_edge(clk);
			irq_in(5) <= '0';
			iack_in <= '1';
			wait until rising_edge(clk);
			wait until falling_edge(clk);
			iack_in <= '0';
			wait until irq_out = '0' for 100 ns;
			assert irq_out = '0'
				report "CPU interrupt line did not clear after IACK"
				severity failure;
		end loop;

		report "All 12 DMA interrupt events reached the CPU" severity note;
		stop;
		wait;
	end process;
end architecture;
