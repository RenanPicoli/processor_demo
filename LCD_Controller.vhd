library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity LCD_Controller is
    port (
      clk		: in  std_logic;
      rst		: in  std_logic;
		-- interface with CPU
		D		: in std_logic_vector(31 downto 0);
      wren	: in std_logic;
		Q		: out std_logic_vector(31 downto 0);
		ready	: out std_logic;--check for writes
		  
        -- LCD control signals
		RS		: out std_logic;
		RW		: out std_logic;
		E		: inout std_logic;
		VO		: out std_logic;
		DB		: inout std_logic_vector(7 downto 0)
    );
end entity LCD_Controller;

architecture behavioral of LCD_Controller is

    type State_Type is (IdleBeforeInit, Init1, Init2, Init3, Init4, Init5, Init6, Init7,
								Idle, ClearDisplay, ReturnHome, EntryModeSet, DisplayOnOff,
								CursorDisplayShift, FunctionSet, SetCGRAMAddr, SetDDRAMAddr,
								ReadBusyAddr, WriteData, ReadData);
    signal current_state, next_state : State_Type;
    
    -- Define time constants for LCD instructions
    constant Time_IdleBeforeInit   : time := 2.5 ms;
    constant Time_Init1   : time := 100 us;
    constant Time_Init2   : time := 2.5 ms;
    constant Time_Init3   : time := 160 us;
    constant Time_Init4   : time := 160 us;
    constant Time_Init5   : time := 160 us;
    constant Time_Init6   : time := 160 us;
    constant Time_Init7   : time := 160 us;
	 constant Time_Idle    : time := 160 us;
    constant Time_ClearDisplay : time := 1.64 ms;
    constant Time_ReturnHome : time := 1.52 ms;
    constant Time_EntryModeSet : time := 37 us;
    constant Time_DisplayOnOff : time := 37 us;
    constant Time_CursorDisplayShift : time := 37 us;
    constant Time_FunctionSet : time := 37 us;
    constant Time_SetCGRAMAddr : time := 37 us;
    constant Time_SetDDRAMAddr : time := 37 us;
    constant Time_ReadBusyAddr : time := 0 us;
    constant Time_WriteData : time := 37 us;
    constant Time_ReadData : time := 37 us;
	 
    signal cmd: std_logic_vector(9 downto 0);
    signal data: std_logic_vector(7 downto 0);
    signal busy: std_logic;
	--timer signals
	signal Time_Expired: std_logic;
	signal timer_cnt: std_logic_vector(31 downto 0);
	signal timer_preset: std_logic_vector(31 downto 0);
	signal timer_preset_prev: std_logic_vector(31 downto 0);
	signal timer_load: std_logic := '0';
	signal timer_en: std_logic := '0';--enables timer counting
	signal rst_delayed: std_logic;
    
begin

    -- Logic for current and next state
    process(clk,rst,next_state,Time_Expired,timer_load)
    begin
        if rising_edge(clk) then
			  if (rst = '1') then
					current_state <= IdleBeforeInit;
           elsif((timer_load='1' and rst='0') or
						(current_state=Idle and next_state/=Idle))then
                current_state <= next_state;
            end if;
        end if;
    end process;

    -- State transition logic
    process(current_state, cmd, rst,rst_delayed,timer_load)
    begin
        next_state <= current_state;
        
        case current_state is
        
            when IdleBeforeInit =>
                -- Execute Initialization Instruction 1
                -- ...
                -- After minimum time, move to the next state
                ----wait for 1 ns;--necessary only in SIMULATION??
					 if(rst_delayed='1')then
						next_state <= IdleBeforeInit;
						timer_preset <= std_logic_vector(to_unsigned(Time_IdleBeforeInit/1us-1,32));
					 else
						next_state <= Init1;
						timer_preset <= std_logic_vector(to_unsigned(Time_Init1/1us-1,32));
					 end if;
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
            when Init1 =>
                -- Execute Initialization Instruction 1
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init2;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init2/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
            when Init2 =>
                -- Execute Initialization Instruction 2
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init3;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init3/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init3 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init4;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init4/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init4 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init5;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init5/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init5 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init6;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init6/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init6 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init7;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init7/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init7 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
            when Idle =>
                if cmd /= b"0000_0000" then
                    -- Transition to the corresponding command state
						  
						  -- case? is valid ONLY in VHDL 2008
                    case? cmd is
                        when "0000000001" =>
                            next_state <= ClearDisplay;
									 timer_preset <= std_logic_vector(to_unsigned(Time_ClearDisplay/1us-1,32));
									 
                        when "000000001-" =>
                            next_state <= ReturnHome;
									 timer_preset <= std_logic_vector(to_unsigned(Time_ReturnHome/1us-1,32));      
									 
                        when "00000001--" =>
                            next_state <= EntryModeSet;
									 timer_preset <= std_logic_vector(to_unsigned(Time_EntryModeSet/1us-1,32));   
									 
                        when "0000001---" =>
                            next_state <= DisplayOnOff;
									 timer_preset <= std_logic_vector(to_unsigned(Time_DisplayOnOff/1us-1,32));     
									 
                        when "000001----" =>
                            next_state <= CursorDisplayShift;
									 timer_preset <= std_logic_vector(to_unsigned(Time_CursorDisplayShift/1us-1,32));
									 
                        when "00001-----" =>
                            next_state <= FunctionSet;
									 timer_preset <= std_logic_vector(to_unsigned(Time_FunctionSet/1us-1,32));
									 
                        when "0001------" =>
                            next_state <= SetCGRAMAddr;
									 timer_preset <= std_logic_vector(to_unsigned(Time_SetCGRAMAddr/1us-1,32));
									 
                        when "001-------" =>
                            next_state <= SetDDRAMAddr;
									 timer_preset <= std_logic_vector(to_unsigned(Time_SetDDRAMAddr/1us-1,32));
									 
                        when "01--------" =>
                            next_state <= ReadBusyAddr;
									 timer_preset <= std_logic_vector(to_unsigned(Time_ReadBusyAddr/1us-1,32));
									 
                        when "10--------" =>
                            next_state <= WriteData;
									 timer_preset <= std_logic_vector(to_unsigned(Time_WriteData/1us-1,32));
									 
                        when "11--------" =>
                            next_state <= ReadData;
									 timer_preset <= std_logic_vector(to_unsigned(Time_ReadData/1us-1,32));
									 
                        -- Handle other LCD commands                        
                        when others =>
                            -- Unknown command, return to the idle state
                            next_state <= Idle;
									 timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
                    end case?;
					 else
						 -- Unknown command, return to the idle state
						 --next_state <= Idle;
						 timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));					 
                end if;
                ----wait for 1 ns;--necessary only in SIMULATION??
                
            when ClearDisplay =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when ReturnHome =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when EntryModeSet =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when DisplayOnOff =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
               
            when CursorDisplayShift =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when FunctionSet =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when SetCGRAMAddr =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when SetDDRAMAddr =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when ReadBusyAddr =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when WriteData =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when ReadData =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when others =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                ----wait for 1 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Idle/1us-1,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
        end case;
		if(rst='1')then
			timer_preset <= std_logic_vector(to_unsigned(Time_IdleBeforeInit/1us-1,32));
			--timer_load <= '1';
		end if;
    end process;
	 
	timer_load <= '1' when (timer_cnt=x"0000_0000" or rst='1') else '0';

    -- Output logic
    process(current_state)
	 begin
		case current_state is
			when ClearDisplay|ReturnHome|EntryModeSet|DisplayOnOff|CursorDisplayShift|FunctionSet|SetCGRAMAddr|SetDDRAMAddr|WriteData =>
				RS <= cmd(9);
				RW <= cmd(8);
				DB <= cmd(7 downto 0);
			when ReadData =>
				RS <= cmd(9);
				RW <= cmd(8);
				DB <= (others=>'Z');
			when ReadBusyAddr =>
				RS <= cmd(9);
				RW <= cmd(8);
				busy <= DB(7);
				DB <= (others=>'Z');
			when Idle|IdleBeforeInit=>
				RS <= '0';
				RW <= '0';
				DB <= (others=>'Z');
			when Init1|Init2|Init3|Init4=>
				RS <= '0';
				RW <= '0';
				DB <= b"0011_1000";
			when Init5=>
				RS <= '0';
				RW <= '0';
				DB <= b"0000_1000";
			when Init6=>
				RS <= '0';
				RW <= '0';
				DB <= b"0000_0001";
			when Init7=>
				RS <= '0';
				RW <= '0';
				DB <= b"0000_0111";
			when others=>
				RS <= '0';
				RW <= '0';
				DB <= b"0000_0000";
		end case;
	 end process;
	 
	 process(rst,E)
	 begin
		if(rst='1')then
			data <= (others=>'0');
		elsif(falling_edge(E))then
			if(current_state=ReadData)then				
				data <= DB;
			elsif(current_state=ReadBusyAddr)then
				data <= busy & DB(6 downto 0);
			end if;
		end if;
	 end process;
    
	 VO <= '1';
	 
	sw_write:process(clk, rst, D, wren, ready, timer_load, current_state)
	begin
		if(rst='1')then
			cmd <= (others=>'0');
		elsif(rising_edge(clk))then
			if(wren='1' and ready='1')then
				cmd <= D(9 downto 0);
			elsif(timer_load='1' and current_state /= Idle)then
				cmd <= (others=>'0');
			end if;
		end if;
	end process sw_write;
	ready <= '0' when (cmd/=x"0000_0000" or current_state=IdleBeforeInit or
							current_state=Init1 or current_state=Init2 or
							current_state=Init3 or current_state=Init4 or
							current_state=Init5 or current_state=Init6 or
							current_state=Init7)
							else '1';
    
	Q <=(31 downto 8=>'0') & data(7 downto 0);
	
	timer: process(clk, rst,timer_load,timer_preset,timer_en,current_state,next_state)
	begin
		if(rst='1')then
			timer_cnt <= (others=>'0');
		elsif(rising_edge(clk))then
			if((timer_load='1' and timer_cnt = x"0000_0000")or
				(current_state=Idle and next_state/=Idle))then
				timer_cnt <= timer_preset;
			elsif(timer_cnt /= x"0000_0000" and timer_en='1')then
				timer_cnt <= timer_cnt - 1;
			end if;
		end if;
	end process timer;
	timer_en <= '0' when current_state=Idle else '1';
	
	process(rst,clk,timer_cnt)
	begin
		if(rst='1')then
			rst_delayed <= '1';
			Time_Expired <= '0';	
		elsif(rising_edge(clk))then
			rst_delayed <= rst;
			if(timer_cnt=x"0000_0000" and rst='0')then
				Time_Expired <= '1';
			else
				Time_Expired <= '0';
			end if;
		end if;
	end process;
	
	E_p: process(rst,clk,current_state,next_state,timer_load)
		type E_state_t is (E_idle,E_1st_low,E_high,E_2nd_low);
		variable E_state: E_state_t;
	begin
		if(rst='1')then
			E_state := E_idle;
		elsif(rising_edge(clk))then
			if((E_state=E_idle and current_state/=Idle) or (current_state=Idle and next_state/=Idle))then
				E_state := E_1st_low;
			elsif(E_state=E_1st_low)then
				E_state := E_high;
			elsif(E_state=E_high)then
				E_state := E_2nd_low;
			elsif(E_state=E_2nd_low and timer_load='1' and next_state/=Idle)then
				E_state := E_1st_low;
			elsif(E_state=E_2nd_low and timer_load='1' and next_state=Idle)then
				E_state := E_idle;
			end if;
		end if;
		
		case E_state is
			when E_high=>
				E <= '1';
			when others =>
				E <= '0';
		end case;
	end process;
end architecture behavioral;