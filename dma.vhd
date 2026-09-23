library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity dma_controller is
	 generic (FIFO_LEN: natural := 640; USE_RAM_BLOCKS: boolean := true);
    port (
		reset     : in  std_logic;--reset synchronized to ram clk (cpu clock)
		reset_mem : in  std_logic;--reset synchronized to mem_clk (e.g. SDRAM clock)

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
		-- mem_ready and mem_valid are used to handle memory latency
		-- they are similar to the ready/valid handshake protocol in ARM's AMBA AXI, but mem_valid is produced by the memory controller and not by the DMA controller
		-- they are also similar to Altera's Avalon Memory-Mapped interface, but mem_ready is the opposite of Avalon waitrequest (Avalon waitrequest is '1' when the slave is not ready, while mem_ready is '1' when the slave is ready)
		mem_ready : in std_logic;
		mem_valid : in std_logic;--indicates mem_data_in is valid in this clock cycle (still valid after CAS latency clocks after mem_ready is deasserted)
		mem_rden  : out std_logic;
		mem_wren  : out std_logic;

		-- Sinal de interrupção ao final da transferência
		irq       : out std_logic;
		iack      : in std_logic
    );
end entity;

architecture behavior of dma_controller is
	component dc_fifo
		generic (
			N: natural;
			REQUESTED_FIFO_DEPTH: natural;
			USE_RAM_BLOCKS: boolean := false;
			LEGACY_READ_POINTER: boolean := true;
			SAME_CLOCK: boolean := false
		);
		port (
			DATA_IN: in std_logic_vector(N-1 downto 0);
			WCLK: in std_logic;
			RCLK: in std_logic;
			RST: in std_logic;
			WREN: in std_logic;
			POP: in std_logic;
			FULL: buffer std_logic;
			EMPTY: buffer std_logic;
			OVF: out std_logic;
			DATA_OUT: out std_logic_vector(N-1 downto 0)
		);
	end component;

    -- Registradores internos
    signal src_addr  : std_logic_vector(31 downto 0);
    signal dst_addr  : std_logic_vector(31 downto 0);
    signal num_xfers    : std_logic_vector(31 downto 0);
	-- count identifica a próxima requisição de leitura a ser emitida.
    signal count     : std_logic_vector(31 downto 0) := (others => '0');
	-- received_count conta respostas válidas, que podem chegar depois de mem_ready.
	signal received_count: std_logic_vector(31 downto 0) := (others => '0');
    
    -- CR agora tem 32 bits com SINC e DINC
    signal CR        : std_logic_vector(31 downto 0) := (others => '0');

    -- FIFO para armazenar dados temporariamente
    type fifo_type is array (0 to FIFO_LEN-1) of std_logic_vector(31 downto 0);
    signal fifo      : fifo_type := (others => (others => '0'));
    signal fifo_head : integer range 0 to FIFO_LEN-1 := 0;-- ! posição na fifo para armazenar o dado sendo pedido
	-- Índice associado à resposta mem_valid atualmente apresentada pela memória.
	signal fifo_head_pending: integer range 0 to FIFO_LEN-1 := 0;--posição na fifo para armazenar o dado chegando
	-- Cada entrada guarda a contagem e o índice da FIFO de dados da requisição aceita.
	signal pending_transfers_data: std_logic_vector(47 downto 0);
	signal pending_transfers_full: std_logic;
	signal pending_transfers_empty: std_logic; -- indica que ainda há respostas para chegar
	signal pending_transfers_ovf: std_logic;
	signal pending_transfers_wren: std_logic;
	signal pending_transfers_pop: std_logic;
	-- Número de requisições aceitas que ainda não produziram mem_valid.
	signal pending_count: integer range 0 to FIFO_LEN := 0;
    signal fifo_tail : integer range 0 to FIFO_LEN-1 := 0;
    signal fifo_count: integer range 0 to FIFO_LEN := 0; -- Capacidade da FIFO = FIFO_LEN palavras
    signal fifo_count_reg: integer range 0 to FIFO_LEN := 0;
	--! for writes if data fifo is implemented with RAM blocks, mem_addr must be delayed to match the data output from the RAM block
	signal mem_addr_comb: std_logic_vector(31 downto 0);
	signal mem_addr_reg: std_logic_vector(31 downto 0);--for writes if data fifo is implemented with RAM blocks, mem_addr must be delayed to match the data output from the RAM block
	signal mem_wren_comb: std_logic;--! for writes if data fifo is implemented with RAM blocks, mem_wren must be delayed to match the data output from the RAM block
	signal mem_wren_reg: std_logic;--for writes if data fifo is implemented with RAM blocks, mem_wren must be delayed to match the data output from the RAM block

    signal state     : std_logic_vector(1 downto 0) := "00"; -- 00 = Idle, 01 = Reading, 10 = Writing
	 
	--  signal mem_valid : std_logic;--indicates mem_data_in is valid (still valid after CAS latency clocks after mem_ready is deasserted)
	 
	 attribute preserve : boolean;
	 attribute preserve of src_addr : signal is true;
	 attribute preserve of dst_addr : signal is true;
	 attribute preserve of num_xfers : signal is true;
	 attribute preserve of count : signal is true;
	 attribute preserve of received_count : signal is true;
	 attribute preserve of CR : signal is true;
	 attribute preserve of fifO : signal is true;
	 attribute preserve of fifo_head : signal is true;
	 attribute preserve of fifo_head_pending : signal is true;
	 attribute preserve of fifo_tail : signal is true;
	 attribute preserve of fifo_count : signal is true;
	 attribute preserve of fifo_count_reg : signal is true;
	attribute preserve of pending_count : signal is true;
	 attribute preserve of state : signal is true;
	--  attribute preserve of mem_valid : signal is true;
begin

	-- Só registra uma requisição se houver espaço para sua futura resposta.
	pending_transfers_wren <= '1' when state = "01" and mem_ready = '1' and fifo_count + pending_count < FIFO_LEN and count < num_xfers and pending_transfers_full = '0' else '0';
	-- Cada mem_valid consome o endereço correspondente na mesma ordem FIFO.
	pending_transfers_pop <= '1' when state = "01" and mem_valid = '1' and pending_transfers_empty = '0' else '0';
	fifo_head_pending <= conv_integer(unsigned(pending_transfers_data(15 downto 0)));

	-- A FIFO de pendências transforma a latência da memória em uma associação explícita
	-- entre cada resposta e o índice onde o dado deve ser escrito.
	pending_transfers_fifo: dc_fifo
		generic map (
			N => 48,
			REQUESTED_FIFO_DEPTH => 8,
			USE_RAM_BLOCKS => false,
			-- O primeiro item precisa estar disponível antes do primeiro POP.
			LEGACY_READ_POINTER => false,
			-- WCLK e RCLK são mem_clk; não há necessidade de sincronizadores CDC.
			SAME_CLOCK => true
		)
		port map (
			DATA_IN => count & conv_std_logic_vector(fifo_head, 16),
			WCLK => mem_clk,
			RCLK => mem_clk,
			RST => reset_mem,
			WREN => pending_transfers_wren,
			POP => pending_transfers_pop,
			FULL => pending_transfers_full,
			EMPTY => pending_transfers_empty,
			OVF => pending_transfers_ovf,
			DATA_OUT => pending_transfers_data
		);

    -- Lógica de leitura/escrita nos registradores via CPU
	 -- CR(0): START
	 -- CR(1): IRQ (finished)
	 -- CR(2): SINC
	 -- CR(3): DINC
	 -- CR(6:4): UNUSED. Previously, was SRC_LAT (source memory latency in mem_clk cycles)
	 -- CR(7): AUTOSTART (after the manual start, repeats the transfer forever
    process (clk, reset, count, num_xfers, fifo_count, iack, irq)
    begin
        if reset = '1' then
            src_addr  <= (others => '0');
            dst_addr  <= (others => '0');
            num_xfers <= (others => '0');
            CR(31 downto 2) <= (others => '0');
        elsif rising_edge(clk) then
            if wr_en = '1' then
                case addr is
                    when "00" => src_addr <= D;
                    when "01" => dst_addr <= D;
                    when "10" => num_xfers<= D;
                    when "11" => CR(31 downto 2) <= D(31 downto 2);-- CR(0) <= D(0);
                    when others => null;
                end case;
            end if;

        end if;
    end process;
	 
	 CR(1) <= irq;--finsihed = '1' when irq='1'
	
    CR0_PROC : process(reset, clk, D, addr, wr_en, CR, state)
    begin
        if reset='1' then
            CR(0) <= '0';
        elsif rising_edge(clk) then
				if state="00" and  wr_en='1' and addr="11" then
					CR(0) <= D(0);
				else
					CR(0) <= '0';
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
    process (mem_clk, reset_mem, iack, mem_ready, mem_valid)
    begin
        if reset_mem = '1' then
            count     <= (others => '0');
            fifo_head <= 0;
            fifo_tail <= 0;
            fifo_count <= 0;
            fifo_count_reg <= 0;
			pending_count <= 0;
			received_count <= (others => '0');
            state     <= "00";-- IDLE
            irq       <= '0';
        elsif rising_edge(mem_clk) then
				
            case state is
                when "00" =>  -- IDLE
                    if CR(0) = '1' then
                        state <= "01"; -- Inicia leitura
                    end if;

                when "01" =>  -- READING
					-- chega uma resposta (mem_valid='1') que estava sendo aguardada (pending_transfers_empty='0')
					-- Armazena o dado somente quando a memória confirma que ele é válido;
					-- o índice vem da FIFO de requisições, não do fifo_head atual.
					if mem_valid = '1' and pending_transfers_empty = '0' then
						fifo(fifo_head_pending) <= mem_data_in;
						received_count <= received_count + 1;
						fifo_count <= fifo_count + 1;
						fifo_count_reg <= fifo_count;
						if (num_xfers /= 0 and received_count + 1 = num_xfers) or (fifo_count + 1 = FIFO_LEN) then
							state <= "11";
						end if;
					end if;

					-- envia nova requisição, para isso, atualiza os contadores abaixo, mas somente se:
					-- o escravo estiver pronto para aceitar nova requisição (mem_ready='1') e
					-- houver espaço na FIFO de dados (para essa requisição e as pendentes) e
					-- não tiver finalizado a etapa de leitura e
					-- houver espaço na FIFO de pendências.
					if mem_ready = '1' and fifo_count + pending_count < FIFO_LEN and count < num_xfers and pending_transfers_full = '0' then
						count <= count + 1;
						fifo_head <= (fifo_head + 1) mod FIFO_LEN;
					end if;

					-- Mantém separado o número de respostas já armazenadas do número de
					-- requisições ainda pendentes, inclusive quando ambos os eventos coincidem.
					if pending_transfers_wren = '1' and mem_valid = '0' then
						pending_count <= pending_count + 1;
					elsif pending_transfers_wren = '0' and mem_valid = '1' and pending_transfers_empty = '0' then
						pending_count <= pending_count - 1;
					end if;
				when "11" => -- WAITING (not used in this implementation, but could be used to wait for some condition before writing)
					--since now we are using synchronous writing, data read from fifo is valid only in the next cycle
					state <= "10";-- start writing immediately in the next cycle
                when "10" =>  -- WRITING
                    if fifo_count > 0 then
								
								--update pointers/counters
								if(mem_ready = '1')then
                        -- Atualiza FIFO
									fifo_tail <= (fifo_tail + 1) mod FIFO_LEN;
									fifo_count <= fifo_count - 1;
									fifo_count_reg <= fifo_count;
								end if;
                    end if;

					-- Se FIFO vazia, volta a ler
					if fifo_count = 1 and count < num_xfers and mem_ready='1' then--escrita do último item da fifo
						state <= "01";
					end if;

                    -- Ao transferir o ultimo item, finaliza OU inicia de novo se AUTOSTART estiver ativo
                    if count = num_xfers and fifo_count = 1 and mem_ready='1' then
                        irq   <= '1';
						if  CR(7)='1' then
							state <= "01";-- goes back to reading
						else
							state <= "00";-- idle
						end if;
						-- get ready for new transfers
						count     <= (others => '0');
						pending_count <= 0;
						received_count <= (others => '0');
						fifo_head <= 0;
						fifo_tail <= 0;
						fifo_count <= 0;
                    end if;

                when others =>
                    state <= "00";
            end case;
			if(iack='1')then
				irq <= '0';
            end if;
        end if;
    end process;
	 
	sync_read: if USE_RAM_BLOCKS generate
		-- A FIFO de dados usa blocos de RAM; a saída registrada gera um ciclo extra
		-- entre fifo_tail e mem_data_out durante a escrita.
		process (mem_clk, fifo_tail, mem_addr_comb, mem_wren_comb)
		begin
			if rising_edge(mem_clk) then
				mem_data_out <= fifo(fifo_tail);--mem_data_out is 1 clock cycle delayed of fifo_tail
				mem_addr_reg <= mem_addr_comb;
				mem_wren_reg <= mem_wren_comb;
			end if;
		end process;
	end generate;

	async_read: if not USE_RAM_BLOCKS generate
		-- A FIFO de dados usa registradores; a saída combinacional evita um ciclo
		-- extra entre fifo_tail e mem_data_out durante a escrita.
		mem_data_out <= fifo(fifo_tail);
	end generate;

	 
	 -- A sensibilidade inclui as contagens porque elas determinam quando uma nova
	 -- requisição pode ser apresentada e qual endereço de escrita está ativo.
	 addr_proc: process (state, CR, count, num_xfers, fifo_count, pending_count, src_addr, dst_addr, pending_transfers_full)
	 begin
		case state is
			when "01" =>  -- READING
				 -- Incrementa `src_addr` se SINC estiver ativado
				if CR(2) = '1' then
					mem_addr <= src_addr+count;
				else
					mem_addr <= src_addr;
				end if;
				if count < num_xfers and fifo_count + pending_count < FIFO_LEN and pending_transfers_full = '0' then
					mem_rden <= '1';
				else
					mem_rden <= '0';
				end if;
				mem_wren  <= '0';
			when "11" => -- preparing to write
				mem_addr <= dst_addr;
				mem_rden <= '0';
				mem_wren  <= '0';
			when "10" =>  -- WRITING
				-- Incrementa `dst_addr` se DINC estiver ativado
				if CR(3) = '1' and USE_RAM_BLOCKS then
						 mem_addr_comb <= dst_addr + count - fifo_count;-- count minus remaining words gives the write offset
						mem_addr <= mem_addr_reg;
				elsif CR(3) = '1' and not USE_RAM_BLOCKS then
						 mem_addr <= dst_addr + count - fifo_count;-- count minus remaining words gives the write offset
				else
					mem_addr <= dst_addr;
				end if;

				if USE_RAM_BLOCKS then
					mem_wren_comb <= '1';
				mem_wren <= mem_wren_reg;
				else
					mem_wren <= '1';
				end if;
				mem_rden <= '0';
			when others =>
				mem_addr <= (others=>'0');
				mem_rden <= '0';
				mem_wren  <= '0';
		end case;		
	end process addr_proc;

end architecture;
