clear;
close all
clc;
daqreset;

%Code ; takes input fro; sensors>DT>PC

% Rukai version, for Matlab > 2012.
% % specify output rate and duration
% outputRate = 100; %[Hz]
% outputDuration = 20; %[s]
% 
% % specify sine wave properties
% amplitude = 0.2;
% frequency = 1;
% 
% t = linspace(0,outputDuration,outputDuration*(outputRate))';
% waveform = amplitude.*sin(frequency*2*pi().*t);
% 
% % show output wave form
% figure();
% plot(t,waveform);
% xlabel('$t$ (s)','Interpreter','latex');
% ylabel('volt (V)','Interpreter','latex');
% 
% % specify device name
% % may need to change the number 00 within the bracket
% DeviceName = 'DT9836(00)';
% % analogue output channel id to add
% aoChannelID = 0;
% 
% % create and configure data acquisition object
% daqObj = daq('dt');
% daqObj.Rate = outputRate;
% addoutput(daqObj,DeviceName,aoChannelID,'Voltage');
% 
% disp('Generating sine wave');
% % generate signal
% write(daqObj,waveform);
% delete(daqObj);


% --- Setup Parameters ---
samplingRate = 1000; 
duration = 5; % seconds

% --- Use Legacy Commands ---
% 1. Create the object (dtol = adaptor name for Data Translation)
ai = analoginput('dtol', '0'); 

% 2. Add the channel (adjust '0' to the channel your sensor is on)
addchannel(ai, 0); 

% 3. Configure sampling
set(ai, 'SampleRate', samplingRate);
set(ai, 'SamplesPerTrigger', samplingRate * duration);

% 4. Start and Fetch Data
fprintf('Recording for %d seconds...\n', duration);
start(ai);
[data, t] = getdata(ai); 

% 5. Cleanup ( board will stay 'Busy' otherwise)
delete(ai);
clear ai;

% --- Plot Results ---
plot(t, data);
xlabel('Time (s)');
ylabel('Voltage (V)');
title('Wave Gauge Reading');
grid on;