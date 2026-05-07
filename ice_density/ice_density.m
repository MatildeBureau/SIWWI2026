% Ice density analysis
% Translated from Python script by matilde (20/03/26)

%% Data
m1 = [1403, 1429, 1491, 1490, 1504, 1500, 1548, 1527, 1549, 1574] * 1e-3; % kg
m2 = [1555, 1548, 1645, 1652, 1619, 1606, 1662, 1610, 1682, 1639] * 1e-3; % kg
m3 = [1578, 1567, 1668, 1685, 1645, 1623, 1680, 1624, 1707, 1652] * 1e-3; % kg

%% Density
rho_w = 1000; % kg/m3
m_ice   = m2 - m1;
m_water = m3 - m1;

rho_i    = rho_w * m_ice ./ m_water;
mean_rho = mean(rho_i);
std_rho  = std(rho_i, 1); % flag=1 uses N (population std), matching numpy default

%% Statistical Uncertainty
N   = length(rho_i); % number of repetitions
sem = std_rho / sqrt(N);

%% Measurement Error
u_scale  = 1e-3;            % 1 g scale resolution / last-digit error (kg)
u_m_diff = sqrt(2) * u_scale; % propagated error for mass differences

%% Propagation Formula
rel_u_rho    = sqrt((u_m_diff ./ m_ice).^2 + (u_m_diff ./ m_water).^2);
u_rho_inst   = rho_i .* rel_u_rho;
mean_u_rho_inst = mean(u_rho_inst);

%% Total Error
u_tot = sqrt(mean_u_rho_inst^2 + sem^2);

%% Results
fprintf('Mean density:             %.2f kg/m3\n', mean_rho);
fprintf('Statistical Uncertainty:  +/- %.2f kg/m3\n', sem);
fprintf('Measurement Uncertainty:  +/- %.2f kg/m3\n', mean_u_rho_inst);
fprintf('Total Uncertainty:        +/- %.2f kg/m3\n', u_tot);
