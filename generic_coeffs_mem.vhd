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
		RST:	in std_logic;--asynchronous reset
		RDEN:	in std_logic;--read enable
		WREN:	in std_logic;--write enable
		CLK:	in std_logic;
		filter_CLK:	in std_logic;--to synchronize read with filter (coeffs are updated at rising_edge)
		filter_WREN: in std_logic;--filter write enable, used to check if all_coeffs must be used
		parallel_write_data: in array32 (0 to 2**N-1);
		parallel_wren: in std_logic;
		parallel_rden: in std_logic;
		parallel_read_data: out array32 (0 to 2**N-1);--used when peripherals other than filter
		Q_coeffs: out std_logic_vector(31 downto 0);--single coefficient reading
		all_coeffs:	out array32((P+Q) downto 0)-- all VALID coefficients are read at once by filter through this port
);

end generic_coeffs_mem;

---------------------------------------------------

architecture behv of generic_coeffs_mem is

component parallel_load_cache
	generic (N: integer);--size in bits of address 
	port (CLK: in std_logic;--borda de subida para escrita, memória pode ser lida a qq momento desde que rden=1
			ADDR: in std_logic_vector(N-1 downto 0);--addr is a word (32 bits) address
			RST:	in std_logic;--asynchronous reset
			write_data: in std_logic_vector(31 downto 0);
			parallel_write_data: in array32 (0 to 2**N-1);
			parallel_wren: in std_logic;
			rden: in std_logic;--habilita leitura
			wren: in std_logic;--habilita escrita
			parallel_rden: in std_logic;--enables parallel read (to shared data bus)
			parallel_read_data: out array32 (0 to 2**N-1);
			Q:	out std_logic_vector(31 downto 0)
			);
end component;

	--lembrar de desabilitar auto RAM replacement em compiler settings>advanced settings (synthesis)
	signal possible_outputs: array32 (0 to 2**N-1);
	signal parallel_rden_stretched: std_logic;--asserted when parallel_rden='1', deasserted next filter_CLK rising edge
	
begin					   
	mem: parallel_load_cache
		generic map (N => N)
		port map(CLK => CLK,
					ADDR=> ADDR,
					RST => RST,
					write_data => D,
					parallel_write_data => parallel_write_data,
					parallel_wren => parallel_wren,
					rden => rden,
					wren => wren,
					parallel_rden => parallel_rden_stretched,
					parallel_read_data => possible_outputs,
					Q => Q_coeffs
		);
		
	process(RST,filter_CLK,parallel_rden)
	begin
		if(RST='1')then
			parallel_rden_stretched <= '0';
		elsif(parallel_rden='1')then
			parallel_rden_stretched <= '1';
		elsif(rising_edge(filter_CLK))then
			parallel_rden_stretched <= '0';
		end if;
	end process;

	process(filter_WREN)
	begin
		if(filter_WREN='1')then
			--filtro tem acesso simultâneo a todos os coeficientes pela porta all_coeffs
			coeffs_b: for i in 0 to P loop--coeficientes de x (b)
				all_coeffs(i) <= possible_outputs(i);
			end loop;
			
			coeffs_a: for j in 1 to Q loop--coeficientes de y (a)
				all_coeffs(j+P) <= possible_outputs(j+P);
			end loop;
		else
			all_coeffs <= (others=>(others=>'Z'));
		end if;
	end process;
	
	parallel_read_data <= 	possible_outputs when (parallel_rden ='1') else
									(others=>(others=>'Z'));--prevents latch

end behv;

----------------------------------------------------
