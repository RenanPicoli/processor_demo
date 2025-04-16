library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity sdram_controller is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;

        -- Barramento de acesso por CPU/DMA (access request)
        addr      : in  std_logic_vector(31 downto 0);  -- address requested
        D         : in  std_logic_vector(31 downto 0); -- input data (write)
        Q         : out std_logic_vector(31 downto 0); -- output data (read)
        wren		: in  std_logic; --write request to memory
        rden		: in  std_logic; --reading request to memory
        -- signal to indicate to CPU/DMA the data on Q is invalid
        ready		: out std_logic;

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
	
	--operation states
	type op_state_t is (
        IDLE, START_READ, READING,
        BURST_STOP, PRECHARGE,
        ACTIVATE
    );
	signal op_state, nxt_op_state: op_state_t;
	signal read_count      : integer range 0 to 2 := 0;
	signal precharge_count : integer range 0 to 2 := 0;
	signal act_count       : integer range 0 to 2 := 0;
	
	signal ADDR_VALID	: std_logic := '0';
	signal offset: std_logic_vector(31 downto 10);--current offset (aka page address, selects a row and a bank)
	signal previous_offset: std_logic_vector(31 downto 10);--offset during previous accesses
begin
	DQM <= "0000";--all bytes are enabled
	
	----------------intialization FSM--------------------------
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
	
	------------operation FSM---------
	process(rst, clk, op_state, init_state, RDEN, ADDR_VALID, read_count, precharge_count, act_count)
		 begin
			if(rst='1')then
					nxt_op_state <= IDLE;
			elsif(rising_edge(clk))then

				case op_state is

					when IDLE =>
						 read_count <= 0;
						 act_count <= 0;
						 precharge_count <= 0;
						 if(init_state = INITIALIZED)then
							 if RDEN = '1' and ADDR_VALID='1' then
								  nxt_op_state <= START_READ;
							 elsif RDEN = '1' and ADDR_VALID='0' then
								  nxt_op_state <= PRECHARGE;
							 end if;
						 end if;

					when START_READ =>
						 if read_count < 2 then
							  read_count <= read_count + 1;
						 else
							  nxt_op_state <= READING;
						 end if;

					when READING =>
						 if RDEN = '0' then
							  nxt_op_state <= IDLE;
						 elsif ADDR_VALID = '0' then--"miss": bank or row changed during burst
							  nxt_op_state <= BURST_STOP;
						 end if;

					when BURST_STOP =>
						 precharge_count <= 0;
						 nxt_op_state <= PRECHARGE;

					when PRECHARGE =>
						 if precharge_count < 2 then
							  precharge_count <= precharge_count + 1;
						 else
							  act_count <= 0;
							  nxt_op_state <= ACTIVATE;
						 end if;

					when ACTIVATE =>
						 if act_count < 2 then
							  act_count <= act_count + 1;
						 else
							  read_count <= 0;
							  nxt_op_state <= START_READ;
						 end if;

					when others =>
						 nxt_op_state <= IDLE;

			  end case;
			end if;
	end process;
	
	process(clk, rst, nxt_op_state)
	begin
		if(rst='1')then
			op_state <= IDLE;
		elsif(rising_edge(clk))then
			op_state <= nxt_op_state;
		end if;
	end process;
	
	-----------------output driving--------------------	
	process(clk,rst,init_state,op_state)
	begin
		case init_state is
			when PWRUP|NOP0|NOP1|NOP2|NOP3|NOP4|NOP5|NOP6|NOP7|NOPF => --NOP
				RAS_N	<= '1';
				CAS_N	<= '1';
				WE_N	<= '1';
			when PRE => -- precharge all banks
				RAS_N	<= '0';
				CAS_N	<= '1';
				WE_N	<= '0';
				A(10)	<= '1';
			when AR0|AR1|AR2|AR3|AR4|AR5|AR6|AR7 => --auto refresh
				RAS_N	<= '0';
				CAS_N	<= '0';
				WE_N	<= '1';
			when LOAD => --load mode register:
				RAS_N	<= '0';
				CAS_N	<= '0';
				WE_N	<= '0';
				BA		<= "00";
				A(12 downto 10)	<= "000";
				A(9)	<= '0';--writes in burst (the same burst length for reading)
				A(8 downto 7)	<= "00";--Standard Operation
				A(6 downto 4)	<= "010";-- CAS latency: 2 cycles
				A(3)	<= '0';--sequencial burst
				A(2 downto 0)	<= "111";--full-page bursts (entire row of 1024 columns)
			when INITIALIZED =>
				case op_state is
					when IDLE => --NOP
						RAS_N	<= '1';
						CAS_N	<= '1';
						WE_N	<= '1';
					when START_READ =>					
						if RDEN = '1' then
							-- READ column without precharge
							RAS_N	<= '1';
							CAS_N	<= '0';
							WE_N	<= '1';
							A(10) <= '0';
							--TODO: add bank and column address
						else--NOP
							RAS_N	<= '1';
							CAS_N	<= '1';
							WE_N	<= '1';
						end if;
					when READING =>--NOP
							RAS_N	<= '1';
							CAS_N	<= '1';
							WE_N	<= '1';
					when BURST_STOP =>--BST
							RAS_N	<= '1';
							CAS_N	<= '1';
							WE_N	<= '0';
					when PRECHARGE => --precharge selected bank
							RAS_N	<= '0';
							CAS_N	<= '1';
							WE_N	<= '0';
							A(10) <= '0';
							--TODO: add bank
					when ACTIVATE => --activate a row
							RAS_N	<= '0';
							CAS_N	<= '1';
							WE_N	<= '1';
							--TODO: add bank and row address
				end case;
			when others => --NOP
				RAS_N	<= '1';
				CAS_N	<= '1';
				WE_N	<= '1';				
		end case;
		CS_N	<= '0';
		CKE	<= '1';--activate clk
	end process;
	
	-----------------ready driving--------------------
	process(op_state)
	begin
		case op_state is
			when READING =>
				ready <='1';
				if(RDEN='0' or ADDR_VALID='0') then
					ready <= '0';
				end if;
			when others =>
				ready <= '0';
		end case;
	end process;
	
	-----------------ADDR_VALID driving--------------------
	process(rden,wren,offset,previous_offset,nxt_op_state,init_state)
	begin
		if(init_state/=INITIALIZED)then
			ADDR_VALID <= '0';--this default value causes an additional PRECHARGE after INITIALIZED
		elsif ((wren='1' or rden='1') and (nxt_op_state=START_READ or op_state=READING)) then--starting burst reading
			if (offset=previous_offset) then
				ADDR_VALID <= '1';
			else
				ADDR_VALID <= '0';
			end if;
		end if;
	end process;
	
	--previous_offset generation
	--registers address for correct operation of flag req_ready
	process(CLK,offset,ADDR_VALID,RST)
	begin
		if(RST='1')then
			previous_offset <= (others=>'0');
		elsif(rising_edge(CLK) and (rden='1' or wren='1') and nxt_op_state=START_READ) then
			if(ADDR_VALID='0') then
				previous_offset <= offset;--update offset
			end if;
		end if;
	end process;
	
	offset <= ADDR(31 downto 10);--current offset (aka page address, selects a row and a bank)
end architecture;