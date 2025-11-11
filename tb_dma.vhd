library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use std.textio.all;-- for reading text file to initialize RAM

entity tb_dma is
end entity;

architecture test of tb_dma is
    -- Sinais do DUT (Device Under Test)
    signal clk       : std_logic := '0';
    signal reset     : std_logic := '1';
    signal addr      : std_logic_vector(1 downto 0) := "00";
    signal D         : std_logic_vector(31 downto 0) := (others => '0');
    signal Q         : std_logic_vector(31 downto 0);
    signal wr_en     : std_logic := '0';

    -- Interface de memória única
    signal mem_CLK   : std_logic;
    signal mem_addr  : std_logic_vector(31 downto 0);
    signal mem_data_in  : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_data_out : std_logic_vector(31 downto 0) := (others => '0');
	signal mem_ready	: std_logic;
    signal mem_rden  : std_logic;
    signal mem_wren  : std_logic;
    
    -- Interrupção do DMA
    signal irq       : std_logic;
    signal iack      : std_logic;

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
    -- Instância do DMA
    uut: entity work.dma_controller
    port map (
        clk       => clk,
        reset     => reset,
        addr      => addr,
        D         => D,
        Q         => Q,
        wr_en     => wr_en,
        mem_clk   => mem_clk,
        mem_addr  => mem_addr,
        mem_data_in  =>  mem_data_in,
        mem_data_out  => mem_data_out,
		mem_ready => mem_ready,
        mem_rden  => mem_rden,
        mem_wren  => mem_wren,
        irq       => irq,
		iack	  => iack
    );

    -- Geração de clock
    process
    begin
        while now < 4000 ns loop
            clk <= '0';
            wait for clk_period / 2;
            clk <= '1';
            wait for clk_period / 2;
        end loop;
        wait;
    end process;

    process
    begin
        while now < 4000 ns loop
            mem_clk <= '0';
            wait for mem_clk_period / 2;
            mem_clk <= '1';
            wait for mem_clk_period / 2;
        end loop;
        wait;
    end process;

    -- Processo para simular memória RAM
    process (mem_clk)
    begin
        if rising_edge(mem_clk) then
            if mem_rden = '1' then
                mem_data_in <= RAM(conv_integer(mem_addr));
            elsif mem_wren = '1' then
                RAM(conv_integer(mem_addr)) <= mem_data_out;
            end if;
        end if;
    end process;
	mem_ready <= '0', '1' after 1130ns;

    -- Teste principal
    process
    begin
        -- Reset do sistema
        reset <= '1';		  
		iack <= '0';
        wait for 20 ns;
        reset <= '0';

        -- Configuração dos registradores do DMA
        wait for clk_period/2-20ns+1ns;-- +1ns to make addr/D/wr_en after clock edges
        wr_en <= '1';
        
        addr <= "00"; D <= x"00000000"; wait for clk_period; -- src_addr = 0x00000000
        addr <= "01"; D <= x"000000D0"; wait for clk_period; -- dst_addr = 0x000000D0
        addr <= "10"; D <= x"00000030"; wait for clk_period; -- length = 48 (48 palavras)
        addr <= "11"; D <= x"0000000D"; wait for clk_period; -- CR: Start = 1, SINC = 1, DINC = 1

        wr_en <= '0';

        -- Aguarda a interrupção (fim da transferência)
        wait until irq = '1';
        wait for 250 ns;
		iack <= '1';

        -- Verifica se os dados foram transferidos corretamente
        for i in 0 to 15 loop
            assert RAM(i + 208) = std_logic_vector(to_unsigned(i+1, 32))
                report "Erro na transferencia! Endereco: " & integer'image(i + 208) & ", valor:" &  to_hstring(RAM(i + 208))
                severity error;
        end loop;

        -- Indica sucesso no teste
        report "Teste concluido com sucesso!" severity note;

        wait;
    end process;

end architecture;
