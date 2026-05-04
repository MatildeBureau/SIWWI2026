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


% --- Rukai version, for Matlab > 2012. To use this, comment from  ai = analoginput('dtol', '0'); to delete(ai); ---
% daqObj = daq('dt');
% daqObj.Rate = samplingRate;
% addinput(daqObj, DeviceName, aiChannelID, 'Voltage');
% [data, t] = read(daqObj, ...);

% create and configure data acquisition object
% --- EDIT FOR R2012A - 2026 ---
ai = analoginput('dtol', '0');       % '0' is your InstalledBoardId from daqhwinfo
addchannel(ai, 0);                   % Adds channel 0
set(ai, 'SampleRate', samplingRate);
set(ai, 'SamplesPerTrigger', samplingRate * samplingTime);

start(ai);
[data, t] = getdata(ai);             % reads the data
delete(ai);                          % clean up the object

% show sampled voltage
figure();
plot(t,data);
xlabel('time (s)');
ylabel('volt (V)');
