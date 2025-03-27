library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity tb_spi_master is
end tb_spi_master;

architecture Behavioral of tb_spi_master is
    constant N : integer := 8;  -- Número de bits do shift register
    constant CLK_PERIOD : time := 100 ns; -- 10 MHz

    -- Sinais de teste
    signal CLK      : std_logic := '0';
    signal RST      : std_logic := '1';
    signal start_en : std_logic := '0';
    signal DR       : std_logic_vector(N-1 downto 0) := "10101010"; -- Dado de entrada
    signal MISO     : std_logic := '0';
    signal MOSI     : std_logic;
    signal CS       : std_logic;
    signal SCK      : std_logic;
    signal REG_OUT  : std_logic_vector(N-1 downto 0);

begin
    -- Instância do Shift Register
    uut: entity work.spi_master
        generic map (N => N)
        port map (
            CLK      => CLK,
            RST      => RST,
            start_en => start_en,
            DR       => DR,
            MISO     => MISO,
            MOSI     => MOSI,
            CS       => CS,
            SCK      => SCK,
            REG_OUT  => REG_OUT
        );

    -- Geração do clock de 10 MHz
    process
    begin
        while now < 2 ms loop
            CLK <= '0';
            wait for CLK_PERIOD / 2;
            CLK <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Processo de estímulo
    process
    begin
        -- Reset inicial
        wait for 200 ns;  
        RST <= '0';
        wait for 150.1 ns;
		  
        -- Inicia a transmissão carregando DR no shift register
        start_en <= '1';
        wait for CLK_PERIOD;
        start_en <= '0';
		  wait;
		end process;
		
		process
		begin
        wait for 450 ns;

        -- Simula entrada de dados no MISO e observa MOSI
        for i in 0 to N-1 loop
            MISO <= not MISO;  -- Alterna bits de entrada
            wait for CLK_PERIOD;
        end loop;

        -- Aguarda a transmissão ser concluída
        wait for CLK_PERIOD * N;

        -- Verifica o valor final armazenado
        assert REG_OUT = "10101010"
        report "Erro: REG_OUT não armazenou o valor correto!"
        severity error;

        wait;
    end process;

end Behavioral;
