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
        cpu_rden: in std_logic;
        cpu_wren: in std_logic;
        cpu_ready: out std_logic;
        cpu_Q: out std_logic_vector(31 downto 0);
        -----
        dma_addr: in std_logic_vector(31 downto 0);
        dma_rden: in std_logic;
        dma_wren: in std_logic;
        dma_ready: out std_logic;
        dma_Q: out std_logic_vector(31 downto 0);
        -----
        mem_addr: out std_logic_vector(31 downto 0);
        mem_rden: out std_logic;
        mem_wren: out std_logic;
        mem_ready: in std_logic;
        mem_Q: out std_logic_vector(31 downto 0)
    );
end arbiter;

architecture rtl of arbiter is

signal dma_access_granted: std_logic;

begin

arb_PROC : process(all)
begin
    case dma_access_granted is
    
        when '1' =>
            mem_addr <= dma_addr;
            mem_wren <= dma_wren;
            mem_rden <= dma_rden;
            dma_ready <= mem_ready;
            cpu_ready <= '0';
            dma_Q <= mem_Q;
            cpu_Q <= (others => '0');
        when others =>
            mem_addr <= cpu_addr;
            mem_wren <= cpu_wren;
            mem_rden <= cpu_rden;
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