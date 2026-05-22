clearvars; close all; clc;

% =========================================================================
%  Wavemaker / DAQ communication check
%  
% Checks that the analog voltage signal sent to the 
% wavemaker is being correctly transmitted by the Data Translation (DT) 
% DAQ hardware. Loads a pre-generated wave signal (.dat), sends it out 
% through an analog output channel, and simultaneously records the physical 
% output via an analog input channel. 
%
% Plots "Sent" signal against "Measured" 
% actual signal to confirm they are the same ( no sampling rate mismatches, 
% phase shifts, or amplitude distortions at hardware level).
% =========================================================================

%  Load wave file 
wave_file = input('Enter .dat file path: ', 's');
s = load(wave_file);
t = s(:,1); % time vector
y = s(:,2); % voltage/amplitude vector


t = double(t(:));
y = double(y(:));


%  hardware sampling rate based on data time steps
dt = mean(diff(t));
samplerate = round(1/dt);
fprintf('Detected samplerate: %.2f Hz\n', samplerate);

% check uniformity 
% DAQ requires uniform sampling rate. error 
% if time vector has irregular steps (prevent hardware glitches)
if max(abs(diff(t) - dt)) > 1e-6
    error('Time vector is not uniform, fix generation script');
end

% setup DAQ

dq = daq("dt");
% Channel 0 Out: sends signal to  wavemaker controller
addoutput(dq, "DT9836(00)", "0", "Voltage");

% Channel 0 In: reads actual pushed out voltage
addinput(dq, "DT9836(00)", "0", "Voltage");
dq.Rate = samplerate;

% input config

ch = dq.Channels(2);
ch.TerminalConfig = "SingleEnded"; % measure voltage // common ground
ch.Range = [-10 10]; % set expected voltage limits to +/- 10V

% run
disp('Running waveform...');
% simultaneously read/write
% 'data' will contain  timetable of the recorded input signal
data = readwrite(dq, y);

% plot
%  hardware output vs theoretical input
figure;
plot(seconds(data.Time), data.Variables, 'r'); % 
hold on;
plot(t, y, 'b--'); 
legend('Measured', 'Sent');
xlabel('Time (s)');
ylabel('Voltage (V)');
grid on;