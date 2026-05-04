clear;
close all
clc;
daqreset;

% specify output rate and duration
outputRate = 100; %[Hz]
outputDuration = 20; %[s]

% specify sine wave properties
amplitude = 0.2;
frequency = 1;

t = linspace(0,outputDuration,outputDuration*(outputRate))';
waveform = amplitude.*sin(frequency*2*pi().*t);

% show output wave form
figure();
plot(t,waveform);
xlabel('$t$ (s)','Interpreter','latex');
ylabel('volt (V)','Interpreter','latex');

% specify device name
% may need to change the number 00 within the bracket
DeviceName = 'DT9836(00)';
% analogue output channel id to add
aoChannelID = 0;

% create and configure data acquisition object
daqObj = daq('dt');
daqObj.Rate = outputRate;
addoutput(daqObj,DeviceName,aoChannelID,'Voltage');

disp('Generating sine wave');
% generate signal
write(daqObj,waveform);
delete(daqObj);