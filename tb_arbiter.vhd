library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use std.textio.all;-- for reading text file to initialize RAM

entity tb_arbiter is
end tb_arbiter;

architecture rtl of tb_arbiter is

signal    clk : std_logic;--cpu clock @4MHz
signal    rst : std_logic;
-----
signal    cpu_addr: std_logic_vector(31 downto 0);
signal    cpu_rden: std_logic;
signal    cpu_wren: std_logic;
signal    cpu_ready: std_logic;
signal    cpu_Q: std_logic_vector(31 downto 0);
-----
signal    dma_addr: std_logic_vector(31 downto 0);
signal    dma_rden: std_logic;
signal  dma_wren: std_logic;
signal  dma_ready: std_logic;
signal  dma_Q: std_logic_vector(31 downto 0);
-----
signal  mem_addr: std_logic_vector(31 downto 0);
signal  mem_rden: std_logic;
signal    mem_wren: std_logic;
signal    mem_ready: std_logic;
signal    mem_Q: std_logic_vector(31 downto 0);
signal    mem_clk: std_logic;--memory clock (e.g. SDRAM) @100MHz
signal mem_data  : std_logic_vector(31 downto 0) := (others => '0');
constant CPU_ADDR_STABLE_CYCLES : natural := 4;

signal irq: std_logic;
signal iack: std_logic;

-- Simulação de uma memória RAM
constant ram_depth : natural := 256;
constant ram_width : natural := 32;
type ram_type is array (0 to ram_depth-1) of std_logic_vector(ram_width-1 downto 0);
    
--code from https://vhdlwhiz.com/initialize-ram-from-file/
impure function init_ram_hex return ram_type is
    file text_file : text open read_mode is "ram_content_hex.txt";
    variable text_line : line;
    variable ram_content : ram_type;
begin
    for i in 0 to ram_depth - 1 loop
        readline(text_file, text_line);
        hread(text_line, ram_content(i));
    end loop;

    return ram_content;
end function;
signal RAM       : ram_type := init_ram_hex;--(others => (others => '0'));

-- Clock de 10 ns (100 MHz)
constant mem_clk_period : time := 10 ns;
-- Clock de 10 ns (4 MHz)
constant clk_period : time := 250 ns;

begin
    uut: entity work.arbiter
    generic map(
        CPU_ADDR_STABLE_CYCLES => CPU_ADDR_STABLE_CYCLES
    )
    port map(
        clk=> mem_CLK,--memory clock (e.g. SDRAM)
        rst=> rst,
        -----
        cpu_addr=> cpu_addr,
        cpu_rden=> cpu_rden,
        cpu_wren=> cpu_wren,
        cpu_ready=> cpu_ready,
        cpu_Q=> cpu_Q,
        -----
        dma_addr=> dma_addr,
        dma_rden=> dma_rden,
        dma_wren=> dma_wren,
        dma_ready=> dma_ready,
        dma_Q=> dma_Q,
        -----
        mem_addr=> mem_addr,
        mem_rden=> mem_rden,
        mem_wren=> mem_wren,
        mem_ready=> mem_ready,
        mem_Q=> mem_Q
    );

    -- Geracao de clock
    process
    begin
        while now < 2000 ns loop
            clk <= '0';
            wait for clk_period / 2;
            clk <= '1';
            wait for clk_period / 2;
        end loop;
        wait;
    end process;

    process
    begin
        while now < 2000 ns loop
            mem_clk <= '0';
            wait for mem_clk_period / 2;
            mem_clk <= '1';
            wait for mem_clk_period / 2;
        end loop;
        wait;
    end process;


    -- Teste principal
    process
    begin
        -- Reset do sistema
        rst <= '1';		  
	    iack <= '0';
        wait for 20 ns;
        rst <= '0';
        cpu_addr <= (others => '0');
        cpu_rden <= '0';
        cpu_wren <= '0';
        dma_addr <= (others => '0');
        dma_rden <= '0';
        dma_wren <= '0';

        wait for 80 ns;
        --acesso pela cpu, sem interrupção
        cpu_addr <= x"0000_000C";
        cpu_rden <= '1';
        cpu_wren <= '0';
        wait for clk_period;
        cpu_addr <= (others => '0');
        cpu_rden <= '0';
        cpu_wren <= '0';
        wait for 2*clk_period;

        -- teste do filtro de estabilidade do endereço da CPU
        cpu_addr <= x"0000_000C";
        cpu_rden <= '1';
        cpu_wren <= '0';
        wait for mem_clk_period;
        cpu_addr <= x"0000_000D";
        wait for mem_clk_period;
        assert mem_addr = x"0000_000C" report "filtro de estabilidade deveria manter o endereço inicial enquanto ele oscila" severity error;
        wait for CPU_ADDR_STABLE_CYCLES * mem_clk_period;
        assert mem_addr = x"0000_000D" report "filtro de estabilidade deveria liberar o acesso após o endereço estabilizar" severity error;
        cpu_addr <= (others => '0');
        cpu_rden <= '0';
        cpu_wren <= '0';
        wait for 2*clk_period;

        --acesso pelo dma sem interrupção
        dma_addr <= x"0000_000D";
        dma_rden <= '1';
        dma_wren <= '0';
        wait for mem_clk_period;
        dma_addr <= (others => '0');
        dma_rden <= '0';
        dma_wren <= '0';


        wait for 10*mem_clk_period;
        --acesso pelo dma COM interrupção pela cpu
        cpu_addr <= x"0000_000C";
        cpu_rden <= '1';
        cpu_wren <= '0';
        wait for 3*mem_clk_period;
        dma_addr <= x"0000_000D";
        dma_rden <= '1';
        dma_wren <= '0';
        wait for clk_period-3*mem_clk_period;
        cpu_addr <= (others => '0');
        cpu_rden <= '0';
        cpu_wren <= '0';
        wait for 2*clk_period;

        wait;
    end process;


    -- Processo para simular memória RAM
    process (mem_clk)
    begin
        if rising_edge(mem_clk) then
            if mem_rden = '1' then
                mem_data <= RAM(conv_integer(mem_addr));
            elsif mem_wren = '1' then
                RAM(conv_integer(mem_addr)) <= mem_data;
            end if;
        end if;
    end process;
	mem_ready <= '1';--, '0' after 145ns, '1' after 205ns, '0' after 695ns, '1' after 905ns;
end architecture;