%% =========================================================
%  window_sensitivity_analysis_v2.m
%
%  PURPOSE:
%    Assess the sensitivity of wave amplitude estimates (from acoustic
%    sensors) to the choice of temporal analysis window.
%    Automatically loops over ALL (ka_set, T_set) conditions found in
%    pairMeta.
%
%    Two analysis modes (selected via user_test_mode):
%
%    MODE A - Window LOCATION sensitivity
%      A fixed window length is applied at n_windows_location different
%      starting times (t_start values, linearly spaced). 
%
%    MODE B - Window LENGTH sensitivity
%      A fixed t_start is used; window length is swept from
%      win_length_min_s to win_length_max_s. 

%  OUTPUTS (written to externalDrivePath/):
%    WindowSensitivity_<mode>_<DATE>.csv   - one row per (sensor, window, condition)
%
%    For PLOT 1 (coloured by window length):
%      Plot1_byLength_ak<X>_<DATE>.pdf/png  - one figure per ka_set
%        Each figure: 1 row of subplots, one column per T_set
%
%    For PLOT 2 (coloured by window start time):
%      Plot2_byTstart_ak<X>_<DATE>.pdf/png  - one figure per ka_set
%        Each figure: 1 row of subplots, one column per T_set
%
%  REQUIRED EXTERNAL FUNCTIONS (same as MAIN_wm_postprocess_all.m):
%    wm_load_location_metadata   wm_load_calibration
%    wm_load_pair_metadata_v2    wm_select_files
%    wm_parse_filename           wm_read_signal
%    wm_lookup_metadata          wm_apply_calibration
%    wm_despike_v2               wm_fft_frequency
%    wm_filter_signal_v2         pick_col
%
%  by Matilde  - SIWWI 2026
% =========================================================

clear; clc; close all;


%% =========================================================
%  SECTION 1: USER CONFIGURATION
% =========================================================

% ---------------------------------------------------------
%  1a. ANALYSIS MODE
%  'location' : fixed window length, sweep t_start   (Mode A)
%  'length'   : fixed t_start, sweep window length   (Mode B)
% ---------------------------------------------------------
user_test_mode = 'length';   % 'location' or 'length'

% ---------------------------------------------------------
%  1b. MODE A - WINDOW LOCATION PARAMETERS
%  Applied only when user_test_mode = 'location'.
%  t_start is swept over n_windows_location linearly spaced
%  values between tstart_min_s and tstart_max_s [s].
%  The window length is fixed at win_fixed_length_s [s].
% ---------------------------------------------------------
win_fixed_length_s  = 10;    % [s]  fixed analysis window length
tstart_min_s        = 10;    % [s]  earliest window start
tstart_max_s        = 100;   % [s]  latest window start
n_windows_location  = 10;    % [-]  number of t_start values to sweep

% ---------------------------------------------------------
%  1c. MODE B - WINDOW LENGTH PARAMETERS
%  Applied only when user_test_mode = 'length'.
%  t_start is fixed; window length is swept from
%  win_length_min_s to win_length_max_s in steps of
%  win_length_step_s [s].
% ---------------------------------------------------------
tstart_fixed_s      = 40;    % [s]  fixed window start time
win_length_min_s    = 10;    % [s]  shortest window to test
win_length_max_s    = 80;   % [s]  longest window to test (inclusive)
win_length_step_s   = 10;    % [s]  step between window lengths

% ---------------------------------------------------------
%  1d. CONDITION MATCHING TOLERANCES
% ---------------------------------------------------------
freq_match_tol = 0.02;   % [Hz]  |f_parsed - f_target| threshold
volt_match_tol = 0.05;   % [V]   |V_parsed - V_target| threshold

% ---------------------------------------------------------
%  1e. FALLBACK SAMPLING FREQUENCY
% ---------------------------------------------------------
Fs_default = 100;   % [Hz]

% ---------------------------------------------------------
%  1f. DESPIKING (acoustic sensors)
% ---------------------------------------------------------
despike_enable = false;
despike_mode   = 'mad';
despike_win_s  = 5.0;   % [s]
despike_thresh = 3;      % [-] MAD multiplier

% ---------------------------------------------------------
%  1g. FILTERING
% ---------------------------------------------------------
filterEnable = true;
filterMode   = 'bandpass';
fc_lp        = 2.0;    % [Hz] used only when filterMode = 'lowpass'
bp_frac      = 1.2;    % [-]  bandpass half-bandwidth as fraction of f_meas
bp_order     = 4;      % [-]  Butterworth filter order
freqTol      = 0.10;   % [Hz] FFT peak search tolerance around target freq

% ---------------------------------------------------------
%  1h. HILBERT ENVELOPE SMOOTHING
% ---------------------------------------------------------
env_smooth_periods = 4;   % [-] smoothing window = this many wave periods

% ---------------------------------------------------------
%  1i. SENSOR TO SKIP
%  Sensor 5 (x ~ 7.80 m)
% ---------------------------------------------------------
skip_sensor5   = true;    % true = exclude Sensor 5
sensor5_loc_m  = 7.80;   % [m]
sensor5_tol_m  = 0.10;   % [m] position tolerance for exclusion

% ---------------------------------------------------------
%  1j. OUTPUT SETTINGS
% ---------------------------------------------------------
date_str          = '200526';
externalDrivePath = 'E:\SIWWI2026\200526\temporalwindow\';
save_csv          = true;
save_fig          = true;

% ---------------------------------------------------------
%  1k. PLOT AESTHETICS
% ---------------------------------------------------------
fs_axis_ticks    = 15;   % [pt] axis tick label size
fs_axis_labels   = 17;   % [pt] axis label size
fs_legend        = 13;   % [pt] legend text size
fs_subplot_title = 14;   % [pt] per-subplot T annotation
fs_row_title     = 15;   % [pt] per-row ka annotation (sgtitle)
lw_data          = 1.6;  % [-]  line/errorbar width
mk_size          = 9;    % [-]  marker size
cap_size         = 5;    % [-]  errorbar cap size
delta_x_m        = 0.05; % [m]  sensor x-position uncertainty


set(groot, 'defaultTextInterpreter',          'none');
set(groot, 'defaultAxesTickLabelInterpreter', 'none');
set(groot, 'defaultLegendInterpreter',        'none');


%% =========================================================
%  SECTION 2: BUILD WINDOW SWEEP VECTORS
% =========================================================

switch lower(user_test_mode)

    case 'location'
        % Mode A: sweep t_start at fixed window length
        t_start_vec    = linspace(tstart_min_s, tstart_max_s, n_windows_location);   % [s]
        win_length_vec = win_fixed_length_s * ones(1, n_windows_location);            % [s]
        n_windows      = n_windows_location;
        fprintf('[CONFIG] Mode A - WINDOW LOCATION sweep\n');
        fprintf('  Fixed length : %.1f s\n', win_fixed_length_s);
        fprintf('  t_start range: %.1f to %.1f s  (%d steps)\n', ...
            tstart_min_s, tstart_max_s, n_windows_location);

    case 'length'
        % Mode B: fix t_start, sweep window length
        win_length_vec = win_length_min_s : win_length_step_s : win_length_max_s;    % [s]
        t_start_vec    = tstart_fixed_s * ones(1, length(win_length_vec));           % [s]
        n_windows      = length(win_length_vec);
        fprintf('[CONFIG] Mode B - WINDOW LENGTH sweep\n');
        fprintf('  Fixed t_start: %.1f s\n', tstart_fixed_s);
        fprintf('  Length range : %.1f to %.1f s  (step %.1f s,  %d steps)\n', ...
            win_length_min_s, win_length_max_s, win_length_step_s, n_windows);

    otherwise
        error('user_test_mode must be ''location'' or ''length''. Got: ''%s''.', user_test_mode);
end
fprintf('  Total window cases per sensor: %d\n\n', n_windows);


%% =========================================================
%  SECTION 3: FILE & METADATA LOADING
% =========================================================
disp('======================================================');
disp('--- Section 3: File & Metadata Loading ---');
disp('======================================================');

fprintf('\n[STEP 1/4] Select the SENSOR PLACEMENT CSV\n');
locExpanded = wm_load_location_metadata();

fprintf('\n[STEP 2/4] Select the ACOUSTIC SENSOR CALIBRATION CSV\n');
calData = wm_load_calibration();

fprintf('\n[STEP 3/4] Select the EXPERIMENT PAIRING CSV\n');
pairMeta = wm_load_pair_metadata_v2();

fprintf('\n[STEP 4/4] Select ACOUSTIC DATA folder(s)\n');
allFiles = wm_select_files();
numFiles = length(allFiles);


%% =========================================================
%  SECTION 3b: EXTRACT ALL (ka_set, T_set) CONDITIONS FROM PAIRING CSV
% The main loop processes every acoustic file and
%  tags each result with the matching (ka_set, T_set).
% =========================================================
pVars = pairMeta.Properties.VariableNames;


col_ka = pick_col(pVars, {'ka', 'ka_set', 'steepness'});
col_f  = pick_col(pVars, {'Set_f_Hz', 'f_Hz', 'freq_Hz'});
col_v  = pick_col(pVars, {'Set_volt_V', 'volt_V', 'voltage_V'});

if isempty(col_ka) || isempty(col_f) || isempty(col_v)
    error('Could not find required columns (ka / f / volt) in pairMeta.\nColumns: %s', ...
        strjoin(pVars, ', '));
end

% Rename to canonical names for the rest of the script
pairMeta.Properties.VariableNames{strcmp(pairMeta.Properties.VariableNames, col_ka)} = 'ka';
pairMeta.Properties.VariableNames{strcmp(pairMeta.Properties.VariableNames, col_f)}  = 'Set_f_Hz';
pairMeta.Properties.VariableNames{strcmp(pairMeta.Properties.VariableNames, col_v)}  = 'Set_volt_V';

% Build unique (ka_set, T_set, V_set) triplets - one row per condition
% T_set = 1 / Set_f_Hz [s]
all_ka_pm   = pairMeta.ka;            % [-]
all_f_pm    = pairMeta.Set_f_Hz;      % [Hz]
all_T_pm    = 1 ./ all_f_pm;         % [s]
all_v_pm    = pairMeta.Set_volt_V;    % [V]

% Round to avoid floating-point duplicates (ka to 4 dp, T to 4 dp)
valid_pm = isfinite(all_ka_pm) & isfinite(all_f_pm) & isfinite(all_v_pm);
cond_mat  = unique([ ...
    round(all_ka_pm(valid_pm), 4), ...
    round(all_T_pm(valid_pm),  4), ...
    round(all_v_pm(valid_pm),  4)], 'rows');    % [nCond x 3]  (ka, T, V)

nCond = size(cond_mat, 1);
fprintf('\n[CONDITIONS] %d unique (ka_set, T_set, V_set) found in pairMeta:\n', nCond);
fprintf('   ka_set   T_set (s)   V_set (V)\n');
for iC = 1:nCond
    fprintf('   %.4f   %7.4f    %7.4f\n', cond_mat(iC,1), cond_mat(iC,2), cond_mat(iC,3));
end
fprintf('\n');


std_freqs = [0.71, 0.83, 1.00, 1.25, 1.67];   % [Hz]


%% =========================================================
%  SECTION 4: PRE-ALLOCATE RESULT STORAGE
% =========================================================

%  upper bound: all files x sensors per file x windows x conditions
maxRows = numFiles * 10 * n_windows * nCond;

out_sensor_loc_m  = NaN(maxRows, 1);   % [m]   sensor x-position along tank
out_sensor_id     = NaN(maxRows, 1);   % [-]   sensor identification number
out_tstart_s      = NaN(maxRows, 1);   % [s]   window start time
out_win_length_s  = NaN(maxRows, 1);   % [s]   window duration
out_amp_m         = NaN(maxRows, 1);   % [m]   mean Hilbert envelope amplitude
out_unc_amp_m     = NaN(maxRows, 1);   % [m]   std error of envelope mean
out_file          = strings(maxRows,1);% [-]   source CSV filename
out_win_index     = NaN(maxRows, 1);   % [-]   index in window sweep (1...n_windows)
out_ka_set        = NaN(maxRows, 1);   % [-]   set wave steepness tag
out_T_set_s       = NaN(maxRows, 1);   % [s]   set wave period tag

kOut = 1;   % running write index into result arrays


%% =========================================================
%  SECTION 5: MAIN PROCESSING LOOP
%
%  For each acoustic CSV:
%    5a. Parse filename tokens (mode, channel, date, V, f).
%    5b. Snap parsed frequency to the nearest standard value.
%    5c. Look up matching conditions in cond_mat.
%        A file can match MORE THAN ONE condition if it was
%        recorded at a voltage / frequency that appears in
%        multiple pairMeta rows (different ka at same f).
%        Each matching condition is processed independently.
%    5d. Read signal, look up placement metadata.
%    5e. Calibrate V->m, optional despike (once per file).
%    5f. Measure f_meas on a representative window for filter centring.
%    5g. Window sweep: extract segment, filter, envelope, store.
% =========================================================
disp('======================================================');
disp('--- Section 5: Main Processing Loop ---');
disp('======================================================');

hWait = waitbar(0, 'Processing files...');

for iFile = 1:numFiles

    try   % catch per-file errors so the loop continues

    if isgraphics(hWait)
        waitbar(iFile/numFiles, hWait, ...
            sprintf('Processing file %d / %d...', iFile, numFiles));
    end

    % ----------------------------------------------------------
    %  5a-5b. FILENAME PARSING AND FREQUENCY SNAPPING
    % ----------------------------------------------------------
    fileName = allFiles(iFile).name;
    fullPath = fullfile(allFiles(iFile).folder, fileName);

    [~, ~, fExt] = fileparts(fileName);
    if ~strcmpi(fExt, '.csv'); continue; end

    [fMode, fChannel, fDate, fAmp_raw, fFreq_raw, Fs, parseOK] = ...
        wm_parse_filename(fileName, Fs_default);
    if ~parseOK
        fprintf('  [SKIP] Parse failed: %s\n', fileName);
        continue;
    end

    % Snap frequency to the nearest standard value
    [~, min_f_idx] = min(abs(std_freqs - fFreq_raw));
    fFreq = fFreq_raw;
    if abs(std_freqs(min_f_idx) - fFreq_raw) < 0.05
        fFreq = std_freqs(min_f_idx);   % [Hz]
    end
    fAmp = fAmp_raw;   % [V]
    fT   = 1 / fFreq;  % [s] period corresponding to parsed frequency

    % ----------------------------------------------------------
    %  5c. FIND ALL MATCHING CONDITIONS IN cond_mat
    %  A file matches condition iC if its parsed (f, V) are within
    %  tolerance of the condition's (T->f, V).
    % ----------------------------------------------------------
    matched_cond_idx = [];
    for iC = 1:nCond
        ka_c  = cond_mat(iC, 1);   % [-]
        T_c   = cond_mat(iC, 2);   % [s]
        f_c   = 1 / T_c;           % [Hz]
        V_c   = cond_mat(iC, 3);   % [V]

        if abs(fFreq - f_c) < freq_match_tol && abs(fAmp - V_c) < volt_match_tol
            matched_cond_idx(end+1) = iC; %#ok<AGROW>
        end
    end

    if isempty(matched_cond_idx)
        % This file does not correspond to any condition in pairMeta
        continue;
    end

    fprintf('\nFILE: %s  | Mode=%s Ch=%d Date=%s A=%.3fV f=%.3fHz\n', ...
        fileName, fMode, fChannel, fDate, fAmp, fFreq);
    fprintf('  Matched %d condition(s).\n', length(matched_cond_idx));

    % ----------------------------------------------------------
    %  5d. SIGNAL READING AND PLACEMENT METADATA
    % ----------------------------------------------------------
    [t, rawMat, ~, readOK] = wm_read_signal(fullPath, Fs);
    if ~readOK
        fprintf('  [SKIP] Read failed.\n');
        continue;
    end
    Fs_t = 1 / mean(diff(t));   % [Hz] actual sample rate

    metaIdx = wm_lookup_metadata(locExpanded, fChannel, fDate);
    if isempty(metaIdx)
        fprintf('  [SKIP] No metadata: Ch=%d Date=%s\n', fChannel, fDate);
        continue;
    end

    % ----------------------------------------------------------
    %  5e-5g. SIGNAL PROCESSING (inner loops: column, metadata, condition)
    %
    %  Calibration, despiking, and f_meas detection are done ONCE
    %  per (column, metadata row) pair. Then the result is stored
    %  separately for each matched condition (they share the same
    %  physical signal but carry different ka_set / T_set tags).
    % ----------------------------------------------------------
    for c = 1:size(rawMat, 2)
    for m = 1:length(metaIdx)

        sensorID = locExpanded.SensorID(metaIdx(m));   % [-]
        xLoc     = locExpanded.x_m(metaIdx(m));        % [m]

        % Optionally skip Sensor 5 (reflection node)
        if skip_sensor5 && abs(xLoc - sensor5_loc_m) < sensor5_tol_m
            fprintf('  [SKIP S5] Sensor %d at x=%.2fm\n', sensorID, xLoc);
            continue;
        end

        % --- 5e. Voltage -> metres calibration ---
        [sig_cal, calOK] = wm_apply_calibration(rawMat(:,c), calData, sensorID, fMode);
        if ~calOK
            fprintf('  [SKIP] Calibration failed: S%d\n', sensorID);
            continue;
        end

        % --- 5f. Optional MAD despiking (applied once to full record) ---
        if despike_enable
            [sig_cal, ~] = wm_despike_v2(sig_cal, Fs_t, ...
                despike_win_s, despike_thresh, despike_mode);
        end

        % --- 5g. FFT frequency detection on a representative sub-window ---

        t_ref_start = min(t_start_vec);
        t_ref_end   = min(t_ref_start + max(win_length_vec), t(end));
        ref_mask    = (t >= t_ref_start) & (t <= t_ref_end);
        if sum(ref_mask) < 50
            ref_mask = true(size(t));   % fall back to full record
        end
        sig_ref = sig_cal(ref_mask) - mean(sig_cal(ref_mask));   % [m] zero-mean

        [fmeas_fft, ~, ~] = wm_fft_frequency(sig_ref, Fs_t, fFreq, freqTol);   % [Hz]
        if ~isfinite(fmeas_fft) || fmeas_fft <= 0
            fprintf('  [SKIP] FFT freq invalid for S%d.\n', sensorID);
            continue;
        end
        fprintf('  S%d (x=%.2fm): f_meas = %.4f Hz\n', sensorID, xLoc, fmeas_fft);

        % ==============================================================
        %  WINDOW SWEEP LOOP
        %  For each (t_start, win_length) pair, extract the segment,
        %  filter, compute envelope amplitude, and store one row per
        %  matched condition.
        % ==============================================================
        for iWin = 1:n_windows

            t_start_win = t_start_vec(iWin);           % [s]
            win_len     = win_length_vec(iWin);         % [s]
            t_end_win   = t_start_win + win_len;        % [s]

            % Guard: window must start before the record ends
            if t_start_win >= t(end)
                continue;
            end
            t_end_win = min(t_end_win, t(end));         % [s] clamp

            % Require at least 2 full wave periods inside the window
            if (t_end_win - t_start_win) < 2 / fmeas_fft
                continue;
            end

            % Extract windowed segment and zero-mean it
            win_mask = (t >= t_start_win) & (t <= t_end_win);
            sig_win  = sig_cal(win_mask) - mean(sig_cal(win_mask));   % [m]
            N_win    = length(sig_win);

            if N_win < 10; continue; end

            % Bandpass filter centred on f_meas
            % Pass band: [fmeas_fft / bp_frac,  fmeas_fft * bp_frac]
            if filterEnable
                sig_filt = wm_filter_signal_v2(sig_win, Fs_t, filterMode, ...
                    fc_lp, fmeas_fft, bp_frac, bp_order, fileName);
            else
                sig_filt = sig_win;
            end

            % Hilbert envelope -> smoothed -> mean amplitude
            env_raw    = abs(hilbert(sig_filt));   % [m]
            sw         = max(1, round(env_smooth_periods * Fs_t / fmeas_fft));
            env_smooth = movmean(env_raw, sw);     % [m]
            ameas      = mean(env_smooth);         % [m] mean amplitude
            N_eff      = max(1, floor(N_win / sw));
            unc_amp    = std(env_smooth) / sqrt(N_eff);   % [m] std error


            for iMC = 1:length(matched_cond_idx)
                iC = matched_cond_idx(iMC);

                out_sensor_loc_m(kOut) = xLoc;              % [m]
                out_sensor_id(kOut)    = sensorID;           % [-]
                out_tstart_s(kOut)     = t_start_win;        % [s]
                out_win_length_s(kOut) = win_len;            % [s]
                out_amp_m(kOut)        = ameas;              % [m]
                out_unc_amp_m(kOut)    = unc_amp;            % [m]
                out_file(kOut)         = fileName;
                out_win_index(kOut)    = iWin;               % [-]
                out_ka_set(kOut)       = cond_mat(iC, 1);   % [-]
                out_T_set_s(kOut)      = cond_mat(iC, 2);   % [s]

                kOut = kOut + 1;
            end

        end % iWin

    end % m - metadata row
    end % c - signal column

    catch ME_loop
        fprintf(2, '\n>>> [ERROR file %d: %s]\n>>> %s  (line %d)\n', ...
            iFile, fileName, ME_loop.message, ME_loop.stack(1).line);
    end

end % iFile

close(hWait);

% Trim pre-allocated arrays to actual stored rows
n_rows = kOut - 1;
if n_rows == 0
    error('No results stored. Check that pairMeta conditions match the acoustic filenames.');
end

out_sensor_loc_m  = out_sensor_loc_m(1:n_rows);
out_sensor_id     = out_sensor_id(1:n_rows);
out_tstart_s      = out_tstart_s(1:n_rows);
out_win_length_s  = out_win_length_s(1:n_rows);
out_amp_m         = out_amp_m(1:n_rows);
out_unc_amp_m     = out_unc_amp_m(1:n_rows);
out_file          = out_file(1:n_rows);
out_win_index     = out_win_index(1:n_rows);
out_ka_set        = out_ka_set(1:n_rows);
out_T_set_s       = out_T_set_s(1:n_rows);

fprintf('\n[LOOP DONE] %d result rows stored.\n', n_rows);



%% =========================================================
%  SECTION 6: PLOTTING
% =========================================================
disp('======================================================');
disp('--- Section 6: Plotting  ---');
disp('======================================================');

% Unique values of the two sweep parameters present in results
unique_win_lengths = unique(out_win_length_s(~isnan(out_win_length_s)));   % [s]
unique_tstarts     = unique(out_tstart_s(~isnan(out_tstart_s)));           % [s]
n_lengths          = length(unique_win_lengths);
n_tstarts          = length(unique_tstarts);


cmap_length = jet(max(n_lengths, 2));   % [n_lengths x 3]

cmap_tstart = jet(max(n_tstarts, 2));      % [n_tstarts x 3]

% Unique ka_set values present in the results, sorted ascending
unique_ka = sort(unique(out_ka_set(~isnan(out_ka_set))), 'ascend');   % [-]

figHandles_p1   = {};
figBaseNames_p1 = {};
figHandles_p2   = {};
figBaseNames_p2 = {};

% Helper: float -> compact filename string (e.g. 0.07 -> '0p07')
val2str = @(v) strrep(sprintf('%.4g', v), '.', 'p');

% Square subplot aspect ratio: pbaspect([1 1 1]) makes axes box square.
sq_aspect = [1 1 1];


%% =========================================================
%  SECTION 6a: PLOT 1 - Amplitude vs position, colour = WINDOW LENGTH

% =========================================================
disp('--- Section 6a: Plot 1 (colour = window length) ---');
 
n_yticks_p1 = 6;   % [-]  number of y-ticks forced on every subplot
 
for iKA = 1:length(unique_ka)
    ka_tgt = unique_ka(iKA);   % [-]
 
    mask_ka = abs(out_ka_set - ka_tgt) < 1e-6;
    T_here  = sort(unique(out_T_set_s(mask_ka & ~isnan(out_T_set_s))), 'descend');   % [s]
    nT      = length(T_here);
 
    if nT == 0
        fprintf('  [SKIP Plot1] No data for ka=%.4f\n', ka_tgt);
        continue;
    end
 
    fprintf('\n[Plot1] ka=%.4f  T=[', ka_tgt);
    fprintf('%.3f ', T_here); fprintf('] s\n');
 
    ka_title_str = sprintf('$(ka)_{\\rm set} = %.2f$', ka_tgt);
    ka_file_str  = sprintf('ak%s', val2str(ka_tgt));

    fig1_w = max(380 * nT + 120, 700);   % [px]
    fig1_h = 580;                          % [px]
 
    fig1_name = sprintf('Plot1_byLength_%s_%s', ka_file_str, date_str);
    fig1      = figure('Name', fig1_name, 'Position', [80, 80, fig1_w, fig1_h]);
 
    ax1_row = gobjects(1, nT);
 
 
    ax_leg1 = axes(fig1, 'Visible', 'off', 'Position', [0 0 0.001 0.001]);
    hold(ax_leg1, 'on');
    leg_handles1 = gobjects(n_lengths, 1);
    for iL = 1:n_lengths
        wlen   = unique_win_lengths(iL);   % [s]
        cColor = cmap_length(iL, :);
        leg_handles1(iL) = plot(ax_leg1, NaN, NaN, 'o', ...
            'Color',           cColor, ...
            'MarkerFaceColor', cColor, ...
            'MarkerSize',      mk_size, ...
            'LineWidth',       lw_data, ...
            'DisplayName',     sprintf('$%.0f$ s', wlen));
    end
 
    % ---- Draw subplots ----
    for iT = 1:nT
        T_tgt     = T_here(iT);   % [s]
        mask_cond = mask_ka & abs(out_T_set_s - T_tgt) < 1e-6;
 
        ax = subplot(1, nT, iT);
        ax1_row(iT) = ax;
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        pbaspect(ax, sq_aspect);   % square axes box
 
        for iL = 1:n_lengths
            wlen   = unique_win_lengths(iL);   % [s]
            cColor = cmap_length(iL, :);
 
            mask_L  = mask_cond & abs(out_win_length_s - wlen) < 1e-6;
            xlocs_L = out_sensor_loc_m(mask_L);
            amps_L  = out_amp_m(mask_L);
            uncs_L  = out_unc_amp_m(mask_L);
 
            if isempty(xlocs_L); continue; end
 
            [xlocs_L, si] = sort(xlocs_L);
            amps_L = amps_L(si);
            uncs_L = uncs_L(si);
 
            errorbar(ax, ...
                xlocs_L, amps_L, uncs_L, uncs_L, ...
                delta_x_m * ones(size(xlocs_L)), delta_x_m * ones(size(xlocs_L)), ...
                'o', ...
                'Color',            cColor, ...
                'MarkerFaceColor',  cColor, ...
                'MarkerSize',       mk_size, ...
                'LineWidth',        lw_data, ...
                'CapSize',          cap_size, ...
                'LineStyle',        'none', ...
                'HandleVisibility', 'off');
        end
 
        % T_set label
        text(ax, 0.5, 1.15, sprintf('$T_{\\rm set} = %.2f$ s', T_tgt), ...
            'Units',               'normalized', ...
            'Interpreter',         'latex', ...
            'FontSize',            fs_subplot_title, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'bottom');
 
        if iT == 1
            ylabel(ax, '$\bar{\eta}$ (m)', 'Interpreter', 'latex', 'FontSize', fs_axis_labels);
        else
            ylabel(ax, '');
            ax.YTickLabel = {};
        end
        xlabel(ax, '$x$ (m)', 'Interpreter', 'latex', 'FontSize', fs_axis_labels);
 
        ax.FontSize   = fs_axis_ticks;
        ax.LineWidth  = 1.2;
        ax.TickLength = [0.015 0.015];
    end
 
    % ---- Shared y-limits and forced 6-tick grid ----
    all_y1 = [];
    for iT = 1:nT
        yl = ylim(ax1_row(iT));
        all_y1 = [all_y1, yl]; %#ok<AGROW>
    end
    ymax1 = max(all_y1) * 1.12;
    ymin1 = max(0, min(all_y1) * 0.88);
    ytk1  = linspace(ymin1, ymax1, n_yticks_p1);
 
    for iT = 1:nT
        ylim(ax1_row(iT),  [ymin1, ymax1]);
        yticks(ax1_row(iT), ytk1);
        if iT > 1
            ax1_row(iT).YTickLabel = {};
        end
    end
 

    drawnow;
 
    legend_gap_p1 = 0.18;   
 
    if nT == 1
        % Single subplot: force a centred square position explicitly
        ax1_row(1).Position = [0.25, 0.35, 0.50, 0.50];
    else
        for iT = 1:nT
            p = ax1_row(iT).Position;
            new_bottom = p(2) + legend_gap_p1;
            new_height = p(4) - legend_gap_p1 * 0.5;
            new_left   = p(1) + 0.015;
            new_width  = p(3) - 0.015;
            if new_height > 0.05
                ax1_row(iT).Position = [new_left, new_bottom, new_width, new_height];
            end
        end
    end
 
    drawnow;
 
    % ---- ka_set annotation just above T titles ----

    ax_top   = ax1_row(1).Position(2) + ax1_row(1).Position(4);
    ka_y_ann = ax_top - 0.65;   % clamped: annotation y must be in [0,1]
 
    annotation(fig1, 'textbox', ...
        [0.0,  ka_y_ann,  1.0,  0.05], ...
        'String',              ka_title_str, ...
        'Interpreter',         'latex', ...
        'FontSize',            fs_row_title, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'middle', ...
        'EdgeColor',           'none', ...
        'FitBoxToText',        'off', ...
        'Margin',              0);
 
    % ---- Legend: 3 columns, centred below subplot row ----
    lgd1 = legend(ax_leg1, leg_handles1, ...
        'Interpreter', 'latex', ...
        'FontSize',    fs_legend, ...
        'Box',         'on', ...
        'NumColumns',  3, ...
        'Location',    'none');
    lgd1.Title.String   = 'Window length';
    lgd1.Title.FontSize = fs_legend;
 
    drawnow;
 
    lgd1.Units = 'normalized';
    lgd1_w = lgd1.Position(3);
    lgd1_h = lgd1.Position(4);
    ax_bot = ax1_row(1).Position(2);
 
    lgd1.Position(1) = 0.5 - lgd1_w / 2;     
    if nT == 1
        lgd1.Position(2) = 0.05;                
    else
        lgd1.Position(2) = ax_bot - lgd1_h;  
    end
 
    figHandles_p1{end+1}   = fig1;
    figBaseNames_p1{end+1} = fig1_name;
 
end % iKA - Plot 1
 

 

%% =========================================================
%  SECTION 6b: PLOT 2 - Amplitude vs position, colour = WINDOW START TIME
% =========================================================
disp('--- Section 6b: Plot 2 (colour = window start time) ---');
 
n_yticks_p2 = 6;   % [-]  number of y-ticks forced on every subplot
 
for iKA = 1:length(unique_ka)
    ka_tgt = unique_ka(iKA);
 
    mask_ka = abs(out_ka_set - ka_tgt) < 1e-6;
    T_here  = sort(unique(out_T_set_s(mask_ka & ~isnan(out_T_set_s))), 'descend');
    nT      = length(T_here);
 
    if nT == 0
        fprintf('  [SKIP Plot2] No data for ka=%.4f\n', ka_tgt);
        continue;
    end
 
    fprintf('\n[Plot2] ka=%.4f  T=[', ka_tgt);
    fprintf('%.3f ', T_here); fprintf('] s\n');
 
    ka_title_str = sprintf('$(ka)_{\\rm set} = %.2f$', ka_tgt);
    ka_file_str  = sprintf('ak%s', val2str(ka_tgt));

    fig2_w = max(380 * nT + 120, 700);   % [px] 
    fig2_h = 600;                        % [px]
 
    fig2_name = sprintf('Plot2_byTstart_%s_%s', ka_file_str, date_str);
    fig2      = figure('Name', fig2_name, 'Position', [120, 120, fig2_w, fig2_h]);
 
    ax2_row = gobjects(1, nT);
 
    ax_leg = axes(fig2, 'Visible', 'off', 'Position', [0 0 0.001 0.001]);
    hold(ax_leg, 'on');
    leg_handles = gobjects(n_tstarts, 1);
    for iTst = 1:n_tstarts
        tst    = unique_tstarts(iTst);
        cColor = cmap_tstart(iTst, :);
        leg_handles(iTst) = plot(ax_leg, NaN, NaN, 'o', ...
            'Color',           cColor, ...
            'MarkerFaceColor', cColor, ...
            'MarkerSize',      mk_size, ...
            'LineWidth',       lw_data, ...
            'DisplayName',     sprintf('$t_s = %.1f$ s', tst));
    end
 
    % ---- Draw subplots ----
    for iT = 1:nT
        T_tgt     = T_here(iT);
        mask_cond = mask_ka & abs(out_T_set_s - T_tgt) < 1e-6;
 
        ax = subplot(1, nT, iT);
        ax2_row(iT) = ax;
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        pbaspect(ax, sq_aspect);
 
        for iTst = 1:n_tstarts
            tst    = unique_tstarts(iTst);
            cColor = cmap_tstart(iTst, :);
 
            mask_T  = mask_cond & abs(out_tstart_s - tst) < 1e-6;
            xlocs_T = out_sensor_loc_m(mask_T);
            amps_T  = out_amp_m(mask_T);
            uncs_T  = out_unc_amp_m(mask_T);
 
            if isempty(xlocs_T); continue; end
 
            [xlocs_T, si] = sort(xlocs_T);
            amps_T = amps_T(si);
            uncs_T = uncs_T(si);
 
            errorbar(ax, ...
                xlocs_T, amps_T, uncs_T, uncs_T, ...
                delta_x_m * ones(size(xlocs_T)), delta_x_m * ones(size(xlocs_T)), ...
                'o', ...
                'Color',            cColor, ...
                'MarkerFaceColor',  cColor, ...
                'MarkerSize',       mk_size, ...
                'LineWidth',        lw_data, ...
                'CapSize',          cap_size, ...
                'LineStyle',        'none', ...
                'HandleVisibility', 'off');
        end
 
        % T_set label:
        text(ax, 0.5, 1.15, sprintf('$T_{\\rm set} = %.2f$ s', T_tgt), ...
            'Units',               'normalized', ...
            'Interpreter',         'latex', ...
            'FontSize',            fs_subplot_title, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'bottom');
 
        if iT == 1
            ylabel(ax, '$\bar{\eta}$ (m)', 'Interpreter', 'latex', 'FontSize', fs_axis_labels);
        else
            ylabel(ax, '');
            ax.YTickLabel = {};
        end
        xlabel(ax, '$x$ (m)', 'Interpreter', 'latex', 'FontSize', fs_axis_labels);
 
        ax.FontSize   = fs_axis_ticks;
        ax.LineWidth  = 1.2;
        ax.TickLength = [0.015 0.015];
    end
 
    % ---- Shared y-limits and forced 6-tick grid ----
    all_y2 = [];
    for iT = 1:nT
        yl = ylim(ax2_row(iT));
        all_y2 = [all_y2, yl]; %#ok<AGROW>
    end
    ymax2 = max(all_y2) * 1.12;
    ymin2 = max(0, min(all_y2) * 0.88);
    ytk2  = linspace(ymin2, ymax2, n_yticks_p2);
 
    for iT = 1:nT
        ylim(ax2_row(iT),  [ymin2, ymax2]);
        yticks(ax2_row(iT), ytk2);
        if iT > 1
            ax2_row(iT).YTickLabel = {};
        end
    end
 
    % ---- Reposition subplot row ----
    drawnow;
    
    if nT == 1
   
        ax2_row(1).Position = [0.25, 0.35, 0.50, 0.50];
    else
       
        legend_gap_norm = 0.18;   
        for iT = 1:nT
            p = ax2_row(iT).Position;   
            new_bottom = p(2) + legend_gap_norm;
            new_height = p(4) - legend_gap_norm * 0.5;   
   
            new_left   = p(1) + 0.015; 
            new_width  = p(3) - 0.015;

            if new_height > 0.05
                ax2_row(iT).Position = [new_left, new_bottom, new_width, new_height];
            end
        end
    end
 
    drawnow;   
 
    % ---- ka_set label  ----
    ax_bot = ax2_row(1).Position(2); 
    ax_top = ax2_row(1).Position(2) + ax2_row(1).Position(4);
    
    if nT == 1
        % ak = 0.1
        annotation(fig2, 'textbox', ...
            [0.0,  ax_top + 0.005,  1.0,  0.08], ...  
            'String',              ka_title_str, ...
            'Interpreter',         'latex', ...
            'FontSize',            fs_row_title, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'EdgeColor',           'none', ...
            'FitBoxToText',        'off', ...
            'Margin',              0);
    else
        % multiple plots
        annotation(fig2, 'textbox', ...
            [0.0,  ax_bot ,  1.0,  0.05], ...  
            'String',              ka_title_str, ...
            'Interpreter',         'latex', ...
            'FontSize',            fs_row_title, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'EdgeColor',           'none', ...
            'FitBoxToText',        'off', ...
            'Margin',              0);
    end
 
 
    lgd2 = legend(ax_leg, leg_handles, ...
        'Interpreter', 'latex', ...
        'FontSize',    fs_legend, ...
        'Box',         'on', ...
        'NumColumns',  3, ...
        'Location',    'none');
    lgd2.Title.String   = '$t_s$ (s)';
    lgd2.Title.FontSize = fs_legend;
 
    drawnow;   
 
    lgd2.Units = 'normalized';
    lgd_w = lgd2.Position(3);
    lgd_h = lgd2.Position(4);
 

    lgd2.Position(1) = 0.5 - lgd_w / 2;        
    
    if nT == 1
 
        lgd2.Position(2) = 0.05;  
    else
      
        lgd2.Position(2) = ax_bot - 0.01 - lgd_h;  
    end
 
    figHandles_p2{end+1}   = fig2;
    figBaseNames_p2{end+1} = fig2_name;
 
end % iKA

%% =========================================================
%  SECTION 7: STATISTICS
%
%  For each unique (ka_set, T_set) condition, and for each
%  sensor location within that condition, compute:
%    - mean amplitude across the window sweep
%    - std deviation across the window sweep
%    - coefficient of variation CV = std/mean x 100 [%]
% =========================================================
disp('======================================================');
disp(['--- Section 7: Statistics (' upper(user_test_mode) ' sweep) ---']);
disp('======================================================');

unique_ka_stat = sort(unique(out_ka_set(~isnan(out_ka_set))), 'ascend');

for iKA = 1:length(unique_ka_stat)
    ka_s = unique_ka_stat(iKA);

    mask_ka_s = abs(out_ka_set - ka_s) < 1e-6;
    T_vals_s  = unique(out_T_set_s(mask_ka_s));
    T_vals_s  = sort(T_vals_s(~isnan(T_vals_s)), 'descend');

    for iT = 1:length(T_vals_s)
        T_s = T_vals_s(iT);

        fprintf('\n  *** (ka)set = %.4f  |  T_set = %.4f s  |  f_set = %.4f Hz ***\n', ...
            ka_s, T_s, 1/T_s);

        switch lower(user_test_mode)
            case 'location'
                sweep_label = sprintf('(window length fixed at %.1f s)', win_fixed_length_s);
            case 'length'
                sweep_label = sprintf('(t_start fixed at %.1f s)', tstart_fixed_s);
        end
        fprintf('  %s sweep  %s\n', upper(user_test_mode), sweep_label);
        fprintf('  %-12s %-12s %-16s %-16s %-16s\n', ...
            'Sensor ID', 'x_loc (m)', 'Mean Amp (m)', 'Std Dev (m)', 'CV (%)');
        fprintf('  %s\n', repmat('-', 1, 74));

        mask_cond_s = mask_ka_s & abs(out_T_set_s - T_s) < 1e-6;
        sIDs_s      = unique(out_sensor_id(mask_cond_s));
        sIDs_s      = sIDs_s(~isnan(sIDs_s));

        for iS = 1:length(sIDs_s)
            sID    = sIDs_s(iS);
            mask_S = mask_cond_s & (out_sensor_id == sID);

            x_loc    = mean(out_sensor_loc_m(mask_S));   % [m]
            amps_S   = out_amp_m(mask_S);                % [m]
            mean_amp = mean(amps_S, 'omitnan');           % [m]
            std_amp  = std(amps_S,  'omitnan');           % [m]
            cov_amp  = (std_amp / mean_amp) * 100;        % [%]

            fprintf('  %-12d %-12.2f %-16.6f %-16.6f %10.2f %%\n', ...
                sID, x_loc, mean_amp, std_amp, cov_amp);
        end
    end
end
fprintf('\n');


%% =========================================================
%  SECTION 8: SAVING
% =========================================================
disp('======================================================');
disp('--- Section 8: Saving ---');
disp('======================================================');

outputDir = externalDrivePath;
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
fprintf('Output directory: %s\n', outputDir);

% --------------------------------------------------------
%  8a. Save Plot 1 figures (coloured by window length)
% --------------------------------------------------------
if save_fig
    nSaved = 0; nFailed = 0;
    all_figs  = [figHandles_p1, figHandles_p2];
    all_names = [figBaseNames_p1, figBaseNames_p2];

    for k = 1:length(all_figs)
        fh = all_figs{k};
        if ~isgraphics(fh); continue; end
        baseName = all_names{k};
        try
            exportgraphics(fh, fullfile(outputDir, [baseName '.png']), 'Resolution', 300);
            exportgraphics(fh, fullfile(outputDir, [baseName '.pdf']), 'ContentType', 'vector');
            nSaved = nSaved + 1;
        catch ME_save
            fprintf('  [WARN] Could not save "%s": %s\n', baseName, ME_save.message);
            nFailed = nFailed + 1;
        end
    end
    fprintf('  Figures saved: %d  |  Failed: %d\n', nSaved, nFailed);
end

% --------------------------------------------------------
%  8b. Save results table (CSV)
%  One row per (sensor, window case, condition).
%  All quantities carry explicit units in column names.
% --------------------------------------------------------
if save_csv
    mode_tag     = upper(user_test_mode);   % 'LOCATION' or 'LENGTH'
    resultsTable = table( ...
        out_file, ...
        out_sensor_id, ...
        out_sensor_loc_m, ...
        out_ka_set, ...
        out_T_set_s, ...
        out_win_index, ...
        out_tstart_s, ...
        out_win_length_s, ...
        out_amp_m, ...
        out_unc_amp_m, ...
        'VariableNames', { ...
            'Source_File', ...
            'Sensor_ID', ...
            'Sensor_Location_m', ...      % [m]  x-position along tank
            'ka_set', ...                 % [-]  set wave steepness
            'T_set_s', ...                % [s]  set wave period
            'Window_Index', ...           % [-]  1 ... n_windows
            'Window_Start_s', ...         % [s]  window start time
            'Window_Length_s', ...        % [s]  window duration
            'Amplitude_m', ...            % [m]  mean Hilbert envelope amplitude
            'Amplitude_Unc_m' ...         % [m]  std error of envelope mean
        });

    csvName = sprintf('WindowSensitivity_%s_%s.csv', mode_tag, date_str);
    csvPath = fullfile(outputDir, csvName);
    writetable(resultsTable, csvPath);
    fprintf('  CSV saved: %s  (%d rows)\n', csvPath, height(resultsTable));
end

fprintf('\n=== window_sensitivity_analysis_v2.m finished ===\n');