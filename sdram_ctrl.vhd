library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity sdram_controller is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;

        -- Barramento de acesso por CPU/DMA (access request)
        addr      : in  std_logic_vector(31 downto 0);  -- Seleção de registrador (2 bits para 4 registradores)
        D         : in  std_logic_vector(31 downto 0); -- Dados de entrada (escrita)
        Q         : out std_logic_vector(31 downto 0); -- Dados de saída (leitura)
        wr_en     : in  std_logic; -- Sinal de escrita nos registradores
        -- Sinal de interrupção ao final da transferência (de/para CPU)
        irq       : out std_logic;
        iack      : in std_logic;

        -- Interface com a SDRAM
        A  : out std_logic_vector(12 downto 0);
        BA  : out std_logic_vector(1 downto 0);
        DQM  : out std_logic_vector(3 downto 0);
        DQ  : inout std_logic_vector(31 downto 0);
        CKE  : out std_logic;
        CLK_OUT  : out std_logic;
        WE_N  : out std_logic;
        CAS_N  : out std_logic;
        RAS_N  : out std_logic;
        CS_N  : out std_logic
    );
end entity;

architecture behavior of sdram_controller is
	type init_state_t is (PWRUP,PRE,AR0,NOP0,AR1,NOP1,AR2,NOP2,AR3,NOP3,AR4,NOP4,AR5,NOP5,AR6,NOP6,AR7,NOP7,LOAD,NOPF,INITIALIZED);
	signal init_state, nxt_init_state: init_state_t;
	signal PWRUP_counter: natural;--conta ciclos de PWRUP (200us)
	signal ref_counter: natural;--conta ciclos em NOP entre dois REFRESHs
	signal tRP_counter: natural;--conta ciclos em NOP entre PRE e ACT
begin
	DQM <= "0000";--all bytes are enabled
	
	--intialization FSM
	process(clk, rst, PWRUP_counter, tRP_counter, ref_counter)
	begin
		if(rst='1')then
				nxt_init_state <= PWRUP;
		elsif(rising_edge(clk))then
			 case init_state is
				when PWRUP => if (PWRUP_counter = 20_000)then nxt_init_state <= PRE; end if;
				when PRE => if (tRP_counter = 2)then nxt_init_state <= AR0; end if;
				when AR0 => nxt_init_state <= NOP0;
				when NOP0 => if (ref_counter = 7)then nxt_init_state <= AR1; end if;
				when AR1 => nxt_init_state <= NOP1;
				when NOP1 => if (ref_counter = 7)then nxt_init_state <= AR2; end if;
				when AR2 => nxt_init_state <= NOP2;
				when NOP2 =>if (ref_counter = 7)then nxt_init_state <= AR3; end if;
				when AR3 => nxt_init_state <= NOP3;
				when NOP3 => if (ref_counter = 7)then nxt_init_state <= AR4; end if;
				when AR4 => nxt_init_state <= NOP4;
				when NOP4 => if (ref_counter = 7)then nxt_init_state <= AR5; end if;
				when AR5 => nxt_init_state <= NOP5;
				when NOP5 => if (ref_counter = 7)then nxt_init_state <= AR6; end if;
				when AR6 => nxt_init_state <= NOP6;
				when NOP6 => if (ref_counter = 7)then nxt_init_state <= AR7; end if;
				when AR7 => nxt_init_state <= NOP7;
				when NOP7 => if (ref_counter = 7)then nxt_init_state <= LOAD; end if;
				when LOAD => nxt_init_state <= NOPF;
				when NOPF => nxt_init_state <= INITIALIZED;
				when INITIALIZED => nxt_init_state <= INITIALIZED;
			 end case;
		end if;
	end process;
	
	process(clk, rst, nxt_init_state)
	begin
		if(rst='1')then
			init_state <= PWRUP;
		elsif(rising_edge(clk))then
			init_state <= nxt_init_state;
		end if;
	end process;
	
	process(clk,rst,init_state)
	begin
		if(rst='1')then
				PWRUP_counter <=0;
				tRP_counter <= 0;
				ref_counter <= 0;
		elsif(rising_edge(clk))then
			if(init_state = PWRUP)then
				PWRUP_counter <= PWRUP_counter+1;
			else
				PWRUP_counter <=0;
			end if;			
			
			case init_state is
				when NOP0|NOP1|NOP2|NOP3|NOP4|NOP5|NOP6|NOP7 =>
					ref_counter <= ref_counter+1;
				when AR0|AR1|AR2|AR3|AR4|AR5|AR6|AR7 =>
					ref_counter <=0;
				when others =>
					ref_counter <=0;
			end case;			
			
			if(init_state=PRE)then
				tRP_counter <= tRP_counter+1;
			elsif(init_state=AR0)then
				tRP_counter <=0;
			end if;
		end if;
	end process;
	
	process(clk,rst,init_state)
	begin
		case init_state is
			when PWRUP|NOP0|NOP1|NOP2|NOP3|NOP4|NOP5|NOP6|NOP7|NOPF => --NOP
				CAS_N	<= '1';
				RAS_N	<= '1';
				WE_N	<= '1';
			when others => --NOP
				CAS_N	<= '1';
				RAS_N	<= '1';
				WE_N	<= '1';				
		end case;
		CS_N	<= '0';
		CKE	<= '1';--activate clk
	end process;
	
end architecture;