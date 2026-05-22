
% =========================================================================
%  Generate_Monochromatic.m
%  Generates a monochromatic wave profile and saves it for the wavemaker.
% =========================================================================
%
%  PURPOSE:
% create a .dat monochromatic waveform input for the wavemaker.
% tunable parameters : samplimg frequency, amplitude, frequency, signal
% duration, plots it and saves it using a filename like 
% mono_wave_DATE_AMPlitude_FREQ_SAMPLINGFREQ_DURation.dat

% =========================================================================
clear; clc; close all;

% save params
filepath = 'C:/Users/mbureau/OneDrive - The University of Melbourne/Desktop/SIWWI2026/wavemaker_codes/wave_inputs';
date_str = '060526'; 

% wave params
sf = 1000;         % Sampling frequency [Hz]
ff = 1.6667;            % Wave frequency [Hz]
cv = 1;            % conversion (1 = 'aa' is in Volts)
aa = 10;         % amplitude (V)
duration = 180;    % signal duration [s] 


ww = 2 * pi * ff;  % Angular frequency

% time vector
tt = (0 : 1/sf : duration)'; 

% sine wave 
yy = aa * sin(ww * tt);

% convert to voltage if input is in m
yv = cv * yy;

% Plot 
figure('Name', 'Monochromatic Wave');
plot(tt, yv);
title(sprintf('Sine Wave: %.1fHz, %.1fV (SF: %dHz)', ff, aa, sf));
xlabel('Time [s]');
ylabel('Wavemaker signal [V]');
grid on;

% format ; [time, voltage]
run_data = [tt, yv];

% save
if ~exist(filepath, 'dir')
    mkdir(filepath); 
end

% handle decimals (eg 4.5 -> 4p5)
amp_str = strrep(num2str(aa), '.', 'p');
ff_str = strrep(num2str(ff), '.', 'p');

% filename: mono_wave_DATE_AMPlitude_FREQ_SAMPLINGFREQ_DURation.dat
% example: mono_wave_130426_4v_1hz_1000sf_180s.dat
filename = sprintf('mono_wave_%s_%sv_%shz_%dsf_%ds.dat', ...
    date_str, amp_str, ff_str, sf, duration);

full_path = fullfile(filepath, filename);


save(full_path, 'run_data', '-ascii');

fprintf('Successfully saved as:\n%s\n', filename);
fprintf('Full path: %s\n', full_path);