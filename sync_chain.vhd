--------------------------------------------------
--synchronizer chain
--by Renan Picoli de Souza
--creates a configurable synchronizer chain to improve MTBF in data transfers between differents clock domains
--N is the bus width in bits
--L is the number of registers in the chain
--------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sync_chain is
	generic (N: natural;--bus width in bits
				L: natural);--number of registers in the chain
	port (
			data_in: in std_logic_vector(N-1 downto 0);--data generated at another clock domain
			CLK: in std_logic;--clock of new clock domain
			RST: in std_logic;--asynchronous reset
			data_out: out std_logic_vector(N-1 downto 0)--data synchronized in CLK domain
	);
end sync_chain;

architecture structure of sync_chain is

type array2d is array (0 to L) of std_logic_vector(N-1 downto 0);
signal D: array2d;
signal Q: array2d;

	begin
	
	chain: for i in 0 to L-1 generate
		process(D,Q,CLK,RST)
		begin
			if (RST='1') then
				Q(i) <= (others => '0');
			elsif (rising_edge(CLK)) then
				Q(i) <= D(i);
			end if;
			D(i+1) <= Q(i);
		end process;
	end generate chain;
	D(0) <= data_in;
	data_out <= Q(L-1);
	
end structure;