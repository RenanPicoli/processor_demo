% filtro IIR
clear all;
close all;
disp('Script iniciado!');

original = load('rise_original','-ascii');
fs = 44100;% original sampling frequency
% original = audioread('Rise From The Ashes.mp3');
x = original(:,1);% x foi gravada com 2 canais, vamos pegar apenas o primeiro
pkg load signal % para usar downsample()
downsample_factor = 2;
x = downsample(x,downsample_factor);
min_x=3200;% esse algoritmo precisa que xN != 0
% max_x=300_000;
% x = x(min_x:max_x);
x = x(min_x:end);
x=single(x);% converte x para precis�o simples
L=length(x);
y=zeros(1,L);
y=single(y);% converte y para precis�o simples

b=[1 0 -2 1]
a=[1 0.590110 0.582896 0.302579 0.076053]

% diplay P, Q, direct form 1 coeffs
b_direct_form_1 = b
a_direct_form_1 = -a(2:end)
P=length(b_direct_form_1)-1
Q=length(a_direct_form_1)
% coeficientes dos multiplicadores no circuito
% u(1:P+1): coeficientes de feed forward
% u(P+2:end): coeficientes de feedback
% u = [b0 .. bP a1 .. aQ]
% y(n) = b0x(n)+..+bPx(n-P)+a1y(n-1)..aQy(n-Q)
u=[b_direct_form_1 a_direct_form_1]

d=filter(u(1:P+1),[1 -u(P+2:end)],x);% d of desired response, same length as x

disp('iniciando filtro');
tic;
%%% Adaptive Filter with adapted step size %%%%%%%%
Pmax=3;
Qmax=4;
tol=1e-13;
[y,w,filters,err,step,n] = adaptive_filter(x,d,Pmax,Qmax,tol);
toc;
disp('filtro conclu�do');

figure;
for i=1:8
  subplot(2,4,i);
  plot(filters(1,i,1:n));
  title(cstrcat('coeficiente ',num2str(i)));
  grid on;
end

%ESCRITA DE ARQUIVO
disp('Gerando string.');

% escrita das entradas do filtro
convertidos=toupper(num2hex(single(x)));% string a ser impressa
s=blanks(9*L);
for i=1:L
  s(9*i-8:9*i)=[convertidos(i,:) "\n"];
end

fname="./simulation/modelsim/input_vectors.txt";
fid=fopen(fname,"w");
fprintf(fid,"%s",s);
fclose(fid);

% escrita das respostas desejadas
convertidos=toupper(num2hex(single(d)));% string a ser impressa
s=blanks(9*L);
for i=1:L
  s(9*i-8:9*i)=[convertidos(i,:) "\n"];
end

fname="./simulation/modelsim/desired_vectors.txt";
fid=fopen(fname,"w");
fprintf(fid,"%s",s);
fclose(fid);

##% leitura de respostas
##disp('Pressione qualquer tecla para ler resultados calculados pelo circuito:');
##kbhit();
##
##fname="C:/Users/renan/Documents/FPGA projects/processor_demo/simulation/modelsim/output_vectors.txt";
##fid=fopen(fname,"r");
##[val]=textscan(fid,"%s");
##fclose(fid);
##
##val=val{1,1};
##disp('val');
##disp(val);
##
##%ignorar os X at� o segundo 0000_0000 inclusive
####count_invalid_outputs=0;
####while(strcmp(char(val(count_invalid_outputs+1,1)), "00000000")==0)% o circuito inicia a sa�da com esse valor ap�s reset
####  count_invalid_outputs++;
####endwhile
####count_invalid_outputs++;% o 1� 00000000 tamb�m � inv�lido
####while(strcmp(char(val(count_invalid_outputs+1,1)), "00000000")==0)
####  count_invalid_outputs++;
####endwhile
##
##% for some reason, two zeros are written before filter output starts
##count_invalid_outputs=2;
##val = val(count_invalid_outputs+1:end,1);
##
##disp('Resutados lidos do circuito:');
##results=hex2num(val,"single");
##disp(results)
##plot(results)
##hold on
##plot(y(1:length(results)))
##legend('circuito','octave')

disp('Resultados calculados no octave:');
octave_result_string = toupper(num2hex(single(y(1:length(x)))));
disp(octave_result_string)

%como o testbench sempre abre o arquivo de sa�da no append_mode, preciso delet�-lo ap�s usar
% se a linha abaixo estiver comentada, manualmente apagar o arquivo de sa�da do hardware antes de reiniciar o testbench
%delete(fname)

% imprime as diverg�ncias entre os resultados do hardware e do octave

##s=blanks(8*length(x));
##for i=1:length(x) % i+1: �ndice do y lido; y(1) sempre � zero
##	if (strcmp(octave_result_string(i,:),char(val(i)))==0)
##		s(18*i-17:18*i)=[octave_result_string(i,:) "," char(val(i)) "\n"]';
##		disp(["Diferen�a octave - circuito na amostra " num2str(i) " � " num2str(results(i) - y(i)) " (" num2str((results(i) - y(i))*100/y(i)) "%)"])
##	endif
##end
##
##fname="C:/Users/renan/Documents/FPGA projects/processor_demo/simulation/modelsim/relat�rio.txt";
##fid=fopen(fname,"w");
##fprintf(fid,"%s",s);
##fclose(fid);
s=blanks(9*L);
for i=1:L
  s(9*i-8:9*i)=[octave_result_string(i,:) "\n"];
end
fname="./simulation/modelsim/output_vectors.txt";
fid=fopen(fname,"w");
fprintf(fid,"%s",s);
fclose(fid);
