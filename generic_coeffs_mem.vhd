--------------------------------------------------
--implementation of memory for filter coefficients
--by Renan Picoli de Souza
---------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use ieee.numeric_std.all;--to_integer
use work.my_types.all;--array32

---------------------------------------------------

entity generic_coeffs_mem is
-- 0..P: índices dos coeficientes de x (b)
-- 1..Q: índices dos coeficientes de y (a)
generic	(N: natural; P: natural; Q: natural);--N address width in bits
port(	D:	in std_logic_vector(31 downto 0);-- um coeficiente é atualizado por vez
		ADDR: in std_logic_vector(N-1 downto 0);--se ALTERAR P, Q PRECISA ALTERAR AQUI
		RST:	in std_logic;--synchronous reset
		RDEN:	in std_logic;--read enable
		WREN:	in std_logic;--write enable
		CLK:	in std_logic;
		Q_coeffs: out std_logic_vector(31 downto 0);--single coefficient reading
		all_coeffs:	out array32((P+Q) downto 0)-- todos os coeficientes VÁLIDOS são lidos de uma vez
);

end generic_coeffs_mem;

---------------------------------------------------

architecture behv of generic_coeffs_mem is

	type memory is array (0 to 2**N-1) of std_logic_vector(31 downto 0);
	--lembrar de desabilitar auto RAM replacement em compiler settings>advanced settings (synthesis)
	signal possible_outputs: memory := (others => x"0000_0000");
	
begin					   

   process(CLK)
   begin
	--processo de escrita (um coeficiente de cada vez)
	if (CLK'event and CLK = '1') then
		if (RST='1') then
--			possible_outputs <= (others=>(others=>'0'));
		elsif (WREN ='1') then
			possible_outputs(to_integer(unsigned(ADDR))) <= D;
		end if;
	end if;
   end process;

	Q_coeffs <= possible_outputs(to_integer(unsigned(ADDR)));	

	--filtro tem acesso simultâneo a todos os coeficientes pela porta all_coeffs
	coeffs_b: for i in 0 to P generate--coeficientes de x (b)
		all_coeffs(i) <= possible_outputs(i);
	end generate;
	
	coeffs_a: for j in 1 to Q generate--coeficientes de y (a)
		all_coeffs(j+P) <= possible_outputs(j+P);
	end generate;

end behv;

----------------------------------------------------
