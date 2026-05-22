% =========================================================================
%  Generate_Pierson_Moskowitz.m
%  Generates an irregular wave profile based on Pierson-Moskowitz spectrum
%  and saves it as an input for the wave maker.
% 
%  Tunable parameters : sampling frequency, peak frequency, significant 
%  wave height, signal duration.
%  Plots it and saves it using a filename like:
%  pm_wave_DATE_Hs_FREQ_SAMPLINGFREQ_DURation.dat

% author ; Matilde
% Based on definition by Passerotti et. al  - 2022
% =========================================================================
clear; clc; close all;

% --- SAVE PARAMS ---
filepath = 'C:/Users/mbureau/OneDrive - The University of Melbourne/Desktop/SIWWI2026/wavemaker_codes/wave_inputs';
date_str = '060526'; 

% --- WAVE PARAMS (Tunable, based on Passerotti et al. 2022) ---
sf = 1000;         % Sampling frequency [Hz] 
fp = 0.625;        % Peak wave frequency [Hz]
Hs = 0.06;         % Significant wave height [m] (Tests used 0.03, 0.06, 0.08)
duration = 1200;   % Signal duration [s] 
cv = 1;            % Conversion (1 = output is in Volts)
g = 9.81;          % Gravitational acceleration [m/s^2]

% --- GENERATE PM SPECTRUM ---
df = 1/duration;   % Frequency resolution
f = (df:df:sf/2)'; % Frequency vector up to Nyquist frequency

% PM spectrum shape
S0_shape = (g^2 ./ f.^5) .* exp(-1.25 .* (f ./ fp).^(-4));
S0_shape(isnan(S0_shape)) = 0; % safety check
 
% Scale spectrum to match target Significant Wave Height (Hs)
m0_target = (Hs / 4)^2;
m0_shape = sum(S0_shape .* df);
alpha_f = m0_target / m0_shape; 
S0 = alpha_f .* S0_shape;

% --- GENERATE TIME SERIES ---
sigma = sqrt(S0 .* df);
A = sigma .* sqrt(-2 .* log(rand(size(f)))); 
phase = rand(size(f)) * 2 * pi;
tt = (0 : 1/sf : duration)'; 

yy = zeros(size(tt));
freq_indices = find(S0 > max(S0)*1e-6); 
for idx = 1:length(freq_indices)
    i = freq_indices(idx);
    yy = yy + A(i) .* cos(2 * pi * f(i) * tt + phase(i)); 
end

yv = cv * yy;

% --- CALCULATE OUTPUT METRICS ---
m00 = sum(S0 .* df);            % Zero-th moment (Variance)
Hs0 = 4 * sqrt(m00);            % Realized Significant Wave Height
Tp0 = 1 / fp;                   % Peak Period
lp0 = g / (2 * pi * fp^2);      % Peak Wavelength (Deep water)
kp0 = (2 * pi) / lp0;           % Peak Wavenumber
steepness = (kp0 * Hs0) / 2;    % Steepness ka

% --- PLOT ---
figure('Name', 'Pierson-Moskowitz Wave', 'Position', [100, 100, 800, 600]);
subplot(2,1,1);
plot(f, S0, 'LineWidth', 1.5);
xlim([0 2]); 
title(sprintf('Target PM Spectrum: f_p = %.3f Hz, H_{s,0} = %.2f m', fp, Hs));
xlabel('Frequency [Hz]');
ylabel('Spectral Density [m^2/s]');
grid on;

subplot(2,1,2);
plot(tt, yv);
title(sprintf('Wavemaker signal (SF: %dHz)', sf));
xlabel('Time [s]');
ylabel('Wavemaker signal [V]');
grid on;

% --- SAVE ---
run_data = [tt, yv];
if ~exist(filepath, 'dir')
    mkdir(filepath); 
end
hs_str = strrep(num2str(Hs), '.', 'p');
fp_str = strrep(num2str(fp), '.', 'p');
filename = sprintf('pm_wave_%s_%sHs_%shz_%dsf_%ds.dat', ...
    date_str, hs_str, fp_str, sf, duration);
full_path = fullfile(filepath, filename);
save(full_path, 'run_data', '-ascii');

% --- FINAL CONSOLE PRINT ---
fprintf('\n================ WAVE PARAMETERS ================\n');
fprintf('Hs0 (Sig. Wave Height):    %.4f m\n', Hs0);
fprintf('alpha_f (Scaling Factor):  %.4e\n', alpha_f);
fprintf('Steepness (k*Hs0/2):       %.4f\n', steepness);
fprintf('lp0 (Peak Wavelength):     %.4f m\n', lp0);
fprintf('fp0 (Peak Frequency):      %.4f Hz\n', fp);
fprintf('Tp0 (Peak Period):         %.4f s\n', Tp0);
fprintf('m00 (Variance/Area):       %.4e m^2\n', m00);
fprintf('================================================\n');
fprintf('Successfully saved as: %s\n', filename);