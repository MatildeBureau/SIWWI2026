% =========================================================================
%  RunWavemaker_CollectData_v2.m
% =========================================================================

clearvars; close all; clc;

fprintf('=========================================================\n');
fprintf('       WAVEMAKER & SENSOR DATA ACQUISITION SCRIPT        \n');
fprintf('=========================================================\n\n');

% =========================================================================
%  1: HARDWARE RESET
% =========================================================================
fprintf('--- 1: Hardware Reset ---\n');
daqreset;
pause(0.5);
fprintf('DAQ hardware reset complete.\n\n');

% =========================================================================
%  2: USER PARAMETERS
% =========================================================================
fprintf('--- 2: User Parameters ---\n');

wave_file = input('Enter .dat file path (sent wave): ', 's');

a_sent   = 8;
f_sent   = 1;
mode     = 'HIGH';
date_str = '280426';

save_results = true;

fprintf('Test parameters: mode=%s | a=%.4g V | f=%.4g Hz | date=%s\n\n', ...
    mode, a_sent, f_sent, date_str);

% =========================================================================
%  3: LOAD WAVE FILE
% =========================================================================
fprintf('--- 3: Loading Wave File ---\n');

s = load(wave_file);
t_out = double(s(:,1));
y_out = double(s(:,2));

dt_step    = mean(diff(t_out));
samplerate = round(1 / dt_step);

fprintf('Detected sample rate from file: %.2f Hz\n', samplerate);
fprintf('Acquisition duration (from file): %.2f s\n', t_out(end));

if max(abs(diff(t_out) - dt_step)) > 1e-6
    error('Time vector is not uniform → fix generation script');
end

fprintf('Time vector uniformity ; ok \n\n');

% =========================================================================
%  4: HARDWARE PRE-CHECK
% =========================================================================
fprintf('--- 4: Hardware Pre-Check ---\n');

DeviceName = 'DT9836(00)';

try
    devs = daqlist('dt');

    if isempty(devs)
        error(['No Data Translation devices detected.\n' ...
               'Check connection and drivers.\n']);
    end

    fprintf('\nConnected Data Translation devices:\n');
    disp(devs);

catch ME
    fprintf('\nERROR during pre-check: %s\n', ME.message);
    error('Hardware pre-check failed.');
end

% =========================================================================
% 5: LOAD SENSOR METADATA
% =========================================================================
fprintf('--- 5: Loading Sensor Metadata ---\n');

[metaFileName, metaFilePath] = uigetfile('*.csv', ...
    'Select Sensor Metadata CSV');

if isequal(metaFileName, 0)
    error('No metadata file selected.');
end

metaTable = readtable(fullfile(metaFilePath, metaFileName), ...
    'VariableNamingRule', 'preserve');

fprintf('Metadata file loaded: %s\n', metaFileName);
fprintf('Columns detected: %s\n', strjoin(metaTable.Properties.VariableNames, ' | '));

requiredCols = {'Sensor', 'Channel', 'x_m'};
for c = 1:length(requiredCols)
    if ~ismember(requiredCols{c}, metaTable.Properties.VariableNames)
        error('Missing column: %s', requiredCols{c});
    end
end

sensorNumbers = double(metaTable.Sensor);
channelIDs    = double(metaTable.Channel);
xLocations    = double(metaTable.x_m);
numChannels   = length(channelIDs);

fprintf('\nSensor mapping loaded (%d sensors):\n', numChannels);
fprintf('  %-10s %-15s %-15s\n', 'Sensor #', 'DAQ Channel', 'x in tank [m]');
fprintf('  %s\n', repmat('-', 1, 42));
for i = 1:numChannels
    fprintf('  %-10d %-15d %-15.3f\n', sensorNumbers(i), channelIDs(i), xLocations(i));
end
fprintf('\n');

% =========================================================================
%  6: DAQ CHANNEL SETUP (FIXED)
% =========================================================================
fprintf('---  6: DAQ Channel Setup ---\n');

try
    dq      = daq('dt');
    dq.Rate = samplerate;

    % --- Output ---
    addoutput(dq, DeviceName, '0', 'Voltage');
    fprintf('Output channel 0 added (wave maker drive signal).\n');

    % ===== FIX 1: SORT CHANNELS =====
    [channelIDs, sortIdx] = sort(channelIDs);
    sensorNumbers = sensorNumbers(sortIdx);
    xLocations    = xLocations(sortIdx);

    % ===== FIX 2: ADD FIRST, CONFIGURE AFTER =====
    %chList = [];
    chList = daq.dt.AnalogInputVoltageChannel.empty;

    for i = 1:numChannels
        chList(i) = addinput(dq, DeviceName, channelIDs(i), 'Voltage');
        fprintf('Input channel %d added  (Sensor %d | x = %.2f m)\n', ...
            channelIDs(i), sensorNumbers(i), xLocations(i));
    end

    % ===== FIX 3: CONFIGURE AFTER CREATION =====
    for i = 1:numChannels
        chList(i).TerminalConfig = 'SingleEnded';
        chList(i).Range          = [-10 10];
    end

catch ME
    fprintf('\nERROR during channel setup: %s\n', ME.message);
    error('DAQ channel setup failed.');
end

fprintf('Channel setup complete.\n\n');

% =========================================================================
%  7: ACQUISITION
% =========================================================================
fprintf('--- 7: Running Acquisition ---\n');

data = readwrite(dq, y_out);

fprintf('Acquisition complete.\n\n');

t_in = seconds(data.Time);
v_in = data.Variables;

% =========================================================================
%  8: PLOTTING
% =========================================================================
fprintf('--- 8: Plotting ---\n');

figure('Name', 'Acquisition Results', 'Color', 'w', 'Position', [100 100 800 800]);

subplot(numChannels + 1, 1, 1);
plot(t_out, y_out, 'k', 'LineWidth', 1.5);
ylabel('Wavemaker (V)');
title(sprintf('Acquisition — %s | A=%.4g V | f=%.4g Hz | mode=%s', ...
    date_str, a_sent, f_sent, mode));
grid on;
set(gca, 'XTickLabel', []);

for i = 1:numChannels
    subplot(numChannels + 1, 1, i + 1);
    plot(t_in, v_in(:, i), 'b');
    ylabel(sprintf('S%d x=%.2fm\n(V)', sensorNumbers(i), xLocations(i)));
    grid on;
    if i < numChannels
        set(gca, 'XTickLabel', []);
    end
end
xlabel('Time (s)');

fprintf('Plot generated.\n\n');

% =========================================================================
%  9: SAVE RESULTS
% =========================================================================
if save_results

    fprintf('--- 9: Saving Results ---\n');

    folder_name = sprintf('wm_test_results_%s', date_str);
    if ~exist(folder_name, 'dir')
        mkdir(folder_name);
    end

    amp_str  = strrep(num2str(a_sent), '.', 'p');
    freq_str = strrep(num2str(f_sent), '.', 'p');

    for i = 1:numChannels

        x_str = strrep(num2str(xLocations(i)), '.', 'p');

        filename = sprintf('%s/raw_data_%s_Sensor%d_x%sm_%s_a%s_f%s.csv', ...
            folder_name, mode, sensorNumbers(i), x_str, ...
            date_str, amp_str, freq_str);

        sensor_data = [t_in, v_in(:, i)];
        writematrix(sensor_data, filename);

        fprintf('Saved: %s\n', filename);
    end

    fprintf('\nAll %d sensor files saved.\n', numChannels);
end

fprintf('\n=========================================================\n');
fprintf('  Done.\n');
fprintf('=========================================================\n');

