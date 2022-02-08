%Objetivo: fazer um filtro cuja saída y para a excitação x seja igual a resposta desejada d (ou seja, descobrir o filtro u usado)
%x: input: input signal
%d: input: Resposta do filtro desconhecido à entrada x
%Pmax: input: número máximo -1 de coeficientes na porção feed forward
%Qmax: input: número máximo de coeficientes na porção feedback
%tol:input: erro percentual entre dois filtros consecutivos |h(n+1)-h(n)| / |h(n)|
%varargin: input: argumento opcional: valor fixo de step size
%y: output: saí­da do FA para entrada x (ao longo do processo de adaptação
%w: output: filtro obtido
%filters: output: filtros intermediários calculados
%err: output: erros em cada amostra
%step: output: step size em cada amostra
%n: output: número de iterações usadas

% último argumento pode ser um valor fixo de step
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
  
    yn = filter_mat(:,:,n)*xN.';% saí­da atual
    y(n) = yn; % adiciona a saída atual ao vetor de saídas
    % aproximação do erro: xN é aproximação do sinal completo
	  err(n) = d(n) - yn;
    
    delta_filter = 2*step(n)*err(n)*xN;% [alfa beta] approx xN: Feintuch's approximation
    filter_mat(:,:,n+1) = filter_mat(:,:,n) + delta_filter;
    %xN contém as últimas Pmax+1 entradas e Qmax saí­das
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
