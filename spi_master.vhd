library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity spi_master is
    Generic ( N : integer := 8 ); -- Número de bits configurável
    Port ( 
        CLK     : in  std_logic;
        RST     : in  std_logic;  -- Reset assíncrono ativo alto
        start_en: in  std_logic;
        DR      : in  std_logic_vector(N-1 downto 0);
        MISO    : in  std_logic;
        MOSI    : out std_logic;
        CS      : out std_logic;
        SCK     : out std_logic;  -- Clock serial
        REG_OUT : out std_logic_vector(N-1 downto 0) -- Registrador de saída
    );
end spi_master;

architecture Behavioral of spi_master is
    signal shift_reg : std_logic_vector(N-1 downto 0);
    signal bit_cnt   : integer range 0 to N := 0;
    signal cs_reg    : std_logic := '1'; -- Controle do CS interno
begin
    process (CLK, RST, bit_cnt)
    begin
        if RST = '1' then
            -- Reset assíncrono
            cs_reg <= '1';
            REG_OUT <= (others => '0');
        elsif rising_edge(CLK) then
            if start_en = '1' then
                -- Início da transmissão
                cs_reg <= '0';  -- Ativa CS
            else
                if bit_cnt = N then
                    -- Último bit transmitido
                    cs_reg <= '1';  -- Finaliza CS
                    REG_OUT <= shift_reg; -- Armazena resultado final
                end if;
            end if;
        end if;
    end process;
	 
    process (SCK, RST)
    begin
        if RST = '1' then
            -- Reset assíncrono
            bit_cnt <= 0;
        elsif rising_edge(SCK) then
            if start_en = '1' then
                -- Início da transmissão
                bit_cnt <= 0;
            else
                if bit_cnt < N then
                    -- Realiza o shift
                    bit_cnt <= bit_cnt + 1;
					 elsif bit_cnt=N then
							bit_cnt <= 0;
                end if;
            end if;
        end if;
    end process;
	 
    process (CLK, RST)
    begin
        if RST = '1' then
            -- Reset assíncrono
            shift_reg <= (others => '0');
        elsif falling_edge(CLK) then
            if start_en = '1' then
                -- Início da transmissão
                shift_reg <= DR;
            else
                if bit_cnt < N then
                    -- Realiza o shift
                    shift_reg <= shift_reg(N-2 downto 0) & MISO;
                end if;
            end if;
        end if;
    end process;
    
    -- Saídas
    MOSI <= shift_reg(N-1) when cs_reg='0' else 'Z';
    CS <= cs_reg;
    SCK <= (not CLK) when cs_reg = '0' else '0'; -- Inverte CLK quando CS = 0, senão mantém 0

end Behavioral;
