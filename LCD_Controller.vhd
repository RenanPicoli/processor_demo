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
		E		: out std_logic;
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
    
begin

    -- Logic for current and next state
    process(clk,rst,next_state,Time_Expired)
    begin
        if (rst = '1') then
            current_state <= IdleBeforeInit;
        elsif rising_edge(clk) then
            if(Time_Expired='1' and timer_load='0')then
                current_state <= next_state;
            end if;
        end if;
    end process;

    -- State transition logic
    process--(current_state, cmd)
    begin
        next_state <= current_state;
        
        case current_state is
        
            when IdleBeforeInit =>
                -- Execute Initialization Instruction 1
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init1;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init1/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
            when Init1 =>
                -- Execute Initialization Instruction 1
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init2;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init2/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
            when Init2 =>
                -- Execute Initialization Instruction 2
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init3;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init2/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init3 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init4;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init3/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init4 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init5;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init4/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init5 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init6;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init5/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init6 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Init7;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init6/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when Init7 =>
                -- Execute Initialization Instruction 3
                -- ...
                -- After minimum time, move to the next state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_Init7/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
            when Idle =>
                if cmd /= b"0000_0000" then
                    -- Transition to the corresponding command state
						  
						  -- case? is valid ONLY in VHDL 2008
                    case? cmd is
                        when "0000000001" =>
                            next_state <= ClearDisplay;
									 
                        when "000000001-" =>
                            next_state <= ReturnHome;       
									 
                        when "00000001--" =>
                            next_state <= EntryModeSet;     
									 
                        when "0000001---" =>
                            next_state <= DisplayOnOff;        
									 
                        when "000001----" =>
                            next_state <= CursorDisplayShift;
									 
                        when "00001-----" =>
                            next_state <= FunctionSet;
									 
                        when "0001------" =>
                            next_state <= SetCGRAMAddr;
									 
                        when "001-------" =>
                            next_state <= SetDDRAMAddr;
									 
                        when "01--------" =>
                            next_state <= ReadBusyAddr;
									 
                        when "10--------" =>
                            next_state <= WriteData;
									 
                        when "11--------" =>
                            next_state <= ReadData;
									 
                        -- Handle other LCD commands                        
                        when others =>
                            -- Unknown command, return to the idle state
                            next_state <= Idle;
                    end case?;
                end if;
                wait for 100 ns;--necessary only in SIMULATION??
                
            when ClearDisplay =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_ClearDisplay/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when ReturnHome =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_ReturnHome/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when EntryModeSet =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_EntryModeSet/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when DisplayOnOff =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_DisplayOnOff/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when CursorDisplayShift =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_CursorDisplayShift/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when FunctionSet =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_FunctionSet/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when SetCGRAMAddr =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_SetCGRAMAddr/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when SetDDRAMAddr =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_SetDDRAMAddr/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when ReadBusyAddr =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_ReadBusyAddr/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when WriteData =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_WriteData/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
                
            when ReadData =>
                -- Execute the Clear Display command
                -- ...
                -- After minimum time, return to the idle state
                next_state <= Idle;
                wait for 100 ns;--necessary only in SIMULATION??
				timer_preset <= std_logic_vector(to_unsigned(Time_ReadData/1us,32));
				--timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';
            
        end case;
		if(rst='1')then
			timer_preset <= std_logic_vector(to_unsigned(Time_IdleBeforeInit/1us,32));
		end if;
    end process;
	
	process
	begin
 		if(rst='1')then
			--timer_load <= '0';
			timer_preset_prev <= (others=>'0');
		elsif(rising_edge(clk))then
			--if(Time_Expired='1')then
			--	timer_load <= '1';
			--else
			--	timer_load <= '0';
			--end if;
			timer_preset_prev <= timer_preset;
		end if;
	end process;
	timer_load <= '1' when (Time_Expired='1' and rst='0') else '0';

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
				data <= DB;
			when ReadBusyAddr =>
				RS <= cmd(9);
				RW <= cmd(8);
				busy <= DB(7);
				data <= '0' & DB(6 downto 0);
			when Idle|IdleBeforeInit=>
				RS <= '0';
				RW <= '0';
				data <= (others => '0');
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
    
	 VO <= '1';
	 
	sw_write:process(clk, rst, D, wren)
	begin
		if(rst='1')then
			cmd <= (others=>'0');
		elsif(rising_edge(clk) and wren='1')then
			cmd <= D(9 downto 0);
		end if;
	end process sw_write;

	Q <=(31 downto 8=>'0') & data(7 downto 0);
	
	timer: process(clk, rst,timer_load,timer_preset)
	begin
		if(rst='1')then
			timer_cnt <= (others=>'0');
		elsif(rising_edge(clk))then
			if(timer_load='1' and timer_cnt = x"0000_0000")then
				timer_cnt <= timer_preset_prev;
			elsif(timer_cnt /= x"0000_0000")then
				timer_cnt <= timer_cnt - 1;
			end if;
		end if;
	end process timer;
	Time_Expired <= '1' when timer_cnt=x"0000_0000" else '0';
end architecture behavioral;
