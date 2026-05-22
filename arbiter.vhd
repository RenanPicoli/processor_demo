library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity arbiter is
    port (
        clk : in std_logic;--memory clock (e.g. SDRAM)
        rst : in std_logic;
        -----
        cpu_addr: in std_logic_vector(31 downto 0);
        cpu_write_data: in std_logic_vector(31 downto 0);
        cpu_rden: in std_logic;
        cpu_wren: in std_logic;
        cpu_ready: out std_logic;
        cpu_Q: out std_logic_vector(31 downto 0);
        -----
        dma_addr: in std_logic_vector(31 downto 0);
        dma_write_data: in std_logic_vector(31 downto 0);
        dma_rden: in std_logic;
        dma_wren: in std_logic;
        dma_ready: out std_logic;
        dma_Q: out std_logic_vector(31 downto 0);
        -----
        mem_addr: out std_logic_vector(31 downto 0);
        mem_write_data: out std_logic_vector(31 downto 0);
        mem_rden: out std_logic;
        mem_wren: out std_logic;
        mem_ready: in std_logic;
        mem_Q: in std_logic_vector(31 downto 0)
    );
end arbiter;

architecture rtl of arbiter is

signal dma_access_granted: std_logic;
signal mem_addr_reg: std_logic_vector(31 downto 0);
signal mem_write_data_reg: std_logic_vector(31 downto 0);
signal mem_rden_reg: std_logic;
signal mem_wren_reg: std_logic;
signal cpu_ready_reg: std_logic;
signal dma_ready_reg: std_logic;
signal cpu_Q_reg: std_logic_vector(31 downto 0);
signal dma_Q_reg: std_logic_vector(31 downto 0);

begin

mem_addr <= mem_addr_reg;
mem_write_data <= mem_write_data_reg;
mem_rden <= mem_rden_reg;
mem_wren <= mem_wren_reg;
-- cpu_ready <= cpu_ready_reg;
-- dma_ready <= dma_ready_reg;
-- cpu_Q <= cpu_Q_reg;
-- dma_Q <= dma_Q_reg;

arb_PROC : process(clk, rst)
begin
    if rst = '1' then
        mem_addr_reg <= (others => '0');
        mem_write_data_reg <= (others => '0');
        mem_rden_reg <= '0';
        mem_wren_reg <= '0';
        cpu_ready_reg <= '0';
        dma_ready_reg <= '0';
        cpu_Q_reg <= (others => '0');
        dma_Q_reg <= (others => '0');
    elsif rising_edge(clk) then
        case dma_access_granted is
        
            when '1' =>
                mem_addr_reg <= dma_addr;
                mem_write_data_reg <= dma_write_data;
                mem_wren_reg <= dma_wren;
                mem_rden_reg <= dma_rden;
                -- dma_ready_reg <= mem_ready;
                -- cpu_ready_reg <= '0';
                -- dma_Q_reg <= mem_Q;
                -- cpu_Q_reg <= (others => '0');
            when others =>
                mem_addr_reg <= cpu_addr;
                mem_write_data_reg <= cpu_write_data;
                mem_wren_reg <= cpu_wren;
                mem_rden_reg <= cpu_rden;
                -- cpu_ready_reg <= mem_ready;
                -- dma_ready_reg <= '0';
                -- dma_Q_reg <= (others => '0');
                -- cpu_Q_reg <= mem_Q;
        
        end case;
    end if;
end process;

-- these processes are separated to avoid introducing additional latency in the data path from memory to cpu/dma
Q_READY_PROC : process(dma_access_granted, mem_ready, mem_Q)
 begin
    case dma_access_granted is

        when '1' =>
            dma_ready <= mem_ready;
            cpu_ready <= '0';
            dma_Q <= mem_Q;
            cpu_Q <= (others => '0');
        when others =>
            cpu_ready <= mem_ready;
            dma_ready <= '0';
            dma_Q <= (others => '0');
            cpu_Q <= mem_Q;

    end case;
end process;

DMA_ACCESS_PROC : process(clk, rst)
begin
    if rst = '1' then            
        dma_access_granted <= '0';--cpu controls memory

    elsif rising_edge(clk) then
        if (dma_rden='1' or dma_wren='1') and (cpu_rden='0' and cpu_wren='0') and dma_access_granted='0' then
            dma_access_granted <= '1';--dma takes control of memory
        elsif (cpu_rden='1' or cpu_wren='1') and (dma_rden='0' and dma_wren='0') and dma_access_granted='1' then
            dma_access_granted <= '0';
        end if;

    end if;
end process;

end architecture;