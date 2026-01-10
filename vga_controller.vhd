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
		  rden		 : in std_logic;
		  Q			 : out std_logic_vector(31 downto 0);--for reading the CR (status)

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

    -- Configuracao VGA 640x480 @ 60Hz
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

    -- Configuracao VGA 800x600 @ 60Hz
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
    signal CR : std_logic_vector(31 downto 0) := (others => '0'); -- Bit 0: SYNC_N, Bit 1: BLANK_N, bit 2: fifo_empty, bit 3: fifo_full
    signal DR : std_logic_vector(31 downto 0);

    -- FIFO de pixels
	 -- since sdram clk/PCLK is ~3.97, this fifo MUST be at least 4x times the size of DMA fifo
	 constant FIFO_LEN: integer := VGA.h_visible;--stores one line
    type fifo_array is array (0 to FIFO_LEN-1) of std_logic_vector(31 downto 0);
    signal fifo      : fifo_array;
    signal write_ptr : integer range 0 to FIFO_LEN-1 := 0;
    signal prev_write_ptr : integer range 0 to FIFO_LEN-1 := 0;
    signal read_ptr  : integer range 0 to FIFO_LEN-1 := 0;
    signal prev_read_ptr : integer range 0 to FIFO_LEN-1 := 0;
    signal fifo_empty: std_logic;
    signal fifo_full : std_logic;

    -- Contadores de sincronismo
    signal h_count, v_count : natural := 0;
    signal hsync_sig, vsync_sig : std_logic := '1';
	 
	 -- Contador de frames
    signal f_count : natural := 0;--31 bits, enough for 9942 hours before flipping to zero again

    -- Zona visivel
    signal pixel_active, line_active : std_logic := '0';
	 signal fifo_rden: std_logic;
	 signal fifo_data_out: std_logic_vector(31 downto 0);
	 
	 --these signals are kept during synthesis for debug
	 attribute preserve_for_debug : boolean;
	 attribute preserve_for_debug of fifo_empty : signal is true;
	 attribute preserve_for_debug of fifo_full : signal is true;
	 attribute preserve_for_debug of f_count : signal is true;
begin

    -- Mapeamento de CR (endereço 1) e DR (endereço 0)
    process(rst, clk, wren, addr)
    begin
		  if(rst = '1')then
				DR <= (others => '0');
				CR(1 downto 0) <= (others => '0');
				write_ptr <= 0;
				prev_write_ptr <= 0;
        elsif rising_edge(clk) then
				prev_write_ptr <= write_ptr;
            if wren = '1' then
                case addr is
                    when "000000" =>
                        DR <= data_in;
                        if fifo_full = '0' then
                            fifo(write_ptr) <= data_in;
                            write_ptr <= (write_ptr + 1) mod  FIFO_LEN;--head pointer
                        end if;
                    when "000001" =>
                        CR(1 downto 0) <= data_in(1 downto 0);
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    -- FIFO status
	 -- write_ptr: head
	 -- read_ptr: tail
    -- fifo_empty <= '1' when write_ptr = read_ptr else '0';
    -- fifo_full  <= '1' when (write_ptr + 1) mod  FIFO_LEN = read_ptr else '0';
	 FIFO_FULL_PROC : process(clk, write_ptr, read_ptr, prev_write_ptr, fifo_rden)
     begin
		  if rst ='1' or (read_ptr = 0 and prev_read_ptr=VGA.h_visible-1) then--resets when last pixel is transmitted by VGA
				fifo_full <= '0';
        elsif falling_edge(clk) then -- falling edge because fifo_full (ready) is sampled on the rising_edge of mem_clk (by DMA)
            --if (write_ptr + 1) mod  FIFO_LEN = read_ptr then
			if write_ptr = 0 and prev_write_ptr = VGA.h_visible-1 then
                fifo_full  <= '1';
--            elsif read_ptr = VGA.h_visible-1 and fifo_rden='1' then
--                fifo_full  <= '0';
            end if;
        end if;
     end process;
	  
	 FIFO_EMPTY_PROC : process(PCLK, write_ptr, read_ptr, prev_read_ptr)
     begin
        if falling_edge(PCLK) then -- falling edge because fifo_full (ready) is sampled on the rising_edge of mem_clk (by DMA)
            --fifo_empty is used only internally, but it is ampled by slower clk PCLK
            if write_ptr = read_ptr and prev_read_ptr /= 0 then
                fifo_empty <= '1';
            else
                fifo_empty <= '0';
            end if;
        end if;
     end process;
	 CR(2) <= fifo_empty;
	 CR(3) <= fifo_full;
	 
	 -- CR/DR reading
	 --this is meant to prevent fifo_empty/fifo_full from being removed
	 Q <= CR when rden='1' and addr="000001" else
			DR when rden='1' and addr="000000" else
			std_logic_vector(to_unsigned(f_count,32)) when rden='1' and addr="000010" else
			(others => '0');

    -- ready information to DMA
    ready <= '0' when fifo_full='1' else '1';        

    -- Geracao de contadores de linha e coluna
	 -- por conveniencia, comeca a contar h_count=0, v_count=0 quando começa a porcao visivel
    process(rst, PCLK)
    begin
		  if(rst = '1')then
				h_count <= 0;
				v_count <= 0;
				f_count <= 0;--frame counter
        elsif rising_edge(PCLK) then
            if h_count = VGA.h_total - 1 then
                h_count <= 0;
                if v_count = VGA.v_total - 1 then
					     -- Starts new frame
                    v_count <= 0;
						  f_count <= f_count + 1;
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
    hsync_sig <= '0' when h_count <  VGA.h_sync
						else '1';
			
	--v_count is 0 during the begining of VSYNC pulse
    vsync_sig <= '0' when v_count < VGA.v_sync
						else '1';

    hsync <= hsync_sig;
    vsync <= vsync_sig;

    -- Zona visível
	-- Sera lido no proximo ciclo de PCLK para inferir RAM para a fifo, por isso subtrai 1
    pixel_active <= '1' when h_count >= (VGA.h_sync + VGA.h_back_porch - 1) and h_count < (VGA.h_sync + VGA.h_back_porch + VGA.h_visible - 1) else '0';
    -- line_active does not need subtract 1 because v_count does not change with every PCLK rising_edge
	 line_active  <= '1' when v_count >= (VGA.v_sync + VGA.v_back_porch) and v_count < (VGA.v_sync + VGA.v_back_porch + VGA.v_visible) else '0';

    -- Saida para DAC durante zona visivel
	-- Leitura da fifo
	fifo_rden <= '1' when hsync_sig = '1' and vsync_sig = '1' and fifo_empty = '0' and
               pixel_active = '1' and line_active = '1' else '0';
					
    process(rst, PCLK, fifo_rden)
    begin
		if (rst ='1') then
			read_ptr <= 0;
        elsif rising_edge(PCLK) then
            prev_read_ptr <= read_ptr;
			if fifo_rden = '1' then
            	read_ptr <= (read_ptr + 1) mod  FIFO_LEN;--tail pointer
			end if;
        end if;
    end process;
			
	process(PCLK, fifo_rden, read_ptr)
    begin
		if rising_edge(PCLK) then
            if fifo_rden='1' then
					fifo_data_out <= fifo(read_ptr);
            else
					fifo_data_out <= (others => '0');
            end if;
		end if;
    end process;	

	 R <= fifo_data_out(23 downto 16);
	 G <= fifo_data_out(15 downto 8);
	 B <= fifo_data_out(7 downto 0);
		
    -- Saidas de controle (mapeadas nos bits de CR)
    SYNC_N  <= CR(0);
    BLANK_N <= CR(1);

end architecture;
