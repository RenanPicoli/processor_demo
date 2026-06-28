library ieee;
use ieee.std_logic_1164.all;

use ieee.numeric_std.all;--to_integer, to_unsigned, unsigned
use work.my_types.all;--boundaries, tuple

entity arbiter is
    --MULTI_CLK: when true, support multiple peripheral clock domains, otherwise all peripherals are assumed to be in the same clock domain and CLK can be ignored (set to others=>'0')
    --DOMAINS: per-peripheral clock domain identifiers, same size as B (array(natural range <>) of tuple(0 to 1))
    generic (
                B: boundaries; MULTI_CLK: boolean := false;
                CPU_ADDR_STABLE_CYCLES: natural := 4 -- number of fast-clock cycles that the CPU request must remain unchanged before it is released to the bus
    );
    port (
        clk : in std_logic;--memory clock (e.g. SDRAM)
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
    for i in 0 to v'length-1 loop
        if v(i) = '1' then
            return i;
        end if;
    end loop;

    return v'length;
end function;

signal dma_access_granted: std_logic;
signal mem_addr_reg: std_logic_vector(31 downto 0);
signal mem_write_data_reg: std_logic_vector(31 downto 0);
signal mem_rden_reg: std_logic;
signal mem_wren_reg: std_logic;
signal cpu_ready_reg: std_logic;
signal dma_ready_reg: std_logic;
signal cpu_Q_reg: std_logic_vector(31 downto 0);
signal dma_Q_reg: std_logic_vector(31 downto 0);

signal sel_periph_index: natural;
signal ready_out_reg: std_logic_vector(CLK_ARR'length-1 downto 0);--one ready_out_reg for each clk possibility
signal ready_out: std_logic;
signal ready: std_logic;

signal ADDR: std_logic_vector(31 downto 0);
type ADDR_array is array(natural range <>) of std_logic_vector(31 downto 0);
signal ADDR_reg: ADDR_array(0 to CLK_ARR'length-1);--register the address at the destination clock domain to detect when a new write starts
signal RDEN: std_logic;
signal WREN: std_logic;
-- CPU address stability filter: hold back CPU requests until the request remains stable for the configured number of fast-clock cycles.
signal cpu_filter_addr: std_logic_vector(31 downto 0);
signal cpu_filter_write_data: std_logic_vector(31 downto 0);
signal cpu_filter_rden: std_logic;
signal cpu_filter_wren: std_logic;
signal cpu_filter_valid: std_logic; -- indicates that the filtered CPU request is ready to be forwarded
signal cpu_filter_count: natural range 0 to CPU_ADDR_STABLE_CYCLES;
signal cpu_filter_sample_addr: std_logic_vector(31 downto 0);
signal cpu_filter_sample_write_data: std_logic_vector(31 downto 0);
signal cpu_filter_sample_rden: std_logic;
signal cpu_filter_sample_wren: std_logic;
signal cpu_filter_enable: std_logic; -- enables the filter whenever the CPU owns the bus and issues a request

type integer_array is array (natural range <>) of integer;
-- per-peripheral clock domain identifiers for writes: same size as ranges
constant DOMAINS: integer_array (0 to 20) := 	(-- 0: CPU clock; 1: SDRAM clk
											0,-- 0: filter coeffs
											0,-- 1: filter xN
											0,-- 2: cache
											0,-- 3: inner_product
											0,-- 4: VMAC
											0,-- 5: I2C
											0,-- 6: I2S
											0,-- 7: current filter output
											0,-- 8: desired response
											0,-- 9: filter status
											0,-- 10: converted_out
											0,-- 11: 7-segments display DR
											0,-- 12: LCD controller
											0,-- 13: general purpose fp32_to_int32
											0,-- 14: UART peripheral (IF AVAILABLE)
											1,-- 15: DMA
											1,-- 16: VGA
											0,-- 17: interrupt controller
											0,-- 18: tmp_vector
											0,-- 19: instruction memory (aka program_data)
											1 --20: SDRAM
											);
begin

mem_addr <= mem_addr_reg;
mem_write_data <= mem_write_data_reg;
mem_rden <= mem_rden_reg;
mem_wren <= mem_wren_reg;

cpu_addr_stability_filter_PROC : process(clk, rst)
    variable cpu_filter_enable_v : std_logic;
begin
    if rst = '1' then
        cpu_filter_enable <= '0';
        cpu_filter_valid <= '0';
        cpu_filter_addr <= (others => '0');
        cpu_filter_write_data <= (others => '0');
        cpu_filter_rden <= '0';
        cpu_filter_wren <= '0';
        cpu_filter_count <= 0;
        cpu_filter_sample_addr <= (others => '0');
        cpu_filter_sample_write_data <= (others => '0');
        cpu_filter_sample_rden <= '0';
        cpu_filter_sample_wren <= '0';
    elsif rising_edge(clk) then
        -- Only filter CPU accesses while the CPU owns the bus; DMA traffic is passed through directly.
        cpu_filter_enable_v := '0';
        if dma_access_granted = '0' and (cpu_rden = '1' or cpu_wren = '1') then
            cpu_filter_enable_v := '1';
        end if;
        cpu_filter_enable <= cpu_filter_enable_v;

        if cpu_filter_enable_v = '1' then
            if cpu_filter_valid = '1' then
                if cpu_addr = cpu_filter_addr and cpu_write_data = cpu_filter_write_data and
                   cpu_rden = cpu_filter_rden and cpu_wren = cpu_filter_wren then
                    cpu_filter_valid <= '1';
                else
                    cpu_filter_sample_addr <= cpu_addr;
                    cpu_filter_sample_write_data <= cpu_write_data;
                    cpu_filter_sample_rden <= cpu_rden;
                    cpu_filter_sample_wren <= cpu_wren;
                    cpu_filter_count <= 1;
                    cpu_filter_valid <= '0';
                end if;
            elsif cpu_filter_count = 0 then
                cpu_filter_sample_addr <= cpu_addr;
                cpu_filter_sample_write_data <= cpu_write_data;
                cpu_filter_sample_rden <= cpu_rden;
                cpu_filter_sample_wren <= cpu_wren;
                cpu_filter_count <= 1;
                cpu_filter_valid <= '0';
            elsif cpu_addr = cpu_filter_sample_addr and cpu_write_data = cpu_filter_sample_write_data and
                  cpu_rden = cpu_filter_sample_rden and cpu_wren = cpu_filter_sample_wren then
                if cpu_filter_count < CPU_ADDR_STABLE_CYCLES then
                    cpu_filter_count <= cpu_filter_count + 1;
                end if;

                if cpu_filter_count = CPU_ADDR_STABLE_CYCLES then
                    cpu_filter_valid <= '1';
                    cpu_filter_addr <= cpu_filter_sample_addr;
                    cpu_filter_write_data <= cpu_filter_sample_write_data;
                    cpu_filter_rden <= cpu_filter_sample_rden;
                    cpu_filter_wren <= cpu_filter_sample_wren;
                    cpu_filter_count <= 0;
                else
                    cpu_filter_valid <= '0';
                end if;
            else
                cpu_filter_sample_addr <= cpu_addr;
                cpu_filter_sample_write_data <= cpu_write_data;
                cpu_filter_sample_rden <= cpu_rden;
                cpu_filter_sample_wren <= cpu_wren;
                cpu_filter_count <= 1;
                cpu_filter_valid <= '0';
            end if;
        else
            cpu_filter_valid <= '0';
            cpu_filter_count <= 0;
        end if;
    end if;
end process;

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
            when others =>
                -- Forward the filtered CPU request only after the address/data/control signals have remained stable for the configured number of cycles.
                if (cpu_filter_valid = '1') then
                    mem_addr_reg <= cpu_filter_addr;
                    mem_write_data_reg <= cpu_filter_write_data;
                    mem_wren_reg <= cpu_filter_wren;
                    mem_rden_reg <= cpu_filter_rden;
                else
                    mem_addr_reg <= mem_addr_reg;
                    mem_write_data_reg <= mem_write_data_reg;
                    mem_wren_reg <= '0';
                    mem_rden_reg <= '0';
                end if;
        
        end case;
    end if;
end process;

ready <= ready_out when mem_rden='1' or mem_wren='1' else '0';
-- these processes are separated to avoid introducing additional latency in the data path from memory to cpu/dma
Q_READY_PROC : process(dma_access_granted, mem_rden, mem_wren, mem_ready, mem_Q, ready, dma_addr, dma_rden, dma_wren, cpu_addr, cpu_rden, cpu_wren, cpu_filter_valid, cpu_filter_addr, cpu_filter_rden, cpu_filter_wren)
 begin
    case dma_access_granted is

        when '1' =>
            ADDR <= dma_addr;
            RDEN <= dma_rden;
            WREN <= dma_wren;
            dma_ready <= ready;
            cpu_ready <= '0';
            dma_Q <= mem_Q;
            cpu_Q <= (others => '0');
            -- mem_next_addr <= dma_addr;-- for the address decoder to detect when a new write starts (for multi-clock support)
        when others =>
            -- Keep the CPU-side control signals quiescent until the filtered request is valid.
            if cpu_filter_valid = '1' then
                ADDR <= cpu_filter_addr;
                RDEN <= cpu_filter_rden;
                WREN <= cpu_filter_wren;
                cpu_ready <= ready;
            else
                ADDR <= ADDR;
                RDEN <= '0';
                WREN <= '0';
                cpu_ready <= '0';
            end if;
            dma_ready <= '0';
            dma_Q <= (others => '0');
            cpu_Q <= mem_Q;
            -- mem_next_addr <= cpu_addr;-- for the address decoder to detect when a new write starts (for multi-clock support)

    end case;
end process;

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

process(RDEN,WREN,sel_periph_index,mem_ready,ready_out_reg,MASTER_CLK_ID)
begin
    if (RDEN='1') then
        ready_out <= mem_ready;
    elsif (WREN='1') then
        if (MULTI_CLK) then
            if (std_logic_vector(to_unsigned(DOMAINS(sel_periph_index), 2)) = MASTER_CLK_ID) then--if the peripheral is in the same clock domain as the bus, use combinational ready signal
                ready_out <= mem_ready;
            else
                ready_out <= ready_out_reg(DOMAINS(sel_periph_index));-- uses registered value
            end if;
        else
            ready_out <= mem_ready;
        end if;
    else
        ready_out <= '1';
    end if;
end process;

reg_multi_clk: for i in 0 to CLK_ARR'length-1 generate
    reg: process(CLK_ARR,RDEN,WREN,sel_periph_index,mem_ready,MASTER_CLK_ID,ADDR,ADDR_reg)
    begin
        report "clock number :" & integer'image(CLK_ARR'length) & " clocks";
        -- when a NEW write starts to a peripheral in a different clock domain, the ready_out_reg at the destination clock domain is reset
        if (WREN='1' and (ADDR /= ADDR_reg(i)) and MULTI_CLK and std_logic_vector(to_unsigned(DOMAINS(sel_periph_index), 2)) /= MASTER_CLK_ID) then--for a write to a peripheral in a different clock domain, register the ready signal at the destination clock domain
            ready_out_reg(i) <= '0';-- start with not ready when a write starts
        -- elsif (rising_edge(CLK_ARR(i))) then--updated at rising edge of destination clock
        else
            ready_out_reg(i) <= mem_ready;-- in this simple implementation, I just directly register the memory ready signal, but ideally this should be a signal generated by the peripheral to indicate it has processed the new data (e.g. after synchronizing the write enable signal to its clock domain and processing the new data)
        end if;
    end process;

    addr_reg_proc: process(CLK_ARR)
    begin
        if rising_edge(CLK_ARR(i)) then
            ADDR_reg(i) <= ADDR;--register the address at the destination clock domain to detect when a new write starts
        end if;
    end process;
end generate reg_multi_clk;

--	assert CLK_ARR'length = 2 report "Numero de clocks errado: "& integer'image(CLK_ARR'length) severity error;
-- mux of data read
process(ADDR,RDEN,WREN)
    variable p: natural;
    variable mask: std_logic_vector(32 downto 0);
    variable mask_length: natural;	
    variable upper_lim_slv: std_logic_vector(31 downto 0);
    variable lower_lim_slv: std_logic_vector(31 downto 0);
begin
    sel_periph_index <= 0;
    -- i-th element of B is associated with address i
    for i in B'range loop
        --decompose B(i)(0) in m * 2^p, m,p natural
        --returns p, greatest dividing exponent of  B(i)(0) (see: https://mathworld.wolfram.com/GreatestDividingExponent.html)
        p := gde(to_unsigned(B(i)(0),32));
        report "Range: [" & integer'image(B(i)(0)) & ", " & integer'image(B(i)(1)) & "]; p = " & integer'image(p);
        
        assert (B(i)(0) <= B(i)(1)) report "Range must be ascending!" severity error;
        if(i > 0)then
            assert (B(i-1)(1) < B(i)(0)) report "Ranges overlap!" severity error;
        end if;
        --aligned start address is not strict requirement: I can subtract base address and get a zero-base internall address
--			assert ((B(i)(1) < B(i)(0) + 2**p) or p=32) report "Unaligned range:[" & integer'image(B(i)(0)) & ", " & integer'image(B(i)(1)) & "]" severity error;
        mask(32) := '1';
        upper_lim_slv := std_logic_vector(to_unsigned(B(i)(1),32));
        lower_lim_slv := std_logic_vector(to_unsigned(B(i)(0),32));
        for j in 31 downto 0 loop
            if(upper_lim_slv(j)=lower_lim_slv(j) and mask(j+1)='1')then
                mask(j) := '1';
            else
                mask(j) :='0';
            end if;
        end loop;
        report "mask=" & integer'image(to_integer(unsigned(mask(31 downto 0))));
        mask_length := 32 - gde(unsigned(mask(31 downto 0)));--address width minus number of zeros in mask
        report "mask_length=" & integer'image(mask_length);
        
        if ((B(i)(0) <= to_integer(unsigned(ADDR))) and (to_integer(unsigned(ADDR)) <= B(i)(1))) then
--			--this is intended to simplify logic, but requires ALIGNED BOUNDARIES
--			if (ADDR(N-1 downto N-mask_length) = lower_lim_slv(N-1 downto N-mask_length)) then
            sel_periph_index <= i;
        end if;
    end loop;    
    
    report "B'length= # of peripherals = " & integer'image(B'length);
end process;

end architecture;