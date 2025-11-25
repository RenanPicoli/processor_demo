library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_controller is
    port (
        clk        : in  std_logic;   -- Clock principal, mesmo do DMA e SDRAM
        rst        : in  std_logic;   -- reset assíncrono
        PCLK       : in  std_logic;   -- Pixel clock
        addr       : in  std_logic_vector(5 downto 0);
        data_in    : in  std_logic_vector(31 downto 0);
        wren       : in  std_logic;
        ready      : out  std_logic;

        SYNC_N     : out std_logic;
        BLANK_N    : out std_logic;

        hsync      : out std_logic;
        vsync      : out std_logic;

        R          : out std_logic_vector(7 downto 0);
        G          : out std_logic_vector(7 downto 0);
        B          : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of vga_controller is

    type vga_config_t is record
        h_visible    : natural;
        h_front_porch: natural;
        h_sync       : natural;
        h_back_porch : natural;
        h_total      : natural;

        v_visible    : natural;
        v_front_porch: natural;
        v_sync       : natural;
        v_back_porch : natural;
        v_total      : natural;
    end record;

    -- Configuração VGA 640x480 @ 60Hz
    constant VGA_640x480_60Hz : vga_config_t := (
        h_visible     => 640,
        h_front_porch => 16,--or 144?
        h_sync        => 96,
        h_back_porch  => 48,
        h_total       => 800,
        v_visible     => 480,
        v_front_porch => 10,
        v_sync        => 2,
        v_back_porch  => 33,
        v_total       => 525
    );

    -- Configuração VGA 800x600 @ 60Hz
    constant VGA_800x600_60Hz : vga_config_t := (
        h_visible     => 800,
        h_front_porch => 40,
        h_sync        => 128,
        h_back_porch  => 88,
        h_total       => 1056,
        v_visible     => 600,
        v_front_porch => 1,
        v_sync        => 4,
        v_back_porch  => 23,
        v_total       => 628
    );

    --selects desired resolution, PCLK must be adjusted accordingly
    constant VGA: vga_config_t := VGA_640x480_60Hz;

    -- Registradores
    signal CR : std_logic_vector(31 downto 0) := (others => '0'); -- Bit 0: SYNC_N, Bit 1: BLANK_N
    signal DR : std_logic_vector(31 downto 0);

    -- FIFO de pixels
    type fifo_array is array (0 to 15) of std_logic_vector(31 downto 0);
    signal fifo      : fifo_array;
    signal write_ptr : integer range 0 to 15 := 0;
    signal read_ptr  : integer range 0 to 15 := 0;
    signal fifo_empty: std_logic;
    signal fifo_full : std_logic;

    -- Contadores de sincronismo
    signal h_count, v_count : natural := 0;
    signal hsync_sig, vsync_sig : std_logic := '1';

    -- Zona visível
    signal pixel_active, line_active : std_logic := '0';

begin

    -- Mapeamento de CR (endereço 1) e DR (endereço 0)
    process(rst, clk, wren, addr)
    begin
		  if(rst = '1')then
				DR <= (others => '0');
				CR <= (others => '0');
				write_ptr <= 0;
        elsif rising_edge(clk) then
            if wren = '1' then
                case addr is
                    when "000000" =>
                        DR <= data_in;
                        if fifo_full = '0' then
                            fifo(write_ptr) <= data_in;
                            write_ptr <= (write_ptr + 1) mod 16;
                        end if;
                    when "000001" =>
                        CR <= data_in;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    -- FIFO status
    fifo_empty <= '1' when write_ptr = read_ptr else '0';
    fifo_full  <= '1' when (write_ptr + 1) mod 16 = read_ptr else '0';

    -- ready information to DMA
    ready <= '0' when fifo_full else '1';        

    -- Geração de contadores de linha e coluna
	 -- por conveniência, começa a contar h_count=0, v_count=0 quando começa a porção visível
    process(rst, PCLK)
    begin
		  if(rst = '1')then
				h_count <= 0;
				v_count <= 0;
        elsif rising_edge(PCLK) then
            if h_count = VGA.h_total - 1 then
                h_count <= 0;
                if v_count = VGA.v_total - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    -- Geração de hsync e vsync
	 --h_count is 0 during the begining of HSYNC pulse
    hsync_sig <= '0' when
        h_count <  VGA.h_sync
        else '1';
			
	--v_count is 0 during the begining of VSYNC pulse
    vsync_sig <= '0' when
        v_count < VGA.v_sync
        else '1';

    hsync <= hsync_sig;
    vsync <= vsync_sig;

    -- Zona visível
	-- Sera lido no proximo ciclo de PCLK para inferir RAM para a fifo, por isso subtrai 1
    pixel_active <= '1' when h_count >= (VGA.h_sync + VGA.h_back_porch - 1) and h_count < (VGA.h_sync + VGA.h_back_porch + VGA.h_visible - 1) else '0';
    line_active  <= '1' when v_count >= (VGA.v_sync + VGA.v_back_porch - 1) and v_count < (VGA.v_sync + VGA.v_back_porch + VGA.v_visible - 1) else '0';

    -- Saída para DAC durante zona visível
	-- Leitura da fifo
    process(rst, PCLK)
    begin
		if (rst ='1') then
			read_ptr <= 0;
        elsif rising_edge(PCLK) then	
			if hsync_sig = '1' and vsync_sig = '1' and fifo_empty = '0' and
               pixel_active = '1' and line_active = '1' then
            	read_ptr <= (read_ptr + 1) mod 16;
			end if;
        end if;
    end process;
			
	process(PCLK, hsync_sig, vsync_sig, fifo_empty, pixel_active, line_active)
    begin
		if rising_edge(PCLK) then
            if hsync_sig = '1' and vsync_sig = '1' and fifo_empty = '0' and
               pixel_active = '1' and line_active = '1' then
                R <= fifo(read_ptr)(23 downto 16);
                G <= fifo(read_ptr)(15 downto 8);
                B <= fifo(read_ptr)(7 downto 0);
            else
                R <= (others => '0');
                G <= (others => '0');
                B <= (others => '0');
            end if;
		end if;
    end process;
				
    -- Saídas de controle (mapeadas nos bits de CR)
    SYNC_N  <= CR(0);
    BLANK_N <= CR(1);

end architecture;
