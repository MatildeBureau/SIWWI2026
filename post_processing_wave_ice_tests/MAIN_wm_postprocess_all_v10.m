%% =========================================================
%  MAIN_wm_postprocess_all.m

%  Post processing SIWWI tests:
%  Acoustic sensors + side-camera time series
%
%  PURPOSE:
%    Reads raw acoustic sensor CSV files and pre-extracted camera
%    displacement time-series CSVs (from tank_process_sidecam_v8.m), 
%    estimates wave amplitude and frequency for every (sensor/camera, 
%    condition) pair, optionally normalises amplitudes against an 
%    open-water benchmark run, and produces diagnostic and final plots.
%
%  WORKFLOW:
%
%    PASS 1 — Open-water (benchmark) run
%      Set  benchmark_mode = true  (Section 1s).
%      Process the open-water acoustic + camera data normally.
%      The output Results_postprocess_all.csv is the benchmark file.
%      No normalisation is applied; hasBenchmark stays false.
%
%    PASS 2 — Ice (experimental) run
%      Set  benchmark_mode = false  (Section 1s).
%      Select the benchmark CSV produced in Pass 1 when prompted.
%      All amplitudes are normalised as  a / a0  before plotting,
%      where a0 is the matched open-water amplitude.
%
%  SIGNAL CHAIN (per acoustic file):
%    Raw CSV  →  voltage-to-metres calibration  →  optional despiking
%    →  steady-state window  →  FFT frequency detection
%    →  bandpass filter  →  Hilbert envelope  →  mean amplitude
%
%  SIGNAL CHAIN (per camera time-series):
%    Pre-extracted eta(t) CSV  →  time windowing  →  NaN removal
%    →  optional despiking  →  FFT frequency detection
%    →  bandpass filter  →  Hilbert envelope  →  mean amplitude
%    and  peak-to-trough half-range  →  both stored
%
%  OUTPUTS (written to results_postprocess_<DATE>/):
%    Results_postprocess_<DATE>.csv     — one row per measurement
%    Calibration_Fits_Per_Location.csv  — linear fit results (Plot 3)
%    Attenuation_Results.csv            — attenuation coefficients
%    PNG + PDF figures for every plot
%
%  REQUIRED EXTERNAL FUNCTIONS:
%    wm_load_location_metadata   wm_load_calibration
%    wm_load_pair_metadata_v2    wm_select_files
%    wm_parse_filename           wm_read_signal
%    wm_lookup_metadata          wm_apply_calibration
%    wm_despike_v2               wm_cam_despike
%    wm_fft_frequency            wm_filter_signal_v2
%    wm_estimate_amplitude       wm_cam_amplitude
%    wm_build_refAmp_from_benchmark   wm_get_ref_amp_numeric
%    wm_validate_benchmark_pairing    wm_compute_attenuation_weighted
%    wm_plot_debug_v2            wm_plot_fft_debug
%    wm_style_for_mode           pick_col

% NOTE: this script should definitely be split into a main loop part to
% 1/ process acoustic + cam raw files, export output csv and THEN 2/ load
% output csv and plot everything. Sorry I planned to split it safely but
% didn't in the end.
%
%  by Matilde
% =========================================================

clear; clc; close all;


%% =========================================================
%  SECTION 1: USER CONFIGURATION
% ---------------------------------------------------------
%  1a. SAVING FLAGS
% ---------------------------------------------------------
save_fig     = true;   % export all open figures to PNG + PDF?
save_results = false;   % write results and attenuation CSVs?

% ---------------------------------------------------------
%  1b. FALLBACK SAMPLING FREQUENCY
%  Used when the MODE token in the filename is unrecognised for acoustic sensors.
% ---------------------------------------------------------
Fs_default = 100;   % [Hz]

% ---------------------------------------------------------
%  1c. FILTERING — ACOUSTIC SENSORS
%  filterMode: 'bandpass' (recommended) or 'lowpass'
%  fc_lp    : low-pass cut-off, used only when filterMode='lowpass' [Hz]
%  bp_frac  : bandpass half-bandwidth as a fraction of the measured frequency
%  bp_order : Butterworth filter order [-]
% ---------------------------------------------------------
filterEnable = true;
filterMode   = 'bandpass';
fc_lp        = 2.0;    % [Hz] — used only for lowpass mode
bp_frac      = 1.2;    % [-]
bp_order     = 4;      % [-]

% ---------------------------------------------------------
%  1d. AMPLITUDE ESTIMATION METHOD
%  'envelope' : mean of the smoothed Hilbert envelope (primary)
%  'PT'       : half peak-to-trough range (used as secondary check)
% ---------------------------------------------------------
amplitudeMethod = 'envelope';

% ---------------------------------------------------------
%  1e. FFT PEAK SEARCH TOLERANCE
%  The dominant FFT peak is searched within ±freqTol of the set frequency.
% ---------------------------------------------------------
freqTol = 0.10;   % [Hz]

% ---------------------------------------------------------
%  1f. DATE STRING FOR OUTPUT FOLDER
%  Format: DDMMYY — used in the output directory name.
% ---------------------------------------------------------
date_str = '280426';

% ---------------------------------------------------------
%  1g. DESPIKING — ACOUSTIC SENSORS
%  despike_mode  : 'mad' (median absolute deviation) or 'absolute'
%  despike_win_s : rolling window length for the MAD filter [s]
%  despike_thresh: rejection threshold (MAD multiplier or absolute [m])
% ---------------------------------------------------------
despike_enable = false;
despike_mode   = 'mad';
despike_win_s  = 5.0;   % [s]
despike_thresh = 3;      % [-] (MAD multiplier)

% ---------------------------------------------------------
%  1h. STEADY-STATE WINDOW — ACOUSTIC SENSORS
%  Samples outside [t_start_sensors, t_end_sensors] are discarded
%  to exclude the transient start-up and any tail.
%  t_end_sensors = 0 means use the full record from t_start onward.
% ---------------------------------------------------------
t_start_sensors = 40;   % [s]
t_end_sensors   = 0;    % [s], 0 = end of record

% ---------------------------------------------------------
%  1i. HILBERT ENVELOPE SMOOTHING
%  The envelope is smoothed with a moving-mean window of
%  env_smooth_periods wave periods.
% ---------------------------------------------------------
env_smooth_periods = 4;   % [-] number of wave periods

% ---------------------------------------------------------
%  1j. SENSOR RESOLUTION THRESHOLD
%  Amplitude measurements below this value are treated as below the
%  sensor noise floor and plotted differently in the calibration plot.
% ---------------------------------------------------------
amp_resolution_m = 0.001;   % [m]

% ---------------------------------------------------------
%  1k. UNCERTAINTY SOURCES
%  delta_V_set : set-voltage uncertainty (resolution of the wavemaker
%                control interface, used as x-error on calibration plots)
%  delta_x_m   : sensor position uncertainty along the tank axis
% ---------------------------------------------------------
delta_V_set = 0.001;   % [V]
delta_x_m   = 0.05;    % [m]

% ---------------------------------------------------------
%  1l. PLOT FILTERING THRESHOLDS
%  n_freq_min      : minimum number of distinct frequencies required
%                    in a voltage group before Plot 7 draws that group
%  n_freq_required : exact number of frequencies required for Plot 8
%  n_amp_min       : minimum number of distinct amplitudes required
%                    in a frequency group for Plot 9
% ---------------------------------------------------------
n_freq_min      = 2;   % [-]
n_freq_required = 4;   % [-]
n_amp_min       = 2;   % [-]

% ---------------------------------------------------------
%  1m. DEBUG / PREVIEW MODE
%  debugEnable    : master switch — opens diagnostic figures per file
%  only_sensors   : preview acoustic signals only (no full main loop)
%  only_cam_water : preview camera signals only (no full main loop)
%  debugFileList  : whitelist of filenames; [] = all files
% ---------------------------------------------------------
debugEnable    = true;
only_sensors   = false;
only_cam_water = true;
debugFileList  = [];

% ---------------------------------------------------------
%  1n. CAMERA SIGNAL PROCESSING PARAMETERS
%  Mirror the acoustic filtering settings but tuned for
%  the camera frame rate.
% ---------------------------------------------------------
vid_filterEnable       = true;
vid_filterMode         = 'bandpass';
vid_fc_lp              = 2.0;    % [Hz] — used only for lowpass mode
vid_bp_frac            = 0.9;    % [-]
vid_bp_order           = 4;      % [-]
vid_env_smooth_periods = 4;      % [-] number of wave periods

% ---------------------------------------------------------
%  1o. PRIMARY CAMERA AMPLITUDE METHOD FOR SUMMARY PLOTS
%  Both PT and envelope are always computed and stored.
%  This switch selects which one is used in the summary plots.
%  'PT'       — peak-to-trough half-range
%  'envelope' — mean Hilbert envelope (recommended)
% ---------------------------------------------------------
cam_amp_method = 'envelope';

% ---------------------------------------------------------
%  1p. ICE FLEXURE ANALYSIS PARAMETERS
%  Used in Section 5c (Plot 10: I/Ibr vs wave steepness).
% ---------------------------------------------------------
g_gravity     = 9.81;    % [m s^-2] gravitational acceleration
water_depth_m = 0.3;     % [m]      still-water depth in tank
E_ice         = 2e9;     % [Pa]     Young's modulus of ice
h_ice         = 0.01;    % [m]      ice thickness
sigma_f_ice   = 1e5;     % [Pa]     flexural strength of ice
nu_ice        = 0.33;    % [-]      Poisson's ratio of ice
rho_ice       = 895;     % [kg m^-3] ice density
rho_water     = 1000;    % [kg m^-3] water density

% ---------------------------------------------------------
%  1q. CALIBRATION CURVE FITTING
%  skipCalib = true  : skip the linear fit in Plot 3 (saves time
%                      if calibration data are not being updated)
%  skipCalib = false : compute slope, intercept, R² for each sensor
%                      location and save to Calibration_Fits_Per_Location.csv
% ---------------------------------------------------------
skipCalib = true;

% ---------------------------------------------------------
%  1r. CAMERA DRIFT / SNR THRESHOLD
%  If std(raw signal) / std(filtered signal) > drift_snr_thresh,
%  the camera record is flagged as drift-dominated. Flagged records
%  are warned in the console but retained in the results unless
%  drop_flagged_data = true (Section 5 plotting block).
% ---------------------------------------------------------
drift_snr_thresh = 20;   % [-]

% ---------------------------------------------------------
%  1s. TWO-PASS MODE SWITCH
%
%  benchmark_mode = true
%    This IS the reference (open-water) run.
%    Section 2f is skipped — no normalisation is applied.
%    The output Results_postprocess_all.csv from this run
%    is used as the reference file in the next pass.
%
%  benchmark_mode = false
%    This is an ice (or any non-reference) run.
%    Section 2f prompts for the benchmark CSV produced in Pass 1.
%    Amplitudes are normalised as a / a0 before plotting.
% ---------------------------------------------------------
benchmark_mode = true;   % set true to skip normalisation (benchmark run)

% Apply plain-text rendering globally so underscores in filenames
% do not trigger LaTeX subscript interpretation in titles/labels.
set(groot, 'defaultTextInterpreter',          'none');
set(groot, 'defaultAxesTickLabelInterpreter', 'none');
set(groot, 'defaultLegendInterpreter',        'none');

% ---------------------------------------------------------
%  1t. CAMERA DESPIKING CONTROL
%
%  vid_despike_enable = true  applies wm_cam_despike to all camera
%  time series, UNLESS the video base name appears in vid_despike_skiplist.
%
%  vid_despike_mode    : 'mad' or 'absolute'
%  vid_despike_win_s   : rolling window length [s]
%  vid_despike_thresh  : threshold — [m] for absolute, multiplier for MAD
%
%  vid_despike_skiplist: cell array of video base names (no extension,
%  no path) that are exempted from despiking even when the master switch
%  is on. 
% ---------------------------------------------------------
vid_despike_enable   = false;
vid_despike_mode     = 'mad';       % 'mad' or 'absolute'
vid_despike_win_s    = 5.0;         % [s]
vid_despike_thresh   = 2.5;         % [-] for MAD, or [m] for absolute

% vid_despike_skiplist = { ...
%     '060526_x4p6_f0p71_ak0p06_nikon', ...
%     '060526_x9p4_f0p83_ak0p06_goproH6', ...
%     '280426_x3_f1_a1_nikon', ...
%     '280426_x3_f1_a2_nikon', ...
%     '280426_x3_f1_a3_nikon', ...
%     '280426_x3_f1_a3p5_nikon', ...
%     '280426_x3_f0p75_a4_nikon', ...
%     '280426_x3_f1_a4_nikon', ...
%     '280426_x3_f1p25_a4_nikon', ...
%     '280426_x3_f1p5_a4_nikon', ...
%     '280426_x3_f1_a5_nikon', ...
%     '280426_x3_f1_a5p5_nikon', ...
%     '280426_x3_f1_a6_nikon', ...
%     '280426_x3_f1_a7_nikon', ...
%     '280426_x3_f1_a8_nikon', ...
%     '280426_x9p4_f1_a1_nikon', ...
%     '280426_x9p4_f1_a2_nikon', ...
%     '280426_x9p4_f1_a3_nikon', ...
%     '280426_x9p4_f1_a3p5_nikon', ...
%     '280426_x9p4_f0p75_a4_nikon', ...
%     '280426_x9p4_f1_a4_nikon', ...
%     '280426_x9p4_f1p25_a4_nikon', ...
%     '280426_x9p4_f1p5_a4_nikon', ...
%     '280426_x9p4_f1_a5_nikon', ...
%     '280426_x9p4_f1_a5p5_nikon', ...
%     '280426_x9p4_f1_a6_nikon', ...
%     '280426_x9p4_f1_a7_nikon', ...
%     '280426_x9p4_f1_a8_nikon', ...
%     '130526_x4p6_f0p71_ak0p08_nikon', ...
%     '130526_x4p6_f1p67_ak0p03_nikon', ...
%     '130526_x9p4_f0p83_ak0p03_goproH6', ...
%     '130526_x9p4_f0p83_ak0p06_goproH6', ...
%     '130526_x4p6_f1_ak0p07_nikon', ...
%     '130526_x9p4_f1p67_ak0p07_goproH6', ...
%     '130526_x9p4_f1p25_ak0p08_goproH6', ...
%     '130526_x9p4_f1_ak0p07_goproH6', ...
%     '130526_x9p4_f0p71_ak0p06_goproH6', ...
%     '130526_x9p4_f0p83_ak0p08_goproH6', ...
%     '130526_x9p4_f0p71_ak0p08_goproH6', ...
%     '140526_x4p6_f0p71_ak0p1_nikon', ...
%     '140526_x4p6_f0p71_ak0p07_nikon', ...
%     '140526_x9p4_f0p71_ak0p1_goproH6', ...
%     '200526_x4p6_f1p25_ak0p05_nikon', ...
%     '_DSC7831', ...
%     '_DSC7832', ...
%     'GH012643', ...
%     'GH012644' ...
% };

vid_despike_skiplist = {};
%% =========================================================
%  SECTION 2: FILE & METADATA LOADING
%  Four sequential file-selection dialogs load all metadata
%  needed by the processing loop. 
% =========================================================
disp('======================================================');
disp('--- Section 2: File & Metadata Loading ---');
disp('======================================================');

fprintf('\n[STEP 1/4] Select the SENSOR PLACEMENT CSV\n');
% locExpanded: table with columns SensorID, Channel, x_m, Date, Camera
% One row per (sensor, date) combination.
locExpanded = wm_load_location_metadata();

fprintf('\n[STEP 2/4] Select the ACOUSTIC SENSOR CALIBRATION CSV\n');
% calData: table mapping (SensorID, Mode) → slope and intercept
% for converting raw voltage measured by acoustic sensors [V] to surface displacement [m].
calData = wm_load_calibration();

fprintf('\n[STEP 3/4] Select the EXPERIMENT PAIRING CSV\n');
% pairMeta: table linking each acoustic CSV filename to its paired
% video file, set voltage, set frequency, and optional video trim times.
pairMeta = wm_load_pair_metadata_v2();

fprintf('\n[STEP 4/4] Select ACOUSTIC DATA folder(s)\n');
% allFiles: struct array (dir-style) of all CSV files found in
% the selected folder(s). Only raw_data_*.csv files are processed.
allFiles = wm_select_files();
numFiles = length(allFiles);


%% =========================================================
%  SECTION 2e: CAMERA TIME-SERIES INDEX LOADING
%
%  The side-camera script (tank_process_sidecam_v8.m) writes one
%  CSV per video (eta(t) time series) and a CamTimeSeries_INDEX.csv
%  that lists all CSVs with their metadata. This section reads that
%  index and pre-loads every time-series CSV into camDataStore so that
%  the main loop (Section 4) can match camera records to acoustic files
%  without re-reading the index on every iteration.
%
%  camDataStore is a struct keyed by a safe alphanumeric string derived
%  from the acoustic filename + an index suffix to handle duplicates.
%  Fields per entry:
%    t_s          — time vector [s]
%    eta_m        — surface displacement [m] (zero-mean)
%    surf_unc_m   — per-frame position uncertainty [m]
%    AcousticFile — matched acoustic CSV base name (no extension)
%    CamLoc_m     — camera x-position along tank [m]
%    Fs_cam_Hz    — nominal camera frame rate [Hz]
%    SetAmp_V     — set wavemaker voltage from index [V]
%    SetFreq_Hz   — set wave frequency from index [Hz]
%    TSfilename   — base name of this camera CSV file
%    vid_t_start_s / vid_t_end_s — trim window from pairing CSV [s]
% =========================================================
fprintf('\nSelect the results_sidecam_*_MID folder containing\n');
fprintf('  CamTimeSeries_INDEX.csv (cancel = acoustic-only run).\n\n');
camTSdir = uigetdir(pwd, ...
    'Select results_sidecam_*_MID folder (cancel = acoustic only)');

camTSindex   = table();
hasCamIndex  = false;
camDataStore = struct();

if isequal(camTSdir, 0)
    fprintf('  [INFO] No camera folder selected — acoustic-only run.\n');
else
    idxPath = fullfile(camTSdir, 'CamTimeSeries_INDEX.csv');
    if ~exist(idxPath, 'file')
        warning('CamTimeSeries_INDEX.csv not found. Running acoustic-only.');
    else
        % Read the index CSV, preserving original column names
        camTSindex = readtable(idxPath, ...
            'Delimiter',          ',', ...
            'ReadVariableNames',  true, ...
            'VariableNamingRule', 'preserve', ...
            'HeaderLines',        0);
        hasCamIndex = true;
        fprintf('  Camera INDEX loaded: %d entries.\n', height(camTSindex));

        % Print column names so the user can verify the CSV structure
        idxVars = camTSindex.Properties.VariableNames;
        fprintf('  INDEX columns (%d):\n', length(idxVars));
        for iV = 1:length(idxVars)
            fprintf('    [%2d] %s\n', iV, idxVars{iV});
        end

        % Resolve column names flexibly — the index CSV may have been
        % written by different versions of the camera script, so pick_col
        % searches a list of candidate names and returns the first match.
        acFile_col  = pick_col(idxVars, { ...
            'Acoustic_sensor_filename', 'AcousticFile', ...
            'Acoustic_sensor_filenam',  'Acoustic_sensor_filename_1'});
        fps_col     = pick_col(idxVars, {'FrameRate_fps',  'Fs_cam_Hz'});
        setAmp_col  = pick_col(idxVars, {'Set_volt_V',     'SetAmplitude_V'});
        setFreq_col = pick_col(idxVars, {'Set_f_Hz',       'SetFrequency_Hz'});
        ts_col      = pick_col(idxVars, { ...
            'wave_TS_sidecam', ...
            'wave_TS_water_sidecam', ...
            'wave_time_series_sidecam', ...
            'CamTS_CSV_filename', 'TSfilename'});

        % Loop over every index row and load the corresponding CSV
        for iIdx = 1:height(camTSindex)

            tsFileName = strtrim(char(camTSindex.(ts_col)(iIdx)));
            tsFile     = fullfile(camTSdir, tsFileName);

            if ~exist(tsFile, 'file')
                fprintf('  [WARN] TS CSV not found: %s\n', tsFileName);
                continue;
            end

            tsData = readtable(tsFile, 'VariableNamingRule', 'preserve');
            acFile = char(camTSindex.(acFile_col)(iIdx));

            % Build a unique struct key: alphanumeric + row index suffix
            safeKey = regexprep(acFile, '[^a-zA-Z0-9_]', '_');
            safeKey = sprintf('%s_%d', safeKey, iIdx);

            % Parse camera x-position from the TS filename
            % Preferred pattern: _x<value>m.csv at end of filename
            tok = regexp(tsFileName, '_x([\d\.]+)m\.csv$', 'tokens', 'once');
            if ~isempty(tok)
                camLoc_parsed = str2double(tok{1});   % [m]
            else
                tok2 = regexp(tsFileName, '_x([\d\.]+)m_', 'tokens', 'once');
                if ~isempty(tok2)
                    camLoc_parsed = str2double(tok2{1});   % [m]
                else
                    fprintf('  [WARN] Cannot parse x from: %s\n', tsFileName);
                    camLoc_parsed = NaN;
                end
            end

            % Store time series and all associated metadata
            camDataStore.(safeKey).t_s          = tsData.t_s;          % [s]
            camDataStore.(safeKey).eta_m        = tsData.eta_m;        % [m]
            camDataStore.(safeKey).AcousticFile = acFile;
            camDataStore.(safeKey).CamLoc_m     = camLoc_parsed;       % [m]
            camDataStore.(safeKey).Fs_cam_Hz    = camTSindex.(fps_col)(iIdx);   % [Hz]
            camDataStore.(safeKey).SetAmp_V     = camTSindex.(setAmp_col)(iIdx);  % [V]
            camDataStore.(safeKey).SetFreq_Hz   = camTSindex.(setFreq_col)(iIdx); % [Hz]
            camDataStore.(safeKey).TSfilename   = tsFileName;

            % Load per-frame position uncertainty if present in the CSV
            if ismember('eta_unc_m', tsData.Properties.VariableNames)
                camDataStore.(safeKey).surf_unc_m = tsData.eta_unc_m;   % [m]
            else
                camDataStore.(safeKey).surf_unc_m = NaN(height(tsData), 1);
            end

            % Look up video trim window from the pairing CSV
            vid_t_start_cam = NaN;
            vid_t_end_cam   = NaN;
            if ~isempty(pairMeta) && ...
               ismember('vid_t_start_s', pairMeta.Properties.VariableNames) && ...
               ismember('vid_t_end_s',   pairMeta.Properties.VariableNames)
                [~, acBase_iIdx, ~] = fileparts(acFile);
                pMatch = false(height(pairMeta), 1);
                for iPM = 1:height(pairMeta)
                    pm = strtrim(char(pairMeta.Acoustic_sensor_filename(iPM)));
                    [~, pmBase, ~] = fileparts(pm);
                    if strcmp(pmBase, acBase_iIdx) || strcmp(pm, acBase_iIdx)
                        pMatch(iPM) = true;
                    end
                end
                if any(pMatch)
                    vid_t_start_cam = pairMeta.vid_t_start_s(find(pMatch,1));   % [s]
                    vid_t_end_cam   = pairMeta.vid_t_end_s(find(pMatch,1));     % [s]
                end
            end
            camDataStore.(safeKey).vid_t_start_s = vid_t_start_cam;   % [s]
            camDataStore.(safeKey).vid_t_end_s   = vid_t_end_cam;     % [s]

            fprintf('  Loaded: %s  x=%.2fm  [%.0f %.0f]s\n', ...
                tsFileName, camLoc_parsed, vid_t_start_cam, vid_t_end_cam);
        end

        fprintf('  camDataStore ready: %d entries.\n', length(fieldnames(camDataStore)));
    end
end


%% =========================================================
%  SECTION 2f: BENCHMARK REFERENCE LOADING
%
%  PASS 1 (benchmark_mode = true): skipped entirely.
%
%  PASS 2 (benchmark_mode = false):
%    The user selects the Results_postprocess CSV produced in Pass 1.
%    wm_build_refAmp_from_benchmark reads that CSV and builds a lookup
%    struct (refAmp) keyed by measurement type + position + frequency
%    + set voltage. Keys have the form:
%      Acoustic:  'S<sensorID>_f<freq>_A<amp>'
%      Camera:    'C<xLoc>_f<freq>_A<amp>'
%
%    These are queried in Sections 4 and 5 to normalise amplitudes.
%
%    refAmp_unc stores the standard error of the mean across benchmark
%    replicates for each key (used for uncertainty propagation in the
%    normalised amplitude: sigma(a/a0)).
% =========================================================
refAmp       = struct();
refAmp_unc   = struct();   % standard error of each benchmark reference amplitude
hasBenchmark = false;

if benchmark_mode
    fprintf('\n[BENCHMARK] benchmark_mode = true — this IS the reference run.\n');
else
    fprintf('\n[BENCHMARK] Select the benchmark Results_postprocess CSV.\n\n');
    [benchCSVfile, benchCSVpath] = uigetfile('*.csv', ...
        'Select benchmark Results_postprocess CSV (cancel = skip)');
    if ~isequal(benchCSVfile, 0)
        benchTable = readtable(fullfile(benchCSVpath, benchCSVfile), ...
            'VariableNamingRule','preserve');
        fprintf('  Benchmark CSV loaded: %d rows.\n', height(benchTable));
        % Build refAmp lookup struct from the benchmark table
        [refAmp, hasBenchmark] = wm_build_refAmp_from_benchmark(benchTable);
        % Warn if any pairing-metadata entries cannot be matched in refAmp
        wm_validate_benchmark_pairing(refAmp, hasBenchmark, pairMeta, camDataStore);
    else
        fprintf('  [INFO] No benchmark selected — raw amplitudes plotted.\n');
    end
end


%% =========================================================
%  SECTION 3: PRE-ALLOCATE RESULT STORAGE
%
%  All result arrays are pre-allocated to maxRows then trimmed at the
%  end of Section 4. Using NaN/empty strings as fill values ensures
%  that unfilled rows are easily identified downstream.
%
%  Column descriptions:
%    res_Measurement    — 'Acoustic_Sensor' or 'Side_Camera'
%    res_File           — source CSV filename
%    res_Mode           — wavemaker mode string (e.g. 'LOW', 'HIGH')
%    res_Date           — date string parsed from filename (DDMMYY)
%    res_SensorID       — sensor number from placement table [-]
%    res_Channel        — acquisition channel number [-]
%    res_SensorLoc      — sensor/camera x-position along tank [m]
%    res_InputAmp       — set wavemaker voltage [V]
%    res_InputFreq      — set wave frequency [Hz]
%    res_FFT_Freq       — dominant FFT frequency [Hz]
%    res_MeanFreq       — same as res_FFT_Freq (alias for compatibility) [Hz]
%    res_MeanAmp        — estimated wave amplitude (primary method) [m]
%    res_UncAmp         — amplitude uncertainty (std error of envelope) [m]
%    res_UncFreq        — frequency resolution of FFT over SS window [Hz]
%    res_MeanAmp_PT     — camera amplitude via peak-to-trough [m]
%    res_UncAmp_PT      — uncertainty on PT amplitude [m]
%    res_MeanAmp_Env    — camera amplitude via Hilbert envelope [m]
%    res_UncAmp_Env     — uncertainty on envelope amplitude [m]
%    res_DriftRatio_water — std(raw)/std(filtered) drift diagnostic [-]
%    res_RefAmp         — matched benchmark reference amplitude [m]
%    res_NormAmp        — normalised amplitude a/a0 [-]
% =========================================================
maxRows = numFiles * 20 * 2;   % large upper bound on result rows

res_Measurement      = strings(maxRows, 1);
res_File             = strings(maxRows, 1);
res_Mode             = strings(maxRows, 1);
res_Date             = strings(maxRows, 1);
res_SensorID         = NaN(maxRows, 1);
res_Channel          = NaN(maxRows, 1);
res_SensorLoc        = NaN(maxRows, 1);   % [m]
res_InputAmp         = NaN(maxRows, 1);   % [V]
res_InputFreq        = NaN(maxRows, 1);   % [Hz]
res_MeanAmp          = NaN(maxRows, 1);   % [m]
res_MeanFreq         = NaN(maxRows, 1);   % [Hz]
res_FFT_Freq         = NaN(maxRows, 1);   % [Hz]
res_UncAmp           = NaN(maxRows, 1);   % [m]
res_UncFreq          = NaN(maxRows, 1);   % [Hz]
res_MeanAmp_PT       = NaN(maxRows, 1);   % [m]  camera only
res_UncAmp_PT        = NaN(maxRows, 1);   % [m]  camera only
res_MeanAmp_Env      = NaN(maxRows, 1);   % [m]  camera only
res_UncAmp_Env       = NaN(maxRows, 1);   % [m]  camera only
res_DriftRatio_water = NaN(maxRows, 1);   % [-]  camera only
res_RefAmp           = NaN(maxRows, 1);   % [m]  benchmark reference
res_NormAmp          = NaN(maxRows, 1);   % [-]  a / a0

% timeSeriesData stores full filtered signals for potential time-domain
% plots. Indexed in parallel with the result arrays.
timeSeriesData = struct('Name',{},'Time',{},'Signal',{},'Envelope',{},...
                        'Amplitude',{},'Loc',{},'SensorID',{},'Mode',{});

kOut        = 1;        % running write index into result arrays
skippedMeta = 0;        % count of files skipped due to missing metadata
skippedCal  = 0;        % count of files skipped due to calibration issues


%% =========================================================
%  SECTION 3b: DEBUG PREVIEW LOOP
%
%  When debugEnable = true AND at least one of only_sensors /
%  only_cam_water is true, this block opens diagnostic figures for
%  a subset of files BEFORE the main loop, allowing signal quality
%  to be inspected without committing to a full run.
%
%  The preview list is built as follows:
%    - If debugFileList is non-empty: process only those files.
%    - If only_sensors (and not only_cam_water): all acoustic CSVs.
%    - If only_cam_water: only acoustic CSVs that have a camera match.
%
%  Figures produced here are the same as those produced inside the
%  main loop (wm_plot_debug_v2, wm_plot_fft_debug).
% =========================================================
disp('======================================================');
disp('--- Section 3b: Debug Preview (pre-loop) ---');
disp('======================================================');
fprintf('  [DIAG] debugEnable     = %d\n', debugEnable);
fprintf('  [DIAG] only_sensors    = %d\n', only_sensors);
fprintf('  [DIAG] only_cam_water  = %d\n', only_cam_water);
fprintf('  [DIAG] hasCamIndex     = %d\n', hasCamIndex);
fprintf('  [DIAG] camDataStore fields: %d\n', length(fieldnames(camDataStore)));
fprintf('  [DIAG] allFiles count  = %d\n', numFiles);

runPreview = debugEnable && (only_sensors || only_cam_water);
if ~runPreview
    fprintf('  [PREVIEW] Skipped.\n');
end

if runPreview
    % Build the list of files to preview
    if ~isempty(debugFileList)
        previewList = cellstr(debugFileList);
        fprintf('  [PREVIEW] WHITELIST (%d files)\n', length(previewList));
    elseif only_sensors && ~only_cam_water
        previewList = {allFiles.name};
        fprintf('  [PREVIEW] ALL files — sensors only (%d)\n', length(previewList));
    elseif only_cam_water
        if ~hasCamIndex
            fprintf('  [WARN] only_cam_water=true but no INDEX loaded.\n');
            previewList = {allFiles.name};
        else
            camKeys_all = fieldnames(camDataStore);
            if isempty(camKeys_all)
                fprintf('  [WARN] camDataStore is empty.\n');
                previewList = {};
            else
                % Collect unique acoustic filenames paired to a camera record
                previewList = cell(length(camKeys_all), 1);
                for iPL = 1:length(camKeys_all)
                    previewList{iPL} = camDataStore.(camKeys_all{iPL}).AcousticFile;
                end
                previewList = unique(previewList);
                fprintf('  [PREVIEW] CAMERA-PAIRED (%d unique acoustic names)\n', ...
                    length(previewList));
            end
        end
    else
        previewList = {allFiles.name};
        fprintf('  [PREVIEW] ALL files — fallback (%d)\n', length(previewList));
    end
    if isempty(previewList)
        fprintf('  [PREVIEW] Nothing to preview.\n');
        runPreview = false;
    end
end

if runPreview
    for iPrev = 1:length(previewList)
        prevName = previewList{iPrev};
        [~, prevBase_loop, prevExt_loop] = fileparts(prevName);

        % Ensure extension is present
        if isempty(prevExt_loop)
            prevName     = [prevName '.csv'];
            prevExt_loop = '.csv';
        end
        if ~strcmpi(prevExt_loop, '.csv'); continue; end

        % Only process acoustic raw data files (ignore camera CSVs)
        if ~startsWith(prevBase_loop, 'raw_data_')
            fprintf('  [PREVIEW SKIP] Not acoustic: %s\n', prevName);
            continue;
        end

        prevIdx = find(strcmp({allFiles.name}, prevName), 1);
        if isempty(prevIdx)
            prevIdx = find(strcmp({allFiles.name}, [prevBase_loop '.csv']), 1);
        end

        % Parse filename tokens (mode, channel, date, set amplitude, set frequency)
        [fMode_p, fChannel_p, fDate_p, fAmp_p, fFreq_p, Fs_p, parseOK_p] = ...
            wm_parse_filename(prevName, Fs_default);
        if ~parseOK_p
            fprintf('  [PREVIEW SKIP] Parse failed: %s\n', prevName);
            continue;
        end

        % ---- Acoustic signal preview ----
        if only_sensors && ~isempty(prevIdx)
            prevPath = fullfile(allFiles(prevIdx).folder, prevName);
            [t_p, rawMat_p, ~, readOK_p] = wm_read_signal(prevPath, Fs_p);
            if ~readOK_p; continue; end

            Fs_t_p    = 1 / mean(diff(t_p));   % [Hz] actual sample rate
            metaIdx_p = wm_lookup_metadata(locExpanded, fChannel_p, fDate_p);
            if isempty(metaIdx_p); continue; end

            sensorID_p = locExpanded.SensorID(metaIdx_p(1));
            [sig_cal_p, calOK_p] = wm_apply_calibration( ...
                rawMat_p(:,1), calData, sensorID_p, fMode_p);
            if ~calOK_p; continue; end

            sig_cal_raw_p = sig_cal_p;   % retain pre-despike copy for plotting
            n_spikes_p    = 0;
            if despike_enable
                [sig_cal_p, n_spikes_p] = wm_despike_v2(sig_cal_p, Fs_t_p, ...
                    despike_win_s, despike_thresh, despike_mode);
            end

            % Apply steady-state window
            t_end_use_p = t_p(end);
            if t_end_sensors > 0
                t_end_use_p = min(t_end_sensors, t_p(end));
            end
            ss_mask_p = (t_p >= t_start_sensors) & (t_p <= t_end_use_p);
            if sum(ss_mask_p) < 50; continue; end

            sig_ss_p = sig_cal_p(ss_mask_p) - mean(sig_cal_p(ss_mask_p));   % [m] zero-mean
            t_ss_p   = t_p(ss_mask_p);   % [s]

            % FFT frequency detection within tolerance of set frequency
            [fmeas_fft_p, f_vec_p, P1_p] = wm_fft_frequency( ...
                sig_ss_p, Fs_t_p, fFreq_p, freqTol);

            % Bandpass filter the steady-state segment and the full record
            if filterEnable
                sig_filt_p      = wm_filter_signal_v2(sig_ss_p, Fs_t_p, filterMode, ...
                    fc_lp, fmeas_fft_p, bp_frac, bp_order, prevName);
                sig_full_filt_p = wm_filter_signal_v2(sig_cal_p, Fs_t_p, filterMode, ...
                    fc_lp, fmeas_fft_p, bp_frac, bp_order, prevName);
            else
                sig_filt_p      = sig_ss_p;
                sig_full_filt_p = sig_cal_p;
            end

            % Estimate amplitude via Hilbert envelope
            [ameas_p, env_p, ~] = wm_estimate_amplitude(sig_filt_p, amplitudeMethod, ...
                fmeas_fft_p, Fs_t_p, env_smooth_periods);

            fprintf('  [PREVIEW acoustic] %s\n', prevName);
            wm_plot_debug_v2(t_p, sig_cal_raw_p, sig_cal_p, sig_full_filt_p, ...
                t_ss_p, sig_filt_p, env_p, ameas_p, ...
                n_spikes_p, despike_enable, amplitudeMethod, prevName, ...
                t_start_sensors, filterEnable, filterMode);
            wm_plot_fft_debug(f_vec_p, P1_p, fmeas_fft_p, fFreq_p, freqTol, ...
                prevName, filterEnable, filterMode, bp_frac);

            % Report harmonic content (2f, 3f, 4f) relative to fundamental
            [~, main_peak_idx] = min(abs(f_vec_p - fmeas_fft_p));
            main_amp = P1_p(main_peak_idx);   % FFT amplitude at fundamental [a.u.]
            fprintf('  Harmonic content for %s:\n', prevName);
            for h = [2 3 4]
                harm_f = fmeas_fft_p * h;   % [Hz] harmonic frequency
                band_h = (f_vec_p >= harm_f*(1-0.1)) & (f_vec_p <= harm_f*(1+0.1));
                if any(band_h)
                    [h_amp, li] = max(P1_p(band_h));
                    bi = find(band_h);
                    fprintf('    %df (%.2f Hz): Amp=%.5f, Rel=%.1f%%\n', ...
                        h, f_vec_p(bi(li)), h_amp, (h_amp/main_amp)*100);
                else
                    fprintf('    %df: Not found.\n', h);
                end
            end
        end % only_sensors preview

        % ---- Camera signal preview ----
        if only_cam_water && hasCamIndex
            camKeys        = fieldnames(camDataStore);
            matchedCamKeys = {};

            % Find all camera entries whose AcousticFile matches this acoustic file
            for ik = 1:length(camKeys)
                stored_ac = camDataStore.(camKeys{ik}).AcousticFile;
                [~, stored_base, ~] = fileparts(stored_ac);
                if strcmp(stored_base, prevBase_loop) || strcmp(stored_ac, prevName) || ...
                   strcmp(stored_ac, prevBase_loop)   || strcmp(stored_base, prevName)
                    matchedCamKeys{end+1} = camKeys{ik}; %#ok<AGROW>
                end
            end

            if isempty(matchedCamKeys)
                fprintf('  [CAM PREVIEW] No match for: %s\n', prevName);
            else
                for iCK = 1:length(matchedCamKeys)
                    ck  = matchedCamKeys{iCK};
                    cam = camDataStore.(ck);
                    fprintf('  [PREVIEW cam] x=%.2fm  %s\n', cam.CamLoc_m, cam.TSfilename);

                    t_cp   = cam.t_s;      % [s]
                    sig_cp = cam.eta_m;    % [m]
                    fSet_c = cam.SetFreq_Hz;   % [Hz]

                    % Apply video trim window from pairing CSV
                    if isfield(cam,'vid_t_start_s') && isfinite(cam.vid_t_start_s)
                        cam_t_start = cam.vid_t_start_s;   % [s]
                    else
                        cam_t_start = t_cp(1);
                    end
                    if isfield(cam,'vid_t_end_s') && isfinite(cam.vid_t_end_s)
                        cam_t_end = cam.vid_t_end_s;   % [s]
                    else
                        cam_t_end = t_cp(end);
                    end

                    prev_win_mask = (t_cp >= cam_t_start) & (t_cp <= cam_t_end);
                    t_cp   = t_cp(prev_win_mask);
                    sig_cp = sig_cp(prev_win_mask);

                    % Remove NaN (missed surface detections)
                    valid_cp   = ~isnan(sig_cp);
                    t_cp_v     = t_cp(valid_cp);   % [s]
                    sig_cp_v   = sig_cp(valid_cp) - mean(sig_cp(valid_cp),'omitnan');   % [m]
                    if length(sig_cp_v) < 20; continue; end

                    Fs_cp_eff = 1 / mean(diff(t_cp_v));   % [Hz] effective sample rate

                    % Optional despiking (skiplist enforced)
                    n_spikes_cp = 0;
                    sig_cp_desp = sig_cp_v;
                    if vid_despike_enable
                        [~, camBaseName] = fileparts(cam.TSfilename);
                        if ~any(strcmpi(vid_despike_skiplist, camBaseName))
                            [sig_cp_desp, n_spikes_cp] = wm_cam_despike(sig_cp_v, Fs_cp_eff, ...
                                vid_despike_win_s, vid_despike_thresh, vid_despike_mode);
                        else
                            fprintf('  [PREVIEW cam SKIP DESPIKE] %s is in skiplist\n', cam.TSfilename);
                        end
                    end

                    % FFT, filter, envelope on the (possibly despiked) signal
                    [fmeas_cp, f_vec_cp, P1_cp] = wm_fft_frequency( ...
                        sig_cp_desp, Fs_cp_eff, fSet_c, freqTol);
                    if vid_filterEnable
                        sig_cp_filt = wm_filter_signal_v2(sig_cp_desp, Fs_cp_eff, ...
                            vid_filterMode, vid_fc_lp, fmeas_cp, ...
                            vid_bp_frac, vid_bp_order, cam.TSfilename);
                    else
                        sig_cp_filt = sig_cp_desp;
                    end

                    env_cp_raw = abs(hilbert(sig_cp_filt));
                    sw_cp      = max(1, round(vid_env_smooth_periods * Fs_cp_eff / fmeas_cp));
                    env_cp     = movmean(env_cp_raw, sw_cp);
                    ameas_cp   = mean(env_cp);   % [m]

                    % Debug plots: show raw → despiked → filtered → envelope
                    wm_plot_debug_v2(t_cp_v, sig_cp_v, sig_cp_desp, sig_cp_filt, ...
                        t_cp_v, sig_cp_filt, env_cp, ameas_cp, n_spikes_cp, vid_despike_enable, ...
                        amplitudeMethod, ...
                        sprintf('CAM_%s_x%.2fm', prevName, cam.CamLoc_m), ...
                        0, vid_filterEnable, vid_filterMode);
                    wm_plot_fft_debug(f_vec_cp, P1_cp, fmeas_cp, fSet_c, freqTol, ...
                        sprintf('CAM_%s_x%.2fm', cam.TSfilename, cam.CamLoc_m), ...
                        vid_filterEnable, vid_filterMode, vid_bp_frac);
                end
            end
        end % only_cam_water preview
    end % iPrev
end % runPreview


%% =========================================================
%  SECTION 4: MAIN PROCESSING LOOP
%
%  Iterates over every acoustic CSV in allFiles.
%  For each file:
%    4a. Parse filename tokens (mode, channel, date, set amp, set freq).
%        Snap frequency and voltage to standard values to avoid
%        floating-point mismatch against the benchmark keys.
%    4b. Read the raw voltage signal.
%    4c. Look up sensor placement metadata.
%    4d. Check for a matching camera time-series in camDataStore.
%    4e. For each signal column × metadata row:
%          — Calibrate (V → m)
%          — Optional despiking
%          — Steady-state windowing
%          — FFT frequency detection
%          — Bandpass filtering
%          — Hilbert envelope amplitude estimation
%          — Benchmark reference lookup and normalisation
%          — Store result row + full time series
%    4-CAM. For each matched camera entry (inside the acoustic loop):
%          — Apply time window
%          — Remove NaN frames
%          — Optional despiking (with skiplist)
%          — FFT, filter, envelope, PT amplitude
%          — Drift / SNR diagnostic
%          — Benchmark reference lookup and normalisation
%          — Store camera result row
% =========================================================
disp('======================================================');
disp('--- Section 4: Main Processing Loop ---');
disp('======================================================');

hWait = waitbar(0, 'Processing files...');

for i = 1:numFiles

    try   % catch any per-file error and continue to the next file

    % Update progress bar 
    if isgraphics(hWait)
        waitbar(i/numFiles, hWait, sprintf('Processing file %d / %d...', i, numFiles));
    end

    % ==================================================================
    %  4a. FILENAME PARSING
    % ==================================================================
    fileName = allFiles(i).name;
    fullPath = fullfile(allFiles(i).folder, fileName);

    % Skip any non-CSV files (video files, MAT files, etc.)
    [~, ~, fExt] = fileparts(fileName);
    if ~strcmpi(fExt, '.csv'); continue; end

    % wm_parse_filename returns: mode string, acquisition channel,
    % date string (DDMMYY), set amplitude [V], set frequency [Hz],
    % nominal sampling rate [Hz], and a success flag.
    [fMode, fChannel, fDate, fAmp, fFreq, Fs, parseOK] = ...
        wm_parse_filename(fileName, Fs_default);
    if ~parseOK
        fprintf('  [SKIP] Parse failed: %s\n', fileName); continue;
    end

    % Snap the parsed frequency to the nearest standard value to prevent
    % floating-point drift from creating spurious benchmark keys
    % (e.g. 1.66 Hz parsed from filename becoming a different key than
    % the 1.67 Hz stored in the benchmark).
    std_freqs = [0.71, 0.83, 1.00, 1.25, 1.67];   % [Hz] nominal frequencies used in experiments
    [~, min_f_idx] = min(abs(std_freqs - fFreq));
    if abs(std_freqs(min_f_idx) - fFreq) < 0.05
        fFreq = std_freqs(min_f_idx);   % [Hz]
    end

    % Snap voltages that are written slightly differently in all csvs (e.g. 8.60 → 8.59 V)
    if abs(fAmp - 8.60) < 0.02
        fAmp = 8.59;   % [V] snap to benchmark value
    end

    fprintf('\nFILE: %s\n  Mode=%s | Ch=%d | Date=%s | A=%.3fV | f=%.3fHz\n', ...
        fileName, fMode, fChannel, fDate, fAmp, fFreq);

    % ==================================================================
    %  4b. SIGNAL READING
    % ==================================================================
    [t, rawMat, ~, readOK] = wm_read_signal(fullPath, Fs);
    if ~readOK
        fprintf('  [SKIP] Read failed: %s\n', fileName); continue;
    end
    % Compute actual sample rate from the time vector (may differ from
    % the nominal Fs encoded in the filename).
    Fs_t = 1 / mean(diff(t));   % [Hz]

    % ==================================================================
    %  4c. SENSOR PLACEMENT METADATA LOOKUP
    %  Returns row indices into locExpanded matching this (channel, date).
    % ==================================================================
    metaIdx = wm_lookup_metadata(locExpanded, fChannel, fDate);
    if isempty(metaIdx)
        fprintf('  [SKIP] No metadata Ch=%d Date=%s\n', fChannel, fDate);
        skippedMeta = skippedMeta + 1; continue;
    end

    % ==================================================================
    %  4d. CAMERA MATCH CHECK
    %  Finds all camDataStore entries whose AcousticFile base name
    %  matches the current acoustic file, regardless of extension.
    % ==================================================================
    [~, fileBase, ~] = fileparts(fileName);
    hasCamMatch  = false;
    camMatchKeys = {};

    if hasCamIndex
        ck_all = fieldnames(camDataStore);
        for ikk = 1:length(ck_all)
            stored_ac = camDataStore.(ck_all{ikk}).AcousticFile;
            [~, stored_base, ~] = fileparts(stored_ac);
            if strcmp(stored_base, fileBase) || strcmp(stored_ac, fileBase)
                camMatchKeys{end+1} = ck_all{ikk}; %#ok<AGROW>
            end
        end
        if ~isempty(camMatchKeys)
            hasCamMatch = true;
            fprintf('  Camera matched: %d entry(ies)\n', length(camMatchKeys));
        end
    end
    if ~hasCamMatch
        fprintf('  [INFO] No camera match — acoustic-only.\n');
    end

    % ==================================================================
    %  4e. ACOUSTIC SIGNAL PROCESSING
    %  Loop over signal columns (typically 1) and metadata rows
    %  (may be >1 if the same channel was used in multiple positions).
    % ==================================================================
    for c = 1:size(rawMat, 2)
        rawSig = rawMat(:, c);   % raw voltage signal for this column [V]

        for m = 1:length(metaIdx)
            sensorID = locExpanded.SensorID(metaIdx(m));   % [-]
            xLoc     = locExpanded.x_m(metaIdx(m));        % [m] along-tank position

            % --- Voltage-to-metres calibration ---
            % wm_apply_calibration applies:  signal_m = slope * rawSig + intercept
            % where slope [m/V] and intercept [m] are read from calData
            % for this (sensorID, mode) combination.
            [sig_cal, calOK] = wm_apply_calibration(rawSig, calData, sensorID, fMode);
            if ~calOK; skippedCal = skippedCal + 1; continue; end

            % --- Optional MAD despiking ---
            n_spikes = 0;
            if despike_enable
                [sig_cal, n_spikes] = wm_despike_v2(sig_cal, Fs_t, ...
                    despike_win_s, despike_thresh, despike_mode);
            end

            % --- Steady-state window ---
            % Exclude the transient start-up period (first t_start_sensors seconds)
            % and optionally the record tail (if t_end_sensors > 0).
            t_end_use = t(end);
            if t_end_sensors > 0
                t_end_use = min(t_end_sensors, t(end));   % [s]
            end
            ss_mask = (t >= t_start_sensors) & (t <= t_end_use);
            if sum(ss_mask) < 50
                fprintf('  [SKIP] SS window < 50 samples.\n');
                skippedCal = skippedCal + 1; continue;
            end

            % Mean-subtract so the signal is centred on zero
            sig_ss = sig_cal(ss_mask) - mean(sig_cal(ss_mask));   % [m]
            t_ss   = t(ss_mask);   % [s]  (unused downstream but kept for clarity)
            Ns     = length(sig_ss);   % [-] number of SS samples

            % Frequency resolution of the FFT (= 1 / record length)
            delta_f_ss = Fs_t / Ns;   % [Hz]

            % --- FFT-based frequency measurement ---
            % Searches for the dominant spectral peak within ±freqTol of fFreq.
            % Returns the peak frequency, the full frequency vector, and the
            % single-sided amplitude spectrum.
            [fmeas_fft, ~, ~] = wm_fft_frequency(sig_ss, Fs_t, fFreq, freqTol);   % [Hz]

            % --- Bandpass filter centred on the measured frequency ---
            % Pass band: [fmeas_fft / bp_frac , fmeas_fft * bp_frac] [Hz]
            if filterEnable
                sig_filt = wm_filter_signal_v2(sig_ss, Fs_t, filterMode, ...
                    fc_lp, fmeas_fft, bp_frac, bp_order, fileName);
            else
                sig_filt = sig_ss;   % [m]
            end

            % --- Amplitude estimation via Hilbert envelope ---
            % ameas  : mean of the smoothed envelope = estimated wave amplitude [m]
            % env    : smoothed instantaneous envelope (Hilbert magnitude) [m]
            % delta_A: standard error of the envelope mean [m]
            [ameas, env, delta_A] = wm_estimate_amplitude(sig_filt, amplitudeMethod, ...
                fmeas_fft, Fs_t, env_smooth_periods);   %#ok<ASGLU>

            % --- Store acoustic result row ---
            res_Measurement(kOut) = "Acoustic_Sensor";
            res_File(kOut)        = fileName;
            res_Mode(kOut)        = fMode;
            res_Date(kOut)        = fDate;
            res_SensorID(kOut)    = sensorID;
            res_Channel(kOut)     = fChannel;
            res_SensorLoc(kOut)   = xLoc;          % [m]
            res_InputAmp(kOut)    = fAmp;           % [V]
            res_InputFreq(kOut)   = fFreq;          % [Hz]
            res_FFT_Freq(kOut)    = fmeas_fft;      % [Hz]
            res_MeanFreq(kOut)    = fmeas_fft;      % [Hz]
            res_MeanAmp(kOut)     = ameas;          % [m]
            res_UncAmp(kOut)      = delta_A;        % [m]
            res_UncFreq(kOut)     = delta_f_ss;     % [Hz]

            % --- Full-record filtered signal and envelope (for time-series store) ---
            % Computed on the full calibrated signal (not just the SS window) so
            % that plots can show the build-up and decay.
            sig_cal_dm    = sig_cal - mean(sig_cal);   % [m] mean-subtracted full record
            if filterEnable
                sig_full_filt = wm_filter_signal_v2(sig_cal_dm, Fs_t, filterMode, ...
                    fc_lp, fmeas_fft, bp_frac, bp_order, fileName);
            else
                sig_full_filt = sig_cal_dm;   % [m]
            end
            env_full_raw = abs(hilbert(sig_full_filt));
            sw_full      = max(1, round(env_smooth_periods * Fs_t / fmeas_fft));
            env_full     = movmean(env_full_raw, sw_full);   % [m] smoothed envelope

            timeSeriesData(kOut).Name      = sprintf('x=%.2fm S%d', xLoc, sensorID);
            timeSeriesData(kOut).Time      = t;          % [s]
            timeSeriesData(kOut).Signal    = sig_full_filt;   % [m]
            timeSeriesData(kOut).Envelope  = env_full;   % [m]
            timeSeriesData(kOut).Amplitude = ameas;      % [m]
            timeSeriesData(kOut).Loc       = xLoc;       % [m]
            timeSeriesData(kOut).SensorID  = sensorID;
            timeSeriesData(kOut).Mode      = char(fMode);

            % --- Benchmark reference lookup ---
            % Bridge through pairMeta to obtain the precise set voltage for
            % this file, which may differ slightly from the voltage token in
            % the filename (rounding in the naming convention).
            res_RefAmp(kOut)  = NaN;
            res_NormAmp(kOut) = NaN;

            fAmp_precise = fAmp;   % [V] fallback to filename-parsed value
            if ~isempty(pairMeta) && ismember('Set_volt_V', pairMeta.Properties.VariableNames)
                [~, acBase, ~] = fileparts(fileName);
                for iPM = 1:height(pairMeta)
                    pm = strtrim(char(pairMeta.Acoustic_sensor_filename(iPM)));
                    [~, pmBase, ~] = fileparts(pm);
                    if strcmp(pmBase, acBase) || strcmp(pm, acBase)
                        fAmp_precise = pairMeta.Set_volt_V(iPM);   % [V]
                        break;
                    end
                end
            end

            % wm_get_ref_amp_numeric returns the benchmark amplitude [m]
            % and its standard error [m] for the matching key.
            [res_RefAmp(kOut), refAmpSEM_tmp] = wm_get_ref_amp_numeric( ...
                refAmp, hasBenchmark, "Acoustic_Sensor", xLoc, fFreq, fAmp_precise);
            if ~isnan(res_RefAmp(kOut)) && res_RefAmp(kOut) > 0
                res_NormAmp(kOut) = ameas / res_RefAmp(kOut);   % [-] normalised amplitude
            end

            % Warn if no benchmark reference was found for this row
            if isnan(res_RefAmp(kOut))
                fprintf(2, '  [DEBUG MISSING REF] Type=%s | S=%d | x=%.2fm | f=%.3f | A=%.3f\n', ...
                    "Acoustic_Sensor", sensorID, xLoc, fFreq, fAmp);
            end

            kOut = kOut + 1;   % advance write index

            % ==============================================================
            %  4-CAM: CAMERA TIME-SERIES PROCESSING
            %
            %  Only entered when a camera time-series was matched above.
            %  Each camera entry is processed independently; the results
            %  are appended as 'Side_Camera' rows to the same result arrays.
            % ==============================================================
            if ~hasCamMatch; continue; end

            for iCK = 1:length(camMatchKeys)
                ck  = camMatchKeys{iCK};
                cam = camDataStore.(ck);

                fprintf('  [CAM] %s (x=%.2fm)\n', cam.TSfilename, cam.CamLoc_m);

                t_cam_raw   = cam.t_s;      % [s] full time vector from TS CSV
                sig_cam_raw = cam.eta_m;    % [m] full displacement from TS CSV
                Fs_cam      = cam.Fs_cam_Hz;   % [Hz] nominal frame rate
                camLoc      = cam.CamLoc_m;    % [m] camera x-position

                % --- Apply time window ---
                % Use vid_t_start_s / vid_t_end_s from the pairing CSV.
                % Fall back to the full TS extent if not available.
                if isfield(cam,'vid_t_start_s') && isfinite(cam.vid_t_start_s)
                    cam_t_start = cam.vid_t_start_s;   % [s]
                else
                    cam_t_start = t_cam_raw(1);
                end
                if isfield(cam,'vid_t_end_s') && isfinite(cam.vid_t_end_s)
                    cam_t_end = cam.vid_t_end_s;   % [s]
                else
                    cam_t_end = t_cam_raw(end);
                end

                win_mask_cam = (t_cam_raw >= cam_t_start) & (t_cam_raw <= cam_t_end);

                % If the window is nearly empty, fall back to the full record
                if sum(win_mask_cam) < 10
                    fprintf('  [CAM WARN] Window [%.0f %.0f]s yields %d frames — ', ...
                        cam_t_start, cam_t_end, sum(win_mask_cam));
                    fprintf('falling back to full TS range [%.0f %.0f]s\n', ...
                        t_cam_raw(1), t_cam_raw(end));
                    win_mask_cam = true(size(t_cam_raw));
                end
                t_cam_raw   = t_cam_raw(win_mask_cam);
                sig_cam_raw = sig_cam_raw(win_mask_cam);

                fprintf('  [CAM] Window [%.0f %.0f]s (%d frames)\n', ...
                    cam_t_start, cam_t_end, sum(win_mask_cam));

                % --- Remove NaN frames  ---
                valid_cam   = ~isnan(sig_cam_raw);
                t_cam_valid = t_cam_raw(valid_cam);   % [s]
                % Zero-mean after NaN removal
                sig_cam = sig_cam_raw(valid_cam) - mean(sig_cam_raw(valid_cam), 'omitnan');   % [m]
                N_cam   = length(sig_cam);   % [-]

                if N_cam < 2
                    fprintf('  [CAM SKIP] Fewer than 2 valid samples after NaN removal.\n');
                    continue;
                end

                % Effective sample rate 
                Fs_cam_eff = 1 / mean(diff(t_cam_valid));   % [Hz]

                % Store the signal before despiking for diagnostic plotting
                sig_cam_predespike = sig_cam;   % [m]
                n_spikes_cam       = 0;

                % --- Optional camera despiking ---
                % Skiplist check: if the video base name is in vid_despike_skiplist,
                % despiking is bypassed even when vid_despike_enable = true.
                if vid_despike_enable
                    [~, this_ts_base, ~] = fileparts(cam.TSfilename);
                    skip_despike = false;
                    for iSkip = 1:length(vid_despike_skiplist)
                        [~, skip_base, ~] = fileparts(vid_despike_skiplist{iSkip});
                        if strcmpi(this_ts_base, skip_base)
                            skip_despike = true;
                            break;
                        end
                    end

                    if skip_despike
                        fprintf('  [CAM despike] SKIPPED for %s (in skiplist).\n', cam.TSfilename);
                    else
                        [sig_cam, n_spikes_cam] = wm_cam_despike( ...
                            sig_cam, Fs_cam_eff, ...
                            vid_despike_win_s, vid_despike_thresh, vid_despike_mode);
                        fprintf('  [CAM despike] Applied (%s mode, thresh=%.3f, win=%.2fs, spikes=%d).\n', ...
                            vid_despike_mode, vid_despike_thresh, vid_despike_win_s, n_spikes_cam);
                    end
                end

                % Minimum-length guard: require at least 2 full wave periods
                if N_cam < 2 * round(Fs_cam / fFreq)
                    fprintf('  [CAM SKIP] Too few frames after despiking (%d).\n', N_cam); continue;
                end

                delta_f_cam = Fs_cam_eff / N_cam;   % [Hz] FFT frequency resolution

                % --- FFT frequency detection on camera signal ---
                [fmeas_cam, ~, ~] = wm_fft_frequency(sig_cam, Fs_cam_eff, fFreq, freqTol);   % [Hz]
                if ~isfinite(fmeas_cam)
                    fprintf('  [CAM SKIP] FFT freq invalid.\n'); continue;
                end

                % --- Bandpass filter the camera signal ---
                if vid_filterEnable
                    sig_cam_filt = wm_filter_signal_v2(sig_cam, Fs_cam_eff, ...
                        vid_filterMode, vid_fc_lp, fmeas_cam, ...
                        vid_bp_frac, vid_bp_order, cam.TSfilename);
                else
                    sig_cam_filt = sig_cam;   % [m]
                end

                % --- Drift / SNR diagnostic ---
                % If the raw signal standard deviation is much larger than the
                % filtered signal std, the record is dominated by slow drift
                % rather than wave motion. Records above drift_snr_thresh are
                % flagged but not automatically excluded.
                std_raw_cam  = std(sig_cam);        % [m]
                std_filt_cam = std(sig_cam_filt);   % [m]
                if std_filt_cam < 1e-12
                    drift_ratio_cam = Inf;   % [-]
                else
                    drift_ratio_cam = std_raw_cam / std_filt_cam;   % [-]
                end
                if drift_ratio_cam > drift_snr_thresh
                    fprintf('  [CAM WARN] DRIFT RATIO = %.1f: %s\n', drift_ratio_cam, cam.TSfilename);
                else
                    fprintf('  [CAM] drift ratio = %.2f (OK)\n', drift_ratio_cam);
                end

                % --- Surface-detection uncertainty ---
                % surf_unc_m is the per-frame HWHM position uncertainty [m]
                % written by tank_process_sidecam_v8. Use mean over valid frames.
                if isfield(cam,'surf_unc_m') && ~isempty(cam.surf_unc_m)
                    mean_surf_unc_m = mean(cam.surf_unc_m(valid_cam), 'omitnan');   % [m]
                else
                    mean_surf_unc_m = NaN;
                end

                % --- Amplitude: peak-to-trough method ---
                % Half the mean crest-to-trough excursion over all identified cycles.
                % delta_A_cam_PT is the uncertainty estimated by wm_cam_amplitude.
                [A_cam_PT, delta_A_cam_PT] = wm_cam_amplitude( ...
                    sig_cam_filt, Fs_cam_eff, fmeas_cam, 1e-6, mean_surf_unc_m);   % [m], [m]

                % --- Amplitude: Hilbert envelope method ---
                env_cam_raw     = abs(hilbert(sig_cam_filt));
                sw_cam          = max(1, round(vid_env_smooth_periods * Fs_cam_eff / fmeas_cam));
                env_cam         = movmean(env_cam_raw, sw_cam);   % [m] smoothed envelope
                A_cam_Env       = mean(env_cam);                   % [m] mean envelope amplitude
                N_eff_cam       = max(1, floor(length(env_cam) / sw_cam));
                delta_A_cam_Env = std(env_cam) / sqrt(N_eff_cam); % [m] std error of envelope mean

                fprintf('  [CAM] f=%.4fHz  PT=%.5fm  Env=%.5fm\n', ...
                    fmeas_cam, A_cam_PT, A_cam_Env);

                % --- Diagnostic figure for this camera–acoustic pair ---
                hFig = figure('Name', sprintf('Cam -- %s | x=%.2fm', cam.TSfilename, camLoc));
                axC  = axes(hFig);
                hold(axC,'on'); grid(axC,'on');
                % Grey: signal before despiking (for comparison)
                plot(axC, t_cam_valid, sig_cam_predespike, 'Color',[0.7 0.7 0.7], ...
                    'LineWidth',0.6,'DisplayName','Raw');
                % Blue: after despiking, before filtering
                plot(axC, t_cam_valid, sig_cam, 'Color',[0.5 0.5 0.9], ...
                    'LineWidth',0.6, 'DisplayName','Despiked (pre-filter)');
                % Green: bandpass-filtered signal
                if vid_filterEnable
                    plot(axC, t_cam_valid, sig_cam_filt, 'Color',[0.2 0.6 0.2], ...
                        'LineWidth',1.0,'DisplayName',sprintf('Filtered (%s)',vid_filterMode));
                end
                % Red dashed: smoothed Hilbert envelope
                plot(axC, t_cam_valid, env_cam, 'r--','LineWidth',1.2, ...
                    'DisplayName',sprintf('Envelope (%d periods)',vid_env_smooth_periods));
                % Purple dashed: ±A_Env reference lines
                yline(axC,  A_cam_Env,'--','Color',[0.70 0.10 0.70],'LineWidth',1.5, ...
                    'DisplayName',sprintf('A_Env=%.4fm',A_cam_Env));
                yline(axC, -A_cam_Env,'--','Color',[0.70 0.10 0.70],'LineWidth',1.5, ...
                    'HandleVisibility','off');
                xlabel(axC,'$t$ (s)',    'Interpreter','latex','FontSize',11);
                ylabel(axC,'$\eta$ (m)', 'Interpreter','latex','FontSize',11);
                title(axC, sprintf('Camera: %s  x=%.2fm', cam.TSfilename, camLoc), ...
                    'Interpreter','none','FontSize',10);
                legend(axC,'show','Location','best','Interpreter','none','FontSize',9);

                % --- Store camera result row ---
                res_Measurement(kOut)      = "Side_Camera";
                res_File(kOut)             = string(cam.TSfilename);
                res_Mode(kOut)             = fMode;
                res_Date(kOut)             = fDate;
                res_SensorID(kOut)         = NaN;       % no sensor ID for camera
                res_Channel(kOut)          = NaN;
                res_SensorLoc(kOut)        = camLoc;                % [m]
                res_InputAmp(kOut)         = fAmp;                  % [V]
                res_InputFreq(kOut)        = fFreq;                 % [Hz]
                res_FFT_Freq(kOut)         = fmeas_cam;             % [Hz]
                res_MeanFreq(kOut)         = fmeas_cam;             % [Hz]
                res_MeanAmp(kOut)          = A_cam_Env;             % [m]  primary amplitude
                res_UncAmp(kOut)           = delta_A_cam_Env;       % [m]
                res_UncFreq(kOut)          = delta_f_cam;           % [Hz]
                res_MeanAmp_PT(kOut)       = A_cam_PT;              % [m]
                res_UncAmp_PT(kOut)        = delta_A_cam_PT;        % [m]
                res_MeanAmp_Env(kOut)      = A_cam_Env;             % [m]
                res_UncAmp_Env(kOut)       = delta_A_cam_Env;       % [m]
                res_DriftRatio_water(kOut) = drift_ratio_cam;       % [-]

                % --- Benchmark reference lookup for camera ---
                % Bridge through cam.AcousticFile to obtain the precise set
                % voltage from pairMeta (same logic as the acoustic lookup above).
                res_RefAmp(kOut)  = NaN;
                res_NormAmp(kOut) = NaN;

                fAmp_precise_cam = cam.SetAmp_V;   % [V] fallback: index CSV value
                if ~isempty(pairMeta) && ismember('Set_volt_V', pairMeta.Properties.VariableNames)
                    [~, acBase_cam, ~] = fileparts(cam.AcousticFile);
                    for iPM_cam = 1:height(pairMeta)
                        pm_cam = strtrim(char(pairMeta.Acoustic_sensor_filename(iPM_cam)));
                        [~, pmBase_cam, ~] = fileparts(pm_cam);
                        if strcmp(pmBase_cam, acBase_cam) || strcmp(pm_cam, acBase_cam)
                            fAmp_precise_cam = pairMeta.Set_volt_V(iPM_cam);   % [V]
                            break;
                        end
                    end
                end

                [res_RefAmp(kOut), ~] = wm_get_ref_amp_numeric( ...
                    refAmp, hasBenchmark, "Side_Camera", camLoc, fFreq, fAmp_precise_cam);
                if ~isnan(res_RefAmp(kOut)) && res_RefAmp(kOut) > 0
                    res_NormAmp(kOut) = A_cam_Env / res_RefAmp(kOut);   % [-]
                end
                if isnan(res_RefAmp(kOut))
                    fprintf(2, ['  [DEBUG MISSING CAM REF] Loc=%.2fm | f=%.3f' ...
                        ' | A_precise=%.4f | A_rounded=%.4f | TS=%s\n'], ...
                        camLoc, fFreq, fAmp_precise_cam, cam.SetAmp_V, cam.TSfilename);
                end

                kOut = kOut + 1;   % advance write index

            end % iCK — camera match loop

        end % m — metadata row loop

    end % c — signal column loop

    catch ME_loop
        % Report error and continue to the next file
        fprintf(2, '\n>>> [ERROR file %d: %s]\n>>> %s\n', i, fileName, ME_loop.message);
        if ~isempty(ME_loop.stack)
            fprintf(2, '>>> Line %d\n', ME_loop.stack(1).line);
        end
        fprintf('  Skipping. %d rows so far.\n', kOut-1);
    end

end % i — main file loop
close(hWait);


%% =========================================================
%  TRIM RESULT ARRAYS TO ACTUAL SIZE
%  Pre-allocated arrays are trimmed to the number of rows
%  actually written (kOut - 1) to remove the unused tail.
% =========================================================
n_rows = kOut - 1;
trimFields = { ...
    'res_Measurement','res_File','res_Mode','res_Date', ...
    'res_SensorID','res_Channel','res_SensorLoc', ...
    'res_InputAmp','res_InputFreq','res_FFT_Freq', ...
    'res_MeanAmp','res_MeanFreq','res_UncAmp','res_UncFreq', ...
    'res_MeanAmp_PT','res_UncAmp_PT','res_MeanAmp_Env','res_UncAmp_Env', ...
    'res_DriftRatio_water','res_RefAmp','res_NormAmp'};
for kf = 1:length(trimFields)
    eval([trimFields{kf} ' = ' trimFields{kf} '(1:n_rows);']);
end


%% =========================================================
%  SECTION 4 REPORT: CONSOLE SUMMARY
% =========================================================

fprintf('\n================ MAIN LOOP REPORT ================\n');
fprintf('benchmark_mode:       %d\n', benchmark_mode);
fprintf('hasBenchmark:         %d\n', hasBenchmark);
fprintf('Amplitude method:     ENVELOPE\n');
fprintf('Total result rows:    %d\n', n_rows);
fprintf('Skipped (no meta):    %d\n', skippedMeta);
fprintf('Skipped (other):      %d\n', skippedCal);

idx_acou = find(res_Measurement == "Acoustic_Sensor");
idx_cam  = find(res_Measurement == "Side_Camera");
fprintf('Acoustic rows:        %d\n', length(idx_acou));
fprintf('Camera rows:          %d\n', length(idx_cam));

% Cross-validate acoustic vs camera for matched conditions
all_amp_diff  = [];
all_freq_diff = [];
uniquePairs   = unique([res_InputAmp, res_InputFreq], 'rows');
for ip = 1:size(uniquePairs,1)
    aSet = uniquePairs(ip,1);   % [V]
    fSet = uniquePairs(ip,2);   % [Hz]
    ia = idx_acou(res_InputAmp(idx_acou)==aSet & res_InputFreq(idx_acou)==fSet);
    ic = idx_cam( res_InputAmp(idx_cam) ==aSet & res_InputFreq(idx_cam) ==fSet);
    if isempty(ia) || isempty(ic); continue; end
    all_amp_diff(end+1)  = abs(mean(res_MeanAmp(ic))  - mean(res_MeanAmp(ia)));    %#ok<AGROW>
    all_freq_diff(end+1) = abs(mean(res_MeanFreq(ic)) - mean(res_MeanFreq(ia)));   %#ok<AGROW>
end
final_amp_error  = mean(all_amp_diff,  'omitnan');   % [m]  mean |cam - acoustic| amplitude
final_freq_error = mean(all_freq_diff, 'omitnan');   % [Hz] mean |cam - acoustic| frequency
fprintf('Mean |cam-acou| amp  = %.6f m\n',  final_amp_error);
fprintf('Mean |cam-acou| freq = %.6f Hz\n', final_freq_error);
fprintf('=============================================\n');


%% =========================================================
%  SECTION 5: PLOTTING
%
%  All figures are collected in figHandles / figBaseNames for
%  batch saving in Section 6. The y-axis label and amplitude
%  arrays automatically switch between raw [m] and normalised
%  [-] depending on whether a benchmark was loaded.
%
%  Plot index:
%    Plot 1  — (debug figures from Section 3b)
%    Plot 2  — Amplitude vs sensor/camera position (per set voltage)
%    Plot 3  — Amplitude calibration: measured amp vs set voltage at f=1 Hz
%    Plot 4  — Frequency check: measured vs set frequency
%    Plot 5  — Amplitude vs set voltage (per position, single frequency)
%    Plot 6  — Amplitude vs position by frequency (per set voltage)
%    Plot 7  — Attenuation rate vs frequency (per set voltage) (never used
%    given my results sigh)
%    Plot 8  — Attenuation rate vs amplitude (per frequency) (never used
%    given my results sigh)
%    Plot 9  — I/Ibr vs wave steepness ka (MUST check this part, weird reuslts -- not used atm)
% =========================================================
disp('======================================================');
disp('--- Section 5: Generating Plots ---');
disp('======================================================');

% Recompute indices in case the report section was skipped
if ~exist('idx_acou','var') || ~exist('idx_cam','var')
    idx_acou = find(res_Measurement == "Acoustic_Sensor");
    idx_cam  = find(res_Measurement == "Side_Camera");
end
if ~exist('final_amp_error','var');  final_amp_error  = NaN; end
if ~exist('final_freq_error','var'); final_freq_error = NaN; end

% --- Optional: drop camera records with excessive drift ---
drop_flagged_data = false;
if drop_flagged_data
    n_cam_total = length(idx_cam);
    idx_cam = idx_cam( ...
        isnan(res_DriftRatio_water(idx_cam)) | ...
        res_DriftRatio_water(idx_cam) <= drift_snr_thresh);
    fprintf('  [FILTER] Camera: %d kept of %d.\n', length(idx_cam), n_cam_total);
else
    fprintf('  [FILTER] drop_flagged_data=false — %d camera records retained.\n', length(idx_cam));
end

% ---------------------------------------------------------
%  Build amplitude arrays for plotting.
%  res_MeanAmp_plot and res_UncAmp_plot start as copies of the
%  raw arrays, then are overwritten with normalised values in the
%  hasBenchmark block below.
% ---------------------------------------------------------
res_MeanAmp_plot = res_MeanAmp;   % [m] or [-] after normalisation
res_UncAmp_plot  = res_UncAmp;   % [m] or [-]

% Apply camera-specific amplitude method to the camera rows
switch lower(cam_amp_method)
    case 'pt'
        res_MeanAmp_plot(idx_cam) = res_MeanAmp_PT(idx_cam);    % [m]
        res_UncAmp_plot(idx_cam)  = res_UncAmp_PT(idx_cam);     % [m]
        cam_method_label = 'Peak-to-trough';
    case 'envelope'
        res_MeanAmp_plot(idx_cam) = res_MeanAmp_Env(idx_cam);   % [m]
        res_UncAmp_plot(idx_cam)  = res_UncAmp_Env(idx_cam);    % [m]
        cam_method_label = 'Hilbert envelope';
    otherwise
        error('Unknown cam_amp_method: "%s".', cam_amp_method);
end

% Default y-axis label (raw metres); overwritten if benchmark loaded
y_label_amp = '$\bar{\eta}$ (m)';

if ~hasBenchmark
    fprintf('No benchmark loaded — raw amplitudes plotted.\n');
end

% ---------------------------------------------------------
%  Normalisation block (Pass 2 only)
%
%  For every result row that has a valid benchmark reference:
%    r = a / a0                              [-]
%    sigma_r = r * sqrt( (sigma_a/a)^2
%                      + (sigma_a0/a0)^2 )  [-]
%  Rows without a valid reference are set to NaN and excluded
%  from plots so that raw and normalised data are never mixed
%  on the same axis.
% ---------------------------------------------------------
if hasBenchmark
    validRef   = ~isnan(res_RefAmp) & res_RefAmp > 0;
    acou_norm  = idx_acou(validRef(idx_acou));
    cam_norm   = idx_cam( validRef(idx_cam));

    % Set un-referenced rows to NaN so they do not appear in plots
    missing_acou = idx_acou(~validRef(idx_acou));
    missing_cam  = idx_cam(~validRef(idx_cam));
    res_MeanAmp_plot([missing_acou; missing_cam]) = NaN;
    res_UncAmp_plot([missing_acou; missing_cam])  = NaN;

    % --- Normalise acoustic rows ---
    r_acou      = res_NormAmp(acou_norm);             % [-]
    sig_a       = res_UncAmp(acou_norm);              % [m]
    a_acou      = res_MeanAmp(acou_norm);             % [m]
    a0_acou     = res_RefAmp(acou_norm);              % [m]
    sig_a0_acou = zeros(size(acou_norm));             % [m] std error of reference
    for ii = 1:length(acou_norm)
        [~, sig_a0_acou(ii)] = wm_get_ref_amp_numeric(refAmp, hasBenchmark, ...
            "Acoustic_Sensor", ...
            res_SensorLoc(acou_norm(ii)), ...
            res_InputFreq(acou_norm(ii)), ...
            res_InputAmp( acou_norm(ii)));
    end
    safe_a_acou = max(abs(a_acou), 1e-12);
    res_MeanAmp_plot(acou_norm) = r_acou;             % [-]
    res_UncAmp_plot(acou_norm)  = r_acou .* sqrt( ...
        (sig_a       ./ safe_a_acou).^2 + ...
        (sig_a0_acou ./ a0_acou    ).^2 );            % [-] propagated uncertainty

    % --- Normalise camera rows ---
    r_cam      = res_NormAmp(cam_norm);               % [-]
    sig_a_cam  = res_UncAmp_plot(cam_norm);           % [m]
    a_cam      = res_MeanAmp_Env(cam_norm);           % [m]
    a0_cam     = res_RefAmp(cam_norm);                % [m]
    sig_a0_cam = zeros(size(cam_norm));               % [m]
    for ii = 1:length(cam_norm)
        [~, sig_a0_cam(ii)] = wm_get_ref_amp_numeric(refAmp, hasBenchmark, ...
            "Side_Camera", ...
            res_SensorLoc(cam_norm(ii)), ...
            res_InputFreq(cam_norm(ii)), ...
            res_InputAmp( cam_norm(ii)));
    end
    safe_a_cam = max(abs(a_cam), 1e-12);
    res_MeanAmp_plot(cam_norm) = r_cam;               % [-]
    res_UncAmp_plot(cam_norm)  = r_cam .* sqrt( ...
        (sig_a_cam  ./ safe_a_cam).^2 + ...
        (sig_a0_cam ./ a0_cam    ).^2 );              % [-]

    y_label_amp = '$\bar{\eta} / a_0$  [-]';
    fprintf('  [NORM] %d acoustic + %d camera rows normalised.\n', ...
        length(acou_norm), length(cam_norm));

    % Report rows that could not be paired with a reference
    n_missing_acou = length(idx_acou) - length(acou_norm);
    n_missing_cam  = length(idx_cam)  - length(cam_norm);
    if n_missing_acou > 0 || n_missing_cam > 0
        fprintf('  [NORM WARN] %d acoustic + %d camera rows have no ref — excluded.\n', ...
            n_missing_acou, n_missing_cam);
        miss_acou_idx = idx_acou(~validRef(idx_acou));
        miss_cam_idx  = idx_cam(~validRef(idx_cam));
        for iDbg = 1:length(miss_acou_idx)
            idx = miss_acou_idx(iDbg);
            fprintf('  [FAIL] Acou: %s (x=%.2fm, f=%.2fHz, V=%.2fV)\n', ...
                res_File(idx), res_SensorLoc(idx), res_InputFreq(idx), res_InputAmp(idx));
        end
        for iDbg = 1:length(miss_cam_idx)
            idx = miss_cam_idx(iDbg);
            fprintf('  [FAIL] Cam:  %s (x=%.2fm, f=%.2fHz, V=%.2fV)\n', ...
                res_File(idx), res_SensorLoc(idx), res_InputFreq(idx), res_InputAmp(idx));
        end
    end
end  % hasBenchmark

% File-name suffix appended to figure base names when normalised
if hasBenchmark
    plotNormSuffix = '_NORM';
else
    plotNormSuffix = '';
end

figHandles   = {};
figBaseNames = {};

% Derive unique conditions from the acoustic result set
if ~isempty(idx_acou)
    uniqueLocs  = unique(res_SensorLoc(idx_acou));
    uniqueAmps  = unique(res_InputAmp( idx_acou(~isnan(res_InputAmp(idx_acou)))));   % [V]
    uniqueFreqs = unique(res_InputFreq(idx_acou(~isnan(res_InputFreq(idx_acou)))));  % [Hz]
else
    uniqueLocs  = [];
    uniqueAmps  = [];
    uniqueFreqs = [];
end

% Colour and line-style map keyed by wavemaker mode string
modeStyleMap.LOW.color       = [0.20 0.45 0.75];
modeStyleMap.LOW.linestyle   = '-';
modeStyleMap.LOW.marker      = 'o';
modeStyleMap.HIGH.color      = [0.85 0.33 0.10];
modeStyleMap.HIGH.linestyle  = '--';
modeStyleMap.HIGH.marker     = 's';
modeStyleMap.UNKNOWN.color   = [0.6 0.1 0.6];
modeStyleMap.UNKNOWN.linestyle = ':';
modeStyleMap.UNKNOWN.marker  = '^';

% Colour map for frequency series (one colour per unique frequency)
freqColorMap = lines(max(length(uniqueFreqs), 1));
getFreqColor = @(f) freqColorMap(find(uniqueFreqs == f, 1), :);





%% =========================================================
%  PLOT 2: AMPLITUDE vs SENSOR/CAMERA POSITION
%
%  All set voltages on a single figure, coloured by set voltage
%  using a perceptually progressive colormap (cool→warm).
%  Acoustic measurements: filled circles (●).
%  Camera measurements:   upward triangles (▲).
%  Optional: filter to a single set frequency (target_f).
%  Optional: exclude Sensor 5 (skipSensor5).
% =========================================================
target_f      = false;
freq_tol_plot = 0.01;
skipSensor5   = true;

% Frequency masks
if isnumeric(target_f) && isscalar(target_f) && isfinite(target_f)
    freq_mask_acou = abs(res_InputFreq(idx_acou) - target_f) < freq_tol_plot;
    freq_mask_cam  = abs(res_InputFreq(idx_cam)  - target_f) < freq_tol_plot;
    fig_freq_label = sprintf('_f%.3gHz', target_f);
    ttl_freq_label = sprintf(', $f$ = %.3g Hz', target_f);
else
    freq_mask_acou = true(size(idx_acou));
    freq_mask_cam  = true(size(idx_cam));
    fig_freq_label = '_allFreq';
    ttl_freq_label = '';
end

if skipSensor5
    sensor5_loc    = 7.80;
    fig_freq_label = [fig_freq_label, '_5skipped'];
end

% Progressive colormap: cool (low V) → warm (high V)
nAmps       = length(uniqueAmps);
rawCmap     = turbo(max(nAmps, 1));   % turbo goes blue→green→yellow→red
getAmpColor = @(ia) rawCmap(ia, :);


fAmpFig = figure('Name', sprintf('Amp_vs_Loc_allV%s%s', fig_freq_label, plotNormSuffix));


fAmpFig.Position = [100, 100, 700, 400]; 

ax2 = axes(fAmpFig); hold(ax2,'on'); grid(ax2,'on');

%axis(ax2, 'square');
pbaspect(ax2, [1 1 1]);


% Legend handle arrays: one patch per voltage (colour), two lines for type
hVoltage = gobjects(nAmps, 1);   % colour legend entries
hAcou    = gobjects(1);          % marker legend: acoustic
hCam     = gobjects(1);          % marker legend: camera

acouPlotted = false;
camPlotted  = false;

for ia = 1:nAmps
    ampSet = uniqueAmps(ia);
    cColor = getAmpColor(ia);
    
    idxA = idx_acou(abs(res_InputAmp(idx_acou) - ampSet) < 1e-6 & ...
                    freq_mask_acou & ...
                    ~isnan(res_MeanAmp_plot(idx_acou)));
    idxC = idx_cam( abs(res_InputAmp(idx_cam)  - ampSet) < 1e-6 & ...
                    freq_mask_cam  & ...
                    ~isnan(res_MeanAmp_plot(idx_cam)));
                    
    if skipSensor5
        idxA = idxA(abs(res_SensorLoc(idxA) - sensor5_loc) > 1e-6);
        idxC = idxC(abs(res_SensorLoc(idxC) - sensor5_loc) > 1e-6);
    end
    
    if isempty(idxA) && isempty(idxC)
        fprintf('  [SKIP Plot2] No data: A=%.3fV%s\n', ampSet, fig_freq_label);
        hVoltage(ia) = gobjects(1);
        continue
    end
    
    % Invisible patch just to get a solid colour swatch in the legend
    hVoltage(ia) = patch(ax2, NaN, NaN, cColor, 'EdgeColor', cColor, ...
        'DisplayName', sprintf('$A_{set}$ = %.3f V', ampSet));
        
    % Acoustic: filled circles
    for ii = idxA'
        h = errorbar(ax2, res_SensorLoc(ii), res_MeanAmp_plot(ii), ...
            res_UncAmp_plot(ii), res_UncAmp_plot(ii), delta_x_m, delta_x_m, ...
            'o', 'Color', cColor, 'MarkerFaceColor', cColor, ...
            'MarkerSize', 6, 'CapSize', 6, 'LineWidth', 1.2, ...
            'HandleVisibility', 'off');
        if ~acouPlotted
            hAcou = errorbar(ax2, NaN, NaN, NaN, NaN, ...
                'o', 'Color', [0.3 0.3 0.3], 'MarkerFaceColor', [0.3 0.3 0.3], ...
                'MarkerSize', 6, 'LineWidth', 1.2, 'CapSize', 6, ...
                'DisplayName', 'Acoustic');
            acouPlotted = true;
        end
    end
    
    % Camera: open upward triangles ('^')
    for ii = idxC'
        errorbar(ax2, res_SensorLoc(ii), res_MeanAmp_plot(ii), ...
            res_UncAmp_plot(ii), res_UncAmp_plot(ii), delta_x_m, delta_x_m, ...
            '^', 'Color', cColor, 'MarkerFaceColor', 'none', ...
            'MarkerSize', 8, 'CapSize', 6, 'LineWidth', 1.5, ...
            'HandleVisibility', 'off');
        if ~camPlotted
            hCam = errorbar(ax2, NaN, NaN, NaN, NaN, ...
                '^', 'Color', [0.3 0.3 0.3], 'MarkerFaceColor', 'none', ...
                'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6, ...
                'DisplayName', 'Camera');
            camPlotted = true;
        end
    end
end

% Build legend: voltage swatches first, then instrument-type markers
% Remove any gobjects that were skipped (no data)
validV = hVoltage(isgraphics(hVoltage));

% Separator: invisible entry to visually split colour vs marker section
hSep = plot(ax2, NaN, NaN, 'LineStyle', 'none', 'Marker', 'none', ...
    'DisplayName', '  ');   % blank spacer row

allHandles = [validV; hSep];
if acouPlotted; allHandles = [allHandles; hAcou]; end
if camPlotted;  allHandles = [allHandles; hCam];  end


lgd = legend(ax2, allHandles, 'Location', 'eastoutside', ...
    'Interpreter', 'latex', 'FontSize', 9, 'NumColumns', 2);

xlabel(ax2, '$x$ (m)',   'Interpreter', 'latex', 'FontSize', 17);
ylabel(ax2, y_label_amp, 'Interpreter', 'latex', 'FontSize', 17);
title(ax2, '');   % no title

figHandles{end+1}   = fAmpFig;
figBaseNames{end+1} = sprintf('Plot2_Amp_vs_Loc_allV%s%s', fig_freq_label, plotNormSuffix);
%% =========================================================
%  PLOT 3: AMPLITUDE CALIBRATION
%
%  Measured wave amplitude [m] vs set wavemaker voltage [V]
%  for a fixed reference frequency (fixedFreq = 1 Hz).
%  One data series per sensor location; linear fits are computed
%  for measurements above the sensor resolution threshold.
%
%  The sensor resolution threshold (amp_resolution_m) is shown
%  as a horizontal dashed line. Points below it are plotted as
%  open markers to indicate that they are below the noise floor.
%
%  Calibration fit results (slope, intercept, R², RMSE) are
%  saved to calResultsPerLoc for export to CSV (Section 6).
% =========================================================
fixedFreq = 1.0;   % [Hz] reference frequency for calibration plot
idxF4     = idx_acou(res_InputFreq(idx_acou)==fixedFreq & ~isnan(res_MeanAmp(idx_acou)));

f4  = figure('Name',['Amp_Calib' plotNormSuffix]);
ax4 = axes(f4); hold(ax4,'on'); grid(ax4,'on');

uniqueModes4     = unique(res_Mode(idxF4));
calResultsPerLoc = table();
uniqueLocs4      = unique(res_SensorLoc(idxF4));
locColors4       = lines(length(uniqueLocs4));

plottedLocs4   = [];
fitLegendAdded = false;

for ii = 1:length(uniqueModes4)
    mStr    = uniqueModes4(ii);
    st      = wm_style_for_mode(mStr, modeStyleMap);
    idxMode = idxF4(strcmp(res_Mode(idxF4), mStr));

    uLocs = unique(res_SensorLoc(idxMode));   % [m]

    for lj = 1:length(uLocs)
        curX   = uLocs(lj);   % [m]
        locIdx = find(uniqueLocs4 == curX, 1);
        cLoc   = locColors4(locIdx,:);

        % Add one legend entry per location (not per mode)
        if ~ismember(curX, plottedLocs4)
            plot(ax4, NaN, NaN, 'Color', cLoc, 'LineStyle', '-', ...
                'LineWidth', 1.5, 'DisplayName', sprintf('x=%.2fm', curX));
            plottedLocs4(end+1) = curX;
        end

        idxML       = idxMode(res_SensorLoc(idxMode)==curX);
        x_data_all  = res_InputAmp(idxML);   % [V]
        y_data_all  = res_MeanAmp(idxML);    % [m]
        ey_data_all = res_UncAmp(idxML);     % [m]
        above       = y_data_all > amp_resolution_m;   % logical mask

        % Points below resolution: open markers, no fit
        if any(~above)
            errorbar(ax4, x_data_all(~above), y_data_all(~above), ...
                ey_data_all(~above), ey_data_all(~above), ...
                delta_V_set*ones(sum(~above),1), delta_V_set*ones(sum(~above),1), ...
                'LineStyle', 'none', 'Color', cLoc, 'Marker', st.marker, ...
                'MarkerFaceColor', 'none', 'CapSize', 6, 'LineWidth', 1.2, ...
                'HandleVisibility', 'off');
        end

        x_data  = x_data_all(above);    % [V]
        y_data  = y_data_all(above);    % [m]
        ey_data = ey_data_all(above);   % [m]

        % --- Linear fit: a = slope * V + intercept ---
        if ~skipCalib && length(x_data) >= 2
            npts   = length(x_data);
            p      = polyfit(x_data, y_data, 1);   % p(1)=slope [m/V], p(2)=intercept [m]
            xfit   = linspace(min(x_data), max(x_data), 50);

            y_fit  = polyval(p, x_data);
            resid  = y_data - y_fit;     % [m] fit residuals
            SS_res = sum(resid.^2);
            SS_tot = sum((y_data - mean(y_data)).^2);
            R2     = 1 - SS_res / max(SS_tot, eps);   % [-] coefficient of determination
            sigma2 = SS_res / (npts - 2);              % [m^2] residual variance
            x_mean = mean(x_data);
            Sxx    = sum((x_data - x_mean).^2);
            SE_slope = sqrt(sigma2 / Sxx);             % [m/V] standard error of slope
            SE_int   = sqrt(sigma2 * sum(x_data.^2) / (npts * Sxx));   % [m] SE of intercept

            if ~fitLegendAdded
                plot(ax4, xfit, polyval(p,xfit), 'k-', 'LineWidth', 1.2, ...
                    'DisplayName', 'Linear fit');
                fitLegendAdded = true;
            else
                plot(ax4, xfit, polyval(p,xfit), 'Color', cLoc, 'LineWidth', 1.2, ...
                    'LineStyle', '-', 'HandleVisibility', 'off');
            end

            sID = res_SensorID(idxML(1));
            row = table(curX, sID, p(1), SE_slope, p(2), SE_int, R2, sqrt(sigma2), mStr, npts, ...
                'VariableNames', {'Sensor_Location_m','Sensor_Number', ...
                'Slope_m_per_V','Slope_SE_m_per_V','Intercept_m', ...
                'Intercept_SE_m','R2','RMSE_m','Mode','N_points_used'});
            calResultsPerLoc = [calResultsPerLoc; row]; %#ok<AGROW>
        end

        % Data points with filled markers above resolution
        if ~isempty(x_data)
            errorbar(ax4, x_data, y_data, ey_data, ey_data, ...
                delta_V_set*ones(size(x_data)), delta_V_set*ones(size(x_data)), ...
                'LineStyle', 'none', 'Color', cLoc, 'Marker', st.marker, ...
                'MarkerFaceColor', cLoc, 'MarkerEdgeColor', cLoc, ...
                'CapSize', 6, 'LineWidth', 1.2, 'HandleVisibility', 'off');
        end
    end
end

% Horizontal line marking the sensor resolution threshold
yline(ax4, amp_resolution_m, 'k--', 'LineWidth', 1.2, 'DisplayName', 'Sensor resolution');

legend(ax4, 'show', 'Location', 'northeastoutside', 'FontSize', 8, 'Interpreter', 'none');
xlabel(ax4, '$A_{set}$ (V)', 'Interpreter', 'latex', 'FontSize', 11);
ylabel(ax4, '$\bar{\eta}$',  'Interpreter', 'latex', 'FontSize', 11);

figHandles{end+1}   = f4;
figBaseNames{end+1} = ['Plot3_AmpCalib' plotNormSuffix];


%% =========================================================
%  PLOT 4: FREQUENCY CHECK
%
%  Measured frequency (FFT peak) vs set frequency for all
%  acoustic and camera measurements. Points should lie on the
%  1:1 line if the wavemaker is operating at the correct frequency
%  and the FFT detection is working correctly.
%  Error bars represent the FFT frequency resolution (1 / T_ss)
%  for acoustic data and 1 / T_cam for camera data.
% =========================================================
f5  = figure('Name',['Freq_Check' plotNormSuffix]);
ax5 = axes(f5);
hold(ax5,'on'); grid(ax5,'on');

errorbar(ax5, res_InputFreq(idx_acou), res_MeanFreq(idx_acou), ...
    res_UncFreq(idx_acou), res_UncFreq(idx_acou), ...
    zeros(length(idx_acou),1), zeros(length(idx_acou),1), ...
    'b.','CapSize',3,'LineWidth',0.8,'DisplayName','Acoustic');
if ~isempty(idx_cam)
    errorbar(ax5, res_InputFreq(idx_cam), res_MeanFreq(idx_cam), ...
        res_UncFreq(idx_cam), res_UncFreq(idx_cam), ...
        zeros(length(idx_cam),1), zeros(length(idx_cam),1), ...
        '+','Color',[0.2 0.6 0.2],'CapSize',3,'LineWidth',0.8,'DisplayName','Camera');
end
line(ax5,[0 5],[0 5],'Color','k','LineStyle','--','DisplayName','1:1');

legend(ax5,'show','Location','best','Interpreter','none');
xlabel(ax5,'$f_{set}$ (Hz)', 'Interpreter','latex','FontSize',11);
ylabel(ax5,'$f_{meas}$ (Hz)','Interpreter','latex','FontSize',11);

figHandles{end+1}   = f5;
figBaseNames{end+1} = ['Plot4_FreqCheck' plotNormSuffix];


%% =========================================================
%  PLOT 5: AMPLITUDE vs SET VOLTAGE
%
%  Measured amplitude vs set wavemaker voltage for a single
%  fixed frequency (fixedFreq6). One series per sensor/camera
%  position, coloured by location. Both acoustic (circles) and
%  camera (crosses) data are shown on the same axes.
%
%  This plot reveals nonlinearity in the wavemaker response and
%  allows cross-validation between acoustic and camera estimates
%  over the full voltage range.
%
%  Optional: exclude Sensor 5 (skipSensor5).
% =========================================================
fixedFreq6    = 0.71;   % [Hz] frequency to plot
freq_tol_plt6 = 0.01;   % [Hz] tolerance for frequency matching
skipSensor5   = true;   % exclude Sensor 5 if true

if isnumeric(fixedFreq6) && isscalar(fixedFreq6) && isfinite(fixedFreq6)
    freq_mask6_acou = abs(res_InputFreq(idx_acou) - fixedFreq6) < freq_tol_plt6;
    freq_mask6_cam  = abs(res_InputFreq(idx_cam)  - fixedFreq6) < freq_tol_plt6;
    ttl6_freq       = sprintf('$f_{set}$ = %.3g Hz', fixedFreq6);
    fig6_freq       = sprintf('_f%.3gHz', fixedFreq6);
else
    freq_mask6_acou = true(size(idx_acou));
    freq_mask6_cam  = true(size(idx_cam));
    ttl6_freq       = 'all frequencies';
    fig6_freq       = '_allFreq';
end

idx_acou6 = idx_acou(freq_mask6_acou);
idx_cam6  = idx_cam(freq_mask6_cam);

if skipSensor5
    sensor5_loc = 7.80;   % [m] x-position of Sensor 5
    idx_acou6   = idx_acou6(abs(res_SensorLoc(idx_acou6) - sensor5_loc) > 1e-6);
    if ~isempty(idx_cam6)
        idx_cam6 = idx_cam6(abs(res_SensorLoc(idx_cam6) - sensor5_loc) > 1e-6);
    end
    fig6_freq = [fig6_freq, '_5skipped'];
end

% Build a shared colour map across all positions (acoustic + camera)
allXlocs6 = unique([res_SensorLoc(idx_acou6(~isnan(res_SensorLoc(idx_acou6)))); ...
                    res_SensorLoc(idx_cam6(~isnan(res_SensorLoc(idx_cam6))))]);
allXlocs6    = allXlocs6(~isnan(allXlocs6));
locColorMap6 = lines(max(length(allXlocs6), 1));
getLocColor6 = @(x) locColorMap6(find(round(allXlocs6*100) == round(x*100), 1), :);

f6  = figure('Name', sprintf('Amplitude_vs_SetVoltage%s%s', fig6_freq, plotNormSuffix));
ax6 = axes(f6); hold(ax6,'on'); grid(ax6,'on');

% Acoustic series (one per position)
uAcouLocs6 = unique(res_SensorLoc(idx_acou6(~isnan(res_SensorLoc(idx_acou6)))));
for iX = 1:length(uAcouLocs6)
    xLoc6  = uAcouLocs6(iX);   % [m]
    cColor = getLocColor6(xLoc6);
    idxX   = idx_acou6(abs(res_SensorLoc(idx_acou6) - xLoc6) < 1e-6 & ...
                       ~isnan(res_MeanAmp_plot(idx_acou6)));
    if isempty(idxX); continue; end
    [vs, si] = sort(res_InputAmp(idxX));   % sort by voltage [V]
    as = res_MeanAmp_plot(idxX(si));       % [m] or [-]
    us = res_UncAmp_plot(idxX(si));        % [m] or [-]
    errorbar(ax6, vs, as, us, us, ...
        delta_V_set*ones(size(vs)), delta_V_set*ones(size(vs)), ...
        'o', 'Color', cColor, 'MarkerFaceColor', 'none', 'MarkerSize', 7, ...
        'CapSize', 10, 'LineWidth', 1.5, ...
        'DisplayName', sprintf('Acoustic x=%.2fm', xLoc6));
end

% Camera series (one per position)
if ~isempty(idx_cam6)
    uCamLocs6 = unique(res_SensorLoc(idx_cam6(~isnan(res_SensorLoc(idx_cam6)))));
    for iX = 1:length(uCamLocs6)
        xLoc6  = uCamLocs6(iX);   % [m]
        cColor = getLocColor6(xLoc6);
        idxCX  = idx_cam6(abs(res_SensorLoc(idx_cam6) - xLoc6) < 1e-6 & ...
                          ~isnan(res_MeanAmp_plot(idx_cam6)));
        if isempty(idxCX); continue; end
        [vs, si] = sort(res_InputAmp(idxCX));
        as = res_MeanAmp_plot(idxCX(si));
        us = res_UncAmp_plot(idxCX(si));
        errorbar(ax6, vs, as, us, us, ...
            delta_V_set*ones(size(vs)), delta_V_set*ones(size(vs)), ...
            'x', 'Color', cColor, 'MarkerSize', 10, 'LineWidth', 1.5, 'CapSize', 10, ...
            'DisplayName', sprintf('Camera x=%.2fm', xLoc6));
    end
end

legend(ax6, 'show', 'Location', 'northwestoutside', 'FontSize', 8, 'Interpreter', 'none');
xlabel(ax6, '$A_{set}$ (V)', 'Interpreter', 'latex', 'FontSize', 11);
ylabel(ax6, y_label_amp,     'Interpreter', 'latex', 'FontSize', 11);
title(ax6,  ttl6_freq,       'Interpreter', 'latex', 'FontSize', 11);

figHandles{end+1}   = f6;
figBaseNames{end+1} = sprintf('Plot5_Amplitude_vs_SetVoltage%s%s', fig6_freq, plotNormSuffix);


%% =========================================================
%  SECTION 5b: ATTENUATION ANALYSIS
%
%  For each (set voltage, set frequency, mode) group with at least
%  two sensor positions, a log-linear fit is performed on the
%  measured amplitude vs position data to extract the spatial
%  attenuation coefficient alpha [m^-1]:
%
%    a(x) = A0 * exp(-alpha * x)
%    ln(a) = ln(A0) - alpha * x       (linearised form)
%
%  wm_compute_attenuation_weighted performs a weighted least-squares
%  fit of ln(a) vs x, with weights = 1/sigma_a^2, where sigma_a is
%  the amplitude uncertainty.
%
%  Outputs per group:
%    alpha      — spatial attenuation coefficient [m^-1]
%    delta_alpha — standard error of alpha [m^-1]
%    A0         — extrapolated amplitude at x = 0 [m] or [-] if normalised
%    delta_A0   — standard error of A0 [m] or [-]
%    R2att      — R² of the log-linear fit [-]
%
%  Results are stored in attenuationResults table for export (Section 6)
%  and used in Plots 7 and 8.
% =========================================================
disp('--- Section 5b: Attenuation Analysis ---');
attenuationResults = table();
uniqueAmpFreq      = unique([res_InputAmp(idx_acou), res_InputFreq(idx_acou)], 'rows');

for iGroup = 1:size(uniqueAmpFreq,1)
    ampSet  = uniqueAmpFreq(iGroup,1);   % [V]
    freqSet = uniqueAmpFreq(iGroup,2);   % [Hz]

    idxGroup = idx_acou(res_InputAmp(idx_acou)==ampSet & ...
                        res_InputFreq(idx_acou)==freqSet & ...
                        ~isnan(res_MeanAmp_plot(idx_acou)));
    modesHere = unique(res_Mode(idxGroup));

    for im = 1:length(modesHere)
        modeStr = modesHere(im);
        idxGM   = idxGroup(strcmp(res_Mode(idxGroup), modeStr));

        % Sort by position for clean exponential fitting
        [xLocs_g, sI] = sort(res_SensorLoc(idxGM));   % [m]
        amps_g         = res_MeanAmp_plot(idxGM(sI));  % [m] or [-]
        delta_g        = res_UncAmp_plot(idxGM(sI));   % [m] or [-]

        % Weighted log-linear fit: ln(a) = ln(A0) - alpha*x
        [alpha, A0, R2att, delta_alpha, delta_A0, ~, ~] = ...
            wm_compute_attenuation_weighted(xLocs_g, amps_g, delta_g);
        % alpha      [m^-1]  attenuation coefficient
        % A0         [m] or [-]  extrapolated amplitude at x=0
        % R2att      [-]     fit quality
        % delta_alpha [m^-1]  standard error
        % delta_A0    [m] or [-]  standard error

        fprintf('  Atten: A=%.3fV f=%.3fHz [%s]: alpha=%.4f+-%.4f R2=%.4f\n', ...
            ampSet, freqSet, modeStr, alpha, delta_alpha, R2att);

        rowAtt = table(ampSet, freqSet, modeStr, alpha, delta_alpha, A0, delta_A0, R2att, ...
            'VariableNames', {'SetAmplitude_V','SetFrequency_Hz','Mode', ...
            'AttenuationRate_1perm','Unc_AttenuationRate_1perm', ...
            'ExtrapAmplitude_A0','Unc_ExtrapAmplitude_A0','R2_loglinear'});
        attenuationResults = [attenuationResults; rowAtt]; %#ok<AGROW>
    end
end


%% =========================================================
%  PLOT 6: AMPLITUDE vs POSITION BY FREQUENCY
%
%  One subplot per set voltage (validAmpsPlot8). Within each
%  subplot, one coloured series per frequency. Acoustic data only.
%  Vertical error bars = res_UncAmp_plot; horizontal = delta_x_m.
%
%  Only voltage groups with at least n_freq_min distinct frequencies
%  are included (Section 1l).
% =========================================================
validAmpsPlot8 = [];
for ia = 1:length(uniqueAmps)
    ampSet    = uniqueAmps(ia);
    idxAmpAll = idx_acou(res_InputAmp(idx_acou)==ampSet & ~isnan(res_MeanAmp_plot(idx_acou)));
    if length(unique(res_InputFreq(idxAmpAll))) >= n_freq_min
        validAmpsPlot8(end+1) = ampSet; %#ok<AGROW>
    end
end

if ~isempty(validAmpsPlot8)
    nSub8  = length(validAmpsPlot8);
    nCols8 = min(nSub8, 3);
    nRows8 = ceil(nSub8 / nCols8);
    f8     = figure('Name', ['Amplitude_vs_Position_byFreq' plotNormSuffix]);

    for iAmp = 1:length(validAmpsPlot8)
        ampSet    = validAmpsPlot8(iAmp);   % [V]
        ax8       = subplot(nRows8, nCols8, iAmp);
        hold(ax8,'on'); grid(ax8,'on');

        idxAmpAll        = idx_acou(res_InputAmp(idx_acou)==ampSet & ~isnan(res_MeanAmp_plot(idx_acou)));
        freqsHere        = unique(res_InputFreq(idxAmpAll));   % [Hz]
        plottedFreqsGrp8 = [];

        for iF = 1:length(freqsHere)
            freqSet   = freqsHere(iF);   % [Hz]
            cFreq     = getFreqColor(freqSet);
            idxAF     = idxAmpAll(res_InputFreq(idxAmpAll)==freqSet);
            modesHere = unique(res_Mode(idxAF));

            for im = 1:length(modesHere)
                modeStr  = modesHere(im);
                st       = wm_style_for_mode(modeStr, modeStyleMap);
                idxGM    = idxAF(strcmp(res_Mode(idxAF), modeStr));
                [xSorted,sI] = sort(res_SensorLoc(idxGM));   % [m]
                aSorted  = res_MeanAmp_plot(idxGM(sI));       % [m] or [-]
                daSorted = res_UncAmp_plot(idxGM(sI));        % [m] or [-]

                showF = ~ismember(freqSet, plottedFreqsGrp8);
                dName = ''; hVis = 'off';
                if showF
                    dName = sprintf('f=%.2fHz', freqSet);
                    hVis  = 'on';
                    plottedFreqsGrp8(end+1) = freqSet;
                end
                errorbar(ax8, xSorted, aSorted, daSorted, daSorted, ...
                    delta_x_m*ones(size(xSorted)), delta_x_m*ones(size(xSorted)), ...
                    st.marker,'Color',cFreq,'MarkerFaceColor',cFreq, ...
                    'MarkerSize',5,'CapSize',3,'LineWidth',0.8, ...
                    'DisplayName',dName,'HandleVisibility',hVis);
            end
        end

        legend(ax8,'show','Location','best','FontSize',7,'Interpreter','none');
        xlabel(ax8,'$x$ (m)',   'Interpreter','latex','FontSize',10);
        ylabel(ax8, y_label_amp,'Interpreter','latex','FontSize',10);
        title(ax8, sprintf('$A_{set}$ = %.3fV', ampSet),'Interpreter','latex','FontSize',9);
    end

    figHandles{end+1}   = f8;
    figBaseNames{end+1} = ['Plot6_AmplitudeVsPosition_byFreq' plotNormSuffix];
end


%% =========================================================
%  PLOT 7: ATTENUATION RATE vs FREQUENCY
%
%  One subplot per set voltage (validAmpsPlot9). Within each subplot,
%  the fitted attenuation coefficient alpha [m^-1] is plotted against
%  set frequency [Hz], with error bars = delta_alpha.
%
%  Only voltage groups with exactly n_freq_required distinct frequencies
%  are included, ensuring that all subplots span the same frequency axis.
%
%  A dashed line at alpha = 0 is shown as a reference. Positive alpha
%  indicates attenuation (amplitude decreasing with distance), negative
%  alpha would indicate amplification (unphysical — likely a fit artefact).
% =========================================================
validAmpsPlot9 = [];
for ia = 1:length(uniqueAmps)
    ampSet = uniqueAmps(ia);
    idxA9  = find(attenuationResults.SetAmplitude_V == ampSet);
    if length(unique(attenuationResults.SetFrequency_Hz(idxA9))) == n_freq_required
        validAmpsPlot9(end+1) = ampSet; %#ok<AGROW>
    end
end

if ~isempty(validAmpsPlot9)
    nSub9  = length(validAmpsPlot9);
    nCols9 = min(nSub9, 3);
    nRows9 = ceil(nSub9 / nCols9);
    f9     = figure('Name', ['AttenuationRate_vs_Frequency' plotNormSuffix]);

    for iAmp = 1:length(validAmpsPlot9)
        ampSet = validAmpsPlot9(iAmp);   % [V]
        ax9    = subplot(nRows9, nCols9, iAmp);
        hold(ax9,'on'); grid(ax9,'on');

        idxAtt          = find(attenuationResults.SetAmplitude_V == ampSet);
        plottedModesGrp9 = {};

        for ia9 = idxAtt'
            st    = wm_style_for_mode(attenuationResults.Mode(ia9), modeStyleMap);
            showM = ~ismember(char(attenuationResults.Mode(ia9)), plottedModesGrp9);
            hVis  = 'off'; dName = '';
            if showM
                dName = char(attenuationResults.Mode(ia9));
                hVis  = 'on';
                plottedModesGrp9{end+1} = dName;
            end
            errorbar(ax9, ...
                attenuationResults.SetFrequency_Hz(ia9), ...      % [Hz]
                attenuationResults.AttenuationRate_1perm(ia9), ... % [m^-1]
                attenuationResults.Unc_AttenuationRate_1perm(ia9), ...
                attenuationResults.Unc_AttenuationRate_1perm(ia9), ...
                st.marker,'Color',st.color,'MarkerFaceColor',st.color, ...
                'CapSize',4,'LineWidth',0.8,'DisplayName',dName,'HandleVisibility',hVis);
        end

        yline(ax9,0,'k:','LineWidth',0.8,'HandleVisibility','off');   % alpha=0 reference
        legend(ax9,'show','Location','best','FontSize',7,'Interpreter','none');
        xlabel(ax9,'$f_{set}$ (Hz)',      'Interpreter','latex','FontSize',10);
        ylabel(ax9,'$\alpha$ (m$^{-1}$)','Interpreter','latex','FontSize',10);
        title(ax9, sprintf('$A_{set}$ = %.3fV', ampSet),'Interpreter','latex','FontSize',9);
    end

    figHandles{end+1}   = f9;
    figBaseNames{end+1} = ['Plot7_AttenuationRate_vs_Frequency' plotNormSuffix];
end


%% =========================================================
%  PLOT 8: ATTENUATION RATE vs SET VOLTAGE
%
%  One subplot per set frequency (validFreqsPlot10). Within each
%  subplot, alpha [m^-1] vs set voltage [V], showing how wave
%  attenuation varies with forcing amplitude.
%
%  Only frequency groups with at least n_amp_min distinct set voltages
%  are included. The alpha = 0 reference line is drawn in all subplots.
%  Amplitude-dependent attenuation would indicate nonlinear dissipation.
% =========================================================
validFreqsPlot10 = [];
for iF = 1:length(uniqueFreqs)
    freqSet = uniqueFreqs(iF);
    idxF10  = find(attenuationResults.SetFrequency_Hz == freqSet);
    if length(unique(attenuationResults.SetAmplitude_V(idxF10))) >= n_amp_min
        validFreqsPlot10(end+1) = freqSet; %#ok<AGROW>
    end
end

if ~isempty(validFreqsPlot10)
    nSub10  = length(validFreqsPlot10);
    nCols10 = min(nSub10, 3);
    nRows10 = ceil(nSub10 / nCols10);
    f10     = figure('Name', ['AttenuationRate_vs_Amplitude' plotNormSuffix]);

    for iFreq = 1:length(validFreqsPlot10)
        freqSet = validFreqsPlot10(iFreq);   % [Hz]
        ax10    = subplot(nRows10, nCols10, iFreq);
        hold(ax10,'on'); grid(ax10,'on');

        idxAtt           = find(attenuationResults.SetFrequency_Hz == freqSet);
        plottedModesGrp10 = {};

        for ia10 = idxAtt'
            st    = wm_style_for_mode(attenuationResults.Mode(ia10), modeStyleMap);
            showM = ~ismember(char(attenuationResults.Mode(ia10)), plottedModesGrp10);
            hVis  = 'off'; dName = '';
            if showM
                dName = char(attenuationResults.Mode(ia10));
                hVis  = 'on';
                plottedModesGrp10{end+1} = dName;
            end
            errorbar(ax10, ...
                attenuationResults.SetAmplitude_V(ia10), ...      % [V]
                attenuationResults.AttenuationRate_1perm(ia10), ... % [m^-1]
                attenuationResults.Unc_AttenuationRate_1perm(ia10), ...
                attenuationResults.Unc_AttenuationRate_1perm(ia10), ...
                delta_V_set, delta_V_set, ...
                st.marker,'Color',st.color,'MarkerFaceColor',st.color, ...
                'CapSize',4,'LineWidth',0.8,'DisplayName',dName,'HandleVisibility',hVis);
        end

        yline(ax10,0,'k:','LineWidth',0.8,'HandleVisibility','off');
        legend(ax10,'show','Location','best','FontSize',7,'Interpreter','none');
        xlabel(ax10,'$A_{set}$ (V)',       'Interpreter','latex','FontSize',10);
        ylabel(ax10,'$\alpha$ (m$^{-1}$)','Interpreter','latex','FontSize',10);
        title(ax10, sprintf('$f_{set}$ = %.3fHz', freqSet),'Interpreter','latex','FontSize',9);
    end

    figHandles{end+1}   = f10;
    figBaseNames{end+1} = ['Plot8_AttenuationRate_vs_Amplitude' plotNormSuffix];
end


%% =========================================================
%  SECTION 5c: ICE FLEXURE ANALYSIS
%
%  Evaluates the Passerotti et al. (2022) flexural breakup criterion
%  for every measurement row. The dimensionless breakup parameter I is:
%
%    I = (Hs * h_ice * E_ice) / (2 * sigma_f_ice * L^2)
%
%  where:
%    Hs = 4 * a     — significant wave height [m]  (a = amplitude [m])
%    h_ice          — ice thickness [m]
%    E_ice          — Young's modulus of ice [Pa]
%    sigma_f_ice    — flexural strength of ice [Pa]
%    L              — wave length [m], computed from the measured
%                     frequency via the linear dispersion relation
%                     solved iteratively for finite water depth
%
%  The wave number k is found from the dispersion relation:
%    omega^2 = g * k * tanh(k * h)
%  using Newton–Raphson iteration (50 iterations, converges in <10).
%  The wave length is L = 2*pi / k [m].
%
%  Wave steepness is defined as ka [-] (wave number × amplitude).
%  The breakup threshold is I_br = 0.014 (from Passerotti et al. 2022).
%
%  NOTE: raw amplitudes (res_MeanAmp) are always used here, not
%  normalised values, because I requires physical metres.
%
%  PLOT 9: I/Ibr vs ka
%  Acoustic measurements: blue circles.
%  Camera measurements:   green triangles.
%  Threshold I/Ibr = 1 shown as a dashed horizontal line.
% =========================================================
disp('--- Section 5c: Ice Flexure Analysis (I/Ibr vs ka) ---');

% Flexural rigidity D = E * h^3 / (12*(1-nu^2))  [Pa m^3]
D_flex   = (E_ice * h_ice^3) / (12 * (1 - nu_ice^2));   % [Pa m^3]
% Flexural length scale  lambda_F = (D / (rho_w * g))^(1/4)  [m]
lambda_F = (D_flex / (rho_water * g_gravity))^(1/4);     % [m]
fprintf('  Flexural rigidity D       = %.4e Pa m^3\n', D_flex);
fprintf('  Flexural length scale     = %.4f m\n',      lambda_F);

I_br_threshold = 0.014;   % [-] breakup threshold (Passerotti et al. 2022)

if n_rows > 0

    ka_vec    = NaN(n_rows, 1);   % [-] wave steepness  k*a
    I_val_vec = NaN(n_rows, 1);   % [-] flexural breakup parameter I
    ratio_vec = NaN(n_rows, 1);   % [-] I / Ibr

    for ir = 1:n_rows
        fMeas = res_FFT_Freq(ir);   % [Hz] measured wave frequency (FFT peak)
        aMeas = res_MeanAmp(ir);    % [m]  raw measured amplitude

        if ~isfinite(fMeas) || ~isfinite(aMeas) || aMeas <= 0
            continue;
        end

        omega = 2 * pi * fMeas;   % [rad s^-1] angular frequency

        % --- Newton–Raphson solution of the dispersion relation ---
        % omega^2 = g * k * tanh(k * h)
        % Initial guess: deep-water approximation k0 = omega^2 / g
        k_est = omega^2 / g_gravity;   % [m^-1]
        for iter = 1:50
            th    = tanh(k_est * water_depth_m);
            f_k   = k_est * g_gravity * th - omega^2;                       % residual
            fp_k  = g_gravity * th + k_est * g_gravity * water_depth_m * (1 - th^2); % derivative
            k_new = k_est - f_k / fp_k;   % Newton step
            if abs(k_new - k_est) < 1e-10; break; end
            k_est = k_new;
        end
        % k_est is now the converged wave number [m^-1]

        Lp = 2 * pi / k_est;   % [m] wave length

        % Wave steepness
        ka_vec(ir) = k_est * aMeas;   % [-]

        % Significant wave height (4 * amplitude for a narrowband signal)
        Hs = 4 * aMeas;   % [m]

        % Flexural breakup parameter (Passerotti et al. 2022)
        I_val = (Hs * h_ice * E_ice) / (2 * sigma_f_ice * Lp^2);   % [-]
        I_val_vec(ir) = I_val;
        ratio_vec(ir) = I_val / I_br_threshold;   % [-]
    end

    valid_iceIdx = find(isfinite(ka_vec) & isfinite(ratio_vec));

    if ~isempty(valid_iceIdx)
        f11  = figure('Name','I_over_Ibr_vs_Steepness');
        ax11 = axes(f11);
        hold(ax11,'on'); grid(ax11,'on');

        % Acoustic measurements
        acou_v = valid_iceIdx(res_Measurement(valid_iceIdx)=="Acoustic_Sensor");
        if ~isempty(acou_v)
            scatter(ax11, ka_vec(acou_v), ratio_vec(acou_v), ...
                60, 'b', 'o', 'filled', 'DisplayName', 'Acoustic');
        end

        % Camera measurements
        cam_v = valid_iceIdx(res_Measurement(valid_iceIdx)=="Side_Camera");
        if ~isempty(cam_v)
            scatter(ax11, ka_vec(cam_v), ratio_vec(cam_v), ...
                60, [0.2 0.6 0.2], '^', 'filled', 'DisplayName', 'Camera');
        end

        % Breakup threshold line
        yline(ax11, 1.0, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Threshold I/Ibr=1');

        legend(ax11,'show','Location','best','Interpreter','none','FontSize',10);
        xlabel(ax11,'$ka$  [-]',       'Interpreter','latex','FontSize',11);
        ylabel(ax11,'$I/I_{br}$  [-]', 'Interpreter','latex','FontSize',11);

        % Parameter summary annotation
        annotStr = sprintf([ ...
            'h=%.3fm  E=%.2e Pa\n' ...
            '\\sigma_f=%.2e Pa  H=%.2fm\n' ...
            'Ibr=%.3f'], ...
            h_ice, E_ice, sigma_f_ice, water_depth_m, I_br_threshold);
        annotation(f11,'textbox',[0.15 0.70 0.25 0.18], ...
            'String', annotStr, 'Interpreter', 'none', 'FontSize', 8, ...
            'BackgroundColor', 'w', 'FitBoxToText', 'on');

        figHandles{end+1}   = f11;
        figBaseNames{end+1} = 'Plot9_I_over_Ibr_vs_Steepness';
        fprintf('  Plot 9: %d valid (ka, I/Ibr) points.\n', length(valid_iceIdx));
    else
        fprintf('  [SKIP] No valid (ka, I/Ibr) pairs — check ice parameters.\n');
    end
end


%% =========================================================
%  SECTION 6: SAVING
%
%  All open figures and result tables are written to the output
%  directory. Figure names are derived from figure window titles,
%  sanitised for filesystem compatibility.
%  Table outputs:
%    Results_postprocess_<DATE>.csv      — full measurement table
%    Attenuation_Results.csv             — attenuation fit results
%    Calibration_Fits_Per_Location.csv   — linear calibration fits
%                                          (only if skipCalib = false)
% =========================================================
disp('======================================================');
disp('--- Section 6: Saving ---');
disp('======================================================');

if save_fig || save_results

    % Output directory on external drive
    externalDrivePath = 'E:\SIWWI2026\280426\';
    outputDir = fullfile(externalDrivePath, ['results_postprocess_' date_str]);
    if ~exist(outputDir, 'dir'); mkdir(outputDir); end
    fprintf('Output directory: %s\n', outputDir);

    % -------------------------------------------------------
    %  6a. SAVE FIGURES
    %  Iterate over all open figures. Each is saved as both
    %  a 300 dpi PNG (for reports) and a vector PDF (for editing).
    %  Errors in saving one figure do not abort the others.
    % -------------------------------------------------------
    if save_fig
        allOpenFigs = findall(0, 'Type', 'figure');
        nFigSaved   = 0;
        nFigFailed  = 0;

        for k = 1:length(allOpenFigs)
            fh = allOpenFigs(k);
            if ~isgraphics(fh); continue; end

            rawName  = get(fh, 'Name');
            if isempty(rawName)
                rawName = sprintf('Figure_%d', fh.Number);
            end
            % Strip characters illegal in filenames
            safeName = strtrim(regexprep(rawName, '[\\/:*?"<>|]', '_'));

            try
                exportgraphics(fh, fullfile(outputDir, [safeName '.png']), 'Resolution', 300);
                exportgraphics(fh, fullfile(outputDir, [safeName '.pdf']), 'ContentType', 'vector');
                nFigSaved = nFigSaved + 1;
            catch ME_save
                fprintf('  [WARN] Could not save figure "%s": %s\n', safeName, ME_save.message);
                nFigFailed = nFigFailed + 1;
            end
        end
        fprintf('  Figures saved: %d  |  Failed: %d\n', nFigSaved, nFigFailed);
    end

end % save_fig || save_results

disp('=== MAIN_wm_postprocess_all.m finished ===');