%% =========================================================
%  MAIN_wm_postprocess_all.m
%  WAVE AMPLITUDE & FREQUENCY POSTPROCESSING — ACOUSTIC + CAMERA
%
%  -------------------------------------------------------
%  FUNCTION AUDIT (vs. global helper file wm_functions.m)
%  -------------------------------------------------------
%  The functions defined at the bottom of THIS file are the
%  CANONICAL versions. The global-file versions differ in the
%  following ways — in every case the LOCAL version below is
%  the one to keep. Comment out or delete any duplicate in the
%  global helper file:
%
%  1. wm_load_location_metadata (DIFFERS)
%     Global: expects columns Sensor/Channel/x_m/Camera, builds HasCamera.
%     Local : same PLUS loads an optional Date column for per-day matching.
%             -> KEEP LOCAL version (handles date-keyed metadata).
%
%  2. wm_load_pair_metadata  (RENAMED here as wm_load_pair_metadata_v2)
%     Global: uses positional column indexing (vars{1}, vars{2} ...).
%     Local:  uses column NAMES (robust to reordering), handles NaN
%             vid_t_start_s / vid_t_end_s gracefully (replaces with 0).
%             -> KEEP LOCAL version (wm_load_pair_metadata_v2).
%
%  3. wm_lookup_metadata (DIFFERS)
%     Global: checks ismember('Date',...) before accessing the column.
%     Local:  same logic, identical result.
%             -> Either version is fine; LOCAL kept for consistency.
%
%  4. wm_plot_debug_v2 (DIFFERS — BUG FIX)
%     Global wm_functions.m version: has unclosed switch/case block
%       (missing 'end' for the 'envelope' case and for the switch).
%       This causes a parse error.
%     Local: corrected — both 'rms' and 'envelope' cases are properly
%       closed; legend / xlabel calls are outside the switch.
%             -> KEEP LOCAL version (bug-fixed).
%
%  5. wm_apply_calibration (DUPLICATED in global file)
%     Appears twice in the global file — identical code.
%     -> Remove one copy from the global file; LOCAL version kept.
%
%  6. wm_cam_test_section (DIFFERS — is_ice argument added)
%     Global: does not accept is_ice flag; always shows single surface.
%     Local:  accepts is_ice and shows two lines when true.
%             -> KEEP LOCAL version.
%
%  All other functions (wm_style_for_mode, wm_select_files,
%  wm_read_signal, wm_parse_filename, wm_fft_frequency,
%  wm_filter_signal_v2, wm_estimate_amplitude, wm_despike_v2,
%  wm_compute_attenuation_weighted, wm_cam_amplitude,
%  wm_find_video, wm_plot_fft_debug) are IDENTICAL between
%  the global file and this script.
%  -------------------------------------------------------
%
%  METADATA COMPATIBILITY (Metadata_wmice_060526.csv format):
%  The pairing CSV now uses physical Set_volt_V values (not
%  integer voltage steps) and ka values instead of freeform
%  amplitude labels. The following changes ensure compatibility:
%
%  - wm_load_pair_metadata_v2 reads columns by NAME (not position),
%    so column reordering in the CSV has no effect.
%  - vid_t_start_s / vid_t_end_s cells that are blank/NaN in the
%    CSV are silently replaced with 0 (= process full video).
%  - wave_time_series_sidecam cells that are blank are replaced
%    with "" (empty string) rather than causing a cast error.
%  - Acoustic_sensor_filename entries do NOT have .csv extension
%    in the new CSV format — wm_load_pair_metadata_v2 no longer
%    strips it; wm_parse_filename still handles both cases.
%
%  WORKFLOW:
%    1.  User configures parameters (Section 1).
%    2.  Metadata loaded (Section 2).
%    3.  Debug preview loop — acoustic + camera (Section 3b).
%    4.  Main processing loop — acoustic + camera (Section 4).
%    5.  Console report (Section 4-REPORT).
%    6.  Plots 2, 4–11 (Sections 5, 5b, 5c).
%    7.  Saving (Section 6).
%
%  by Matilde
% =========================================================

clear; clc; close all;


%% =========================================================
%  SECTION 1: USER CONFIGURATION
% =========================================================

% ---------------------------------------------------------
%  1a. SAVING FLAGS
% ---------------------------------------------------------
save_fig     = true;
save_results = true;
mid_save     = true;

% ---------------------------------------------------------
%  1b. FALLBACK SAMPLING FREQUENCY
% ---------------------------------------------------------
Fs_default = 50;   % [Hz]

% ---------------------------------------------------------
%  1c. FILTERING OPTIONS — ACOUSTIC SENSORS
% ---------------------------------------------------------
filterEnable = true;
filterMode   = 'bandpass';   % 'lowpass' | 'bandpass'
fc_lp        = 2.0;          % [Hz]  low-pass cutoff (lowpass mode only)
bp_frac      = 0.80;         % ±80% fractional bandwidth (bandpass)
bp_order     = 4;            % Butterworth order per stage

% ---------------------------------------------------------
%  1d. AMPLITUDE METHOD — ENVELOPE ONLY
% ---------------------------------------------------------
amplitudeMethod = 'envelope';

% ---------------------------------------------------------
%  1e. FFT PEAK SEARCH TOLERANCE
% ---------------------------------------------------------
freqTol = 0.10;   % ±10% around set frequency

% ---------------------------------------------------------
%  1f. DATE STRING FOR OUTPUT FOLDER
% ---------------------------------------------------------
date_str = '060526';

% ---------------------------------------------------------
%  1g. DESPIKING — ACOUSTIC SENSORS
% ---------------------------------------------------------
despike_enable = false;
despike_mode   = 'mad';
despike_win_s  = 5.0;
despike_thresh = 3;

% ---------------------------------------------------------
%  1h. STEADY-STATE WINDOW — ACOUSTIC SENSORS
% ---------------------------------------------------------
t_start_sensors = 40;   % [s]
t_end_sensors   = 0;    % [s], 0 = full record from t_start

% ---------------------------------------------------------
%  1i. ENVELOPE SMOOTHING WINDOW
% ---------------------------------------------------------
env_smooth_periods = 4;   % [wave periods]

% ---------------------------------------------------------
%  1j. SENSOR RESOLUTION THRESHOLD (for Plot 4)
% ---------------------------------------------------------
amp_resolution_m = 0.001;   % [m]

% ---------------------------------------------------------
%  1k. UNCERTAINTY SOURCES
% ---------------------------------------------------------
delta_V_set = 0.001;   % [V]  voltage setting uncertainty
delta_x_m   = 0.05;   % [m]  sensor position uncertainty

% ---------------------------------------------------------
%  1l. PLOT FILTERING THRESHOLDS
% ---------------------------------------------------------
n_freq_min      = 2;
n_freq_required = 4;
n_amp_min       = 2;

% ---------------------------------------------------------
%  1m. DEBUG / PREVIEW SETTINGS
% ---------------------------------------------------------
debugAllFiles  = true;
debugCamSeries = true;

debugFileList = [
    "raw_data_HIGH_Sensor6_x9p4m_060526_a0p42_f1p66.csv"
];

% ---------------------------------------------------------
%  1n. CAMERA SIGNAL PROCESSING PARAMETERS
% ---------------------------------------------------------
vid_filterEnable       = true;
vid_filterMode         = 'bandpass';
vid_fc_lp              = 2.0;
vid_bp_frac            = 0.90;
vid_bp_order           = 4;
vid_env_smooth_periods = 4;

% ---------------------------------------------------------
%  1o. CAMERA AMPLITUDE METHOD FOR SUMMARY PLOTS
%  'PT'       — peak-to-trough half-range
%  'envelope' — mean Hilbert envelope
% ---------------------------------------------------------
cam_amp_method = 'envelope';

% ---------------------------------------------------------
%  1p. ICE FLEXURE ANALYSIS PARAMETERS
% ---------------------------------------------------------
g_gravity          = 9.81;
water_depth_m      = 0.3;
wave_steepness_col = '';   % '' = compute from dispersion each time

E_ice       = 5e9;
h_ice       = 0.07;
sigma_f_ice = 1e5;
nu_ice      = 0.33;
rho_ice     = 917;
rho_water   = 1025;

% ---------------------------------------------------------
%  1q. CALIBRATION OVERRIDE
% ---------------------------------------------------------
skipCalib = false;

% Global interpreter: 'none' everywhere; LaTeX applied selectively
set(groot, 'defaultTextInterpreter',          'none');
set(groot, 'defaultAxesTickLabelInterpreter', 'none');
set(groot, 'defaultLegendInterpreter',        'none');


%% =========================================================
%  SECTION 2: FILE & METADATA LOADING
% =========================================================
disp('======================================================');
disp('--- Section 2: File & Metadata Loading ---');
disp('======================================================');

% (a) Sensor placement: Sensor | Channel | x_m | Camera
fprintf('\n[STEP 1/4] Select the SENSOR PLACEMENT CSV\n');
fprintf('           (e.g. Metadata_sensors_060526.csv)\n\n');
locExpanded = wm_load_location_metadata();

% (b) Calibration: Source | Mode | Slope_a | Intercept_b
fprintf('\n[STEP 2/4] Select the ACOUSTIC SENSOR CALIBRATION CSV\n');
fprintf('           (maps raw voltage [V] -> displacement [m])\n\n');
calData = wm_load_calibration();

% (c) Pairing metadata (v2) — read by column name, handles blank
%     vid_t_start_s / vid_t_end_s / wave_time_series_sidecam
fprintf('\n[STEP 3/4] Select the EXPERIMENT PAIRING CSV\n');
fprintf('           (e.g. Metadata_wmice_060526.csv)\n');
fprintf('           Links acoustic CSVs to video files and\n');
fprintf('           camera time-series CSVs.\n\n');
pairMeta = wm_load_pair_metadata_v2();

% (d) Acoustic CSV data files
fprintf('\n[STEP 4/4] Select ACOUSTIC DATA folder(s)\n');
fprintf('           (containing raw_data_*.csv files)\n\n');
allFiles = wm_select_files();
numFiles = length(allFiles);

% ---------------------------------------------------------
%  Load the camera time-series INDEX CSV produced by
%  tank_process_sidecam_v3.m.  Cancelling -> acoustic-only.
% ---------------------------------------------------------
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
        camTSindex  = readtable(idxPath, 'VariableNamingRule', 'preserve');
        hasCamIndex = true;
        fprintf('  Camera index loaded: %d entries.\n', height(camTSindex));

        % ----------------------------------------------------------
        %  METADATA COMPATIBILITY: determine correct column names.
        %  The INDEX CSV may use different column headers depending on
        %  which version of tank_process_sidecam produced it.
        %  We look for the camera-location and acoustic-filename columns
        %  by trying a ranked list of known aliases.
        % ----------------------------------------------------------
        idxVars = camTSindex.Properties.VariableNames;

        camLoc_col  = pick_col(idxVars, {'CameraLocation_m','Camera_loc_m','CamLoc_m'});
        acFile_col  = pick_col(idxVars, {'AcousticFile','Acoustic_sensor_filename'});
        tsFile_col  = pick_col(idxVars, {'wave_time_series_sidecam','CamTS_CSV_filename','TSfilename'});
        fps_col     = pick_col(idxVars, {'FrameRate_fps','Fs_cam_Hz'});
        setAmp_col  = pick_col(idxVars, {'Set_volt_V','SetAmplitude_V'});
        setFreq_col = pick_col(idxVars, {'Set_f_Hz','SetFrequency_Hz'});

        for iIdx = 1:height(camTSindex)
            tsFile = fullfile(camTSdir, char(camTSindex.(tsFile_col)(iIdx)));
            if ~exist(tsFile, 'file')
                fprintf('  [WARN] Camera CSV not found: %s\n', ...
                    char(camTSindex.(tsFile_col)(iIdx)));
                continue;
            end
            tsData = readtable(tsFile, 'VariableNamingRule', 'preserve');

            acFile  = char(camTSindex.(acFile_col)(iIdx));
            safeKey = regexprep(acFile, '[^a-zA-Z0-9_]', '_');
            safeKey = sprintf('%s_%d', safeKey, iIdx);

            camDataStore.(safeKey).t_s          = tsData.t_s;
            camDataStore.(safeKey).eta_m        = tsData.eta_m;
            camDataStore.(safeKey).AcousticFile = acFile;
            camDataStore.(safeKey).CamLoc_m    = camTSindex.(camLoc_col)(iIdx);
            camDataStore.(safeKey).Fs_cam_Hz   = camTSindex.(fps_col)(iIdx);
            camDataStore.(safeKey).SetAmp_V    = camTSindex.(setAmp_col)(iIdx);
            camDataStore.(safeKey).SetFreq_Hz  = camTSindex.(setFreq_col)(iIdx);
            camDataStore.(safeKey).TSfilename  = char(camTSindex.(tsFile_col)(iIdx));
              % Load per-frame position uncertainty columns if present.
            % These are written by tank_process_sidecam_v4 when
            % pick_best_peak returns HWHM-based uncertainty estimates.
            % If the CSV was produced by an older version, the columns
            % won't exist — we default to NaN (handled gracefully below).
            if ismember('eta_water_unc_m', tsData.Properties.VariableNames)
                camDataStore.(safeKey).surf_unc_m = tsData.eta_water_unc_m;
            else
                camDataStore.(safeKey).surf_unc_m = NaN(height(tsData), 1);
            end
 
            if ismember('eta_ice_unc_m', tsData.Properties.VariableNames)
                camDataStore.(safeKey).ice_unc_m = tsData.eta_ice_unc_m;
            else
                camDataStore.(safeKey).ice_unc_m = NaN(height(tsData), 1);
            end

            fprintf('  Pre-loaded: %s  (%d frames, x=%.2fm)\n', ...
                char(camTSindex.(tsFile_col)(iIdx)), ...
                length(tsData.t_s), camTSindex.(camLoc_col)(iIdx));
        end
        fprintf('  Camera data store: %d entries ready.\n', ...
            length(fieldnames(camDataStore)));
    end
end


%% =========================================================
%  SECTION 3: PRE-ALLOCATE RESULT STORAGE
% =========================================================
maxRows = numFiles * 10 * 3;

res_Measurement = strings(maxRows, 1);
res_File        = strings(maxRows, 1);
res_Mode        = strings(maxRows, 1);
res_Date        = strings(maxRows, 1);
res_SensorID    = NaN(maxRows, 1);
res_Channel     = NaN(maxRows, 1);
res_SensorLoc   = NaN(maxRows, 1);
res_InputAmp    = NaN(maxRows, 1);
res_InputFreq   = NaN(maxRows, 1);
res_MeanAmp     = NaN(maxRows, 1);
res_MeanFreq    = NaN(maxRows, 1);
res_FFT_Freq    = NaN(maxRows, 1);
res_UncAmp      = NaN(maxRows, 1);
res_UncFreq     = NaN(maxRows, 1);
res_MeanAmp_PT  = NaN(maxRows, 1);
res_UncAmp_PT   = NaN(maxRows, 1);
res_MeanAmp_Env = NaN(maxRows, 1);
res_UncAmp_Env  = NaN(maxRows, 1);

timeSeriesData = struct('Name',{},'Time',{},'Signal',{},'Envelope',{},...
                        'Amplitude',{},'Loc',{},'SensorID',{},'Mode',{});

kOut        = 1;
skippedMeta = 0;
skippedCal  = 0;


%% =========================================================
%  SECTION 3b: DEBUG PREVIEW LOOP
% =========================================================
disp('======================================================');
disp('--- Section 3b: Debug Preview (pre-loop) ---');
disp('======================================================');

if debugAllFiles
    previewList = {allFiles.name};
    fprintf('Preview mode: ALL files (%d total)\n', length(previewList));
else
    previewList = cellstr(debugFileList);
    fprintf('Preview mode: selected files (%d listed)\n', length(previewList));
end

for iPrev = 1:length(previewList)

    prevName = previewList{iPrev};
    prevIdx  = find(strcmp({allFiles.name}, prevName), 1);
    if isempty(prevIdx)
        fprintf('  [PREVIEW SKIP] Not in file list: %s\n', prevName); continue;
    end
    prevPath = fullfile(allFiles(prevIdx).folder, prevName);

    [fMode_p, fChannel_p, fDate_p, fAmp_p, fFreq_p, Fs_p, parseOK_p] = ...
        wm_parse_filename(prevName, Fs_default);
    if ~parseOK_p; continue; end

    [t_p, rawMat_p, ~, readOK_p] = wm_read_signal(prevPath, Fs_p);
    if ~readOK_p; continue; end
    Fs_t_p = 1 / mean(diff(t_p));

    metaIdx_p = wm_lookup_metadata(locExpanded, fChannel_p, fDate_p);
    if isempty(metaIdx_p); continue; end
    sensorID_p = locExpanded.SensorID(metaIdx_p(1));

    [sig_cal_p, calOK_p] = wm_apply_calibration(rawMat_p(:,1), calData, sensorID_p, fMode_p);
    if ~calOK_p; continue; end
    sig_cal_raw_p = sig_cal_p;

    n_spikes_p = 0;
    if despike_enable
        [sig_cal_p, n_spikes_p] = wm_despike_v2(sig_cal_p, Fs_t_p, ...
            despike_win_s, despike_thresh, despike_mode);
    end

    t_end_use_p = t_p(end);
    if t_end_sensors > 0; t_end_use_p = min(t_end_sensors, t_p(end)); end
    ss_mask_p = (t_p >= t_start_sensors) & (t_p <= t_end_use_p);
    if sum(ss_mask_p) < 50; continue; end
    sig_ss_p = sig_cal_p(ss_mask_p);
    t_ss_p   = t_p(ss_mask_p);

    [fmeas_fft_p, f_vec_p, P1_p] = wm_fft_frequency(sig_ss_p, Fs_t_p, fFreq_p, freqTol);

    if filterEnable
        sig_filt_p      = wm_filter_signal_v2(sig_ss_p, Fs_t_p, filterMode, ...
            fc_lp, fmeas_fft_p, bp_frac, bp_order, prevName);
        sig_full_filt_p = wm_filter_signal_v2(sig_cal_p, Fs_t_p, filterMode, ...
            fc_lp, fmeas_fft_p, bp_frac, bp_order, prevName);
    else
        sig_filt_p      = sig_ss_p;
        sig_full_filt_p = sig_cal_p;
    end

    [ameas_p, env_p, ~] = wm_estimate_amplitude(sig_filt_p, amplitudeMethod, ...
        fmeas_fft_p, Fs_t_p, env_smooth_periods);

    fprintf('  [PREVIEW] Acoustic: %s\n', prevName);
    wm_plot_debug_v2(t_p, sig_cal_raw_p, sig_cal_p, sig_full_filt_p, ...
        t_ss_p, sig_filt_p, env_p, ameas_p, ...
        n_spikes_p, despike_enable, amplitudeMethod, prevName, ...
        t_start_sensors, filterEnable, filterMode);

    wm_plot_fft_debug(f_vec_p, P1_p, fmeas_fft_p, fFreq_p, freqTol, ...
        prevName, filterEnable, filterMode, bp_frac);

    % Harmonic report
    [~, main_peak_idx] = min(abs(f_vec_p - fmeas_fft_p));
    main_amp = P1_p(main_peak_idx);
    fprintf('  Harmonic content for %s:\n', prevName);
    for h = [2 3 4]
        target_f  = fmeas_fft_p * h;
        band_h    = (f_vec_p >= target_f - fmeas_fft_p*0.1) & ...
                    (f_vec_p <= target_f + fmeas_fft_p*0.1);
        if any(band_h)
            [h_amp, li]  = max(P1_p(band_h));
            bi           = find(band_h);
            actual_h_f   = f_vec_p(bi(li));
            fprintf('    %df (%.2f Hz): Amp=%.5f, Rel=%.1f%%\n', ...
                h, actual_h_f, h_amp, (h_amp/main_amp)*100);
        else
            fprintf('    %df (%.2f Hz): Not found in spectrum.\n', h, target_f);
        end
    end

    % Camera preview
    if debugCamSeries && hasCamIndex
        camKeys      = fieldnames(camDataStore);
        matchedCamKeys = {};
        for ik = 1:length(camKeys)
            if strcmp(camDataStore.(camKeys{ik}).AcousticFile, prevName)
                matchedCamKeys{end+1} = camKeys{ik}; %#ok<AGROW>
            end
        end

        if isempty(matchedCamKeys)
            fprintf('  [CAM PREVIEW] No camera series for: %s\n', prevName);
        else
            for iCK = 1:length(matchedCamKeys)
                ck  = matchedCamKeys{iCK};
                cam = camDataStore.(ck);
                fprintf('  [CAM PREVIEW] Camera at x=%.2fm: %s\n', ...
                    cam.CamLoc_m, cam.TSfilename);

                t_cam_prev   = cam.t_s;
                sig_cam_prev = cam.eta_m;
                Fs_cam_prev  = cam.Fs_cam_Hz;
                fSet_cam     = cam.SetFreq_Hz;

                valid_cam        = ~isnan(sig_cam_prev);
                t_cam_valid_prev = t_cam_prev(valid_cam);
                sig_cam_valid    = sig_cam_prev(valid_cam) - mean(sig_cam_prev(valid_cam),'omitnan');
                if length(sig_cam_valid) < 20; continue; end

                Fs_cam_eff_prev = 1 / mean(diff(t_cam_valid_prev));
                [fmeas_cam_prev, f_vec_cam_prev, P1_cam_prev] = ...
                    wm_fft_frequency(sig_cam_valid, Fs_cam_eff_prev, fSet_cam, freqTol);

                if vid_filterEnable
                    sig_cam_filt_prev = wm_filter_signal_v2(sig_cam_valid, ...
                        Fs_cam_eff_prev, vid_filterMode, vid_fc_lp, ...
                        fmeas_cam_prev, vid_bp_frac, vid_bp_order, cam.TSfilename);
                else
                    sig_cam_filt_prev = sig_cam_valid;
                end

                env_cam_raw_prev = abs(hilbert(sig_cam_filt_prev));
                sw_cam = max(1, round(vid_env_smooth_periods * Fs_cam_eff_prev / fmeas_cam_prev));
                env_cam_prev     = movmean(env_cam_raw_prev, sw_cam);
                ameas_cam_prev   = mean(env_cam_prev);

                wm_plot_debug_v2( ...
                    t_cam_valid_prev, sig_cam_valid, sig_cam_valid, ...
                    sig_cam_filt_prev, t_cam_valid_prev, sig_cam_filt_prev, ...
                    env_cam_prev, ameas_cam_prev, 0, false, amplitudeMethod, ...
                    sprintf('CAM_%s_x%.2fm', prevName, cam.CamLoc_m), ...
                    0, vid_filterEnable, vid_filterMode);

                wm_plot_fft_debug(f_vec_cam_prev, P1_cam_prev, ...
                    fmeas_cam_prev, fSet_cam, freqTol, ...
                    sprintf('CAM_%s_x%.2fm', cam.TSfilename, cam.CamLoc_m), ...
                    vid_filterEnable, vid_filterMode, vid_bp_frac);
            end
        end
    end

end % preview loop


%% =========================================================
%  SECTION 4: MAIN PROCESSING LOOP
% =========================================================
disp('======================================================');
disp('--- Section 4: Main Processing Loop ---');
disp('======================================================');

hWait = waitbar(0, 'Processing files...');

for i = 1:numFiles

    try

    if isgraphics(hWait)
        waitbar(i/numFiles, hWait, sprintf('Processing file %d / %d...', i, numFiles));
    end

    fileName = allFiles(i).name;
    fullPath = fullfile(allFiles(i).folder, fileName);

    % 4a. Filename parsing
    [fMode, fChannel, fDate, fAmp, fFreq, Fs, parseOK] = ...
        wm_parse_filename(fileName, Fs_default);
    if ~parseOK
        fprintf('  [SKIP] wm_parse_filename failed: %s\n', fileName); continue;
    end
    fprintf('\nFILE: %s\n  Mode=%s | Fs=%d Hz | Ch=%d | Date=%s | A_set=%.3fV | f_set=%.3fHz\n', ...
        fileName, fMode, Fs, fChannel, fDate, fAmp, fFreq);

    % 4b. Read raw acoustic signal
    [t, rawMat, ~, readOK] = wm_read_signal(fullPath, Fs);
    if ~readOK
        fprintf('  [SKIP] wm_read_signal failed: %s\n', fileName); continue;
    end
    Fs_t = 1 / mean(diff(t));

    % 4c. Location metadata lookup
    metaIdx = wm_lookup_metadata(locExpanded, fChannel, fDate);
    if isempty(metaIdx)
        fprintf('  [SKIP] No metadata for Ch=%d, Date=%s\n', fChannel, fDate);
        skippedMeta = skippedMeta + 1; continue;
    end

    % 4d. Camera series matching
    %  The pairing CSV stores filenames WITHOUT .csv extension;
    %  we try both bare name and with extension stripped.
    [~, fileBase, ~] = fileparts(fileName);
    pairRow = find(strcmp(string(pairMeta.Acoustic_sensor_filename), fileBase), 1);
    if isempty(pairRow)
        % Try with .csv appended (old format fallback)
        pairRow = find(strcmp(string(pairMeta.Acoustic_sensor_filename), ...
            [fileBase '.csv']), 1);
    end

    hasCamMatch  = false;
    camMatchKeys = {};

    if ~isempty(pairRow) && hasCamIndex
        if ismember('wave_time_series_sidecam', pairMeta.Properties.VariableNames)
            camCSVname = strtrim(string(pairMeta.wave_time_series_sidecam(pairRow)));
            if strlength(camCSVname) > 0
                ck_all = fieldnames(camDataStore);
                for ikk = 1:length(ck_all)
                    if strcmp(camDataStore.(ck_all{ikk}).TSfilename, char(camCSVname)) || ...
                       strcmp(camDataStore.(ck_all{ikk}).AcousticFile, fileBase)
                        camMatchKeys{end+1} = ck_all{ikk}; %#ok<AGROW>
                    end
                end
                if ~isempty(camMatchKeys)
                    hasCamMatch = true;
                    fprintf('  Camera series matched: %d entry(ies) for %s\n', ...
                        length(camMatchKeys), fileName);
                end
            end
        else
            % No wave_time_series_sidecam column — match by acoustic filename only
            ck_all = fieldnames(camDataStore);
            for ikk = 1:length(ck_all)
                if strcmp(camDataStore.(ck_all{ikk}).AcousticFile, fileBase)
                    camMatchKeys{end+1} = ck_all{ikk}; %#ok<AGROW>
                end
            end
            if ~isempty(camMatchKeys); hasCamMatch = true; end
        end
    end

    if ~hasCamMatch
        fprintf('  [INFO] No camera match — acoustic-only for: %s\n', fileName);
    end

    % Inner loop: signal columns × metadata rows
    for c = 1:size(rawMat, 2)
        rawSig = rawMat(:, c);

        for m = 1:length(metaIdx)
            sensorID = locExpanded.SensorID(metaIdx(m));
            xLoc     = locExpanded.x_m(metaIdx(m));

            % 4e. Calibration V -> m
            [sig_cal, calOK] = wm_apply_calibration(rawSig, calData, sensorID, fMode);
            if ~calOK
                skippedCal = skippedCal + 1; continue;
            end
            sig_cal_raw = sig_cal;

            % 4e2. Despiking
            n_spikes = 0;
            if despike_enable
                [sig_cal, n_spikes] = wm_despike_v2(sig_cal, Fs_t, ...
                    despike_win_s, despike_thresh, despike_mode);
            end

            % 4f. Steady-state window
            t_end_use = t(end);
            if t_end_sensors > 0; t_end_use = min(t_end_sensors, t(end)); end
            ss_mask = (t >= t_start_sensors) & (t <= t_end_use);
            if sum(ss_mask) < 50
                fprintf('  [SKIP] SS window < 50 samples.\n');
                skippedCal = skippedCal + 1; continue;
            end
            sig_ss   = sig_cal(ss_mask);
            t_ss     = t(ss_mask);
            Ns       = length(sig_ss);
            delta_f_ss = Fs_t / Ns;

            % 4g. FFT frequency
            [fmeas_fft, f_vec_dbg, P1_dbg] = ...
                wm_fft_frequency(sig_ss, Fs_t, fFreq, freqTol);

            % 4h. Filter
            if filterEnable
                sig_filt = wm_filter_signal_v2(sig_ss, Fs_t, filterMode, ...
                    fc_lp, fmeas_fft, bp_frac, bp_order, fileName);
            else
                sig_filt = sig_ss;
            end

            % 4i. Amplitude (Hilbert envelope)
            [ameas, env, delta_A] = wm_estimate_amplitude(sig_filt, amplitudeMethod, ...
                fmeas_fft, Fs_t, env_smooth_periods);

            % 4j. Store acoustic result
            res_Measurement(kOut) = "Acoustic_Sensor";
            res_File(kOut)        = fileName;
            res_Mode(kOut)        = fMode;
            res_Date(kOut)        = fDate;
            res_SensorID(kOut)    = sensorID;
            res_Channel(kOut)     = fChannel;
            res_SensorLoc(kOut)   = xLoc;
            res_InputAmp(kOut)    = fAmp;
            res_InputFreq(kOut)   = fFreq;
            res_FFT_Freq(kOut)    = fmeas_fft;
            res_MeanFreq(kOut)    = fmeas_fft;
            res_MeanAmp(kOut)     = ameas;
            res_UncAmp(kOut)      = delta_A;
            res_UncFreq(kOut)     = delta_f_ss;

            if filterEnable
                sig_full_filt = wm_filter_signal_v2(sig_cal, Fs_t, filterMode, ...
                    fc_lp, fmeas_fft, bp_frac, bp_order, fileName);
            else
                sig_full_filt = sig_cal;
            end
            env_full_raw = abs(hilbert(sig_full_filt));
            sw_full      = max(1, round(env_smooth_periods * Fs_t / fmeas_fft));
            env_full     = movmean(env_full_raw, sw_full);

            timeSeriesData(kOut).Name      = sprintf('x=%.2fm S%d', xLoc, sensorID);
            timeSeriesData(kOut).Time      = t;
            timeSeriesData(kOut).Signal    = sig_full_filt;
            timeSeriesData(kOut).Envelope  = env_full;
            timeSeriesData(kOut).Amplitude = ameas;
            timeSeriesData(kOut).Loc       = xLoc;
            timeSeriesData(kOut).SensorID  = sensorID;
            timeSeriesData(kOut).Mode      = char(fMode);

            kOut = kOut + 1;

            % =========================================================
            %  4-CAM: CAMERA WAVE SERIES PROCESSING
            % =========================================================
            if ~hasCamMatch; continue; end

            for iCK = 1:length(camMatchKeys)
                ck  = camMatchKeys{iCK};
                cam = camDataStore.(ck);

                fprintf('  [CAM] Processing: %s (x=%.2fm)\n', ...
                    cam.TSfilename, cam.CamLoc_m);

                t_cam_raw   = cam.t_s;
                sig_cam_raw = cam.eta_m;
                Fs_cam      = cam.Fs_cam_Hz;
                camLoc      = cam.CamLoc_m;

                valid_cam   = ~isnan(sig_cam_raw);
                t_cam_valid = t_cam_raw(valid_cam);
                sig_cam     = sig_cam_raw(valid_cam) - mean(sig_cam_raw(valid_cam),'omitnan');
                N_cam       = length(sig_cam);

                if N_cam < 2 * round(Fs_cam / fFreq)
                    fprintf('  [CAM SKIP] Too few valid frames (%d).\n', N_cam);
                    continue;
                end

                Fs_cam_eff  = 1 / mean(diff(t_cam_valid));
                delta_f_cam = Fs_cam_eff / N_cam;

                [fmeas_cam, ~, ~] = wm_fft_frequency(sig_cam, Fs_cam_eff, fFreq, freqTol);
                if ~isfinite(fmeas_cam)
                    fprintf('  [CAM SKIP] FFT frequency invalid.\n'); continue;
                end

                if vid_filterEnable
                    sig_cam_filt = wm_filter_signal_v2(sig_cam, Fs_cam_eff, ...
                        vid_filterMode, vid_fc_lp, fmeas_cam, ...
                        vid_bp_frac, vid_bp_order, cam.TSfilename);
                else
                    sig_cam_filt = sig_cam;
                end

                % Method 1: Peak-to-trough
                  % ----------------------------------------------------------
                %  Compute mean per-frame position uncertainty [m].
                %  These come from the HWHM-based estimates in pick_best_peak,
                %  saved as columns in the camera time-series CSV and loaded
                %  into camDataStore in Section 2.
                %
                %  mean(...,'omitnan') handles frames where detection failed
                %  (NaN entries).  If the whole column is NaN (old CSV format
                %  without uncertainty columns), mean_surf_unc_m falls back
                %  to NaN, and wm_cam_amplitude will use the 0.2px floor.
                % ----------------------------------------------------------
                if isfield(cam, 'surf_unc_m') && ~isempty(cam.surf_unc_m)
                    % Only use uncertainty values from the valid (non-NaN signal) frames
                    mean_surf_unc_m = mean(cam.surf_unc_m(valid_cam), 'omitnan');
                else
                    mean_surf_unc_m = NaN;   % triggers 0.2px fallback in wm_cam_amplitude
                end
 
                if isfield(cam, 'ice_unc_m') && ~isempty(cam.ice_unc_m)
                    mean_ice_unc_m = mean(cam.ice_unc_m(valid_cam), 'omitnan');
                else
                    mean_ice_unc_m = NaN;
                end
 
                fprintf('  [CAM] mean surf unc = %.6f m   mean ice unc = %.6f m\n', ...
                    mean_surf_unc_m, mean_ice_unc_m);
           
                % mm_per_px is not available in this script (calibration was
                % done in tank_process_sidecam); we pass mean_surf_unc_m directly
                % as the position uncertainty, bypassing the px-based floor.
                % The 4th argument (mm_per_px) is only used as fallback when
                % mean_pos_unc_m is NaN — pass 1e-6 as a near-zero dummy so
                % the HWHM value dominates whenever it is available.
                [A_cam_PT, delta_A_cam_PT] = wm_cam_amplitude( ...
                    sig_cam_filt, Fs_cam_eff, fmeas_cam, ...
                    1e-6, ...              % mm_per_px dummy (uncertainty comes from HWHM)
                    mean_surf_unc_m);      % <-- NEW: HWHM-based position uncertainty [m]

                % Method 2: Hilbert envelope
                env_cam_raw     = abs(hilbert(sig_cam_filt));
                sw_cam          = max(1, round(vid_env_smooth_periods * Fs_cam_eff / fmeas_cam));
                env_cam         = movmean(env_cam_raw, sw_cam);
                A_cam_Env       = mean(env_cam);
                N_eff_cam       = max(1, floor(length(env_cam) / sw_cam));
                delta_A_cam_Env = std(env_cam) / sqrt(N_eff_cam);

                fprintf('  [CAM] f_meas=%.4f Hz  A_PT=%.5f m  A_Env=%.5f m\n', ...
                    fmeas_cam, A_cam_PT, A_cam_Env);

                % Camera diagnostic plot
                hFinalCam = figure('Name', ...
                    sprintf('Cam Wave -- %s | x=%.2fm', cam.TSfilename, camLoc));
                axCam = axes(hFinalCam);
                hold(axCam,'on'); grid(axCam,'on');

                plot(axCam, t_cam_valid, sig_cam, ...
                    'Color',[0.7 0.7 0.7],'LineWidth',0.6,'DisplayName','Raw');
                if vid_filterEnable
                    plot(axCam, t_cam_valid, sig_cam_filt, ...
                        'Color',[0.2 0.6 0.2],'LineWidth',1.0, ...
                        'DisplayName',sprintf('Filtered (%s)', vid_filterMode));
                end
                plot(axCam, t_cam_valid, env_cam, 'r--','LineWidth',1.2, ...
                    'DisplayName', sprintf('Envelope (%d periods)', vid_env_smooth_periods));
                yline(axCam,  A_cam_PT,  '-','Color',[0.85 0.10 0.10],'LineWidth',2.0, ...
                    'DisplayName', sprintf('A_PT = %.4fm +/- %.4fm', A_cam_PT, delta_A_cam_PT));
                yline(axCam, -A_cam_PT,  '-','Color',[0.85 0.10 0.10],'LineWidth',2.0, ...
                    'HandleVisibility','off');
                yline(axCam,  A_cam_Env, '--','Color',[0.70 0.10 0.70],'LineWidth',1.5, ...
                    'DisplayName', sprintf('A_Env = %.4fm +/- %.4fm', A_cam_Env, delta_A_cam_Env));
                yline(axCam, -A_cam_Env, '--','Color',[0.70 0.10 0.70],'LineWidth',1.5, ...
                    'HandleVisibility','off');
                xlabel(axCam,'$t$ (s)',    'Interpreter','latex','FontSize',11);
                ylabel(axCam,'$\eta$ (m)', 'Interpreter','latex','FontSize',11);
                title(axCam, sprintf('Camera wave: %s  |  x=%.2f m', ...
                    cam.TSfilename, camLoc), 'Interpreter','none','FontSize',10);
                legend(axCam,'show','Location','best','Interpreter','none','FontSize',9);

                % Store camera result
                res_Measurement(kOut) = "Side_Camera";
                res_File(kOut)        = string(cam.TSfilename);
                res_Mode(kOut)        = fMode;
                res_Date(kOut)        = fDate;
                res_SensorID(kOut)    = NaN;
                res_Channel(kOut)     = NaN;
                res_SensorLoc(kOut)   = camLoc;
                res_InputAmp(kOut)    = fAmp;
                res_InputFreq(kOut)   = fFreq;
                res_FFT_Freq(kOut)    = fmeas_cam;
                res_MeanFreq(kOut)    = fmeas_cam;
                res_MeanAmp(kOut)     = A_cam_PT;
                res_UncAmp(kOut)      = delta_A_cam_PT;
                res_UncFreq(kOut)     = delta_f_cam;
                res_MeanAmp_PT(kOut)  = A_cam_PT;
                res_UncAmp_PT(kOut)   = delta_A_cam_PT;
                res_MeanAmp_Env(kOut) = A_cam_Env;
                res_UncAmp_Env(kOut)  = delta_A_cam_Env;
                kOut = kOut + 1;

            end % camera match loop
        end % metadata row loop
    end % signal column loop

    catch ME_loop
        fprintf(2, '\n>>> [ERROR in file %d: %s] <<<\n', i, fileName);
        fprintf(2, '>>> %s\n', ME_loop.message);
        if ~isempty(ME_loop.stack)
            fprintf(2, '>>> Line: %d\n', ME_loop.stack(1).line);
        end
        fprintf('  Skipping. Results so far (%d rows) preserved.\n', kOut-1);
    end

end % main file loop
close(hWait);


%% =========================================================
%  TRIM ARRAYS TO ACTUAL SIZE
% =========================================================
n_rows = kOut - 1;
fields = {'res_Measurement','res_File','res_Mode','res_Date','res_SensorID', ...
    'res_Channel','res_SensorLoc','res_InputAmp','res_InputFreq','res_FFT_Freq', ...
    'res_MeanAmp','res_MeanFreq','res_UncAmp','res_UncFreq', ...
    'res_MeanAmp_PT','res_UncAmp_PT','res_MeanAmp_Env','res_UncAmp_Env'};
for kf = 1:length(fields)
    eval([fields{kf} ' = ' fields{kf} '(1:n_rows);']);
end


%% =========================================================
%  SECTION 4-REPORT: CONSOLE SUMMARY
% =========================================================
fprintf('\n================ FINAL REPORT ================\n');
fprintf('Amplitude method:     ENVELOPE (Hilbert)\n');
fprintf('Filter:               %s\n', mat2str(filterEnable));
if filterEnable; fprintf('Filter mode:          %s\n', filterMode); end
fprintf('Total result rows:    %d\n', n_rows);
fprintf('Skipped (no meta):    %d\n', skippedMeta);
fprintf('Skipped (other):      %d\n', skippedCal);

idx_acou = find(res_Measurement == "Acoustic_Sensor");
idx_cam  = find(res_Measurement == "Side_Camera");
fprintf('Acoustic rows:        %d\n', length(idx_acou));
fprintf('Camera rows:          %d\n', length(idx_cam));

all_amp_diff = []; all_freq_diff = [];
uniquePairs  = unique([res_InputAmp, res_InputFreq], 'rows');
for ip = 1:size(uniquePairs,1)
    aSet=uniquePairs(ip,1); fSet=uniquePairs(ip,2);
    ia=idx_acou(res_InputAmp(idx_acou)==aSet & res_InputFreq(idx_acou)==fSet);
    ic=idx_cam( res_InputAmp(idx_cam) ==aSet & res_InputFreq(idx_cam) ==fSet);
    if isempty(ia)||isempty(ic); continue; end
    all_amp_diff(end+1)  = abs(mean(res_MeanAmp(ic))  - mean(res_MeanAmp(ia)));  %#ok<AGROW>
    all_freq_diff(end+1) = abs(mean(res_MeanFreq(ic)) - mean(res_MeanFreq(ia))); %#ok<AGROW>
    fprintf('  A=%.3fV f=%.3fHz | dA=%.5fm | df=%.5fHz\n', ...
        aSet,fSet,all_amp_diff(end),all_freq_diff(end));
end
final_amp_error  = mean(all_amp_diff,  'omitnan');
final_freq_error = mean(all_freq_diff, 'omitnan');
fprintf('\n>>> Mean |cam-acoustic| amplitude  = %.6f m\n',  final_amp_error);
fprintf('>>> Mean |cam-acoustic| frequency  = %.6f Hz\n', final_freq_error);
fprintf('=============================================\n');


%% =========================================================
%  SECTION 5: PLOTTING
% =========================================================
disp('======================================================');
disp('--- Section 5: Generating Plots ---');
disp('======================================================');

% Choose camera amplitude column for Plots 6/7
res_MeanAmp_plot = res_MeanAmp;
res_UncAmp_plot  = res_UncAmp;
switch lower(cam_amp_method)
    case 'pt'
        res_MeanAmp_plot(idx_cam) = res_MeanAmp_PT(idx_cam);
        res_UncAmp_plot(idx_cam)  = res_UncAmp_PT(idx_cam);
        cam_method_label = 'Peak-to-trough';
    case 'envelope'
        res_MeanAmp_plot(idx_cam) = res_MeanAmp_Env(idx_cam);
        res_UncAmp_plot(idx_cam)  = res_UncAmp_Env(idx_cam);
        cam_method_label = 'Hilbert envelope';
    otherwise
        error('Unknown cam_amp_method: "%s".', cam_amp_method);
end

figHandles   = {};
figBaseNames = {};

if ~isempty(idx_acou)
    uniqueLocs  = unique(res_SensorLoc(idx_acou));
    uniqueAmps  = unique(res_InputAmp( idx_acou(~isnan(res_InputAmp(idx_acou)))));
    uniqueFreqs = unique(res_InputFreq(idx_acou(~isnan(res_InputFreq(idx_acou)))));
else
    uniqueLocs=[]; uniqueAmps=[]; uniqueFreqs=[];
end

modeStyleMap.LOW.color       = [0.20 0.45 0.75];
modeStyleMap.LOW.linestyle   = '-';
modeStyleMap.LOW.marker      = 'o';
modeStyleMap.HIGH.color      = [0.85 0.33 0.10];
modeStyleMap.HIGH.linestyle  = '--';
modeStyleMap.HIGH.marker     = 's';
modeStyleMap.UNKNOWN.color      = [0.6 0.1 0.6];
modeStyleMap.UNKNOWN.linestyle  = ':';
modeStyleMap.UNKNOWN.marker     = '^';

freqColorMap = lines(max(length(uniqueFreqs),1));
getFreqColor = @(f) freqColorMap(find(uniqueFreqs==f,1),:);


%% --- Plot 2: Mean Amplitude vs Sensor Location ---
for ia = 1:length(uniqueAmps)
    ampSet = uniqueAmps(ia);
    if ampSet == 4
        idxA = idx_acou(res_InputAmp(idx_acou)==ampSet & ...
                        res_InputFreq(idx_acou)==1 & ...
                        ~isnan(res_MeanAmp(idx_acou)));
    else
        idxA = idx_acou(res_InputAmp(idx_acou)==ampSet & ...
                        ~isnan(res_MeanAmp(idx_acou)));
    end
    fAmpFig = figure('Name', sprintf('Amp_vs_Loc_A%.2f_envelope', ampSet));
    ax2 = axes(fAmpFig); hold(ax2,'on'); grid(ax2,'on');
    plottedModes2 = strings(0);
    for ii = idxA'
        st  = wm_style_for_mode(res_Mode(ii), modeStyleMap);
        ms2 = string(res_Mode(ii));
        hVis = 'off'; dName = '';
        if ~ismember(ms2, plottedModes2); hVis='on'; dName=ms2; plottedModes2(end+1)=ms2; end
        errorbar(ax2, res_SensorLoc(ii), res_MeanAmp(ii), ...
            res_UncAmp(ii), res_UncAmp(ii), delta_x_m, delta_x_m, ...
            st.marker,'Color',st.color,'MarkerFaceColor','none', ...
            'MarkerSize',7,'CapSize',8,'LineWidth',1.2, ...
            'DisplayName',dName,'HandleVisibility',hVis);
    end
    legend(ax2,'show','Location','best','Interpreter','none');
    xlabel(ax2,'x (m)',   'Interpreter','latex','FontSize',11);
    ylabel(ax2,'$\bar{\eta}$ (m)','Interpreter','latex','FontSize',11);
    title(ax2, sprintf('$A_{set}$ = %.3f V', ampSet),'Interpreter','latex','FontSize',11);
    figHandles{end+1}   = fAmpFig;
    figBaseNames{end+1} = sprintf('Plot2_MeanAmplitude_vs_Loc_A%.3fV', ampSet);
end


%% --- Plot 4: Amplitude Calibration ---
fixedFreq = 1.0;
idxF4     = idx_acou(res_InputFreq(idx_acou)==fixedFreq & ~isnan(res_MeanAmp(idx_acou)));

f4 = figure('Name','Amp_Calib_envelope');
ax4 = axes(f4); hold(ax4,'on'); grid(ax4,'on');

uniqueModes4     = unique(res_Mode(idxF4));
calResultsPerLoc = table();
uniqueLocs4      = unique(res_SensorLoc(idxF4));
locColors4       = lines(length(uniqueLocs4));
plottedModes4    = strings(0);
plottedLocs4     = [];

for ii = 1:length(uniqueModes4)
    mStr    = uniqueModes4(ii);
    st      = wm_style_for_mode(mStr, modeStyleMap);
    idxMode = idxF4(strcmp(res_Mode(idxF4), mStr));
    if ~ismember(string(mStr), plottedModes4)
        plot(ax4, NaN, NaN, 'k', 'Marker',st.marker,'LineStyle','none', ...
            'MarkerFaceColor','k','DisplayName',sprintf('Mode: %s', mStr));
        plottedModes4(end+1) = string(mStr);
    end
    for lj = 1:length(unique(res_SensorLoc(idxMode)))
        curX   = unique(res_SensorLoc(idxMode));  curX = curX(lj);
        locIdx = find(uniqueLocs4 == curX);
        cLoc   = locColors4(locIdx, :);
        if ~ismember(curX, plottedLocs4)
            plot(ax4, NaN, NaN,'Color',cLoc,'LineStyle','-','LineWidth',1.5, ...
                'DisplayName',sprintf('x = %.2f m', curX));
            plottedLocs4(end+1) = curX;
        end
        idxML       = idxMode(res_SensorLoc(idxMode)==curX);
        x_data_all  = res_InputAmp(idxML);
        y_data_all  = res_MeanAmp(idxML);
        ey_data_all = res_UncAmp(idxML);
        above = y_data_all > amp_resolution_m;
        if any(~above)
            plot(ax4, x_data_all(~above), y_data_all(~above),'o', ...
                'Color',cLoc,'MarkerFaceColor','none','HandleVisibility','off');
        end
        x_data=x_data_all(above); y_data=y_data_all(above); ey_data=ey_data_all(above);
        if ~skipCalib && length(x_data)>=2
            npts=length(x_data); p=polyfit(x_data,y_data,1);
            xfit=linspace(min(x_data),max(x_data),50);
            y_fit=polyval(p,x_data); resid=y_data-y_fit;
            SS_res=sum(resid.^2); SS_tot=sum((y_data-mean(y_data)).^2);
            R2=1-SS_res/max(SS_tot,eps); sigma2=SS_res/(npts-2);
            x_mean=mean(x_data); Sxx=sum((x_data-x_mean).^2);
            SE_slope=sqrt(sigma2/Sxx); SE_int=sqrt(sigma2*sum(x_data.^2)/(npts*Sxx));
            plot(ax4,xfit,polyval(p,xfit),'Color',cLoc,'LineWidth',1.0, ...
                'LineStyle','-','HandleVisibility','off');
            sID=res_SensorID(idxML(1));
            row=table(curX,sID,p(1),SE_slope,p(2),SE_int,R2,sqrt(sigma2),mStr,npts, ...
                'VariableNames',{'Sensor_Location_m','Sensor_Number', ...
                'Slope_m_per_V','Slope_SE_m_per_V','Intercept_m', ...
                'Intercept_SE_m','R2','RMSE_m','Mode','N_points_used'});
            calResultsPerLoc=[calResultsPerLoc;row]; %#ok<AGROW>
        end
        if ~isempty(x_data)
            errorbar(ax4,x_data,y_data,ey_data,ey_data, ...
                delta_V_set*ones(size(x_data)),delta_V_set*ones(size(x_data)), ...
                st.marker,'Color',cLoc,'MarkerFaceColor',cLoc, ...
                'HandleVisibility','off','CapSize',3,'LineWidth',0.8);
        end
    end
end
yline(ax4,amp_resolution_m,'k--','LineWidth',1.2, ...
    'Label',sprintf('Resolution %.4f m',amp_resolution_m), ...
    'LabelHorizontalAlignment','left','LabelVerticalAlignment','bottom', ...
    'DisplayName',sprintf('Resolution (%.4f m)',amp_resolution_m));
legend(ax4,'show','Location','northeastoutside','FontSize',8,'Interpreter','none');
xlabel(ax4,'A_{set} (V)','Interpreter','none','FontSize',11);
ylabel(ax4,'$\bar{\eta}$ (m)','Interpreter','latex','FontSize',11);
figHandles{end+1}=f4; figBaseNames{end+1}='Plot4_AmpCalib_envelope';


%% --- Plot 5: Frequency Check ---
f5=figure('Name','Freq_Check'); ax5=axes(f5); hold(ax5,'on'); grid(ax5,'on');
errorbar(ax5,res_InputFreq(idx_acou),res_MeanFreq(idx_acou), ...
    res_UncFreq(idx_acou),res_UncFreq(idx_acou), ...
    zeros(length(idx_acou),1),zeros(length(idx_acou),1), ...
    'b.','CapSize',3,'LineWidth',0.8,'DisplayName','Acoustic');
if ~isempty(idx_cam)
    errorbar(ax5,res_InputFreq(idx_cam),res_MeanFreq(idx_cam), ...
        res_UncFreq(idx_cam),res_UncFreq(idx_cam), ...
        zeros(length(idx_cam),1),zeros(length(idx_cam),1), ...
        '+','Color',[0.85 0.33 0.10],'CapSize',3,'LineWidth',0.8,'DisplayName','Camera');
end
line(ax5,[0 5],[0 5],'Color','k','LineStyle','--','DisplayName','1:1 reference');
legend(ax5,'show','Location','best','Interpreter','none');
xlabel(ax5,'$f_{set}$ (Hz)','Interpreter','latex','FontSize',11);
ylabel(ax5,'$f_{meas}$ (Hz)','Interpreter','latex','FontSize',11);
figHandles{end+1}=f5; figBaseNames{end+1}='Plot5_FreqCheck';


%% --- Plot 6: Amplitude vs Set Voltage ---
f6=figure('Name','Amplitude_vs_SetVoltage'); ax6=axes(f6); hold(ax6,'on'); grid(ax6,'on');
allXlocs6=unique([res_SensorLoc(idx_acou(~isnan(res_SensorLoc(idx_acou))));
                  res_SensorLoc(idx_cam( ~isnan(res_SensorLoc(idx_cam))))]);
allXlocs6=allXlocs6(~isnan(allXlocs6));
locColorMap6=lines(length(allXlocs6));
getLocColor6=@(x) locColorMap6(find(round(allXlocs6*100)==round(x*100),1),:);
fixedFreq6=1.0;
uniqueAcouLocs6=unique(res_SensorLoc(idx_acou(~isnan(res_SensorLoc(idx_acou)))));
for iX=1:length(uniqueAcouLocs6)
    xLoc6=uniqueAcouLocs6(iX); cColor=getLocColor6(xLoc6);
    idxX=idx_acou(res_SensorLoc(idx_acou)==xLoc6 & res_InputFreq(idx_acou)==fixedFreq6 & ...
                  ~isnan(res_MeanAmp_plot(idx_acou)));
    if isempty(idxX); continue; end
    [vs,si]=sort(res_InputAmp(idxX)); as=res_MeanAmp_plot(idxX(si)); us=res_UncAmp_plot(idxX(si));
    errorbar(ax6,vs,as,us,us,delta_V_set*ones(size(vs)),delta_V_set*ones(size(vs)), ...
        'o','Color',cColor,'MarkerFaceColor','none','MarkerSize',7, ...
        'CapSize',10,'LineWidth',1.5,'DisplayName',sprintf(' x=%.2fm',xLoc6));
end
if ~isempty(idx_cam)
    uniqueCamLocs6=unique(res_SensorLoc(idx_cam(~isnan(res_SensorLoc(idx_cam)))));
    for iX=1:length(uniqueCamLocs6)
        xLoc6=uniqueCamLocs6(iX); cColor=getLocColor6(xLoc6);
        idxCX=idx_cam(res_SensorLoc(idx_cam)==xLoc6 & res_InputFreq(idx_cam)==fixedFreq6 & ...
                      ~isnan(res_MeanAmp_plot(idx_cam)));
        if isempty(idxCX); continue; end
        [vs,si]=sort(res_InputAmp(idxCX)); as=res_MeanAmp_plot(idxCX(si)); us=res_UncAmp_plot(idxCX(si));
        errorbar(ax6,vs,as,us,us,delta_V_set*ones(size(vs)),delta_V_set*ones(size(vs)), ...
            'x','Color',cColor,'MarkerSize',10,'LineWidth',1.5,'CapSize',10, ...
            'DisplayName',sprintf('Camera x=%.2fm',xLoc6));
    end
end
plot(ax6,NaN,NaN,'ko','MarkerFaceColor','none','MarkerSize',7,'LineWidth',1.5,'DisplayName','Acoustic');
plot(ax6,NaN,NaN,'kx','MarkerSize',10,'LineWidth',1.5,'DisplayName','Camera');
legend(ax6,'show','Location','northwestoutside','FontSize',8,'Interpreter','none');
xlabel(ax6,'$A_{set}$ (V)','Interpreter','latex','FontSize',11);
ylabel(ax6,'$\bar{\eta}$ (m)','Interpreter','latex','FontSize',11);
title(ax6,sprintf('$f_{set}$ = %.1f Hz',fixedFreq6),'Interpreter','latex','FontSize',11);
figHandles{end+1}=f6; figBaseNames{end+1}='Plot6_Amplitude_vs_SetVoltage';


%% --- Plot 7: Camera Amplitude at Two Locations + Ratio ---
if ~isempty(idx_cam)
    fixedFreqCam=1.0;
    idx_cam_f1=idx_cam(res_InputFreq(idx_cam)==fixedFreqCam & ~isnan(res_MeanAmp_plot(idx_cam)));
    camLocs_f1=unique(res_SensorLoc(idx_cam_f1));
    if length(camLocs_f1)>=1
        fNew=figure('Name','Camera_Amplitude_vs_SetVolt_TwoLocs');
        yyaxis left; ax7L=gca; hold(ax7L,'on'); grid(ax7L,'on');
        ampHandles=gobjects(0); ampLabels={}; locPalette=lines(length(camLocs_f1));
        camAmpByLoc=cell(length(camLocs_f1),1);
        camVoltByLoc=cell(length(camLocs_f1),1);
        camUncByLoc=cell(length(camLocs_f1),1);
        for iCL=1:length(camLocs_f1)
            cLoc_cam=camLocs_f1(iCL); cColor=locPalette(iCL,:);
            idxCL=idx_cam_f1(res_SensorLoc(idx_cam_f1)==cLoc_cam);
            [vs,si]=sort(res_InputAmp(idxCL));
            as=res_MeanAmp_plot(idxCL(si)); us=res_UncAmp_plot(idxCL(si));
            camVoltByLoc{iCL}=vs; camAmpByLoc{iCL}=as; camUncByLoc{iCL}=us;
            hE=errorbar(ax7L,vs,as,us,us,delta_V_set*ones(size(vs)),delta_V_set*ones(size(vs)), ...
                'o','Color',cColor,'MarkerFaceColor','none','MarkerSize',8, ...
                'CapSize',10,'LineWidth',1.5, ...
                'DisplayName',sprintf('A%d  x=%.2fm',iCL,cLoc_cam));
            ampHandles(end+1)=hE; ampLabels{end+1}=sprintf('A%d  x=%.2fm',iCL,cLoc_cam);
        end
        ylabel(ax7L,'$\bar{\eta}$ (m)','Interpreter','latex','FontSize',11);
        ax7L.YColor='k';
        yyaxis right; ax7R=gca; hold(ax7R,'on');
        if length(camLocs_f1)==2
            v1=camVoltByLoc{1}; a1=camAmpByLoc{1}; e1=camUncByLoc{1};
            v2=camVoltByLoc{2}; a2=camAmpByLoc{2}; e2=camUncByLoc{2};
            v1r=round(v1*100)/100; v2r=round(v2*100)/100; vCom=intersect(v1r,v2r);
            if ~isempty(vCom)
                [v1u,~,ic1]=unique(v1r); a1u=accumarray(ic1,a1,[],@mean); e1u=accumarray(ic1,e1,[],@mean);
                [v2u,~,ic2]=unique(v2r); a2u=accumarray(ic2,a2,[],@mean); e2u=accumarray(ic2,e2,[],@mean);
                a1c=interp1(v1u,a1u,vCom); a2c=interp1(v2u,a2u,vCom);
                e1c=interp1(v1u,e1u,vCom); e2c=interp1(v2u,e2u,vCom);
                ratio=a2c./a1c;
                ratio_unc=ratio.*sqrt((e2c./max(a2c,eps)).^2+(e1c./max(a1c,eps)).^2);
                hR=errorbar(ax7R,vCom,ratio,ratio_unc,ratio_unc,'s', ...
                    'Color',[0.2 0.7 0.3],'MarkerFaceColor','none', ...
                    'MarkerSize',8,'CapSize',10,'LineWidth',1.5,'DisplayName','A2/A1');
                ylabel(ax7R,'A_2 / A_1','Interpreter','none','FontSize',11);
                ax7R.YColor=[0.2 0.7 0.3];
                legend(ax7L,[ampHandles,hR],[ampLabels,{'A2/A1'}], ...
                    'Location','northwestoutside','Interpreter','none','FontSize',9);
            else
                legend(ax7L,ampHandles,ampLabels,'Location','best','Interpreter','none','FontSize',9);
            end
        else
            legend(ax7L,ampHandles,ampLabels,'Location','best','Interpreter','none','FontSize',9);
        end
        yyaxis left;
        xlabel(ax7L,'$A_{set}$ (V)','Interpreter','latex','FontSize',11);
        title(ax7L,sprintf('Camera amplitude | $f_{set}$=%.1f Hz',fixedFreqCam), ...
            'Interpreter','latex','FontSize',10);
        figHandles{end+1}=fNew; figBaseNames{end+1}='Plot7_Camera_Amp_TwoLocs_Ratio';
    end
end


%% =========================================================
%  SECTION 5b: ATTENUATION ANALYSIS
% =========================================================
disp('--- Section 5b: Attenuation Analysis ---');
attenuationResults = table();
uniqueAmpFreq = unique([res_InputAmp(idx_acou), res_InputFreq(idx_acou)], 'rows');

for iGroup = 1:size(uniqueAmpFreq,1)
    ampSet=uniqueAmpFreq(iGroup,1); freqSet=uniqueAmpFreq(iGroup,2);
    idxGroup=idx_acou(res_InputAmp(idx_acou)==ampSet & ...
                      res_InputFreq(idx_acou)==freqSet & ...
                      ~isnan(res_MeanAmp(idx_acou)));
    modesHere=unique(res_Mode(idxGroup));
    for im=1:length(modesHere)
        modeStr=modesHere(im);
        idxGM=idxGroup(strcmp(res_Mode(idxGroup),modeStr));
        [xLocs_g,sI]=sort(res_SensorLoc(idxGM));
        amps_g=res_MeanAmp(idxGM(sI)); delta_g=res_UncAmp(idxGM(sI));
        [alpha,A0,R2att,delta_alpha,delta_A0,~,~]=...
            wm_compute_attenuation_weighted(xLocs_g,amps_g,delta_g);
        fprintf('  Atten: A=%.3fV f=%.3fHz [%s]: alpha=%.4f+-%.4f 1/m R2=%.4f\n', ...
            ampSet,freqSet,modeStr,alpha,delta_alpha,R2att);
        rowAtt=table(ampSet,freqSet,modeStr,alpha,delta_alpha,A0,delta_A0,R2att, ...
            'VariableNames',{'SetAmplitude_V','SetFrequency_Hz','Mode', ...
            'AttenuationRate_1perm','Unc_AttenuationRate_1perm', ...
            'ExtrapAmplitude_A0_m','Unc_ExtrapAmplitude_A0_m','R2_loglinear'});
        attenuationResults=[attenuationResults;rowAtt]; %#ok<AGROW>
    end
end


%% --- Plot 8: A_meas(x) per f_set ---
plot8_show_fit = false;
validAmpsPlot8 = [];
for ia=1:length(uniqueAmps)
    ampSet=uniqueAmps(ia);
    idxAmpAll=idx_acou(res_InputAmp(idx_acou)==ampSet & ~isnan(res_MeanAmp(idx_acou)));
    if length(unique(res_InputFreq(idxAmpAll)))>=n_freq_min
        validAmpsPlot8(end+1)=ampSet; %#ok<AGROW>
    end
end
if ~isempty(validAmpsPlot8)
    nSub8=length(validAmpsPlot8); nCols8=min(nSub8,3); nRows8=ceil(nSub8/nCols8);
    f8=figure('Name','Amplitude_vs_Position_byFreq');
    for iAmp=1:length(validAmpsPlot8)
        ampSet=validAmpsPlot8(iAmp); ax8=subplot(nRows8,nCols8,iAmp);
        hold(ax8,'on'); grid(ax8,'on');
        idxAmpAll=idx_acou(res_InputAmp(idx_acou)==ampSet & ~isnan(res_MeanAmp(idx_acou)));
        freqsHere=unique(res_InputFreq(idxAmpAll)); plottedFreqsGrp8=[];
        for iF=1:length(freqsHere)
            freqSet=freqsHere(iF); cFreq=getFreqColor(freqSet);
            idxAF=idxAmpAll(res_InputFreq(idxAmpAll)==freqSet);
            modesHere=unique(res_Mode(idxAF));
            for im=1:length(modesHere)
                modeStr=modesHere(im); st=wm_style_for_mode(modeStr,modeStyleMap);
                idxGM=idxAF(strcmp(res_Mode(idxAF),modeStr));
                [xSorted,sI]=sort(res_SensorLoc(idxGM));
                aSorted=res_MeanAmp(idxGM(sI)); daSorted=res_UncAmp(idxGM(sI));
                showF=~ismember(freqSet,plottedFreqsGrp8);
                dName=''; hVis='off';
                if showF; dName=sprintf('f=%.2fHz',freqSet); hVis='on'; plottedFreqsGrp8(end+1)=freqSet; end
                errorbar(ax8,xSorted,aSorted,daSorted,daSorted, ...
                    delta_x_m*ones(size(xSorted)),delta_x_m*ones(size(xSorted)), ...
                    st.marker,'Color',cFreq,'MarkerFaceColor',cFreq, ...
                    'MarkerSize',5,'CapSize',3,'LineWidth',0.8, ...
                    'DisplayName',dName,'HandleVisibility',hVis);
            end
        end
        legend(ax8,'show','Location','best','FontSize',7,'Interpreter','none');
        xlabel(ax8,'x (m)','Interpreter','latex','FontSize',10);
        ylabel(ax8,'$\bar{\eta}$ (m)','Interpreter','latex','FontSize',10);
        title(ax8,sprintf('$A_{set}$ = %.3f V',ampSet),'Interpreter','latex','FontSize',9);
    end
    figHandles{end+1}=f8; figBaseNames{end+1}='Plot8_AmplitudeVsPosition_byFreq';
end


%% --- Plot 9: Attenuation rate vs f_set ---
validAmpsPlot9=[];
for ia=1:length(uniqueAmps)
    ampSet=uniqueAmps(ia);
    idxA9=find(attenuationResults.SetAmplitude_V==ampSet);
    if length(unique(attenuationResults.SetFrequency_Hz(idxA9)))==n_freq_required
        validAmpsPlot9(end+1)=ampSet; %#ok<AGROW>
    end
end
if ~isempty(validAmpsPlot9)
    nSub9=length(validAmpsPlot9); nCols9=min(nSub9,3); nRows9=ceil(nSub9/nCols9);
    f9=figure('Name','AttenuationRate_vs_Frequency');
    for iAmp=1:length(validAmpsPlot9)
        ampSet=validAmpsPlot9(iAmp); ax9=subplot(nRows9,nCols9,iAmp);
        hold(ax9,'on'); grid(ax9,'on');
        idxAtt=find(attenuationResults.SetAmplitude_V==ampSet);
        plottedModesGrp9={};
        for ia=idxAtt'
            st=wm_style_for_mode(attenuationResults.Mode(ia),modeStyleMap);
            showM=~ismember(char(attenuationResults.Mode(ia)),plottedModesGrp9);
            hVis='off'; dName='';
            if showM; dName=char(attenuationResults.Mode(ia)); hVis='on'; plottedModesGrp9{end+1}=dName; end
            errorbar(ax9,attenuationResults.SetFrequency_Hz(ia), ...
                attenuationResults.AttenuationRate_1perm(ia), ...
                attenuationResults.Unc_AttenuationRate_1perm(ia), ...
                attenuationResults.Unc_AttenuationRate_1perm(ia), ...
                st.marker,'Color',st.color,'MarkerFaceColor',st.color, ...
                'CapSize',4,'LineWidth',0.8,'DisplayName',dName,'HandleVisibility',hVis);
        end
        yline(ax9,0,'k:','LineWidth',0.8,'HandleVisibility','off');
        legend(ax9,'show','Location','best','FontSize',7,'Interpreter','none');
        xlabel(ax9,'$f_{set}$ (Hz)','Interpreter','latex','FontSize',10);
        ylabel(ax9,'$\alpha$ (m$^{-1}$)','Interpreter','latex','FontSize',10);
        title(ax9,sprintf('$A_{set}$ = %.3f V',ampSet),'Interpreter','latex','FontSize',9);
    end
    figHandles{end+1}=f9; figBaseNames{end+1}='Plot9_AttenuationRate_vs_Frequency';
end


%% --- Plot 10: Attenuation rate vs A_set ---
validFreqsPlot10=[];
for iF=1:length(uniqueFreqs)
    freqSet=uniqueFreqs(iF);
    idxF10=find(attenuationResults.SetFrequency_Hz==freqSet);
    if length(unique(attenuationResults.SetAmplitude_V(idxF10)))>=n_amp_min
        validFreqsPlot10(end+1)=freqSet; %#ok<AGROW>
    end
end
if ~isempty(validFreqsPlot10)
    nSub10=length(validFreqsPlot10); nCols10=min(nSub10,3); nRows10=ceil(nSub10/nCols10);
    f10=figure('Name','AttenuationRate_vs_Amplitude');
    for iFreq=1:length(validFreqsPlot10)
        freqSet=validFreqsPlot10(iFreq); ax10=subplot(nRows10,nCols10,iFreq);
        hold(ax10,'on'); grid(ax10,'on');
        idxAtt=find(attenuationResults.SetFrequency_Hz==freqSet);
        plottedModesGrp10={};
        for ia=idxAtt'
            st=wm_style_for_mode(attenuationResults.Mode(ia),modeStyleMap);
            showM=~ismember(char(attenuationResults.Mode(ia)),plottedModesGrp10);
            hVis='off'; dName='';
            if showM; dName=char(attenuationResults.Mode(ia)); hVis='on'; plottedModesGrp10{end+1}=dName; end
            errorbar(ax10,attenuationResults.SetAmplitude_V(ia), ...
                attenuationResults.AttenuationRate_1perm(ia), ...
                attenuationResults.Unc_AttenuationRate_1perm(ia), ...
                attenuationResults.Unc_AttenuationRate_1perm(ia), ...
                delta_V_set,delta_V_set, ...
                st.marker,'Color',st.color,'MarkerFaceColor',st.color, ...
                'CapSize',4,'LineWidth',0.8,'DisplayName',dName,'HandleVisibility',hVis);
        end
        yline(ax10,0,'k:','LineWidth',0.8,'HandleVisibility','off');
        legend(ax10,'show','Location','best','FontSize',7,'Interpreter','none');
        xlabel(ax10,'$A_{set}$ (V)','Interpreter','latex','FontSize',10);
        ylabel(ax10,'$\alpha$ (m$^{-1}$)','Interpreter','latex','FontSize',10);
        title(ax10,sprintf('$f_{set}$ = %.3f Hz',freqSet),'Interpreter','latex','FontSize',9);
    end
    figHandles{end+1}=f10; figBaseNames{end+1}='Plot10_AttenuationRate_vs_Amplitude';
end


%% =========================================================
%  SECTION 5c: ICE FLEXURE ANALYSIS — I/Ibr vs WAVE STEEPNESS
% =========================================================
disp('--- Section 5c: I/Ibr vs Wave Steepness ---');

D_flex   = (E_ice * h_ice^3) / (12 * (1 - nu_ice^2));
lambda_F = (D_flex / (rho_water * g_gravity))^(1/4);
fprintf('  Flexural rigidity D = %.4e Pa m^3\n', D_flex);
fprintf('  Flexural length     = %.4f m\n', lambda_F);

I_br_threshold = 0.014;

if n_rows > 0
    ka_vec    = NaN(n_rows,1);
    I_val_vec = NaN(n_rows,1);
    ratio_vec = NaN(n_rows,1);

    for ir = 1:n_rows
        fMeas = res_MeanFreq(ir); aMeas = res_MeanAmp(ir);
        if ~isfinite(fMeas)||~isfinite(aMeas)||aMeas<=0; continue; end
        omega=2*pi*fMeas; k_est=omega^2/g_gravity;
        for iter=1:50
            th=tanh(k_est*water_depth_m);
            f_k=k_est*g_gravity*th-omega^2;
            fp_k=g_gravity*th+k_est*g_gravity*water_depth_m*(1-th^2);
            k_new=k_est-f_k/fp_k;
            if abs(k_new-k_est)<1e-10; break; end
            k_est=k_new;
        end
        Lp=2*pi/k_est;
        ka_vec(ir)=k_est*aMeas;
        Hs=2*aMeas;
        I_val=(Hs*h_ice*E_ice)/(2*sigma_f_ice*Lp^2);
        I_val_vec(ir)=I_val;
        ratio_vec(ir)=I_val/I_br_threshold;
    end

    valid_iceIdx=find(isfinite(ka_vec)&isfinite(ratio_vec));
    if ~isempty(valid_iceIdx)
        f11=figure('Name','I_over_Ibr_vs_Steepness'); ax11=axes(f11);
        hold(ax11,'on'); grid(ax11,'on');
        acou_v=valid_iceIdx(res_Measurement(valid_iceIdx)=="Acoustic_Sensor");
        cam_v =valid_iceIdx(res_Measurement(valid_iceIdx)=="Side_Camera");
        if ~isempty(acou_v)
            scatter(ax11,ka_vec(acou_v),ratio_vec(acou_v),60,'b','o','filled', ...
                'DisplayName','Acoustic sensor');
        end
        if ~isempty(cam_v)
            scatter(ax11,ka_vec(cam_v),ratio_vec(cam_v),60,[0.85 0.33 0.10],'^','filled', ...
                'DisplayName','Camera');
        end
        yline(ax11,1.0,'k--','LineWidth',1.5,'DisplayName','Threshold I/Ibr = 1');
        legend(ax11,'show','Location','best','Interpreter','none','FontSize',10);
        xlabel(ax11,'$ka$  [-]','Interpreter','latex','FontSize',11);
        ylabel(ax11,'$I / I_{br}$  [-]','Interpreter','latex','FontSize',11);
        annotStr=sprintf('h=%.3fm\nE=%.2gPa\nsigma_f=%.2gPa\nH=%.2fm\nIbr=%.3f', ...
            h_ice,E_ice,sigma_f_ice,water_depth_m,I_br_threshold);
        annotation(f11,'textbox',[0.15 0.70 0.25 0.18], ...
            'String',annotStr,'Interpreter','none','FontSize',8, ...
            'BackgroundColor','w','FitBoxToText','on');
        figHandles{end+1}=f11; figBaseNames{end+1}='Plot11_I_over_Ibr_vs_Steepness';
        fprintf('  Plot 11 produced (%d valid points).\n', length(valid_iceIdx));
    else
        fprintf('  [SKIP] No valid (ka, I/Ibr) pairs found.\n');
    end
end


%% =========================================================
%  SECTION 6: SAVING
% =========================================================
disp('======================================================');
disp('--- Section 6: Saving ---');
disp('======================================================');

if save_fig || save_results
    outputDir = fullfile(pwd, ['results_postprocess_ENVELOPE_' date_str]);
    if ~exist(outputDir,'dir'); mkdir(outputDir); end
    fprintf('Output directory: %s\n', outputDir);

    if save_fig
        allOpenFigs=findall(0,'Type','figure'); nFigSaved=0;
        for k=1:length(allOpenFigs)
            fh=allOpenFigs(k); if ~isgraphics(fh); continue; end
            rawName=get(fh,'Name');
            if isempty(rawName); rawName=sprintf('Figure_%d',fh.Number); end
            safeName=regexprep(rawName,'[\\/:*?"<>|]','_'); safeName=strtrim(safeName);
            try
                exportgraphics(fh,fullfile(outputDir,[safeName '.png']),'Resolution',300);
                exportgraphics(fh,fullfile(outputDir,[safeName '.pdf']),'ContentType','vector');
                nFigSaved=nFigSaved+1;
            catch ME_save
                fprintf('  [WARN] Could not save "%s": %s\n',safeName,ME_save.message);
            end
        end
        fprintf('  Saved %d figures.\n',nFigSaved);
    end

    if save_results && ~isempty(calResultsPerLoc)
        writetable(calResultsPerLoc, ...
            fullfile(outputDir,'Calibration_Fits_Per_Location.csv'));
        fprintf('  Saved: Calibration_Fits_Per_Location.csv\n');
    end

    if save_results
        fullResultsTable=table(res_Measurement,res_File,res_Mode,res_Date, ...
            res_SensorID,res_Channel,res_SensorLoc, ...
            res_InputAmp,res_InputFreq, ...
            res_FFT_Freq,res_MeanAmp,res_UncAmp,res_UncFreq, ...
            res_MeanAmp_PT,res_UncAmp_PT,res_MeanAmp_Env,res_UncAmp_Env, ...
            'VariableNames',{'Measurement','Filename','Mode','Date_DDMMYY', ...
            'SensorID','Channel','SensorLocation_m', ...
            'SetAmplitude_V','SetFrequency_Hz', ...
            'MeasuredFrequency_FFT_Hz','MeasuredAmplitude_m', ...
            'UncertaintyAmplitude_m','UncertaintyFrequency_Hz', ...
            'Cam_Amplitude_PT_m','Cam_Uncertainty_PT_m', ...
            'Cam_Amplitude_Envelope_m','Cam_Uncertainty_Envelope_m'});
        fullResultsTable.Final_amp_error_m  =repmat(final_amp_error, n_rows,1);
        fullResultsTable.Final_freq_error_Hz=repmat(final_freq_error,n_rows,1);
        writetable(fullResultsTable,fullfile(outputDir,'Results_postprocess_all.csv'));
        fprintf('  Saved: Results_postprocess_all.csv (%d rows)\n',n_rows);
        if ~isempty(attenuationResults)
            writetable(attenuationResults,fullfile(outputDir,'Attenuation_Results.csv'));
            fprintf('  Saved: Attenuation_Results.csv\n');
        end
    end
end

disp('=== MAIN_wm_postprocess_all.m finished ===');















