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
port(	D:	in std_logic_vector(31 downto 0);-- um coeficiente é carregado por vez
		ADDR: in std_logic_vector(N-1 downto 0);--se ALTERAR P, Q PRECISA ALTERAR AQUI
		RST:	in std_logic;--synchronous reset
		RDEN:	in std_logic;--read enable
		WREN:	in std_logic;--write enable
		CLK:	in std_logic;
		Q_coeffs: out std_logic_vector(31 downto 0);--single coefficient reading
		all_coeffs:	out std_logic_vector(32*(P+Q+1)-1 downto 0)-- todos os coeficientes VÁLIDOS são lidos de uma vez
);

end generic_coeffs_mem;

---------------------------------------------------

architecture behv of generic_coeffs_mem is

	type memory is array (0 to 2**N-1) of std_logic_vector(31 downto 0);
	--lembrar de desabilitar auto RAM replacement em compiler settings>advanced settings (synthesis)

	-- generates initial values of possible_outputs signal
--	function initial_values return memory is
--		variable retval: memory := (others => x"0000_0000");
--	begin
--		retval (0) := x"3F00_0000";-- b0: 0.5
--		retval (P+1) := x"BF00_0000";-- a1: -0.5
--		return retval;		
--	end function;
--	signal possible_outputs: memory := initial_values;
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
	
	--processo de leitura (um coeficiente de cada vez)
	if (CLK'event and CLK = '1') then
		if (RDEN ='1' and RST='0') then
			Q_coeffs <= possible_outputs(to_integer(unsigned(ADDR)));
		else
			Q_coeffs <= (others=>'Z');
		end if;
	end if;
   end process;	

	--filtro tem acesso simultâneo a todos os coeficientes pela porta all_coeffs
	coeffs_b: for i in 0 to P generate--coeficientes de x (b)
		all_coeffs((32*i+31) downto (32*i)) <= possible_outputs(i);
	end generate;
	
	coeffs_a: for j in 1 to Q generate--coeficientes de y (a)
		all_coeffs((32*(j+P)+31) downto (32*(j+P))) <= possible_outputs(j+P);
	end generate;

end behv;

----------------------------------------------------
