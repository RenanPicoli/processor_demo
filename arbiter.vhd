library ieee;
use ieee.std_logic_1164.all;

use ieee.numeric_std.all;--to_integer, to_unsigned, unsigned
use work.my_types.all;--boundaries, tuple

entity arbiter is
    --MULTI_CLK: when true, support multiple peripheral clock domains, otherwise all peripherals are assumed to be in the same clock domain and CLK can be ignored (set to others=>'0')
    --DOMAINS: per-peripheral clock domain identifiers, same size as B (array(natural range <>) of tuple(0 to 1))
    generic (
                B: boundaries; MULTI_CLK: boolean := false;
                CPU_ADDR_STABLE_CYCLES: natural := 4; -- number of fast-clock cycles that the CPU request must remain unchanged before it is released to the bus
                LOCAL_DOMAIN: natural := 0 -- clock domain owned by this arbiter; CDC is handled outside the arbiter
    );
    port (
        clk : in std_logic;--FASTEST memory clock (e.g. SDRAM)
        rst : in std_logic;
		MASTER_CLK_ID: out std_logic_vector(1 downto 0);--identifies the clock controlling the bus (for synchronization purposes)
        CLK_ARR: in array_of_std_logic(0 to 1) := (others => '0');-- input clocks for peripherals, same size as ranges
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
        -- mem_next_addr: out std_logic_vector(31 downto 0);-- for the address decoder to detect when a new write starts (for multi-clock support)
        mem_write_data: out std_logic_vector(31 downto 0);
        mem_rden: out std_logic;
        mem_wren: out std_logic;
        mem_ready: in std_logic;
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

signal ready_out: std_logic;
signal ready: std_logic;
signal RDEN: std_logic;
signal WREN: std_logic;

---- CPU address stability filter: hold back CPU requests until the request remains stable for the configured number of fast-clock cycles.
--signal cpu_filter_addr: std_logic_vector(31 downto 0);
--signal cpu_filter_write_data: std_logic_vector(31 downto 0);
--signal cpu_filter_rden: std_logic;
--signal cpu_filter_wren: std_logic;
--signal cpu_filter_valid: std_logic; -- indicates that the filtered CPU request is ready to be forwarded
--signal cpu_filter_count: natural range 0 to CPU_ADDR_STABLE_CYCLES;
--signal cpu_filter_sample_addr: std_logic_vector(31 downto 0);
--signal cpu_filter_sample_write_data: std_logic_vector(31 downto 0);
--signal cpu_filter_sample_rden: std_logic;
--signal cpu_filter_sample_wren: std_logic;
--signal cpu_filter_enable: std_logic; -- enables the filter whenever the CPU owns the bus and issues a request

begin

mem_addr <= mem_addr_reg;
mem_write_data <= mem_write_data_reg;
mem_rden <= mem_rden_reg;
mem_wren <= mem_wren_reg;

--cpu_addr_stability_filter_PROC : process(clk, rst)
--    variable cpu_filter_enable_v : std_logic;
--begin
--    if rst = '1' then
--        cpu_filter_enable <= '0';
--        cpu_filter_valid <= '0';
--        cpu_filter_addr <= (others => '0');
--        cpu_filter_write_data <= (others => '0');
--        cpu_filter_rden <= '0';
--        cpu_filter_wren <= '0';
--        cpu_filter_count <= 0;
--        cpu_filter_sample_addr <= (others => '0');
--        cpu_filter_sample_write_data <= (others => '0');
--        cpu_filter_sample_rden <= '0';
--        cpu_filter_sample_wren <= '0';
--    elsif rising_edge(clk) then
--        -- Only filter CPU accesses while the CPU owns the bus; DMA traffic is passed through directly.
--        cpu_filter_enable_v := '0';
--        if dma_access_granted = '0' and (cpu_rden = '1' or cpu_wren = '1') then
--            cpu_filter_enable_v := '1';
--        end if;
--        cpu_filter_enable <= cpu_filter_enable_v;
--
--        if cpu_filter_enable_v = '1' then
--            if cpu_filter_valid = '1' then
--                if cpu_addr = cpu_filter_addr and cpu_write_data = cpu_filter_write_data and
--                   cpu_rden = cpu_filter_rden and cpu_wren = cpu_filter_wren then
--                    cpu_filter_valid <= '1';
--                else
--                    cpu_filter_sample_addr <= cpu_addr;
--                    cpu_filter_sample_write_data <= cpu_write_data;
--                    cpu_filter_sample_rden <= cpu_rden;
--                    cpu_filter_sample_wren <= cpu_wren;
--                    cpu_filter_count <= 1;
--                    cpu_filter_valid <= '0';
--                end if;
--            elsif cpu_filter_count = 0 then
--                cpu_filter_sample_addr <= cpu_addr;
--                cpu_filter_sample_write_data <= cpu_write_data;
--                cpu_filter_sample_rden <= cpu_rden;
--                cpu_filter_sample_wren <= cpu_wren;
--                cpu_filter_count <= 1;
--                cpu_filter_valid <= '0';
--            elsif cpu_addr = cpu_filter_sample_addr and cpu_write_data = cpu_filter_sample_write_data and
--                  cpu_rden = cpu_filter_sample_rden and cpu_wren = cpu_filter_sample_wren then
--                if cpu_filter_count < CPU_ADDR_STABLE_CYCLES then
--                    cpu_filter_count <= cpu_filter_count + 1;
--                end if;
--
--                if cpu_filter_count = CPU_ADDR_STABLE_CYCLES then
--                    cpu_filter_valid <= '1';
--                    cpu_filter_addr <= cpu_filter_sample_addr;
--                    cpu_filter_write_data <= cpu_filter_sample_write_data;
--                    cpu_filter_rden <= cpu_filter_sample_rden;
--                    cpu_filter_wren <= cpu_filter_sample_wren;
--                    cpu_filter_count <= 0;
--                else
--                    cpu_filter_valid <= '0';
--                end if;
--            else
--                cpu_filter_sample_addr <= cpu_addr;
--                cpu_filter_sample_write_data <= cpu_write_data;
--                cpu_filter_sample_rden <= cpu_rden;
--                cpu_filter_sample_wren <= cpu_wren;
--                cpu_filter_count <= 1;
--                cpu_filter_valid <= '0';
--            end if;
--        else
--            cpu_filter_valid <= '0';
--            cpu_filter_count <= 0;
--        end if;
--    end if;
--end process;

dma_Q <= dma_Q_reg;
cpu_Q <= cpu_Q_reg;

arb_PROC : process(clk, rst)
begin
    if rst = '1' then
        mem_addr_reg <= (others => '0');
        mem_write_data_reg <= (others => '0');
        mem_rden_reg <= '0';
        mem_wren_reg <= '0';
--        cpu_ready_reg <= '0';
--        dma_ready_reg <= '0';
        cpu_Q_reg <= (others => '0');
        dma_Q_reg <= (others => '0');
        dma_access_granted_reg  <= '0';
    elsif rising_edge(clk) then
        dma_access_granted_reg <= dma_access_granted;
        case dma_access_granted is
        
            when '1' =>
                mem_addr_reg <= dma_addr;
                mem_write_data_reg <= dma_write_data;
                mem_wren_reg <= dma_wren;
                mem_rden_reg <= dma_rden;
                dma_Q_reg <= mem_Q;
                cpu_Q_reg <= (others => '0');
            when others =>
--                -- Forward the filtered CPU request only after the address/data/control signals have remained stable for the configured number of cycles.
--                if (cpu_filter_valid = '1') then
--                    mem_addr_reg <= cpu_filter_addr;
--                    mem_write_data_reg <= cpu_filter_write_data;
--                    mem_wren_reg <= cpu_filter_wren;
--                    mem_rden_reg <= cpu_filter_rden;
--                else
--                    mem_addr_reg <= mem_addr_reg;
--                    mem_write_data_reg <= mem_write_data_reg;
--                    mem_wren_reg <= '0';
--                    mem_rden_reg <= '0';
--                end if;
                    mem_addr_reg <= cpu_addr;
                    mem_write_data_reg <= cpu_write_data;
                    mem_wren_reg <= cpu_wren;
                    mem_rden_reg <= cpu_rden;
                dma_Q_reg <= (others => '0');
                cpu_Q_reg <= mem_Q;
        
        end case;
    end if;
end process;

ready <= ready_out when mem_rden='1' or mem_wren='1' else '0';
-- these processes are separated to avoid introducing additional latency in the data path from memory to cpu/dma
--CTRL_PROC : process(rst,clk,dma_access_granted, mem_rden, mem_wren, mem_ready, mem_Q, ready, dma_addr, dma_rden, dma_wren, cpu_addr, cpu_rden, cpu_wren, cpu_filter_valid, cpu_filter_addr, cpu_filter_rden, cpu_filter_wren)
CTRL_PROC : process(rst,clk,dma_access_granted, mem_rden, mem_wren, mem_ready, mem_Q, ready, dma_addr, dma_rden, dma_wren, cpu_addr, cpu_rden, cpu_wren)
 begin
    if rst = '1' then
        RDEN <= '0';
        WREN <= '0';
		--   dma_ready <= '0';
        -- cpu_ready <= '0';
    elsif rising_edge(clk) then
        case dma_access_granted is

            when '1' =>
                RDEN <= dma_rden;
                WREN <= dma_wren;
                -- dma_ready <= ready;
                -- cpu_ready <= '0';
                -- dma_Q <= mem_Q;
                -- cpu_Q <= (others => '0');
                -- mem_next_addr <= dma_addr;-- for the address decoder to detect when a new write starts (for multi-clock support)
            when others =>
					  RDEN <= cpu_rden;
					  WREN <= cpu_wren;
--                -- Keep the CPU-side control signals quiescent until the filtered request is valid.
--                if cpu_filter_valid = '1' then
--                    RDEN <= cpu_filter_rden;
--                    WREN <= cpu_filter_wren;
--                    -- cpu_ready <= ready;
--                else
--                    RDEN <= '0';
--                    WREN <= '0';
--                    -- cpu_ready <= '0';
--                end if;
                -- dma_ready <= '0';
                -- dma_Q <= (others => '0');
                -- cpu_Q <= mem_Q;
                -- mem_next_addr <= cpu_addr;-- for the address decoder to detect when a new write starts (for multi-clock support)
        end case;
    end if;
end process;

dma_ready <= ready when dma_access_granted='1' else '0';
cpu_ready <= ready when dma_access_granted='0' else '0';
--cpu_ready <= ready when dma_access_granted='0' and cpu_filter_valid='1' else '0';

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

-- This arbiter is local to CLK. Cross-domain transactions must arrive through
-- cdc_transaction_bridge before arbitration, so completion is taken directly
-- from the endpoint in this clock domain. The old DOMAINS/ready_out_reg path
-- is intentionally bypassed and will be removed after both local arbiters
-- are integrated in processor_demo.vhd.
process(RDEN,WREN,mem_ready)
begin
    if RDEN='1' or WREN='1' then
        ready_out <= mem_ready;
    else
        ready_out <= '1';
    end if;
end process;

end architecture;