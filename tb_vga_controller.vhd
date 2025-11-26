library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vga_controller is
end entity;

architecture sim of tb_vga_controller is

    -- Component declaration
    component vga_controller is
        port (
            clk     : in  std_logic;
				rst     : in  std_logic;   -- reset assíncrono
            PCLK    : in  std_logic;
            addr    : in  std_logic_vector(5 downto 0);
            data_in : in  std_logic_vector(31 downto 0);
            wren    : in  std_logic;

            SYNC_N  : out std_logic;
            BLANK_N : out std_logic;
            hsync   : out std_logic;
            vsync   : out std_logic;
            R       : out std_logic_vector(7 downto 0);
            G       : out std_logic_vector(7 downto 0);
            B       : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Test signals
    signal clk, PCLK, rst : std_logic := '0';
    signal addr      : std_logic_vector(5 downto 0) := (others => '0');
    signal data_in   : std_logic_vector(31 downto 0) := (others => '0');
    signal wren     : std_logic := '0';

    signal SYNC_N, BLANK_N, hsync, vsync : std_logic;
    signal R, G, B : std_logic_vector(7 downto 0);

    -- Clock generation
    constant CLK_PERIOD  : time := 40 ns;  -- 25 MHz
    constant PCLK_PERIOD : time := 40 ns;  -- Same as clk for test

begin

    -- Instantiate DUT
    uut: vga_controller
        port map (
            clk     => clk,
				rst	  => rst,
            PCLK    => PCLK,
            addr    => addr,
            data_in => data_in,
            wren    => wren,
            SYNC_N  => SYNC_N,
            BLANK_N => BLANK_N,
            hsync   => hsync,
            vsync   => vsync,
            R       => R,
            G       => G,
            B       => B
        );
		  
	 -- reset process
	 rst <='1', '0' after 80 ns;

    -- Clock process
    clk_process : process
    begin
        while now < 72 ms loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    PCLK_process : process
    begin
        while now < 72 ms loop
            PCLK <= '0';
            wait for PCLK_PERIOD / 2;
            PCLK <= '1';
            wait for PCLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Stimulus process
    stim_proc : process
    begin
        -- Aguarda inicializacao
        wait for 100 ns;

        -- Ativa SYNC_N e BLANK_N
        addr    <= "000001";  -- Endereco do CR
        data_in <= x"0000_0003";  -- SYNC_N=1, BLANK_N=1
        wren   <= '1';
        wait for CLK_PERIOD;
        wren   <= '0';

        -- Escreve alguns pixels na FIFO (vermelho, verde, azul)
        addr    <= "000000";
        wren   <= '1';

        data_in <= x"00FF_0000"; wait for CLK_PERIOD;  -- Vermelho
        data_in <= x"0000_FF00"; wait for CLK_PERIOD;  -- Verde
        data_in <= x"0000_00FF"; wait for CLK_PERIOD;  -- Azul

        wren <= '0';

        -- Simula por alguns milissegundos
        wait for 72 ms;
        wait;
    end process;

end architecture;
