library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity dma_controller is
	 generic (FIFO_LEN: natural := 640);
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
    signal count_del : std_logic_vector(31 downto 0) := (others => '0');--count delayed according source memory latency, incremented when data is latched
    type count_sr_type is array (0 to 3) of std_logic_vector(31 downto 0);
    signal count_sr: count_sr_type := (others => (others => '0'));
    
    -- CR agora tem 32 bits com SINC e DINC
    signal CR        : std_logic_vector(31 downto 0) := (others => '0');

    -- FIFO para armazenar dados temporariamente
    type fifo_type is array (0 to FIFO_LEN-1) of std_logic_vector(31 downto 0);
    signal fifo      : fifo_type := (others => (others => '0'));
    signal fifo_head : integer range 0 to FIFO_LEN-1 := 0;
    signal fifo_head_del: integer range 0 to FIFO_LEN-1 := 0;--fifo_head delayed according source memory latency
    type head_sr_type is array (0 to 3) of integer range 0 to FIFO_LEN-1;
    signal fifo_head_sr: head_sr_type := (others => 0);
    signal fifo_tail : integer range 0 to FIFO_LEN-1 := 0;
    signal fifo_count: integer range 0 to FIFO_LEN := 0; -- Capacidade da FIFO = FIFO_LEN palavras
    signal fifo_count_reg: integer range 0 to FIFO_LEN := 0;

    signal state     : std_logic_vector(1 downto 0) := "00"; -- 00 = Idle, 01 = Reading, 10 = Writing
	 
--	 signal	prev_mem_ready: std_logic;
	 type mem_ready_sr_type is array (0 to 3) of std_logic;
	 signal mem_ready_sr: mem_ready_sr_type := (others => '0');
	 signal mem_valid : std_logic;--indicates mem_data_in is valid (still valid after CAS latency clocks after mem_ready is deasserted)
	 
	 attribute preserve : boolean;
	 attribute preserve of src_addr : signal is true;
	 attribute preserve of dst_addr : signal is true;
	 attribute preserve of num_xfers : signal is true;
	 attribute preserve of count : signal is true;
	 attribute preserve of count_del : signal is true;
	 attribute preserve of count_sr : signal is true;
	 attribute preserve of CR : signal is true;
	 attribute preserve of fifO : signal is true;
	 attribute preserve of fifo_head : signal is true;
	 attribute preserve of fifo_head_del : signal is true;
	 attribute preserve of fifo_head_sr : signal is true;
	 attribute preserve of fifo_tail : signal is true;
	 attribute preserve of fifo_count : signal is true;
	 attribute preserve of fifo_count_reg : signal is true;
	 attribute preserve of state : signal is true;
	 attribute preserve of mem_ready_sr : signal is true;
	 attribute preserve of mem_valid : signal is true;
begin

    -- Lógica de leitura/escrita nos registradores via CPU
	 -- CR(0): START
	 -- CR(1): IRQ (finished)
	 -- CR(2): SINC
	 -- CR(3): DINC
	 -- CR(5:4): SRC_LAT (source memory latency in mem_clk cycles)
	 -- CR(6): AUTOSTART (after the manual start, repeats the transfer forever
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

    --selects fifo_head value according to source memory latency (only for reading)
	fifo_head_del <= fifo_head_sr(conv_integer(unsigned(CR(5 downto 4))));
	fifo_head_sr(0)<=fifo_head;--no latency added
	
    --selects count value according to source memory latency (only for reading)
	count_del <= count_sr(conv_integer(unsigned(CR(5 downto 4))));
	count_sr(0)<=count;--no latency added
	
	 --keeps track of which data is valid when reading
	 mem_valid  <= mem_ready_sr(conv_integer(unsigned(CR(5 downto 4))));
	 mem_ready_sr(0) <= mem_ready;--no latency added
    -- Máquina de estados para leitura e escrita usando FIFO
    process (mem_clk, reset, iack, mem_ready)
    begin
        if reset = '1' then
            count     <= (others => '0');
            fifo_head <= 0;
            fifo_head_sr(1 to 3)	<= (others => 0);
				count_sr(1 to 3)		<= (others => (others => '0'));
            fifo_tail <= 0;
            fifo_count <= 0;
            fifo_count_reg <= 0;
            state     <= "00";-- IDLE
            irq       <= '0';
				mem_ready_sr(1 to 3)	<= (others => '0');
        elsif rising_edge(mem_clk) then
			  if mem_rden = '0' then
					mem_ready_sr(1 to 3)	<= (others => '0');
				else
					mem_ready_sr(1 to 3)	<= mem_ready_sr(0 to 2);
				end if;
				
				if mem_valid  = '1' or mem_ready='1' then
					fifo_head_sr(1 to 3)	<= fifo_head_sr(0 to 2);
					count_sr(1 to 3)		<= count_sr(0 to 2);
				end if;
				
            case state is
                when "00" =>  -- IDLE
                    if CR(0) = '1' then
                        state <= "01"; -- Inicia leitura
                    end if;

                when "01" =>  -- READING
                    if fifo_count < FIFO_LEN and count < num_xfers then
                        -- Inicia leitura
								if mem_valid ='1' then
									-- Armazena na FIFO após leitura
									fifo(fifo_head_del) <= mem_data_in;--fifo_head delayed according source memory latency
								end if;                    

								if mem_ready='1' then--we need to check if ready is still asserted (ready for receiving new commands)
									-- Incrementa count (contador de endereços lidos)
									count <= count + 1;
									fifo_head <= (fifo_head + 1) mod FIFO_LEN;
									fifo_count <= fifo_count + 1;
									fifo_count_reg <= fifo_count;
								end if;

                        -- -- Se FIFO cheia, troca para escrita
                        -- if fifo_head_del + 1 = FIFO_LEN then--uses delayed signal to start writing only after last data is latched 
                        --     state <= "11";
                        -- end if;
								
                    elsif count_del = num_xfers then--uses delayed signal to start writing only after last data is latched
                        -- Se terminou a leitura, começa a escrita
                        state <= "11";
						  
						  elsif fifo_head_del < FIFO_LEN then--this is meant to latch the last words
								if mem_valid  = '1' then
									-- Armazena na FIFO após leitura
									fifo(fifo_head_del) <= mem_data_in;--fifo_head delayed according source memory latency
								
									-- Se escreve o ultimo elemento, troca para escrita
									if fifo_head_del + 1 = FIFO_LEN then--uses delayed signal to start writing only after last data is latched 
										 state <= "11";
									end if;
								end if;
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
								if  CR(6)='1' then
									state <= "01";-- goes back to reading
								else
									state <= "00";-- idle
								end if;
								-- get ready for new transfers
								count     <= (others => '0');
								fifo_head <= 0;
								fifo_head_sr(1 to 3)<= (others => 0);
								fifo_tail <= 0;
								fifo_count <= 0;
                    end if;

                when others =>
                    state <= "00";
            end case;
			if(iack='1')then
                irq       <= '0';
            end if;
        end if;
    end process;
	 
	-- Escreve na memória
	-- devido a leitura assincrona, fifo sera feita com registradores
	-- mem_data_out <= fifo(fifo_tail);

	-- Escreve na memória de forma síncrona
	-- data read from fifo is valid only in the next cycle
	SYNC_READ: process(mem_clk,fifo_tail)
	begin
		if rising_edge(mem_clk) then
			mem_data_out <= fifo(fifo_tail);
		end if;
	end process SYNC_READ;

	 
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
			when "11" => -- preparing to write
				mem_addr <= dst_addr;
				mem_rden <= '0';
				mem_wren  <= '0';
			when "10" =>  -- WRITING
				-- Incrementa `dst_addr` se DINC estiver ativado
				if CR(3) = '1' then
					 mem_addr <= dst_addr + count - fifo_count_reg;-- uses fifo_count_reg to get the correct address since fifo is read synchronously
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
