% filtro y(n)=[x(n)-y(n-1)]/2
close all;
% disp('Pressione qualquer tecla para iniciar o script.');
% kbhit();
disp('Script iniciado!');

%x=[0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0];
original = load('rise_original','-ascii');
fs = 44100;% original sampling frequency
% original = audioread('Rise From The Ashes.mp3');
x = original(:,1);% x foi gravada com 2 canais, vamos pegar apenas o primeiro
pkg load signal % para usar downsample()
downsample_factor = 2;
x = downsample(x,downsample_factor);
min_x=3200;% esse algoritmo precisa que xN != 0
max_x=360000;
x = x(min_x:max_x);
x=single(x);% converte x para precisão simples
L=length(x);
y=zeros(1,L);
y=single(y);

disp('iniciando filtro');
tic;
for i=2:L
   y(i)=(x(i-1)-y(i-1))/2; 
end
toc;
disp('filtro concluído');

##stem(x(1:L))
##hold on
##stem(y(1:L))
##legend('x','y')

%ESCRITA DE ARQUIVO
disp('Gerando string.');

convertidos=toupper(num2hex(single(x)));% string a ser impressa
s=blanks(9*L);
for i=1:L
  s(9*i-8:9*i)=[convertidos(i,:) "\n"];
end

fname="C:/Users/renan/Documents/FPGA projects/processor_demo/simulation/modelsim/input_vectors.txt";
fid=fopen(fname,"w");
fprintf(fid,"%s",s);
fclose(fid);

disp('Pressione qualquer tecla para ler resultados calculados pelo circuito:');
kbhit();

fname="C:/Users/renan/Documents/FPGA projects/processor_demo/simulation/modelsim/output_vectors.txt";
fid=fopen(fname,"r");
[val]=textscan(fid,"%s");
fclose(fid);

val=val{1,1};
disp('val');
disp(val);

%ignorar os X até o primeiro 0000_0000 inclusive
count_invalid_outputs=0;
while(strcmp(char(val(count_invalid_outputs+1,1)), "00000000")==0)% o circuito inicia a saída com esse valor após reset
  count_invalid_outputs++;
endwhile
count_invalid_outputs++;% 00000000 também é inválida
val = val(count_invalid_outputs+1:end,1);

disp('Resutados lidos do circuito:');
results=hex2num(val,"single");
disp(results)
plot(results)
hold on
plot(y(2:length(results)+1))
legend('circuito','octave')

disp('Resultados calculados no octave:');
octave_result_string = toupper(num2hex(single(y(2:length(results)+1))))
disp(octave_result_string)

%como o testbench sempre abre o arquivo de saída no append_mode, preciso deletá-lo após usar
% se a linha abaixo estiver comentada, manualmente apagar o arquivo de saída do hardware antes de reiniciar o testbench
%delete(fname)

% imprime as divergências entre os resultados do hardware e do octave

s=blanks(18*length(results));
for i=1:length(results) % i+1: índice do y lido; y(1) sempre é zero
	if (strcmp(octave_result_string(i,:),char(val(i)))==0)
		s(18*i-17:18*i)=[octave_result_string(i,:) "," char(val(i)) "\n"]';
		disp(["Diferença octave - circuito na amostra " num2str(i) " é " num2str(results(i) - y(i+1)) " (" num2str((results(i) - y(i+1))*100/y(i+1)) "%)"])
	endif
end

fname="C:/Users/renan/Documents/FPGA projects/processor_demo/simulation/modelsim/relatório.txt";
fid=fopen(fname,"w");
fprintf(fid,"%s",s);
fclose(fid);