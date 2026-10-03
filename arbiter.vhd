library ieee;
use ieee.std_logic_1164.all;

use ieee.numeric_std.all;--to_integer, to_unsigned, unsigned
use work.my_types.all;--boundaries, tuple

entity arbiter is
    generic (
                LOCAL_DOMAIN: natural := 0 -- clock domain owned by this arbiter; CDC is handled outside the arbiter
    );
    port (
        clk : in std_logic;--FASTEST memory clock (e.g. SDRAM)
        rst : in std_logic;
		MASTER_CLK_ID: out std_logic_vector(1 downto 0);--identifies the clock controlling the bus (for synchronization purposes)
        -----
        cpu_addr: in std_logic_vector(31 downto 0);
        cpu_write_data: in std_logic_vector(31 downto 0);
        cpu_rden: in std_logic;
        cpu_wren: in std_logic;
        cpu_ready: out std_logic;
        cpu_valid: out std_logic;
        cpu_Q: out std_logic_vector(31 downto 0);
        -----
        dma_addr: in std_logic_vector(31 downto 0);
        dma_write_data: in std_logic_vector(31 downto 0);
        dma_rden: in std_logic;
        dma_wren: in std_logic;
        dma_ready: out std_logic;
        dma_valid: out std_logic;
        dma_Q: out std_logic_vector(31 downto 0);
        -----
        mem_addr: out std_logic_vector(31 downto 0);
        -- mem_next_addr: out std_logic_vector(31 downto 0);-- for the address decoder to detect when a new write starts (for multi-clock support)
        mem_write_data: out std_logic_vector(31 downto 0);
        mem_rden: out std_logic;
        mem_wren: out std_logic;
        mem_ready: in std_logic;
        mem_valid: in std_logic;-- it means mem_Q is valid, and the arbiter can forward it to the requesting master
        mem_Q: in std_logic_vector(31 downto 0)
    );
end arbiter;

architecture rtl of arbiter is

--decompose n in m * 2^p, with n,m,p natural
--returns p, greatest dividing exponent of  n (see: https://mathworld.wolfram.com/GreatestDividingExponent.html)
--n_width is the width in bits of the representantion of n (in this case, address width)
function gde(v : unsigned) return natural is
begin

assert LOCAL_DOMAIN <= 1
    report "LOCAL_DOMAIN must be 0 (ram_clk) or 1 (sdram_ctrl_clk)"
    severity error;
    for i in 0 to v'length-1 loop
        if v(i) = '1' then
            return i;
        end if;
    end loop;

    return v'length;
end function;

signal dma_access_granted: std_logic;
signal dma_access_granted_reg: std_logic;
signal mem_addr_reg: std_logic_vector(31 downto 0);
signal mem_write_data_reg: std_logic_vector(31 downto 0);
signal mem_rden_reg: std_logic;
signal mem_wren_reg: std_logic;
--signal cpu_ready_reg: std_logic;
--signal dma_ready_reg: std_logic;
signal cpu_Q_reg: std_logic_vector(31 downto 0);
signal dma_Q_reg: std_logic_vector(31 downto 0);

-- signal ready_out: std_logic;
signal ready: std_logic;
-- signal RDEN: std_logic;
-- signal WREN: std_logic;

begin

mem_addr <= mem_addr_reg;
mem_write_data <= mem_write_data_reg;
mem_rden <= mem_rden_reg;
mem_wren <= mem_wren_reg;

-- slave outputs are forwarded to corresponding masters based on dma_access_granted,
-- so that the master that is not currently accessing the bus does not see the slave outputs

-- se o periferico aceitou o comando nesse ciclo,
-- o arbiter envia ready='1' para o master que esta requisitando poder executar o próximo acesso
-- se o periferico nao aceitou o comando nesse ciclo,
-- o arbiter envia ready='0' para o master que esta requisitando NÃO atualizar o barramento de controle/dados
dma_Q <= mem_Q when dma_access_granted='1' else (others => '0');
dma_ready <= mem_ready when dma_access_granted='1' else '0';
dma_valid <= mem_valid when dma_access_granted='1' else '0';

cpu_ready <= mem_ready when dma_access_granted='0' else '0';
cpu_valid <= mem_valid when dma_access_granted='0' else '0';
cpu_Q <= mem_Q when dma_access_granted='0' else (others => '0');

arb_PROC : process(clk, rst)
begin
    if rst = '1' then
        mem_addr_reg <= (others => '0');
        mem_write_data_reg <= (others => '0');
        mem_rden_reg <= '0';
        mem_wren_reg <= '0';
--        cpu_ready_reg <= '0';
--        dma_ready_reg <= '0';
--        cpu_Q_reg <= (others => '0');
--        dma_Q_reg <= (others => '0');
        dma_access_granted_reg  <= '0';
    elsif rising_edge(clk) then
        dma_access_granted_reg <= dma_access_granted;
        case dma_access_granted is
        
            when '1' =>
                mem_addr_reg <= dma_addr;
                mem_write_data_reg <= dma_write_data;
                mem_wren_reg <= dma_wren;
                mem_rden_reg <= dma_rden;
--                dma_Q_reg <= mem_Q;
--                cpu_Q_reg <= (others => '0');
            when others =>
					  mem_addr_reg <= cpu_addr;
					  mem_write_data_reg <= cpu_write_data;
					  mem_wren_reg <= cpu_wren;
					  mem_rden_reg <= cpu_rden;
--                dma_Q_reg <= (others => '0');
--                cpu_Q_reg <= mem_Q;
        
        end case;
    end if;
end process;

-- ready <= ready_out when mem_rden='1' or mem_wren='1' else '0';

-- -- these processes are separated to avoid introducing additional latency in the data path from memory to cpu/dma
-- --CTRL_PROC : process(rst,clk,dma_access_granted, mem_rden, mem_wren, mem_ready, mem_Q, ready, dma_addr, dma_rden, dma_wren, cpu_addr, cpu_rden, cpu_wren, cpu_filter_valid, cpu_filter_addr, cpu_filter_rden, cpu_filter_wren)
-- CTRL_PROC : process(rst,clk,dma_access_granted, mem_rden, mem_wren, mem_ready, mem_Q, ready, dma_addr, dma_rden, dma_wren, cpu_addr, cpu_rden, cpu_wren)
--  begin
--     if rst = '1' then
--         RDEN <= '0';
--         WREN <= '0';
-- 		--   dma_ready <= '0';
--         -- cpu_ready <= '0';
--     elsif rising_edge(clk) then
--         case dma_access_granted is

--             when '1' =>
--                 RDEN <= dma_rden;
--                 WREN <= dma_wren;
--                 -- dma_ready <= ready;
--                 -- cpu_ready <= '0';
--                 -- mem_next_addr <= dma_addr;-- for the address decoder to detect when a new write starts (for multi-clock support)
--             when others =>
-- 					  RDEN <= cpu_rden;
-- 					  WREN <= cpu_wren;
--                 -- dma_ready <= '0';
--                 -- mem_next_addr <= cpu_addr;-- for the address decoder to detect when a new write starts (for multi-clock support)
--         end case;
--     end if;
-- end process;

DMA_ACCESS_PROC : process(clk, rst, dma_rden, dma_wren, cpu_rden, cpu_wren, dma_access_granted)
begin
    if rst = '1' then            
        dma_access_granted <= '0';--cpu controls memory
        MASTER_CLK_ID <= "00";-- assuming the CPU is in clock domain 0, if there are multiple clock domains

    elsif rising_edge(clk) then
        if (dma_rden='1' or dma_wren='1') and (cpu_rden='0' and cpu_wren='0') and dma_access_granted='0' then
            dma_access_granted <= '1';--dma takes control of memory
            MASTER_CLK_ID <= "01";-- assuming the DMA is in clock domain 1, if there are multiple clock domains
        elsif (cpu_rden='1' or cpu_wren='1') and (dma_rden='0' and dma_wren='0') and dma_access_granted='1' then
            dma_access_granted <= '0';
            MASTER_CLK_ID <= "00";-- assuming the CPU is in clock domain 0, if there are multiple clock domains
        end if;

    end if;
end process;

-- -- This arbiter is local to CLK. Cross-domain transactions must arrive through
-- -- cdc_transaction_bridge before arbitration, so completion is taken directly
-- -- from the endpoint in this clock domain. The old DOMAINS/ready_out_reg path
-- -- is intentionally bypassed and will be removed after both local arbiters
-- -- are integrated in processor_demo.vhd.
-- process(mem_rden,mem_wren,mem_ready)
-- begin
--     if mem_rden='1' or mem_wren='1' then
--         -- se o periferico aceitou o comando nesse ciclo,
--         -- o arbiter envia ready='1' para o master que esta requisitando poder executar o próximo acesso
--         ready <= mem_ready;
--     else
--         -- se nenhum master esta requisitando acesso, o arbiter envia ready='1' para o master que esta requisitando poder executar um acesso
--         ready <= '1';
--     end if;
-- end process;

end architecture;