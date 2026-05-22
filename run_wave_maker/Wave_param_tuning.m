%% =========================================================
%  Wave_param_tuning.m
%  Wave input tuning for ice/wave experiments.
%
%  PURPOSE:
%    Given a set of desired wave parameters, this script computes all
%    corresponding wave quantities needed to configure the wave maker or just 
% for information,
%    including:
%      - Angular frequency  omega  [rad/s]
%      - Wave frequency     f      [Hz]
%      - Wave period        T      [s]
%      - Wavenumber         k      [m^-1]  (from linear dispersion relation)
%      - Wavelength         lambda [m]
%      - Wave steepness     ka     [-]
%      - Wave amplitude     a      [m]
%      - Wave maker voltage V      [V]      (inverted from calibration fit)
%
%    Voltage is what i sent as an input to the wave maker.
%    It is derived by inverting the linear calibration fit at the
%    reference sensor location 
%  (I used x = 1 m, closest to the wave maker, but it can be tuned in this script):
%      a_meas [m] = Slope [m/V] * V_set [V] + Intercept [m]
%    =>  V_set [V] = (a_target [m] - Intercept) / Slope
%
%    The dispersion relation for linear gravity waves in finite depth h is:
%      omega^2 = g * k * tanh(k * h)
%    where g = 9.81 m/s^2 and h = tank water depth [m].
%    >> solved  iteratively (Newton-Raphson) with first guess from deep water.
%
%  INPUTS (flexible, two choices for each axis — asked at run time):
%    FREQUENCY AXIS — choose one of:
%      (a) Wave periods     T  [s]   — one or more, space-separated
%      (b) Wave frequencies f  [Hz]  — one or more, space-separated
%    AMPLITUDE AXIS — choose one of:
%      (a) Wave steepnesses ka [-]   — dimensionless,  a = ka / k
%      (b) Wave amplitudes  a  [m]   — wave amplitude (mean-to-crest
%      definition, not peak to peak)
%      (c) Wave maker voltages V [V] — converted to metres via calibration

%
%  Other inputs (user defined):
%    1. Water depth h [m]
%    2. Wave maker mode: LOW (Fs=50 Hz) or HIGH (Fs=100 Hz)
%
%  OUTPUT:
%    A formatted table printed to the console showing all combinations
%    of (T, ka) with their corresponding wave parameters and units.
%    Optionally saved as a CSV file.
%
%  CALIBRATION FILE:
%    Loaded automatically at the start. Format must match the output
%    of the main processing script (Calibration_Fits_Per_Location.csv).
%    The reference location used here is x = 1 m, nearest the wave maker - 
%    but is tunable.
%  DEPENDENCIES:
%    No toolboxes required.
%  by   Matilde
%  22/04/26 
% =========================================================

clc; clear; close all;



%% =========================================================
%  1: LOAD CALIBRATION DATA
%
%  The calibration file maps sensor voltage to physical wave
%  amplitude at each sensor location.
%
%  Here, uses the fit at x = 1 m (the sensor closest to the wave
%  maker) as the reference for setting wave maker voltages, but can be changed.
%
%  The calibration model is:
%    a_meas [m] = Slope [m/V] * V_set [V] + Intercept [m]
%  Inverted to get the required voltage:
%    V_set  [V] = (a_target [m] - Intercept [m]) / Slope [m/V]
% =========================================================

fprintf('--- 1: Loading Calibration File ---\n');

% Prompt user to locate the calibration CSV 
[calFileName, calFilePath] = uigetfile('*.csv', ...
    'Select Calibration_Fits_Per_Location.csv');

if isequal(calFileName, 0)
    error('No calibration file selected. Aborting.');
end

calData = readtable(fullfile(calFilePath, calFileName), ...
    'VariableNamingRule', 'preserve');

fprintf('Calibration file loaded: %s\n', calFileName);
fprintf('Columns found: %s\n\n', strjoin(calData.Properties.VariableNames, ' | '));


refLoc_m = 1.0;   % reference sensor x-position [m]

fprintf('Reference sensor location: x = %.1f m\n', refLoc_m);


%% =========================================================
%  2: USER INPUTS
%
%  2a. Water depth           — needed for the dispersion relation
%  2b. Wave maker mode       — LOW (50 Hz) or HIGH (100 Hz)
%                              determines which calibration row to use
%  2c. Frequency axis choice — period T [s]  OR  frequency f [Hz]
%  2d. Amplitude axis choice — steepness ka [-]  OR  amplitude a [m]
%                              OR  voltage V [V]
%
%  all combinations of the two input vectors are computed:
%    N frequency values × M amplitude values → N*M rows in the output table.
% =========================================================

fprintf('\n---2: User Inputs ---\n');

% ---------------------------------------------------------
%  2a. Water depth
% ---------------------------------------------------------
answer_depth = inputdlg( ...
    {'Enter tank water depth  h  [m]:'}, ...
    'Water Depth', 1, {'0.5'});

if isempty(answer_depth)
    error('Water depth not provided. Aborting.');
end

h = str2double(answer_depth{1});

if isnan(h) || h <= 0
    error('Invalid water depth: must be a positive number. Got: %s', answer_depth{1});
end
fprintf('Water depth: h = %.3f m\n', h);


% ---------------------------------------------------------
%  2b. Wave maker mode (LOW or HIGH)
%
%  This selects which row of the calibration table to use.
%  LOW  -> Fs = 50  Hz  
%  HIGH -> Fs = 100 Hz  
% ---------------------------------------------------------
modeChoice = questdlg( ...
    'Select wave maker operating mode:', ...
    'Wave Maker Mode', ...
    'LOW (50 Hz)', 'HIGH (100 Hz)', 'HIGH (100 Hz)');   % default = HIGH

if isempty(modeChoice)
    error('Mode not selected. Aborting.');
end

if contains(modeChoice, 'LOW')
    waveMode = 'LOW';
else
    waveMode = 'HIGH';
end
fprintf('Wave maker mode: %s\n', waveMode);


% ---------------------------------------------------------
%  2c. Frequency axis input: period T [s]  OR  frequency f [Hz]
%  Enter one or more values separated by spaces.
%  Example periods:     "1 1.5 2"
%  Example frequencies: "1 0.67 0.5"   
% ---------------------------------------------------------

freqAxisChoice = questdlg( ...
    'How do you want to specify the wave frequency axis?', ...
    'Frequency Input Type', ...
    'Periods T [s]', 'Frequencies f [Hz]', 'Periods T [s]');   % default = periods

if isempty(freqAxisChoice)
    error('Frequency axis type not selected. Aborting.');
end

if contains(freqAxisChoice, 'Period')
    % ---- USER PROVIDES PERIODS ----
    freqInputType = 'T';   % flag used in Section 4 logging

    answer_freq = inputdlg( ...
        {'Enter desired wave periods  T  [s]  (space-separated):'}, ...
        'Wave Periods', 1, {'1 1.5 2'});

    if isempty(answer_freq)
        error('Wave periods not provided. Aborting.');
    end

    T_input = str2num(answer_freq{1}); %#ok<ST2NM>  % str2num handles space-separated lists

    if isempty(T_input) || any(T_input <= 0)
        error('Invalid wave periods. Enter positive numbers separated by spaces.');
    end

    T_vec = T_input;                  % periods [s]  — used directly in Section 4
    fprintf('Wave periods requested: %s s\n', mat2str(T_vec));

else
    % ---- USER PROVIDES FREQUENCIES ----
    freqInputType = 'f';   % flag used in Section 4 logging

    answer_freq = inputdlg( ...
        {'Enter desired wave frequencies  f  [Hz]  (space-separated):'}, ...
        'Wave Frequencies', 1, {'1 0.67 0.5'});

    if isempty(answer_freq)
        error('Wave frequencies not provided. Aborting.');
    end

    f_input = str2num(answer_freq{1}); %#ok<ST2NM>

    if isempty(f_input) || any(f_input <= 0)
        error('Invalid wave frequencies. Enter positive numbers separated by spaces.');
    end

    % Convert immediately to periods — all downstream code uses T_vec
    T_vec = 1 ./ f_input;            % T = 1/f  [s]
    fprintf('Wave frequencies requested: %s Hz  (converted to periods: %s s)\n', ...
        mat2str(f_input), mat2str(round(T_vec, 4)));
end


% ---------------------------------------------------------
%  2d. Amplitude axis input: steepness ka [-], amplitude a [m], voltage V [V]
%
%    ka [-] : dimensionless wave steepness = k * a
%
%    a  [m] : physical wave amplitude (half-height, crest to mean level).
%
%    V  [V] : wave maker set voltage, as read from the controller.
%
%  Enter one or more values separated by spaces.
% ---------------------------------------------------------

ampAxisChoice = questdlg( ...
    'How do you want to specify the wave amplitude axis?', ...
    'Amplitude Input Type', ...
    'Steepness ka [-]', 'Amplitude a [m]', 'Voltage V [V]', 'Steepness ka [-]'); 

if isempty(ampAxisChoice)
    error('Amplitude axis type not selected. Aborting.');
end

% Store a short flag for use in Section 5 and in log messages
if     contains(ampAxisChoice, 'ka')
    ampInputType = 'ka';
elseif contains(ampAxisChoice, 'Amplitude')
    ampInputType = 'a';
else
    ampInputType = 'V';
end


switch ampInputType

    case 'ka'
        amp_prompt  = 'Enter desired wave steepnesses  ka  [-]  (space-separated):';
        amp_default = '0.05 0.10 0.20';
        amp_title   = 'Wave Steepnesses (ka)';

    case 'a'
        amp_prompt  = 'Enter desired wave amplitudes  a  [m]  (space-separated):';
        amp_default = '0.005 0.010 0.020';
        amp_title   = 'Wave Amplitudes (m)';

    case 'V'
        amp_prompt  = 'Enter desired wave maker voltages  V  [V]  (space-separated):';
        amp_default = '1 2 4';
        amp_title   = 'Wave Maker Voltages (V)';

end

answer_amp = inputdlg({amp_prompt}, amp_title, 1, {amp_default});

if isempty(answer_amp)
    error('Amplitude values not provided. Aborting.');
end

amp_input = str2num(answer_amp{1}); %#ok<ST2NM>

if isempty(amp_input) || any(amp_input <= 0)
    error('Invalid amplitude values. Enter positive numbers separated by spaces.');
end

fprintf('Amplitude input (%s): %s\n', ampInputType, mat2str(amp_input));


%% =========================================================
%  3: LOOK UP CALIBRATION COEFFICIENTS
%
%  Find the calibration row matching the reference location
%  x = 1 m and the selected wave maker mode.
%
%  The calibration gives us:
%    Slope     S  [m/V]  :  physical amplitude per unit voltage
%    Intercept b  [m]    :  amplitude at zero voltage (offset)
%
%  used later (Section 5) to convert target amplitude
%  a [m] into required wave maker set voltage V [V].
% =========================================================

fprintf('\n---  3: Extracting calibration coefficients ---\n');


% Match on both location (within 1 mm tolerance) and mode string
locTol   = 0.001;   % [m] tolerance for floating-point location comparison
calMatch = find( ...
    abs(calData.Sensor_Location_m - refLoc_m) < locTol & ...
    strcmpi(string(calData.Mode), waveMode) );

if isempty(calMatch)
    % List available locations so the user knows what is in the file
    fprintf('\nAvailable locations in calibration file:\n');
    disp(calData(:, {'Sensor_Location_m', 'Mode', 'Slope_m_per_V', 'R2'}));
    error('No calibration entry found for x = %.3f m in mode %s.\nCheck the calibration file.', ...
        refLoc_m, waveMode);
end

% Use the first match if multiple rows exist (should not happen)
calRow      = calMatch(1);
cal_slope   = calData.Slope_m_per_V(calRow);      % S  [m/V]
cal_icept   = calData.Intercept_m(calRow);         % b  [m]
cal_R2      = calData.R2(calRow);
cal_RMSE    = calData.RMSE_m(calRow);
cal_SensorN = calData.Sensor_Number(calRow);

fprintf('Calibration match found:\n');
fprintf('  Sensor #%d at x = %.1f m | Mode = %s\n', cal_SensorN, refLoc_m, waveMode);
fprintf('  Slope     S = %.6f m/V\n', cal_slope);
fprintf('  Intercept b = %.6f m\n',   cal_icept);
fprintf('  R2          = %.4f\n',     cal_R2);
fprintf('  RMSE        = %.6f m\n',   cal_RMSE);

% Warn if calibration quality is poor
if cal_R2 < 0.95
    warning('Calibration R2 = %.4f is below 0.95. Voltage estimates may be unreliable.', cal_R2);
end


%% =========================================================
% 4: DISPERSION RELATION 
%
%  For each requested wave period T, we solve the wave dispersion relation:
%
%    omega^2 = g * k * tanh(k * h)          ... (*)
%
%  where:
%    omega = 2*pi / T   [rad/s]  angular frequency 
%    g     = 9.81       [m/s^2]  gravity
%    k                  [rad/m]  wavenumber  (to solve for)
%    h                  [m]      water depth 
%    lambda = 2*pi / k  [m]      wavelength
%
%  NEWTON-RAPHSON METHOD:
%    We want the root of:  F(k) = omega^2 - g*k*tanh(k*h) = 0
%    Starting from an initial guess k0 (deep-water approximation):
%      k0 = omega^2 / g   (exact for h -> infinity)
%    Each iteration updates:
%      k_{n+1} = k_n - F(k_n) / F'(k_n)
%    where the derivative is:
%      F'(k) = -g * [tanh(k*h) + k*h / cosh^2(k*h)]
%    Convergence is typically reached in 5-10 iterations.
%
%  DEPTH REGIME CHECK (informational):
%    Deep water    : k*h > pi         (lambda < 2h)   tanh(kh) ≈ 1
%    Intermediate  : pi/10 < k*h < pi
%    Shallow water : k*h < pi/10      (lambda > 20h)  tanh(kh) ≈ kh
% =========================================================

fprintf('\n--- 4: Solving Dispersion Relation ---\n');

g        = 9.81;         % gravity [m/s^2]
tol_disp = 1e-10;        % convergence tolerance for Newton-Raphson
max_iter = 200;          % maximum Newton-Raphson iterations (safety cap)

% Pre-allocate arrays for dispersion results (one value per period)
nT       = length(T_vec);
k_vec    = NaN(1, nT);   % wavenumber     [rad/m]
lam_vec  = NaN(1, nT);   % wavelength     [m]
omega_vec= NaN(1, nT);   % angular freq   [rad/s]
f_vec_hz = NaN(1, nT);   % frequency      [Hz]
kh_vec   = NaN(1, nT);   % depth parameter kh [–]  (for regime info)

for iT = 1:nT
    T     = T_vec(iT);
    omega = 2 * pi / T;      % angular frequency [rad/s]
    f_hz  = 1 / T;           % linear frequency  [Hz]

    % --- Initial guess: deep-water wavenumber ---
    % In deep water tanh(kh) -> 1, so omega^2 = g*k gives k0 = omega^2/g.
    %  ok starting point for all depths.
    k = omega^2 / g;

    % --- Newton-Raphson iteration ---
    for iter = 1:max_iter
        th  = tanh(k * h);                              % tanh(kh)
        F   = omega^2 - g * k * th;                     % F(k)  — should -> 0
        dF  = -g * (th + k * h / cosh(k * h)^2);       % F'(k)

        k_new = k - F / dF;                            

        % Prevent k from going negative 
        if k_new <= 0
            k_new = k / 2;
        end

        % Check convergence
        if abs(k_new - k) < tol_disp
            k = k_new;
            break;
        end
        k = k_new;

        if iter == max_iter
            warning('Dispersion solver did not converge for T = %.3f s (kh = %.3f). Results may be inaccurate.', T, k*h);
        end
    end

    lambda = 2 * pi / k;   % wavelength [m]
    kh     = k * h;        % depth parameter

    % Report depth regime for user information
    if kh > pi
        regime = 'deep water (kh > pi)';
    elseif kh > pi/10
        regime = 'intermediate depth';
    else
        regime = 'shallow water (kh < pi/10)';
    end

    fprintf('  T = %.3f s (f = %.4f Hz) : omega = %.4f rad/s | k = %.4f rad/m | lambda = %.4f m | kh = %.4f [%s]\n', ...
        T, f_hz, omega, k, lambda, kh, regime);

    % Store results
    k_vec(iT)     = k;
    lam_vec(iT)   = lambda;
    omega_vec(iT) = omega;
    f_vec_hz(iT)  = f_hz;
    kh_vec(iT)    = kh;
end


%% =========================================================
%  4b: DISPERSION RELATION CHECK
%
%  Check pure gravity wave relation can be used, ie surface tension part 
% can be neglectd. Full relation is:
%
%    omega^2 = ( g*k  +  sigma/rho * k^3 ) * tanh(k*h)   ... (gravity + capillary)
%
%  where:
%    sigma [N/m]    : surface tension coefficient
%    rho   [kg/m^3] : water density
%    k     [rad/m]  : wavenumber
%
%  Capillary term negligible if:
%
%    (sigma/rho) * k^3  <<  g * k
%    (sigma/rho) * k^2  <<  g
%    k^2                <<  g*rho / sigma
%
%  The ratio printed is:
%    R = capillary term / gravity term = (sigma * k^2) / (rho * g)
%  Neglecting surface tension is justified when R << 1.
%    sigma = 0.074 N/m
%    rho   = 1000  kg/m^3
% =========================================================

fprintf('\n--- 4b: Dispersion relation check ---\n');

% --- Physical constants  ---
sigma_water = 0.074;    % surface tension coefficient [N/m]   (water-air, ~20 degC)
rho_water   = 1000;     % water density               [kg/m^3]

% --- Representative wavenumber: use the largest k from the user's inputs ---
% The capillary term scales as k^2, so the shortest wave (largest k) is the
% worst case. If surface tension is negligible there, it is negligible for all
% waves in the experiment.
k_check = max(k_vec);                            % worst-case wavenumber  [rad/m]
T_check = T_vec(k_vec == k_check);               % corresponding period   [s]
T_check = T_check(1);                            % take first if degenerate

% --- Compute the two terms of the dispersion relation (before tanh) ---
% Both are evaluated at k_check; tanh(k*h) cancels in the ratio so we drop it.
term_gravity   = g            * k_check;         % g * k         [rad^2/s^2 / m * m = rad^2/s^2]
term_capillary = (sigma_water / rho_water) * k_check^3;  % (sigma/rho) * k^3

R_cap = term_capillary / term_gravity;           % dimensionless ratio

% --- Equivalent capillary length scale  ---
% The capillary length lambda_c = sqrt(sigma / (rho*g)) is the length scale
% below which surface tension dominates over gravity.
% For water: lambda_c = sqrt(0.074 / (1000*9.81)) ≈ 2.7 mm
% Waves with lambda >> lambda_c are gravity-dominated.
lambda_c    = sqrt(sigma_water / (rho_water * g));   % capillary length [m]
lambda_check = 2 * pi / k_check;                     % wavelength at k_check [m]

% --- Print  ---
fprintf('\n');
fprintf('  +----------------------------------------------------------+\n');
fprintf('  |          DISPERSION RELATION CHECK                |\n');
fprintf('  +----------------------------------------------------------+\n');
fprintf('  Used:\n');
fprintf('    g     = %.2f  m/s^2    (gravity)\n',         g);
fprintf('    sigma = %.4f N/m      (water-air surface tension)\n', sigma_water);
fprintf('    rho   = %.0f  kg/m^3   (water density)\n',   rho_water);
fprintf('    h     = %.3f  m        (tank water depth, from user input)\n', h);
fprintf('\n');
fprintf('  Worst-case wavenumber :\n');
fprintf('    T_min    = %.4f s    =>  k_max = %.4f rad/m  |  lambda_min = %.4f m\n', ...
    T_check, k_check, lambda_check);
fprintf('\n');
fprintf('  Dispersion relation terms at k = k_max :\n');
fprintf('    Gravity term   :  g * k            = %.6f  rad^2/s^2\n', term_gravity);
fprintf('    Capillary term :  (sigma/rho) * k^3 = %.6f  rad^2/s^2\n', term_capillary);
fprintf('\n');
fprintf('  Ratio  R = capillary / gravity = (sigma * k^2) / (rho * g)\n');
fprintf('         R = %.2e\n', R_cap);
fprintf('\n');
fprintf('  Capillary length scale:  lambda_c = sqrt(sigma/(rho*g)) = %.4f m = %.2f mm\n', ...
    lambda_c, lambda_c * 1000);
fprintf('  Shortest wavelength in experiment:              lambda_min = %.4f m = %.2f mm\n', ...
    lambda_check, lambda_check * 1000);
fprintf('  lambda_min / lambda_c = %.1f   (want >> 1 for pure gravity waves)\n', ...
    lambda_check / lambda_c);
fprintf('\n');

% --- Print ---
if R_cap < 0.01
    fprintf('   R = %.2e << 1  =>  Surface tension is negligible, ok pure gravity disp rel (< 1%% of gravity term).\n', R_cap);
elseif R_cap < 0.05
    fprintf('  R = %.2e  =>  Surface tension small but non-trivial (~%.1f%% of gravity).\n', R_cap, R_cap*100);

else
    fprintf('  R = %.2e  =>  Surface tension is significant (%.1f%% of gravity term) > adjust wave rel ?.\n', R_cap, R_cap*100);

end

fprintf('  +----------------------------------------------------------+\n\n');


%% =========================================================
%  \5: COMPUTE ALL (frequency, amplitude) COMBINATIONS
%
%    STEP A — Resolve amplitude in metres [m]
%      ka input : a_m = ka / k          (steepness definition)
%      a  input : a_m = a               (already in metres, use directly)
%      V  input : a_m = Slope * V + Intercept   (calibration)
%
%    STEP B — Derive all remaining amplitude quantities
%      From a_m:   ka    = k  * a_m     (steepness)
%                  H_m   = 2  * a_m     (peak-to-trough wave height)
%                  V_set = (a_m - Intercept) / Slope   (calibration inverse)
%
%    STEP C — Flag any physically problematic cases:
%      BELOW_RESOLUTION — a_m below sensor accuracy threshold (0.001 m)
%      NEGATIVE_VOLTAGE — calibration inversion yields V < 0
%      V>10V            — unusually high voltage (check wave maker range)
%
%  Results are assembled row-by-row into arrays for Section 6.
% =========================================================

fprintf('\n---  5: Computing Wave Parameters ---\n');

% Physical constants / thresholds
amp_resolution_m = 0.001;   % sensor accuracy floor [m] (UltraLab datasheet)
V_max_warn       = 10.0;    % warn if required voltage exceeds this [V]


nT      = length(T_vec);   
nAmp    = length(amp_input);
nCombos = nT * nAmp;        % total (frequency × amplitude) combinations

% Pre-allocate output arrays — one row per combination
out_T       = NaN(nCombos, 1);   % wave period            [s]
out_f       = NaN(nCombos, 1);   % wave frequency         [Hz]
out_omega   = NaN(nCombos, 1);   % angular frequency      [rad/s]
out_k       = NaN(nCombos, 1);   % wavenumber             [rad/m]
out_lambda  = NaN(nCombos, 1);   % wavelength             [m]
out_kh      = NaN(nCombos, 1);   % depth parameter        [–]
out_ka      = NaN(nCombos, 1);   % wave steepness         [–]
out_a_m     = NaN(nCombos, 1);   % wave amplitude         [m]
out_H_m     = NaN(nCombos, 1);   % wave height (= 2a)     [m]
out_V_set   = NaN(nCombos, 1);   % wave maker set voltage [V]
out_flag    = strings(nCombos, 1); % warning flags (empty = OK)

row = 0;   

for iT = 1:nT
    T      = T_vec(iT);
    k      = k_vec(iT);
    lambda = lam_vec(iT);
    omega  = omega_vec(iT);
    f_hz   = f_vec_hz(iT);
    kh     = kh_vec(iT);

    for iA = 1:nAmp
        row = row + 1;

        % ----------------------------------------------------------
        %  STEP A: resolve amplitude in metres from the chosen input type
        % ----------------------------------------------------------
        switch ampInputType

            case 'ka'
                ka_in = amp_input(iA);
                a_m   = ka_in / k;

            case 'a'

                a_m   = amp_input(iA);

            case 'V'
                % Voltage given — apply calibration forward pass:
                %   a [m] = Slope [m/V] * V [V] + Intercept [m]
                % This is the same model used in the processing script.
                a_m   = cal_slope * amp_input(iA) + cal_icept;
                % Guard: calibration might give a slightly negative value
                % for very small voltages near the intercept — flag it.
                if a_m < 0
                    a_m = 0;   % clamp to zero; NEGATIVE_AMP flag added below
                end

        end % switch ampInputType

        % ----------------------------------------------------------
        %  STEP B: derive all other amplitude quantities from a_m
        % ----------------------------------------------------------
        ka    = k * a_m;                           % steepness  [-]
        H_m   = 2 * a_m;                           % wave height (peak-to-trough) [m]

        % Invert calibration to get the set voltage:
        %   V_set = (a [m] - Intercept [m]) / Slope [m/V]
        V_set = (a_m - cal_icept) / cal_slope;     % wave maker set voltage [V]

        % ----------------------------------------------------------
        %  STEP C: flag checks
        % ----------------------------------------------------------
        flags = {};

        if a_m < amp_resolution_m
            flags{end+1} = 'BELOW_RESOLUTION';   % too small to measure reliably
        end
 
        if V_set < 0
            flags{end+1} = 'NEGATIVE_VOLTAGE';    % calibration extrapolation issue
        end
        if V_set > V_max_warn
            flags{end+1} = sprintf('V>%.0fV', V_max_warn);
        end
        % Extra flag when voltage input produces a non-positive amplitude
        if strcmp(ampInputType, 'V') && (cal_slope * amp_input(iA) + cal_icept) < 0
            flags{end+1} = 'NEGATIVE_AMP';        % voltage below calibration range
        end

        flag_str = strjoin(flags, ' | ');

        % ----------------------------------------------------------
        %  Store row
        % ----------------------------------------------------------
        out_T(row)      = T;
        out_f(row)      = f_hz;
        out_omega(row)  = omega;
        out_k(row)      = k;
        out_lambda(row) = lambda;
        out_kh(row)     = kh;
        out_ka(row)     = ka;
        out_a_m(row)    = a_m;
        out_H_m(row)    = H_m;
        out_V_set(row)  = V_set;
        out_flag(row)   = flag_str;

    end 
end 


%% =========================================================
%  6: PRINT RESULTS TABLE
%  Columns printed (with units in the header):
%    T [s]        | Wave period
%    f [Hz]       | Wave frequency
%    omega [rad/s]| Angular frequency
%    k [rad/m]    | Wavenumber
%    lambda [m]   | Wavelength
%    kh [-]       | Relative depth (dispersion parameter)
%    ka [-]       | Wave steepness (input)
%    a [m]        | Wave amplitude (half height)
%    H [m]        | Wave height (= 2a, peak-to-trough)
%    V_set [V]    | Required wave maker voltage
%    Flags        | Warnings (empty = no issues)
% =========================================================

fprintf('\n');
fprintf('========================================================\n');
fprintf('   WAVE PARAMETER TABLE   (ref: x = %.1f m | mode: %s)\n', refLoc_m, waveMode);
fprintf('   Frequency input: %s  |  Amplitude input: %s\n', freqInputType, ampInputType);
fprintf('========================================================\n');

resultsTable = table( ...
    out_T,       out_f,     out_omega,   out_k,     out_lambda, ...
    out_kh,      out_ka,    out_a_m,     out_H_m,   out_V_set, ...
    out_flag, ...
    'VariableNames', { ...
        'T_s',  'f_Hz',  'omega_rad_s',  'k_rad_m',  'lambda_m', ...
        'kh',   'ka',    'a_m',          'H_m',       'V_set_V', ...
        'Flags' ...
    });

% Print a unit header row before the data
fprintf('\n');
fprintf('  %-8s %-8s %-12s %-10s %-10s %-8s %-8s %-10s %-10s %-10s  %s\n', ...
    'T [s]', 'f [Hz]', 'omega[r/s]', 'k [r/m]', 'lam [m]', ...
    'kh [-]', 'ka [-]', 'a [m]', 'H [m]', 'V_set [V]', 'Flags');
fprintf('  %s\n', repmat('-', 1, 108));

for r = 1:nCombos
    fprintf('  %-8.4f %-8.4f %-12.4f %-10.4f %-10.4f %-8.4f %-8.4f %-10.5f %-10.5f %-10.4f  %s\n', ...
        out_T(r),      out_f(r),     out_omega(r),  out_k(r),    out_lambda(r), ...
        out_kh(r),     out_ka(r),    out_a_m(r),    out_H_m(r),  out_V_set(r), ...
        out_flag(r));
end

fprintf('  %s\n', repmat('-', 1, 108));
fprintf('\n');
fprintf('  Calibration used: Sensor %d | x = %.1f m | Mode = %s\n', ...
    cal_SensorN, refLoc_m, waveMode);
fprintf('  Slope = %.6f m/V | Intercept = %.6f m | R2 = %.4f | RMSE = %.6f m\n', ...
    cal_slope, cal_icept, cal_R2, cal_RMSE);
fprintf('  Water depth: h = %.3f m | g = %.2f m/s^2\n', h, g);
fprintf('\n  FLAG LEGEND:\n');
fprintf('    BELOW_RESOLUTION  — a < %.4f m: amplitude below sensor accuracy threshold\n', amp_resolution_m);
fprintf('    NEGATIVE_VOLTAGE  — calibration inversion gives V < 0 (check calibration or ka)\n');
fprintf('    NEGATIVE_AMP      — voltage input converts to a <= 0 m (below calibration range)\n');
fprintf('    V>%.0fV            — voltage exceeds %.0f V: verify wave maker operating range\n', V_max_warn, V_max_warn);
fprintf('\n========================================================\n\n');


%% =========================================================
%  7: OPTIONAL CSV SAVE
% =========================================================

saveChoice = questdlg('Save results table as CSV?', ...
    'Save Results', 'Yes', 'No', 'No');

dateLabel = datetime('now', 'Format', 'ddMMyy');
datestr = char(dateLabel);   % e.g. '0

if strcmp(saveChoice, 'Yes')
    defaultName = sprintf('Waves_param_%s_%s.csv', waveMode, datestr);
    [saveName, savePath] = uiputfile('*.csv', 'Save Results CSV As', defaultName);

    if isequal(saveName, 0)
        fprintf('Save cancelled.\n');
    else
        fullSavePath = fullfile(savePath, saveName);
        writetable(resultsTable, fullSavePath);
        fprintf('Results saved to: %s\n', fullSavePath);
    end
end

fprintf('=== Done ===\n');