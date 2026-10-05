library ieee;
use ieee.std_logic_1164.all;

entity tb_arbiter_request_handshake is
end entity;

architecture test of tb_arbiter_request_handshake is
	signal clk: std_logic := '0';
	signal rst: std_logic := '1';
	signal cpu_addr: std_logic_vector(31 downto 0) := (others => '0');
	signal cpu_write_data: std_logic_vector(31 downto 0) := (others => '0');
	signal cpu_rden: std_logic := '0';
	signal cpu_wren: std_logic := '0';
	signal cpu_ready: std_logic;
	signal cpu_valid: std_logic;
	signal cpu_Q: std_logic_vector(31 downto 0);
	signal dma_addr: std_logic_vector(31 downto 0) := (others => '0');
	signal dma_write_data: std_logic_vector(31 downto 0) := (others => '0');
	signal dma_rden: std_logic := '0';
	signal dma_wren: std_logic := '0';
	signal dma_ready: std_logic;
	signal dma_valid: std_logic;
	signal dma_Q: std_logic_vector(31 downto 0);
	signal mem_addr: std_logic_vector(31 downto 0);
	signal mem_write_data: std_logic_vector(31 downto 0);
	signal mem_rden: std_logic;
	signal mem_wren: std_logic;
	signal mem_ready: std_logic := '1';
	signal mem_valid: std_logic := '1';
	signal mem_Q: std_logic_vector(31 downto 0);
	signal master_clk_id: std_logic_vector(1 downto 0);
begin
	clk <= not clk after 5 ns;
	mem_Q <= x"ABCD_1234" when mem_addr=x"0000_007D" else x"0000_0000";

	dut: entity work.arbiter
		port map (
			clk => clk,
			rst => rst,
			MASTER_CLK_ID => master_clk_id,
			cpu_addr => cpu_addr,
			cpu_write_data => cpu_write_data,
			cpu_rden => cpu_rden,
			cpu_wren => cpu_wren,
			cpu_ready => cpu_ready,
			cpu_valid => cpu_valid,
			cpu_Q => cpu_Q,
			dma_addr => dma_addr,
			dma_write_data => dma_write_data,
			dma_rden => dma_rden,
			dma_wren => dma_wren,
			dma_ready => dma_ready,
			dma_valid => dma_valid,
			dma_Q => dma_Q,
			mem_addr => mem_addr,
			mem_write_data => mem_write_data,
			mem_rden => mem_rden,
			mem_wren => mem_wren,
			mem_ready => mem_ready,
			mem_valid => mem_valid,
			mem_Q => mem_Q
		);

	stimulus: process
	begin
		wait for 12 ns;
		assert cpu_ready='0'
			report "CPU must not see ready during reset/idle" severity failure;
		rst <= '0';
		wait for 1 ns;
		assert cpu_ready='0'
			report "Idle memory-ready must not complete a CPU read" severity failure;

		cpu_addr <= x"0000_007D";
		cpu_rden <= '1';
		wait for 1 ns;
		assert cpu_ready='0'
			report "CPU read must wait until the arbiter registers the request" severity failure;

		wait until rising_edge(clk);
		wait for 1 ns;
		assert mem_addr=x"0000_007D" and mem_rden='1'
			report "Arbiter did not register the CPU read request" severity failure;
		assert cpu_ready='1' and cpu_valid='1' and cpu_Q=x"ABCD_1234"
			report "CPU response must carry the selected address data" severity failure;

		mem_ready <= '0';
		wait for 1 ns;
		assert cpu_ready='0'
			report "CPU must wait while the selected memory is not ready" severity failure;

		mem_ready <= '1';
		cpu_rden <= '0';
		wait for 1 ns;
		assert cpu_ready='0'
			report "CPU ready must drop after its request is withdrawn" severity failure;

		wait until rising_edge(clk);
		wait for 1 ns;
		assert mem_rden='0' and cpu_ready='0'
			report "Arbiter did not return to idle cleanly" severity failure;

		report "tb_arbiter_request_handshake passed" severity note;
		wait;
	end process;
end architecture;
