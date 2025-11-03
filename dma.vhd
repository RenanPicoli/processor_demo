library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity dma_controller is
	 generic (FIFO_LEN: natural := 32);
    port (
        reset     : in  std_logic;

        -- Barramento de CPU para configuração
        clk       : in  std_logic; -- cpu clock
        addr      : in  std_logic_vector(1 downto 0);  -- Seleção de registrador (2 bits para 4 registradores)
        D         : in  std_logic_vector(31 downto 0); -- Dados de entrada (escrita)
        Q         : out std_logic_vector(31 downto 0); -- Dados de saída (leitura)
        wr_en     : in  std_logic; -- Sinal de escrita nos registradores

        -- Interface única de memória
        mem_clk   : in  std_logic;--memory clock (e.g. SDRAM)
        mem_addr  : out std_logic_vector(31 downto 0);
        mem_data_in: in std_logic_vector(31 downto 0);
        mem_data_out: out std_logic_vector(31 downto 0);
		mem_ready : in std_logic;
        mem_rden  : out std_logic;
        mem_wren  : out std_logic;

        -- Sinal de interrupção ao final da transferência
        irq       : out std_logic;
        iack      : in std_logic
    );
end entity;

architecture behavior of dma_controller is
    -- Registradores internos
    signal src_addr  : std_logic_vector(31 downto 0);
    signal dst_addr  : std_logic_vector(31 downto 0);
    signal num_xfers    : std_logic_vector(31 downto 0);
    signal count     : std_logic_vector(31 downto 0) := (others => '0');
    
    -- CR agora tem 32 bits com SINC e DINC
    signal CR        : std_logic_vector(31 downto 0) := (others => '0');

    -- FIFO para armazenar dados temporariamente
    type fifo_type is array (0 to FIFO_LEN-1) of std_logic_vector(31 downto 0);
    signal fifo      : fifo_type := (others => (others => '0'));
    signal fifo_head : integer range 0 to FIFO_LEN-1 := 0;
    signal fifo_tail : integer range 0 to FIFO_LEN-1 := 0;
    signal fifo_count: integer range 0 to FIFO_LEN := 0; -- Capacidade da FIFO = FIFO_LEN palavras

    signal state     : std_logic_vector(1 downto 0) := "00"; -- 00 = Idle, 01 = Reading, 10 = Writing
begin

    -- Lógica de leitura/escrita nos registradores via CPU
    process (clk, reset, count, num_xfers, fifo_count, iack)
    begin
        if reset = '1' then
            src_addr  <= (others => '0');
            dst_addr  <= (others => '0');
            num_xfers    <= (others => '0');
            CR        <= (others => '0');

        elsif rising_edge(clk) then
            if wr_en = '1' then
                case addr is
                    when "00" => src_addr <= D;
                    when "01" => dst_addr <= D;
                    when "10" => num_xfers   <= D;
                    when "11" => CR       <= D;
                    when others => null;
                end case;
            end if;		
				
				if iack='0' then
					CR(1) <= '0'; -- finished = 0
					CR(0) <= '0'; -- started = 0				
				-- Ao transferir o ultimo item, finaliza
				elsif count = num_xfers and fifo_count = 1 then
					CR(1) <= '1'; -- finished = 1
					CR(0) <= '0'; -- started = 0
				end if;

        end if;
    end process;

	 process(addr,src_addr,dst_addr, num_xfers,CR)
	 begin
		case addr is
			 when "00" => Q <= src_addr;
			 when "01" => Q <= dst_addr;
			 when "10" => Q <= num_xfers;
			 when "11" => Q <= CR;
			 when others => Q <= (others => '0');
		end case;
	end process;

    -- Máquina de estados para leitura e escrita usando FIFO
    process (mem_clk, reset, iack, mem_ready)
    begin
        if reset = '1' then
            count     <= (others => '0');
            fifo_head <= 0;
            fifo_tail <= 0;
            fifo_count <= 0;
            state     <= "00";-- IDLE
            irq       <= '0';
			elsif(iack='1')then
            irq       <= '0';
        elsif rising_edge(mem_clk) then
            case state is
                when "00" =>  -- IDLE
                    if CR(0) = '1' and CR(1) = '0' then
                        state <= "01"; -- Inicia leitura
                    end if;

                when "01" =>  -- READING
                    if fifo_count < FIFO_LEN and count < num_xfers and mem_ready='1' then
                        -- Inicia leitura

                        -- Armazena na FIFO após leitura
                        fifo(fifo_head) <= mem_data_in;
                        fifo_head <= (fifo_head + 1) mod FIFO_LEN;
                        fifo_count <= fifo_count + 1;                        

                        -- Incrementa `count`
                        count <= count + 1;

                        -- Se FIFO cheia, troca para escrita
                        if fifo_count + 1 = FIFO_LEN then
                            state <= "10";
                        end if;

                    elsif count = num_xfers then
                        -- Se terminou a leitura, começa a escrita
                        state <= "10";
                    end if;

                when "10" =>  -- WRITING
                    if fifo_count > 0 then
                        -- Escreve na memória
                        mem_data_out <= fifo(fifo_tail);
								
								--update pointers/counters
								if(mem_ready = '1')then
                        -- Atualiza FIFO
									fifo_tail <= (fifo_tail + 1) mod FIFO_LEN;
									fifo_count <= fifo_count - 1;
								end if;
                    end if;

							-- Se FIFO vazia, volta a ler
							if fifo_count = 0 and count < num_xfers then
								 state <= "01";
							end if;

                    -- Ao transferir o ultimo item, finaliza
                    if count = num_xfers and fifo_count = 1 then
                        irq   <= '1';
                        state <= "00";
                    end if;

                when others =>
                    state <= "00";
            end case;
        end if;
    end process;
	 
	 addr_proc: process (state, CR, count, fifo_count, src_addr, dst_addr)
	 begin
		case state is
			when "01" =>  -- READING
				 -- Incrementa `src_addr` se SINC estiver ativado
				if CR(2) = '1' then
					mem_addr <= src_addr+count;
				else
					mem_addr <= src_addr;
				end if;
				mem_rden <= '1';
				mem_wren  <= '0';
			when "10" =>  -- WRITING
				-- Incrementa `dst_addr` se DINC estiver ativado
				if CR(3) = '1' then
					 mem_addr <= dst_addr + count - fifo_count;
				else
					mem_addr <= dst_addr;
				end if;
				mem_wren <= '1';
				mem_rden <= '0';
			when others =>
				mem_addr <= (others=>'0');
				mem_rden <= '0';
				mem_wren  <= '0';
		end case;		
	end process addr_proc;

end architecture;
