-- Code your testbench here
library IEEE;
use IEEE.std_logic_1164.all;

entity tb is
end entity tb;

architecture bhv of tb is
component LCD_Controller
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
end component;

signal D: std_logic_vector(31 downto 0);
signal Q: std_logic_vector(31 downto 0);
signal wren: std_logic;
signal clk: std_logic;
signal rst: std_logic;
signal ready: std_logic;

signal RS: std_logic;
signal RW: std_logic;
signal E: std_logic;
signal VO: std_logic;
signal DB: std_logic_vector(7 downto 0);

begin
	clk_p: process
    begin
    	clk <= '0';
		wait for 0.5 us;
    	clk <= '1';
		wait for 0.5 us;
    end process clk_p;
    
	rst <= '1', '0' after 10 us;
	D <= (others=>'0'), x"0000_0038" after 6000 us, (others=>'0') after 6001 us;
	wren <= '0', '1' after 6000 us, '0' after 6001 us;
   dut: LCD_Controller port map (
        clk => clk,
        rst => rst,
		-- interface with CPU
		D => D,
        wren => wren,
		Q => Q,
		ready => ready,
		  
        -- LCD control signals
		RS => RS,
		RW => RW,
		E => E,
		VO => VO,
		DB => DB
    );
end architecture bhv;