-------------------------------------------------------------
--memory management unit - MMU
--by Renan Picoli de Souza
-------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;--to_integer

use work.my_types.all;

-------------------------------------------------------------

entity mmu is
generic (N: integer; F: integer);--total number of fifo stages and fifo output stage depth, respectively
port (
out_fifo_full: 	out std_logic_vector(1 downto 0):= "00";
out_cache_request: out	std_logic:= '0';
out_fifo_out_isempty: out std_logic:= '1';--'1' means fifo output stage is empty
		CLK: in std_logic;--same clock of processor
		CLK_fifo: in std_logic;--fifo clock
		rst: in std_logic;
		receive_cache_request: in std_logic;
--		fifo_valid:  in std_logic_vector(F-1 downto 0);--1 means a valid data
		iack: in std_logic;
		irq: out std_logic;--data sent
		invalidate_output: buffer std_logic:='0';--invalidate memmory positions after parallel transfer
		fill_cache:  buffer std_logic
);
end entity;

architecture bhv of mmu is

--fifo_full(0) means fifo full this cycle; fifo_full(1) means fifo was full on previous cycle
signal fifo_full: 	std_logic_vector(1 downto 0):= "00";
signal cache_request: 	std_logic:= '0';
signal fifo_out_isempty:std_logic:= '1';--'1' means fifo output stage is empty
signal tmp: std_logic_vector(F-1 downto 0);
signal tmp2: std_logic_vector(F-1 downto 0);
signal fill_cache_delayed: std_logic:='0';--previous value of fill cache
signal CLK_fifo_delayed: std_logic:='0';--previous fifo clock, sampled at rising edge of CLK
signal CLK_fifo_rising_edge: std_logic:='0';--detects a rising edge has occurred
signal valid: std_logic_vector (N-1 downto 0):=(others=>'0');
signal invalidate_output_ack: std_logic:='0';--processo update_valid usa para reconhecer que invalidou a saída

begin

	--(not valid(0)) and (not valid(1)) and ... (not valid(31)) = fifo_out_isempty
	tmp2(0) <= not valid(0);
	product2: for i in 1 to F-1 generate
		tmp2(i) <= tmp2(i-1) and (not valid(i));
	end generate product2;
	fifo_out_isempty <= tmp2(F-1);--the entire output stage is invalid

	--valid(0) and valid(1) and ... valid(31) => fifo_full
	tmp(0) <= valid(0);
	product: for i in 1 to F-1 generate
		tmp(i) <= tmp(i-1) and valid(i);
	end generate product;
	
	--REMOVER
	out_cache_request <= cache_request;
	out_fifo_full <= fifo_full;
	out_fifo_out_isempty <= fifo_out_isempty;
	
	process_request: process(CLK,invalidate_output_ack)
	begin
		if(CLK'event and CLK='1') then
			if(rst='0') then
			
				if (receive_cache_request='1') then
					cache_request <= '1';
--				elsif (receive_cache_request='0' and fifo_full="01") then
--				elsif (receive_cache_request='0' and fifo_out_isempty='1' and fifo_full(1)='1') then
				elsif (receive_cache_request='0' and fill_cache_delayed='1') then
					cache_request <= '0';--cache request foi atendida
				end if;

				if (iack='0') then
					--detects when parallel transfer SHOULD occur
					fill_cache <= cache_request and fifo_full(0) and (not fifo_full(1));--mesmo se wren='1', habilita o carregamento paralelo.
					irq <= fill_cache;
				else
					fill_cache <= '0';
					irq <= '0';
				end if;

				--invalidate_output <= (cache_request and fill_cache) and not invalidate_output_ack;
				if ((cache_request='1') and (fill_cache='1') and (invalidate_output_ack='0')) then
					invalidate_output <= '1';
				elsif (invalidate_output_ack = '1') then
					invalidate_output <= '0';
				end if;
			
			else--if reset is activated
				cache_request <= '0';
				irq <= '0';
				
			end if;
			fifo_full(1) <= fifo_full(0);
			fifo_full(0) <= tmp(F-1);--update fifo_full
			
			fill_cache_delayed <= fill_cache;
			CLK_fifo_delayed	 <= CLK_fifo;--TODO: fix
			CLK_fifo_rising_edge <= CLK_fifo and (not CLK_fifo_delayed);

		end if;
	end process;
	
	update_valid: process (CLK_fifo)--during rising edge of fifo clock, updates valid bits
		begin
		if CLK_fifo'event and CLK_fifo='1' then
			if rst = '0' then
				
				if(invalidate_output='1') then
					invalidate_output_ack <= '1';
				else
					invalidate_output_ack <= '0';
				end if;
				
				--variable assignments take place immediately and order matters!!!
				for i in 0 to F-2 loop-- F-2 por causa de um delay para perceber que foi dado comando para invalidar
--					O(i) := O(i+1);
					valid(i) <= valid(i+1) and (not invalidate_output);
				end loop;

				for i in F-1 to N-2 loop
--					O(i) := O(i+1);
					valid(i) <= valid(i+1);
				end loop;

--				O(N-1) := D;
				valid(N-1) <= '1';-- '1' means valid data
				
			else--rst='1'
			
--				O := (others => (others => '0'));
				valid <= (others => '0');-- '0' means invalid data
				invalidate_output_ack <= '0';

			end if;
		end if;
--		Q <= O(0 to OS-1);--LSB first
	end process;
end bhv;