% =========================================================================
% ICE DENSITY 
% =========================================================================
% PURPOSE:
%   Estimate the density of ice samples.
%   Each ice piece is weighed three times:
%     m1 : mass of the empty container + water 
%     m2 : mass of container + water + ice floating freely 
%     m3 : mass of container + water + ice fully submerged (ice pushed
%          below the surface so it displaces its full volume of water)
%
%   From these three measurements:
%     m_ice   = m2 - m1   : true mass of the ice piece (kg)
%     m_water = m3 - m1   : mass of water displaced by the ice = rho_w * V_ice (kg)
%
%   force balance gives :  rho_ice = rho_water * m_ice / m_water
%
% UNCERTAINTY:
%   - Measurement uncertainty: propagated from the 1 g scale resolution
%     (last-digit uncertainty = 1 g is fluctuating during some measurements).
%   - Statistical uncertainty: standard error of the mean (SEM) across
%     the N repeated measurements, using the unbiased (N-1) std estimator.
%   - Total uncertainty: both measurement and statistical
%     contributions.
% =========================================================================

% scale readings 

% m1: mass of container + water alone 
m1 = [1255, 1277, 1334, 1344, 1351, 1376, 1380, 1408, 1411, 1431, 1407, 1361] * 1e-3; % kg

% m2: mass of container + water + ice piece (ice floating)
%  m2-m1 gives the mass of the ice piece
m2 = [1405, 1441, 1439, 1478, 1443, 1540, 1490, 1493, 1537, 1565, 1623, 1517] * 1e-3; % kg

% m3: mass of container + water + ice piece fully submerged
%  m3-m1 gives the mass of water displaced = rho_w * V_ice
m3 = [1420, 1465, 1451, 1494, 1451, 1562, 1503, 1503, 1552, 1583, 1647, 1534] * 1e-3; % kg

% constants 

rho_w = 1000; % density of fresh water (kg/m3)

%  Derived quantities

m_ice   = m2 - m1;         
m_water = m3 - m1;              % mass of water displaced by each sample (kg) = rho_w * V_ice


rho_i = rho_w * m_ice ./ m_water; % density of each ice sample (kg/m3)

% mean and standard deviation

mean_rho = mean(rho_i);          % mean ice density across all samples (kg/m3)
std_rho  = std(rho_i, 0);        % std (kg/m3)

% Statistical uncertainty (standard error of the mean)

N   = length(rho_i);             % number of ice samples
sem = std_rho / sqrt(N);         % SEM: uncertainty on the estimated mean (kg/m3)

% measurement uncertainty  

u_scale  = 1e-3;                 % last-digit uncertainty of the scale: 1 g 
                                

u_m_diff = sqrt(2) * u_scale;   
                                  

%  propagating error
% through rho = rho_w * m_ice / m_water 
rel_u_rho  = sqrt((u_m_diff ./ m_ice).^2 + (u_m_diff ./ m_water).^2);

u_rho_inst = rho_i .* rel_u_rho; % absolute measurement uncertainty per sample (kg/m3)

mean_u_rho_inst = mean(u_rho_inst); % average measurement uncertainty across samples (kg/m3)

%  Total uncertainty 

u_tot = sqrt(mean_u_rho_inst^2 + sem^2); % total uncertainty on mean density (kg/m3)

% results 

fprintf('Mean density:             %.2f kg/m3\n', mean_rho);
fprintf('Statistical Uncertainty:  +/- %.2f kg/m3\n', sem);
fprintf('Measurement Uncertainty:  +/- %.2f kg/m3\n', mean_u_rho_inst);
fprintf('Total Uncertainty:        +/- %.2f kg/m3\n', u_tot);