--This testbench aims to simulate control of on-board SRAM

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;--for floor(), ceil()
use work.all;
use std.textio.all;--for file reading
use ieee.std_logic_textio.all;--for reading of std_logic_vectors

use work.my_types.all;


entity testbench_SRAM_ctrl is
end testbench_SRAM_ctrl;

architecture test of testbench_SRAM_ctrl is

--emulates 1/16 of the onboard sram (65536 16bit words)
component tb_sram
	PORT
	(
		address	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
end component;

---------------------------------------------------
--produces 12MHz from 50MHz
component pll_12MHz
	port
	(
		areset		: in std_logic  := '0';
		inclk0		: in std_logic  := '0';
		c0				: out std_logic 
	);
end component;

---------------------------------------------------
--produces fs and 256fs from 12MHz
component pll_audio
	port
	(
		areset		: in std_logic  := '0';
		inclk0		: in std_logic  := '0';
		c0				: out std_logic;
		c1				: out std_logic;
		locked		: out std_logic
	);
end component;

---------------------------------------------------

component pll_dbg_uproc
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC ;
		c1 	: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC 
	);
END component;

---------------------------------------------------

--reset duration must be long enough to be perceived by the slowest clock (filter clock, both polarities)
constant TIME_RST : time := 50 us;
-- internal clock period.
constant TIME_DELTA : time := 20 ns;

signal  	CLK_IN:std_logic;--50MHz
signal	rst: std_logic;

----------adaptive filter algorithm inputs----------------
signal data_in: std_logic_vector(31 downto 0);--data to be filtered (encoded in IEEE 754 single precision)
signal desired: std_logic_vector(31 downto 0);--desired response (encoded in IEEE 754 single precision)

--sram interface
signal	ram_CLK: std_logic;--needed for conversion between sram and altsyncram (sram doesn't have clock)
signal	ram_wren: std_logic;--needed for conversion between sram and altsyncram write enable pins
signal	ram_Q: std_logic_vector(15 downto 0);--needed for conversion between sram and altsyncram data output pins

--000: will read* lower 16bits of input vectors
--001: will read* lower 16bits of desired vectors
--010: will read* upper 16bits of input vectors
--011: will read* upper 16bits of desired vectors
--100: stop: will wait until filter_CLK rising edge (since sampling edge is the rising)
--101: reset: after stop, remain in this state while filter_CLK ='1' waiting for the filter_CLK falling_edge
-- * : on next rising edge of CLK, sram_ADDR will be updated, at next CLK falling edge IO will be latched
signal 	sram_reading_state: std_logic_vector(2 downto 0);
signal 	count: std_logic_vector(17 downto 0);--counter: generates the address for SRAM, 1 bit must be added to obtain address
signal 	sram_WE_n: std_logic;--write enable ACTIVE LOW
signal	sram_IO: std_logic_vector(15 downto 0);--sram data; input because we'll only read
signal	sram_ADDR: std_logic_vector(19 downto 0);--ADDR for SRAM
signal	sram_ADDR_shortened: std_logic_vector(15 downto 0);--ADDR for emulated SRAM (tb_sram is smaller than actual SRAM)

signal	filter_CLK: std_logic;--filter clock generated with PLL
signal	filter_rst: std_logic;
signal 	filter_enable: std_logic;--bit 0, enables filter_CLK
signal 	filter_CLK_state: std_logic := '0';--starts in zero, changes to 1 when first rising edge of filter_CLK occurs
signal 	i2s_SCK_IN_PLL_LOCKED: std_logic;--'1' if PLL that provides SCK_IN is locked

-------------------clocks---------------------------------
--signal rising_CLK_occur: std_logic;--rising edge of CLK occurred after filter_CLK falling edge
signal CLK: std_logic;--clock for processor and cache (50MHz)
signal CLK_dbg: std_logic;--clock for debug, check timing analyzer or the pll_dbg wizard
signal CLK_fs: std_logic;-- 11.029kHz clock
signal CLK12MHz: std_logic;-- 12MHz clock (MCLK for audio codec)
signal CLK16_928571MHz: std_logic;-- 16.928571MHz clock (1536fs, for I2S peripheral)

begin
-----------------SRAM interfacing---------------------
	sram_WE_n <= '1';--reading always enabled
	
	sram_reading: process(CLK,filter_rst,sram_reading_state,filter_CLK,count,rst)
	begin
		if(rst='1')then
			sram_reading_state <= "101";
--			sram_ADDR <= (others=>'0');
		elsif(filter_CLK='1')then
			sram_reading_state <= "101";
		elsif(rising_edge(CLK) and filter_rst='0') then
			if (sram_reading_state(2)/='1')then--"100" or "101"
--				sram_ADDR <= sram_reading_state(0) & count & sram_reading_state(1);--data is launched
				sram_reading_state <= sram_reading_state + 1;
			elsif (sram_reading_state="101") then
				--sram_ADDR will update next rising_edge of CLK
				sram_reading_state <= "000";
			end if;
		end if;
		
		if (rst='1')then
			sram_ADDR <= (others=>'0');
		elsif (sram_reading_state(2)/='1')then--"100" or "101"
			sram_ADDR <= sram_reading_state(0) & count & sram_reading_state(1);--data is launched
		end if;
	end process;
	
	--index of sample being fetched
	--generates address for reading SRAM
	--counts from 0 to 256K
	counter: process(rst,filter_rst,filter_CLK)
	begin
		if(rst='1' or filter_rst='1')then
			count <= (others=>'0');
		elsif(rising_edge(filter_CLK) and filter_rst='0')then--this ensures, count is updated after used for sram_ADDR
			count <= count + 1;
		end if;
	end process;
	
	process(CLK,rst,sram_ADDR,filter_rst,sram_reading_state)
	begin
		if(rst='1')then
			data_in <= (others=>'0');
			desired <= (others=>'0');
		--sram_ADDR is updated at rising_edge, must wait at least 10 ns to latch valid data
		elsif (falling_edge(CLK) and filter_rst='0' and sram_reading_state(2)='0') then--data is latched
			if(sram_ADDR(19)='0')then--reading input vectors
				if(sram_ADDR(0)='0')then--reading lower half
					data_in(15 downto 0) <= sram_IO;
				else--reading upper half
					data_in(31 downto 16) <= sram_IO;
				end if;
			else--reading desired vectors
				if(sram_ADDR(0)='0')then--reading lower half
					desired(15 downto 0) <= sram_IO;
				else--reading upper half
					desired(31 downto 16) <= sram_IO;
				end if;
			end if;
		end if;
	end process;
--------------------------------------------------------
				
	filter_CLK <= CLK_fs;
	filter_enable <= i2s_SCK_IN_PLL_LOCKED;--bit 0 enables filter_CLK, after PLL is locked
					
	filter_reset_process: process (filter_CLK,filter_CLK_state,filter_enable,i2s_SCK_IN_PLL_LOCKED)
	begin
		if(RST='1')then
			filter_rst <='1';
			filter_CLK_state <= '0';
		else
			if (rising_edge(filter_CLK) and i2s_SCK_IN_PLL_LOCKED='1') then--pll_audio must be locked
				filter_CLK_state <= '1';
			end if;
			if (falling_edge(filter_CLK) and filter_CLK_state = '1' and filter_enable='1' and i2s_SCK_IN_PLL_LOCKED='1') then
					filter_rst <= '0';
			end if;
		end if;
	end process filter_reset_process;
	
	--wren: active HIGH
	--sram_WE_n: active LOW
	ram_wren <= not sram_WE_n;
	sram_ADDR_shortened <= sram_ADDR(19) & sram_ADDR(14 downto 0);
	ram: tb_sram
	port map
	(
		--trick: in real SRAM, bit 19 divides upper and lower halfs, in tb_sram this is done by bit 15
		address	=> sram_ADDR_shortened,
		clock		=> ram_CLK,--because address is updated at rising_edge of CLK in my system
		data		=> (others=>'0'),--data for write, but I will only read
		wren		=> ram_wren,--active HIGH
		q			=> ram_Q
	);
	ram_CLK <= transport CLK after 1 ns;-- this delay ensures that sram_ADDR is read after its update
	sram_IO <= transport ram_Q after 8 ns;--emulates delay in sram response (less than 10 ns)
--	sram_IO <= ram_Q;
	
	clock: process--50MHz input clock
	begin
		CLK_IN <= '0';
		wait for 10 ns;
		CLK_IN <= '1';
		wait for 10 ns;
	end process clock;
	
	rst <= '1', '0' after TIME_RST;--reset must be long enough to be perceived by the slowest clock (fifo)
	
	clk_dbg_uproc:	pll_dbg_uproc
	port map
	(
		areset=> '0',
		inclk0=> CLK_IN,
		c0		=> CLK_dbg,
		c1		=> CLK,--produces CLK=4MHz for processor
		locked=> open
	);

	--produces 12MHz (MCLK) from 50MHz input
	clk_12MHz: pll_12MHz
	port map (
	inclk0 => CLK_IN,
	areset => rst,
	c0 => CLK12MHz
	);
	
	--produces 11025Hz (fs) and 16.928571 MHz (1536fs for BCLK_IN) from 12MHz input
	clk_fs_1536fs: pll_audio
	port map (
	inclk0 => CLK12MHz,
	areset => rst,
	c0 => CLK_fs,
	c1 => CLK16_928571MHz,
	locked => i2s_SCK_IN_PLL_LOCKED
	);
	
end architecture test;