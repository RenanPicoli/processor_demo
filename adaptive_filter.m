%Objetivo: fazer um filtro cuja sa�da y para a excita��o x seja igual a resposta desejada d (ou seja, descobrir o filtro u usado)
%x: input: input signal
%d: input: Resposta do filtro desconhecido � entrada x
%Pmax: input: n�mero m�ximo -1 de coeficientes na por��o feed forward
%Qmax: input: n�mero m�ximo de coeficientes na por��o feedback
%tol:input: erro percentual entre dois filtros consecutivos |h(n+1)-h(n)| / |h(n)|
%varargin: input: argumento opcional: valor fixo de step size
%y: output: sa��da do FA para entrada x (ao longo do processo de adapta��o
%w: output: filtro obtido
%filters: output: filtros intermedi�rios calculados
%err: output: erros em cada amostra
%step: output: step size em cada amostra
%n: output: n�mero de itera��es usadas

% �ltimo argumento pode ser um valor fixo de step
function [y,w,filters,err,step,n] = adaptive_filter(x,d,Pmax,Qmax,tol,varargin)
N=Pmax+Qmax+1;
L=length(x);
err=single(zeros(1,L));
y=single(zeros(1,L));
xN=single(zeros(1,N));% vector with last Pmax+1 inputs AND last Qmax outputs
filter_mat=single(zeros(1,N,L));
step=single(zeros(1,L));% this parameter is adjusted to accelerate convergence
if (nargin > 5)
  string = sprintf('Using input step=%d\n',varargin{1});
  disp(string);
end
    
% itera sobre as amostras
for n=1:L % cálculo de filtro em n+1 usando filtro em n
    %xN contém as últimas Pmax+1 entradas e Qmax saídas
    % atualiza com última entrada
    xN = [x(n) xN(1:Pmax) xN(Pmax+2:N)];
    if (nargin == 5)
      step(n)=min(1/(2*xN*xN.'),1e4);% this parameter is adjusted to accelerate convergence
    else
      step(n)=varargin{1};
    end
  
    %yn = filter_mat(:,:,n)*xN.';% saída atual
    % reproduzindo as operações acima na exata ordem realizada pelo filtro em hardware
    tmp_i=single(0);
    for i=Pmax:-1:0
      tmp_i = tmp_i + (filter_mat(:,:,n)(i+1)*xN(i+1));
    end
    tmp_j=single(filter_mat(:,:,n)(N)*xN(N));
    for j=Qmax-1:-1:1
      tmp_j = tmp_j + (filter_mat(:,:,n)(Pmax+j+1)*xN(Pmax+j+1));
    end
    tmp_j = tmp_j + tmp_i;
    yn=tmp_j;
    
    y(n) = yn; % adiciona a saída atual ao vetor de saídas
    % aproximação do erro: xN é aproximação do sinal completo
	  err(n) = d(n) - yn;
    
    delta_filter = ((2*step(n))*err(n))*xN;% [alfa beta] approx xN: Feintuch's approximation
    filter_mat(:,:,n+1) = filter_mat(:,:,n) + delta_filter;
    %xN contém as últimas Pmax+1 entradas e Qmax saídas
    % atualiza com a saída atual (será o y(n-1) da próxima iteração)
    xN = [xN(1:Pmax+1) yn xN(Pmax+2:N-1)];
    % testa se já convergiu
##    if(norm(delta_filter)/norm(filter_mat(:,:,n)) < tol)
##      if (norm(filter_mat(:,:,n))==0)
##        disp('Divisão por zero na iteração:');
##        n
##       end;
##      break;
##    end
    n=n+1;
end
n=n-1;

w=filter_mat(:,:,n);
%y=filter(w(1:Pmax+1),[1 -w(Pmax+2:end)],x);
filters = filter_mat;
end
