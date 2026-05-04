clear;
close all
clc;
daqreset;

% specify sampling rate and time
samplingRate = 1000; %[Hz]
samplingTime = 5; %[s]

% specify device name
% may need to change the number 00 within the bracket
DeviceName = 'DT9836(00)';
% analogue input channel id to add
aiChannelID = 0;

% create and configure data acquisition object
daqObj = daq('dt');
daqObj.Rate = samplingRate;

% add analogue input channel
addinput(daqObj,DeviceName,aiChannelID,'Voltage');

disp('Sampling voltage');
% read data
[data,t] = read(daqObj,samplingRate*samplingTime,'OutputFormat','Matrix');

% show sampled voltage
figure();
plot(t,data);
xlabel('time (s)');
ylabel('volt (V)');
