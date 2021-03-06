function [theta_new, beta_new, z_mode, subICmean, subICvar, grpICmean, grpICvar, error] = UpdateThetaBetaAprx (Y, X_mtx, theta, C_matrix_diag, beta, N, T, q, p, m, V)
%[theta_new, beta_new] = UpdateThetaBeta (Y, X_mtx, theta, beta, N, T, q, p, m, V)
% After preprocessing, T=q 
% Y           :  Y(:,V)  individual i scan time T at voxel v,      TN*V
% X_mtx       :  X(i,k)  predictor k for individual i,             p*N
% beta        :  beta (k, l, v)  coefficients at voxel v,          p*q*V
% C_matrix_diag: diagnal elements of C_matrix

% miu_svi     :  E(si(v) | Y(v), theta)                            q*1*N
% miu_sv      :  E(s(v)  | Y(v), theta)                            q*1
% miu_svi_sviT:  E(si(v)si(v)'| Y(v), theta)                       q*q*N
% miu_sv_svT  :  E(s(v)s(v)'  | Y(v), theta)                       q*q
% miu_sv_sviT :  E(s(v)si(v)' | Y(v), theta)                       q*q*N

% First calculate the conditional probability of ICs given the data and
% latent sorce state

error=0;
theta_new.A         = zeros(T, q, N);
theta_new.sigma1_sq = 0;

theta_new.sigma2_sq = zeros(q, 1);
theta_new.miu3      = zeros(m*q, 1);   %pi, miu3, sigma3 in the order of miul1,...,miulm, l=1:q
theta_new.sigma3_sq = zeros(m*q, 1);
theta_new.pi        = zeros(m*q, 1);

beta_new            = zeros(p, q, V);

A_ProdPart1         = zeros(T, q, N);  %first part of the product format for Ai
A_ProdPart2         = zeros(q, q, N);  %second part of the product format for Ai
sigma2_sq_all       = zeros(q, q);     %%% record all second level variance-covariance

z_mode = zeros(V, 1);

X  = reshape(X_mtx, N*p, 1); %reshape by column
sumXiXiT_inv  = eye(p)/(X_mtx*X_mtx');

         subICmean = zeros(q, N, V);
         subICvar = zeros(q, q, N, V);
         grpICmean = zeros(q, V);
         grpICvar = zeros(q, q, V);

A   = zeros(N*T, N*q) ;
C_inv = zeros(T, N);
for i = 1:N
    A( (i-1)*T+1:(i-1)*T+T , (i-1)*q+1:(i-1)*q+q) = theta.A(:,:,i);
    C_inv(:,i) = 1./C_matrix_diag((T*i-T+1):T*i) ;
end;

B   =   kron(ones(N, 1), eye(q)); 
W2  =   [A, A*B];
P   =   [ eye(N*q) , B; zeros(q, N*q), eye(q) ];
Sigma1   =   diag(C_matrix_diag.*theta.sigma1_sq);
Sigma1_inv = diag(1./diag(Sigma1));     
Sigma2   =   kron(eye(N), diag(theta.sigma2_sq));
Sigma_gamma0  =   W2' * Sigma1_inv * W2 ;

%%%%% dictionary for the z(v) s 
%%%%% apprximateion: only consider 
z_dict = [2*ones(q)-eye(q), 2*ones(q, 1)];
G_z_dict = zeros(q, m*q, q+1);
for i = 1:(q+1);
    G_z_dict(:,:,i) = G_zv_gen(z_dict(:,i), m, q);
end
mvn_mean  = zeros(1, N*T);
%%%flag = 0;
VoxelIC = zeros(V, 1);

        miu_sv_all_condz     = zeros( (N+1)*q,   1,     q+1 );
        miu_sv_svT_all_condz = zeros( (N+1)*q, (N+1)*q,  q+1 );
        
for v = 1:V
        beta_v = beta(:,:,v);
        %E-Step: generating all moments for updating 
        Y_v  = Y(:, v);        
        Beta_v_trans =    kron(eye(N), beta_v');
        %%%%% Save p^r
        Probzv       =   zeros(q+1, 1);
        %%%%% Save moments conditional on z_r
%         miu_sv_all_condz     = zeros( (N+1)*q,   1,     m^q );
%         miu_sv_svT_all_condz = zeros( (N+1)*q, (N+1)*q, m^q );
        
        
        for i = 1:(q+1)
            G_z = G_z_dict(:,:,i);
            miu3z = G_z*theta.miu3;
            miu_temp = B*miu3z + Beta_v_trans*X;
            Y_star   = Y_v - A*miu_temp;
            % Probzv(i)    = Cal_wtProbzv (Y_star, z, theta, N, T, q, m);     % P(z(v) = z | Y(v), theta)
            %%% Calculate weighted probability           
            Sigma3z  = diag(G_z * theta.sigma3_sq);
            Sigma23z = blkdiag(Sigma2, Sigma3z);             
            pi_z      = G_z * theta.pi;
            
            mvn_cov   = W2*Sigma23z*W2' + Sigma1;
            %%%------ Calculate weighted Probzv
            %%%% Probzv(i) = prod(pi_z) * 10^(N*q)* mvnpdf(Y_star',mvn_mean, mvn_cov) ; 
            %%%% Approximate the above probability by factorization
            Probzv(i) = prod(pi_z);
            Probzvmvn = zeros(N, 1);
            for j = 1:N
              Probzvmvn(j)  =  10^q * ...
                    mvnpdf ( Y_star( (q*j-q+1): q*j)', mvn_mean((q*j-q+1): q*j), mvn_cov((q*j-q+1): q*j, (q*j-q+1): q*j) );
            end
            Probzv(i) = Probzv(i)*prod(Probzvmvn);
            Sigma_gamma  = eye((N+1)*q)/(Sigma_gamma0 + diag(1./diag(Sigma23z)));
            miu_gamma    = Sigma_gamma*W2'*Sigma1_inv*Y_star;
            miu_star     = P * miu_gamma + [miu_temp; miu3z ];    
            Sigma_star   = P * Sigma_gamma * P';
            miu_sv_all_condz (:, :, i)     = miu_star;                          %store first order moments from this iteration
            miu_sv_svT_all_condz (:, :, i) = miu_star*miu_star'+Sigma_star;     %store second order moments from this interation
            %clear miu_star Sigma_star miu_gamma Sigma_gamma;
        end;
        %PostProbz    =  Probzv/sum(Probzv);  clear Probzv;
        [~, maxid] = max(Probzv); 
        VoxelIC(v) = maxid;        
        z_mode(v) =maxid;
        if( sum(isnan(Probzv)) >0 )    %%%%% Handling errors when evaluating mvnpdf
            disp('error in calculate Pr(z(v) | Y(v), theta) !');
            error = 1;
            return;
            %flag = flag + 1;
            %vnum(flag) = v;
        end;

        miu_sv_all     =  miu_sv_all_condz(:,:,maxid);
        miu_sv_svT_all =  miu_sv_svT_all_condz(:,:,maxid);
        
        
        miu_svi      = zeros(q, 1, N);   %first order moments of si(v) for each subject
        miu_svi_sviT = zeros(q, q, N);   %second order moments of si(v) for each subject
        miu_svi_svT  = zeros(q, q, N);   %interactions between si(v) and s(v)

        for i = 1: N
            miu_svi      (:, :, i) =  miu_sv_all( ((i-1)*q+1) : i*q , :);
            miu_svi_sviT (:, :, i) =  miu_sv_svT_all ( ((i-1)*q+1) : i*q , ((i-1)*q+1) : i*q );
            miu_svi_svT  (:, :, i) =  miu_sv_svT_all ( ((i-1)*q+1) : i*q , (N*q+1): (N+1)*q  );
        end;
        miu_sv         =  miu_sv_all     ( (N*q+1) : (N+1)*q , :);
        miu_sv_svT     =  miu_sv_svT_all ( (N*q+1) : (N+1)*q , (N*q+1): (N+1)*q );
        
        clear miu_sv_all miu_sv_svT_all;
         
         subICmean(:,:,v) = squeeze(miu_svi);
         subICvar(:,:,:,v) = miu_svi_sviT;
         grpICmean(:,v) = miu_sv;
         grpICvar(:,:,v) = miu_sv_svT;
         
         for i = 1:N
                   A_ProdPart1(:,:,i) = A_ProdPart1(:,:,i) + Y((T*i-T+1):T*i,v)*miu_svi(:,:,i)' ;
                   A_ProdPart2(:,:,i) = A_ProdPart2(:,:,i) + miu_svi_sviT(:,:,i) ;
                   beta_new(:,:,v)    = beta_new(:,:,v)    + X_mtx(:,i)*(miu_svi(:,:,i) - miu_sv)';
         end;
         %weighting \sum(XiXiT)^{-1}, similar to the design matrix
         %----------------------- Update beta at each voxel ----------------
         beta_new(:,:,v)    = sumXiXiT_inv * beta_new(:,:,v);  % new beta(v), coefficient matrix at voxel v
         
         %%% Update for sigma2 requires beta_new
         for i = 1:N
                   sigma2_sq_all       = sigma2_sq_all + miu_svi_sviT(:,:,i) + miu_sv_svT - 2*miu_svi_svT(:,:,i) ...
                                        + 2*(miu_sv - miu_svi(:,:,i)) * X_mtx(:,i)'*beta_new(:,:,v)...
                                        + beta_new(:,:,v)'*X_mtx(:,i) * X_mtx(:,i)'*beta_new(:,:,v) ;                    
         end;
         
end;
theta_new.sigma2_sq = 1/(N*V) * diag(sigma2_sq_all);                        % new sigma2_sq


for l = 1:q
    act = find(VoxelIC == l);
    nois = find(VoxelIC ~= l);
    theta_new.pi(1+(l-1)*m) =  (length(act)+1)/(length(nois)+length(act)+1); %%%%% in case no activation is identified
    theta_new.pi(2+(l-1)*m) =  length(nois)/(length(nois)+length(act)+1);
    theta_new.miu3(1+(l-1)*m) = mean(grpICmean(l, act));
    theta_new.miu3(2+(l-1)*m) = mean(grpICmean(l, nois));
    theta_new.sigma3_sq(1 +(l-1)*m) = mean(grpICvar(l,l,act));
    theta_new.sigma3_sq(2 +(l-1)*m) = mean(grpICvar(l,l,nois));
end
theta_new.sigma3_sq = theta_new.sigma3_sq - theta_new.miu3.^2;     % new sigma3

%%%% Handle NaN in previous iteration
nanid = find(isnan(theta_new.miu3));
if ~isempty(nanid)
    theta_new.sigma3_sq(nanid) = theta.sigma3_sq(nanid);
    theta_new.miu3(nanid) = theta.miu3(nanid);
end

for i = 1:N
    theta_new.A(:,:,i) = A_ProdPart1(:,:,i) * inv(A_ProdPart2(:,:,i));   %new Ai
     % Symmetric orthogonalization. 
    theta_new.A(:,:,i) = theta_new.A(:,:,i)*real(inv(theta_new.A(:,:,i)'*theta_new.A(:,:,i))^(1/2));
end;
for v=1:V
          for i = 1:N
              theta_new.sigma1_sq = theta_new.sigma1_sq + ...
                               Y((T*i-T+1):T*i,v)'*diag(C_inv(:,i))*Y((T*i-T+1):T*i,v)-...
                               2*Y((T*i-T+1):T*i,v)'*diag(C_inv(:,i))*theta_new.A(:,:,i) * subICmean(:,i,v)+ ...
                               trace( theta_new.A(:,:,i)'*diag(C_inv(:,i))* theta_new.A(:,:,i) * subICvar(:,:,i,v) );          
          end;
end
theta_new.sigma1_sq = 1/(N*T*V)*theta_new.sigma1_sq;
end  %%% end of function






