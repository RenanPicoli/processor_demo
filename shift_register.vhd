library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use work.my_types.all;

--OBJETIVOS: * implementar uma FIFO para leitura de dados de sensor; e
--				 * permitir a leitura em paralelo destes dados.
--LSB é transmitido primeiro (operação shif right)
--TODO: adicionar controle para operar shift left se desejado
--TODO: habilitar auto-load
entity shift_register is
	generic (N: integer; OS: integer);--number of stages and number of stages in the output, respectively.
	port (CLK: in std_logic;
			rst: in std_logic;
			D: in std_logic_vector (31 downto 0);
--			invalidate_output: in std_logic;
			Q: out array32 (0 to OS-1));
--			valid: buffer std_logic_vector (N-1 downto 0):=(others=>'0'));--for memory manager use
end shift_register;

architecture bhv of shift_register is
	begin
	process (CLK)
		variable O: array32 (0 to N-1);
		begin
		if CLK'event and CLK='1' then
			if rst = '0' then
			
				--variable assignments take place immediately and order matters!!!
				for i in 0 to OS-1 loop
					O(i) := O(i+1);
--					valid(i) <= valid(i+1) and (not invalidate_output);
				end loop;

				for i in OS to N-2 loop
					O(i) := O(i+1);
--					valid(i) <= valid(i+1);
				end loop;

				O(N-1) := D;
--				valid(N-1) <= '1';-- '1' means valid data
				
			else --TODO: load from bus
			
				O := (others => (others => '0'));
--				valid <= (others => '0');-- '0' means invalid data

			end if;
		end if;
		Q <= O(0 to OS-1);--LSB first
	end process;
end bhv;