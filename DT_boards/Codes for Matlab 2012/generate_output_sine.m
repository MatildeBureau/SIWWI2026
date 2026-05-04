% --- Setup Parameters ---
Fs = 1000;          % Sampling frequency (Hz)
duration = 10;      % How long to output (seconds)
freq = 1;           % Frequency of the sine wave (1 Hz)
amplitude = 2;      % Amplitude in Volts (Peak-to-peak will be 4V)

% --- 1. Create Output Object ---
ao = analogoutput('dtol', '0'); 

% --- 2. Add Output Channel ---
addchannel(ao, 0);  % This sends the signal to DAC 0

% --- 3. Generate the Sine Wave Signal ---
t = (0:1/Fs:duration)'; 
data = amplitude * sin(2 * pi * freq * t);

% --- 4. Queue and Start Output ---
set(ao, 'SampleRate', Fs);
putdata(ao, data);  % Load the wave into the box memory
fprintf('Outputting sine wave to DAC 0 for %d seconds...\n', duration);

start(ao);          % The box starts "playing" the wave
wait(ao, duration + 1); % Wait for it to finish

% --- 5. Cleanup  ---
delete(ao);
clear ao;
fprintf('Output finished and object cleared.\n');