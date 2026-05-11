%% =========================================================
%  tank_process_sidecam_v4.m
%  SIDE-CAMERA VIDEO ANALYSIS — RAW WAVE TIME SERIES EXTRACTION
%
%  PURPOSE:
%    Processes side-camera videos of an ice-covered wave tank and
%    extracts the raw water-surface (and optionally ice-bottom)
%    displacement time series eta(t) from each video.
%    No amplitude / frequency estimation is done here — that is
%    delegated to MAIN_wm_postprocess_all.m.
%
%  KEY CHANGES vs previous version:
%    - UX: all prompts carry explicit descriptions of WHAT to select.
%    - File loading merged: the wmice pairing CSV is loaded ONCE,
%      no second selection needed.
%    - Per-video calib mode: a surface-detection preview is shown
%      BEFORE the calibration dialog for every video.
%    - Temporal-continuity filter in the frame loop:
%        If the detected peak position differs from the previous
%        frame's accepted position by more than peak_jump_tol_frac
%        (fraction of frame height, tunable), the algorithm retries
%        on the next-best candidate peak.  Prevents jumps to noise.
%
%  BUG FIX (v4):
%    pick_best_peak was incorrectly defined as a nested function
%    inside the frame loop (illegal in MATLAB scripts).  It has been
%    moved to the LOCAL HELPER FUNCTIONS section at the end of the
%    file and is now called normally.
%
%  WORKFLOW:
%    1.  User configures flags and parameters (Section 1).
%    2.  Metadata CSVs are loaded in one pass (Section 2).
%    3.  Video readability pre-check (Section 3c-PRE).
%    4.  Calibration-mode choice (Section 3c-CALIB-MODE).
%    5a. Per-location calib: interactive ROI + pixel calibration once
%        per camera x-position (Section 3c-MAIN).
%    5b. Per-video calib: calib runs inside Section 4 for every video,
%        always preceded by a surface-detection preview.
%    6.  Main processing loop (Section 4).
%    7.  Intermediate save (Section 4b).
%
%  OUTPUTS (written to results_sidecam_<DATE>_MID/):
%    - CamTS_<VideoBase>_A<V>V_f<Hz>Hz_x<m>m.csv  (t_s | eta_m)
%    - CamTimeSeries_INDEX.csv
%    - All open figures as PNG (300 dpi) and vector PDF.
%
%  DEPENDENCIES:
%    Signal Processing Toolbox  — imgaussfilt(), findpeaks()
%    Image Processing Toolbox   — rgb2gray(), imshow()
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
save_fig = true;   % export all open figures to PNG + PDF
mid_save = true;   % save CSV archive after the main loop

% ---------------------------------------------------------
%  1b. ICE-COVER FLAG
%  true  -> detect TWO gradient peaks (ice-bottom AND water surface)
%  false -> detect single strongest peak (open-water surface only)
% ---------------------------------------------------------
is_ice = true;

% ---------------------------------------------------------
%  1c. SAMPLING FREQUENCY (acoustic, for filename parsing only)
% ---------------------------------------------------------
Fs_default = 50;   % fallback [Hz] when MODE string is unrecognised

% ---------------------------------------------------------
%  1d. DATE STRING FOR OUTPUT FOLDER
% ---------------------------------------------------------
date_str = '060526';   % update each session (DDMMYY)

% ---------------------------------------------------------
%  1e. STEADY-STATE WINDOW (acoustic, metadata reference only)
% ---------------------------------------------------------
t_start_sensors = 40;   % [s]
t_end_sensors   = 0;    % [s], 0 = full record from t_start onward

% ---------------------------------------------------------
%  1f. VIDEO ANALYSIS PARAMETERS
% ---------------------------------------------------------
vid_grad_smooth      = 3;      % Gaussian sigma [px] for profile smoothing
vid_despike_enable   = false;  % despike the raw surface-position series?
vid_despike_thresh_m = 0.03;   % absolute threshold [m] for despiking
vid_test_nframes     = 10;     % frames shown in surface-detection preview
vid_show_preview_per_video = true;  % show detection preview in per-video mode

% ---------------------------------------------------------
%  FRAME PREPROCESSING PARAMETERS
%  Applied to every frame BEFORE the strip profile + gradient step.
%  Helps detect the ice-bottom interface when it has low contrast.
%
%  Build defaults then override individual fields as needed.
% ---------------------------------------------------------
pp = wm_cam_preprocess_defaults();   % load all defaults
 
% --- Override individual fields here to tune detection ---
pp.enable        = false;   % set false to disable all preprocessing
pp.clahe_cliplim = 0.05;    % increase if ice edge still invisible (try 0.03-0.10)
pp.denoise_sigma = 3.0;     % increase if gradient is still very noisy (1.0-4.0)
pp.sharpen_amount= 1.0;     % increase if interface edge is blurry after denoise
pp.gamma_val     = 0.60;    % decrease toward 0.5 to further brighten dark ice regions

% ==========================================================================
%  TUNING GUIDE
%
%  Run the script and check the Detection Preview and Threshold Preview.
%  Use these guidelines to adjust pp fields in Section 1h:
%
%  SYMPTOM                               WHAT TO CHANGE
%  -------                               --------------
%  Ice edge still invisible (no blue)    Increase pp.clahe_cliplim (try 0.05)
%                                        Decrease pp.gamma_val (try 0.6)
%  Gradient still very noisy/spiky       Increase pp.denoise_sigma (try 3.0)
%  Interface lines blurry / wide peak    Increase pp.sharpen_amount (try 1.2)
%  False detections on tank wall/wires   Decrease pp.clahe_cliplim
%                                        Decrease pp.sharpen_amount
%  Preprocessing makes things worse      Set pp.enable = false to compare
% ==========================================================================


% Minimum gradient amplitude thresholds (peaks below are ignored).
% Set to 0 to disable.
grad_amp_min_water = 0.5;   % [a.u.] — lowered: let amplitude window do the work
grad_amp_min_ice   = 0.3;   % [a.u.] — keep low so weak ice peak is not excluded
 
% Maximum gradient amplitude thresholds (peaks ABOVE are also ignored).
% KEY TUNING PARAMETER: set grad_amp_max_ice BELOW the dominant surface peak.
% From your gradient profile, the water/ice-top peak is ~6 a.u.
% Setting grad_amp_max_ice = 2.5 excludes that dominant peak from ice search,
% forcing the algorithm to look for a weaker (but real) secondary peak.
% Set to Inf to disable the ceiling.
grad_amp_max_water = Inf;   % [a.u.] — no ceiling on water peak (take strongest)
grad_amp_max_ice   = 2.5;   % [a.u.] — exclude the dominant peak from ice search
                             %  TUNE: look at the gradient plot right panel.
                             %  Set this just below the dominant peak amplitude.
                             %  If ice peak is still missed, lower this further.
 
% Minimum vertical separation between water and ice detections [px].
% Ice bottom must be AT LEAST this many pixels below the water surface.
% Estimate: ice thickness in mm / mm_per_px_cam.
% If you don't know, start with 10 px and increase if they still collapse.
min_sep_ice_px = 10;        % [px] — TUNE based on visible ice thickness
 


%  Summary of new parameters:
%    grad_amp_max_water  — reject peaks STRONGER than this as water candidates
%                          (prevents the dominant peak from also being ice)
%    grad_amp_max_ice    — reject peaks STRONGER than this as ice candidates
%                          Tip: set this BELOW the dominant peak amplitude.
%                          From your gradient plot, the dominant peak is ~6 a.u.
%                          so grad_amp_max_ice = 3.0 excludes it from ice search.
%    min_sep_ice_px      — minimum pixel distance between water and ice detections
%                          Prevents both being assigned to the same peak.
%                          Estimate from ice thickness: if ice is ~5mm thick and
%                          your calibration is ~1 px/mm, use min_sep_ice_px = 5.
% =========================================================================

% ---------------------------------------------------------
%  1g. TEMPORAL-CONTINUITY FILTER
% ---------------------------------------------------------
% Displacement-based jump filter (applied to WATER interface only).
% If detected position differs from previous by more than this fraction
% of frame height, the detection is rejected.
peak_jump_tol_frac = 0.10;   % 10% of frame height
 
% Amplitude-continuity filter (applied to ICE interface).
% Rejects ice peak candidates whose gradient amplitude differs from the
% previously accepted ice amplitude by more than this fractional threshold.
% |new_amp / prev_amp - 1| > amp_jump_tol_frac  =>  reject candidate.
%
% WHY THIS INSTEAD OF DISPLACEMENT FOR ICE:
%   Noise peaks near the ice bottom are spatially clustered (small pixel
%   separation), so a displacement filter cannot distinguish a valid ice
%   edge from a neighbouring noise peak.  However, a real ice-bottom peak
%   has a consistent amplitude across frames; noise hops show as sudden
%   amplitude changes.
%
% TUNE: 0.4 = tight (±40% change tolerated), 0.7 = loose (±70%).
%   Start at 0.5 and tighten if ice still jumps between frames.
amp_jump_tol_frac = 0.5;    % fractional amplitude tolerance for ice


%% =========================================================
%  SECTION 2: FILE & METADATA LOADING  
% =========================================================
disp('======================================================');
disp('--- Section 2: File & Metadata Loading ---');
disp('  All metadata CSVs are loaded here — each file is    ');
disp('  selected exactly once.                              ');
disp('======================================================');

% --- 2a. Sensor placement metadata ---
fprintf('\n[STEP 1/4] Select the SENSOR PLACEMENT metadata CSV.\n');
fprintf('           (e.g. Metadata_sensors_060526.csv)\n');
fprintf('           Columns expected: Sensor, Channel, x_m, Camera\n\n');
locExpanded = wm_load_location_metadata();

% --- 2b. Acoustic sensor calibration (V -> m) ---
fprintf('\n[STEP 2/4] Select the ACOUSTIC SENSOR CALIBRATION CSV.\n');
fprintf('           (e.g. Calibration_sensors.csv)\n');
fprintf('           Columns: Source, Mode, Slope_a, Intercept_b\n\n');
calData = wm_load_calibration();

% --- 2c. Acoustic-video pairing metadata (loaded ONCE) ---
fprintf('\n[STEP 3/4] Select the EXPERIMENT PAIRING metadata CSV.\n');
fprintf('           (e.g. Metadata_wmice_060526.csv)\n');
fprintf('           Links acoustic CSVs to video files, wave conditions,\n');
fprintf('           video trim times, and camera time-series names.\n\n');

[pairRawFile, pairRawPath] = uigetfile('*.csv', ...
    '[STEP 3/4] Select Experiment Pairing Metadata CSV (wmice)');
if isequal(pairRawFile, 0)
    error('No pairing CSV selected. Aborting.');
end

pairRawTable = readtable(fullfile(pairRawPath, pairRawFile), ...
    'VariableNamingRule', 'preserve');
fprintf('  Pairing CSV loaded: %d rows, %d columns.\n', ...
    height(pairRawTable), width(pairRawTable));
fprintf('  Columns: %s\n', strjoin(pairRawTable.Properties.VariableNames, ', '));

% Build working pairMeta from the already-loaded table (no second dialog)
pairMeta = wm_build_pairmeta_from_table(pairRawTable);

% --- 2d. Acoustic data folders ---
fprintf('\n[STEP 4/4] Select ACOUSTIC SENSOR DATA folder(s).\n');
fprintf('           Enter the number of folders containing raw_data_*.csv.\n');
fprintf('           NOTE: SENSOR DATA ONLY — video files are asked next.\n\n');
allFiles = wm_select_files();
numFiles = length(allFiles);

% --- 2e. Optional separate video folder ---
fprintf('\n  Are your VIDEO FILES in a DIFFERENT folder from the acoustic CSVs?\n');
addVidFolder = questdlg( ...
    ['Are your video files in a DIFFERENT folder from the acoustic CSVs?' ...
     newline newline ...
     '"Yes" — browse for the video root folder.' newline ...
     '"No"  — videos and acoustic CSVs are in the same folder(s).'], ...
    'Video Folder Location', ...
    'Yes — browse for video folder', ...
    'No  — same folder as acoustic CSVs', ...
    'No  — same folder as acoustic CSVs');

if strcmp(addVidFolder, 'Yes — browse for video folder')
    fprintf('\n  Select the ROOT folder containing your video files.\n\n');
    vidRootDir = uigetdir(pwd, 'Select root folder containing video files');
    if isequal(vidRootDir, 0)
        warning('No video folder selected — videos must be co-located with acoustic files.');
    else
        vidFileList = dir(fullfile(vidRootDir, '*.*'));
        vidFileList = vidFileList(~[vidFileList.isdir]);
        allFiles    = [allFiles; vidFileList];
        numFiles    = length(allFiles);
        fprintf('  Video folder added: %s (%d files found)\n', ...
            vidRootDir, length(vidFileList));
    end
end


%% =========================================================
%  SECTION 2b: DERIVE Camera_loc_m FROM SENSOR PLACEMENT TABLE
% =========================================================
disp('--- Section 2b: Deriving Camera_loc_m from sensor placement ---');

nPairRows      = height(pairMeta);
camLoc_derived = NaN(nPairRows, 1);

for iPM = 1:nPairRows
    vidName = strtrim(string(pairMeta.Video_filename(iPM)));
    if strlength(vidName) == 0; continue; end

    acFname   = char(pairMeta.Acoustic_sensor_filename(iPM));
    tok       = regexp(acFname, '[Ss]ensor(\d+)', 'tokens', 'once');
    if isempty(tok)
        fprintf('  [WARN] Cannot parse sensor number from: %s\n', acFname);
        continue;
    end
    sensorNum = str2double(tok{1});

    locIdx = find(locExpanded.SensorID == sensorNum, 1);
    if isempty(locIdx)
        fprintf('  [WARN] Sensor %d not in placement table (row %d).\n', sensorNum, iPM);
        continue;
    end
    if ~locExpanded.HasCamera(locIdx)
        fprintf('  [WARN] Row %d has a video but Sensor %d has no Camera entry.\n', iPM, sensorNum);
    end
    camLoc_derived(iPM) = locExpanded.x_m(locIdx);
    fprintf('  Row %2d: Sensor%d -> x_m=%.2f m  (Camera: %s)\n', ...
        iPM, sensorNum, locExpanded.x_m(locIdx), char(locExpanded.Camera(locIdx)));
end

pairMeta.Camera_loc_m = camLoc_derived;
fprintf('Camera_loc_m derived for %d / %d rows with videos.\n\n', ...
    sum(~isnan(camLoc_derived)), nPairRows);


%% =========================================================
%  SECTION 3: INITIALISE STORES
% =========================================================
camCalib_store = struct();

camTimeSeries = struct('VideoFile',{},'AcousticFile',{}, ...
                       't_s',{},'eta_m',{},'ice_m',{}, ...
                       'surf_unc_m',{},'ice_unc_m',{}, ...   
                       'InputAmp_V',{},'InputFreq_Hz',{}, ...
                       'CamLoc_m',{},'Fs_cam_Hz',{}, ...
                       'PairRowIdx',{})
kCamTS       = 1;
isFirstVideo = true;


%% =========================================================
%  SECTION 3c-PRE: VIDEO READABILITY PRE-CHECK
% =========================================================
disp('======================================================');
disp('--- Section 3c-PRE: Video Readability Pre-Check ---');
disp('  Checks every listed video before interactive setup. ');
disp('======================================================');

fprintf('Checking %d video entries...\n\n', height(pairMeta));
problemVideos = {};

fprintf('%-40s %-30s %-8s %-10s %-12s %s\n', ...
    'Acoustic CSV','Video file','Found','Size(MB)','Duration(s)','Status');
fprintf('%s\n', repmat('-',1,115));

for iPM = 1:height(pairMeta)
    vidName = strtrim(string(pairMeta.Video_filename(iPM)));
    if strlength(vidName) == 0; continue; end
    acousticName = char(pairMeta.Acoustic_sensor_filename(iPM));

    vidPath    = wm_find_video(vidName, allFiles, numFiles);
    foundFile  = strlength(vidPath) > 0;
    fileSizeMB = NaN;
    if foundFile
        d = dir(char(vidPath));
        if ~isempty(d); fileSizeMB = d.bytes / 1e6; end
    end

    vidDuration = NaN; vrOK = false; vrErrMsg = '';
    if foundFile && ~isnan(fileSizeMB) && fileSizeMB > 0
        try
            vTest       = VideoReader(char(vidPath));
            vidDuration = vTest.Duration;
            vrOK        = true;
        catch ME_vr; vrErrMsg = ME_vr.message; end
    end

    frameOK = false; frameErrMsg = '';
    if vrOK
        try
            vTest.CurrentTime = 0;
            firstFrame = readFrame(vTest);
            if ~isempty(firstFrame); frameOK = true; end
            clear firstFrame vTest;
        catch ME_fr; frameErrMsg = ME_fr.message; clear vTest; end
    end

    if     ~foundFile;                               status = 'NOT FOUND';   isProblem = true;
    elseif isnan(fileSizeMB) || fileSizeMB == 0;     status = 'EMPTY FILE';  isProblem = true;
    elseif ~vrOK;    status = sprintf('VR FAIL: %s',    vrErrMsg);  isProblem = true;
    elseif ~frameOK; status = sprintf('READ FAIL: %s', frameErrMsg); isProblem = true;
    else;            status = 'OK';                  isProblem = false;
    end

    fprintf('%-40s %-30s %-8s %-10.2f %-12.2f %s\n', ...
        acousticName, char(vidName), mat2str(foundFile), fileSizeMB, vidDuration, status);

    if isProblem
        problemVideos{end+1,1} = acousticName; %#ok<AGROW>
        problemVideos{end,2}   = char(vidName);
        problemVideos{end,3}   = status;
    end
end

fprintf('\n--- PRE-CHECK SUMMARY ---\n');
if isempty(problemVideos)
    fprintf('All videos passed.\n\n');
else
    fprintf('WARNING: %d video(s) failed:\n', size(problemVideos,1));
    for iPrb = 1:size(problemVideos,1)
        fprintf('  %-40s %-30s %s\n', ...
            problemVideos{iPrb,1}, problemVideos{iPrb,2}, problemVideos{iPrb,3});
    end
    choice = questdlg( ...
        sprintf('%d video(s) could not be opened. Continue anyway?', size(problemVideos,1)), ...
        'Pre-Check Warning','Continue','Abort','Continue');
    if strcmp(choice,'Abort') || isempty(choice)
        error('Aborted by user after video pre-check.');
    end
    fprintf('Continuing with %d problem video(s).\n\n', size(problemVideos,1));
end


%% =========================================================
%  SECTION 3c-CALIB-MODE: CALIBRATION STRATEGY CHOICE
% =========================================================
disp('======================================================');
disp('--- Section 3c-CALIB-MODE: Calibration Strategy ---');
disp('======================================================');
fprintf('\n  "Per location" = one ROI + calibration per camera x-position.\n');
fprintf('    Recommended when the camera does not move between videos.\n\n');
fprintf('  "Per video"    = ROI + calibration dialog for EVERY video.\n');
fprintf('    Use when the camera was repositioned between runs.\n\n');

calibModeChoice = questdlg( ...
    ['Choose calibration strategy:' newline newline ...
     '"Per location" = one ROI + calibration per camera x-position.' newline ...
     '"Per video"    = ROI + calibration dialog for every individual video.'], ...
    'Calibration Strategy','Per location','Per video','Per location');

if isempty(calibModeChoice); calibModeChoice = 'Per location'; end
calib_per_video = strcmp(calibModeChoice, 'Per video');

if calib_per_video
    fprintf('>>> PER VIDEO mode: preview shown before each calibration dialog.\n\n');
else
    fprintf('>>> PER LOCATION mode: one calibration per camera x-position.\n\n');
end


%% =========================================================
%  SECTION 3c-MAIN: ROI & CALIBRATION — PER-LOCATION MODE
%  (Skipped when calib_per_video = true)
% =========================================================
if ~calib_per_video
    disp('--- Section 3c-MAIN: ROI & Calibration (per-location) ---');
    fprintf('  For each camera x-position:\n');
    fprintf('    1. Select a representative video.\n');
    fprintf('    2. Define the analysis ROI.\n');
    fprintf('    3. Review a %d-frame detection preview.\n', vid_test_nframes);
    fprintf('    4. Perform pixel-to-mm calibration.\n\n');

    camLocsAll = unique(pairMeta.Camera_loc_m( ...
        strlength(strtrim(pairMeta.Video_filename)) > 0));

    for iCL = 1:length(camLocsAll)
        camX   = camLocsAll(iCL);
        locKey = loc_to_key(camX);
        fprintf('\n--- Camera at x = %.2f m ---\n', camX);

        rowsForLoc = find(pairMeta.Camera_loc_m == camX & ...
                          strlength(strtrim(pairMeta.Video_filename)) > 0);
        if isempty(rowsForLoc)
            fprintf('  [SKIP] No videos at x=%.2f m\n', camX); continue;
        end

        vidNames          = cellstr(pairMeta.Video_filename(rowsForLoc));
        vidNamesAnnotated = cell(size(vidNames));
        for iVN = 1:length(vidNames)
            thisVid = strtrim(vidNames{iVN}); note = '[OK]';
            for iPrb = 1:size(problemVideos,1)
                if strcmp(problemVideos{iPrb,2}, thisVid)
                    note = sprintf('[PROBLEM: %s]', problemVideos{iPrb,3}); break;
                end
            end
            vidNamesAnnotated{iVN} = sprintf('%s  %s', thisVid, note);
        end

        [selIdx, ok] = listdlg('ListString', vidNamesAnnotated, ...
            'SelectionMode','single', ...
            'Name', sprintf('ROI/Calib for camera at x=%.2f m', camX), ...
            'PromptString', { ...
                sprintf('Camera position: x = %.2f m', camX), ...
                'Select a representative video for ROI & calibration:'});
        if ~ok; fprintf('  [SKIP] Cancelled for x=%.2f m\n', camX); continue; end

        vidFileForCalib = strtrim(string(vidNames{selIdx}));
        vidPathForCalib = wm_find_video(vidFileForCalib, allFiles, numFiles);
        if vidPathForCalib == ""
            fprintf('  [SKIP] Video not found on disk: %s\n', char(vidFileForCalib));
            continue;
        end

        try; vObjCalib = VideoReader(char(vidPathForCalib));
        catch ME_vrc; fprintf('  [SKIP] VideoReader failed: %s\n', ME_vrc.message); continue; end

        % Step 1: ROI definition
        fprintf('  Step 1/3 — ROI definition ...\n');
        [strip_x_f, strip_w_f, search_y_f] = ...
            wm_cam_define_roi(vObjCalib, camX, vidFileForCalib);

        % Step 2: Detection preview BEFORE calibration
        fprintf('  Step 2/3 — Detection preview (%d frames) ...\n', vid_test_nframes);
        vObjPrev = VideoReader(char(vidPathForCalib));
        wm_cam_test_section(vObjPrev, 1, vid_test_nframes, ...
            strip_x_f, strip_w_f, search_y_f, vid_grad_smooth, ...
            char(vidFileForCalib), is_ice, pp);   

        % Step 3: Pixel-to-mm calibration
        fprintf('  Step 3/3 — Pixel-to-mm calibration ...\n');
        vObjCalib2   = VideoReader(char(vidPathForCalib));
        calib_result = wm_cam_calibrate(vObjCalib2);

        camCalib_store.(locKey).mm_per_px     = calib_result.mm_per_px;
        camCalib_store.(locKey).strip_x_frac  = strip_x_f;
        camCalib_store.(locKey).strip_w_frac  = strip_w_f;
        camCalib_store.(locKey).search_y_frac = search_y_f;
        camCalib_store.(locKey).done          = true;

        fprintf('  Stored: mm_per_px=%.5f strip_x=%.3f strip_w=%.3f search_y=[%.3f %.3f]\n', ...
            calib_result.mm_per_px, strip_x_f, strip_w_f, search_y_f(1), search_y_f(2));
    end
end

fprintf('\nPre-loop calibration setup complete.\n\n');


%% =========================================================
%  SECTION 4: MAIN PROCESSING LOOP
% =========================================================
set(groot,'defaultTextInterpreter',          'none');
set(groot,'defaultAxesTickLabelInterpreter', 'none');
set(groot,'defaultLegendInterpreter',        'none');

disp('======================================================');
disp('--- Section 4: Main Processing Loop ---');
disp('======================================================');

hWait = waitbar(0, 'Processing files...');

for i = 1:numFiles

    % ------------------------------------------------------------------
    %  Single outer try/catch — catches any unhandled error, reports it,
    %  and moves to the next file.  No nested try/catch anywhere.
    %  Skip logic uses skip_flag only — never 'continue' inside try.
    % ------------------------------------------------------------------
    try

    skip_flag = false;
    hDynFig   = gobjects(1);   % invalid handle — isgraphics() = false

    % ==================================================================
    %  4a. Progress + filename parsing
    % ==================================================================
    if isgraphics(hWait)
        waitbar(i/numFiles, hWait, ...
            sprintf('Processing file %d / %d...', i, numFiles));
    end

    fileName = allFiles(i).name;
    fullPath = fullfile(allFiles(i).folder, fileName);

    [fMode, fChannel, fDate, fAmp, fFreq, Fs, parseOK] = ...
        wm_parse_filename(fileName, Fs_default);
    if ~parseOK
        fprintf('  [SKIP] Bad filename: %s\n', fileName);
        skip_flag = true;
    end

    if ~skip_flag
        fprintf('\nFILE: %s\n  Mode=%s Fs=%d Ch=%d Date=%s A=%.3fV f=%.3fHz\n', ...
            fileName, fMode, Fs, fChannel, fDate, fAmp, fFreq);
    end

    % ==================================================================
    %  4b. Read acoustic signal (time vector only, for metadata)
    % ==================================================================
    if ~skip_flag
        [t, ~, ~, readOK] = wm_read_signal(fullPath, Fs); %#ok<ASGLU>
        if ~readOK
            fprintf('  [SKIP] Cannot read: %s\n', fileName);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  4c. Location metadata lookup
    % ==================================================================
    if ~skip_flag
        metaIdx = wm_lookup_metadata(locExpanded, fChannel, fDate);
        if isempty(metaIdx)
            fprintf('  [SKIP] No metadata for Ch=%d Date=%s\n', fChannel, fDate);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  4d. Pairing metadata lookup
    % ==================================================================
    if ~skip_flag
        [~, fileBase, ~] = fileparts(fileName);
        pairRow  = find(strcmp(string(pairMeta.Acoustic_sensor_filename), ...
                               fileBase), 1);
        hasVideo = ~isempty(pairRow) && ...
                   strlength(strtrim(string( ...
                       pairMeta.Video_filename(pairRow)))) > 0;
        if ~hasVideo
            fprintf('  [SKIP] No video paired for: %s\n', fileName);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  4d-cont. Extract pairing info
    % ==================================================================
    if ~skip_flag
        videoFile        = strtrim(string(pairMeta.Video_filename(pairRow)));
        camLoc           = pairMeta.Camera_loc_m(pairRow);
        vid_t_start_this = 0;
        vid_t_end_this   = 0;

        if ismember('vid_t_start_s', pairMeta.Properties.VariableNames)
            v = pairMeta.vid_t_start_s(pairRow);
            if isnumeric(v) && isfinite(v); vid_t_start_this = v; end
        end
        if ismember('vid_t_end_s', pairMeta.Properties.VariableNames)
            v = pairMeta.vid_t_end_s(pairRow);
            if isnumeric(v) && isfinite(v); vid_t_end_this = v; end
        end

        fprintf('  Paired video: %s  (x=%.2fm  trim=[%.0f %.0f]s)\n', ...
            videoFile, camLoc, vid_t_start_this, vid_t_end_this);
    end

    % ==================================================================
    %  4e. Find video on disk + compute locKey_cam
    % ==================================================================
    if ~skip_flag
        locKey_cam = loc_to_key(camLoc);
        videoPath  = wm_find_video(videoFile, allFiles, numFiles);
        if videoPath == ""
            fprintf('  [SKIP] Video not found on disk: %s\n', videoFile);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  4f. Calibration — per-video or per-location
    % ==================================================================
    if ~skip_flag

        if calib_per_video
            fprintf('  [PER-VIDEO CALIB] Starting for: %s\n', char(videoFile));

            % Step 1/3 — ROI
            fprintf('  Step 1/3 — ROI definition ...\n');
            vObjRoi = VideoReader(char(videoPath));
            [strip_x_frac_cam, strip_w_frac_cam, search_y_frac_cam] = ...
                wm_cam_define_roi(vObjRoi, camLoc, videoFile);
            clear vObjRoi;

            % Step 2/3 — Detection preview (flag-controlled)
            if vid_show_preview_per_video
                fprintf('  Step 2/3 — Detection preview (%d frames)...\n', ...
                    vid_test_nframes);
                vObjPrev = VideoReader(char(videoPath));
                 wm_cam_test_section(vObjPrev, 1, vid_test_nframes, ...
                    strip_x_frac_cam, strip_w_frac_cam, search_y_frac_cam, ...
                    vid_grad_smooth, char(videoFile), is_ice, pp);
                clear vObjPrev;
            else
                fprintf('  Step 2/3 — Preview SKIPPED.\n');
            end

            % Step 3/3 — Pixel-to-mm calibration
            fprintf('  Step 3/3 — Pixel-to-mm calibration ...\n');
            vObjCalib = VideoReader(char(videoPath));
            calib_result  = wm_cam_calibrate(vObjCalib);
            mm_per_px_cam = calib_result.mm_per_px;
            clear vObjCalib;

            % Store for reuse
            camCalib_store.(locKey_cam).mm_per_px     = mm_per_px_cam;
            camCalib_store.(locKey_cam).strip_x_frac  = strip_x_frac_cam;
            camCalib_store.(locKey_cam).strip_w_frac  = strip_w_frac_cam;
            camCalib_store.(locKey_cam).search_y_frac = search_y_frac_cam;
            camCalib_store.(locKey_cam).done          = true;
            fprintf('  [PER-VIDEO CALIB] Done: %.5f mm/px\n', mm_per_px_cam);

        else
            % Per-location: retrieve stored calibration
            if ~isfield(camCalib_store, locKey_cam) || ...
               ~camCalib_store.(locKey_cam).done
                fprintf('  [SKIP] No calibration for x=%.2f m (key=%s).\n', ...
                    camLoc, locKey_cam);
                skip_flag = true;
            else
                mm_per_px_cam     = camCalib_store.(locKey_cam).mm_per_px;
                strip_x_frac_cam  = camCalib_store.(locKey_cam).strip_x_frac;
                strip_w_frac_cam  = camCalib_store.(locKey_cam).strip_w_frac;
                search_y_frac_cam = camCalib_store.(locKey_cam).search_y_frac;
                fprintf('  [CALIB LOADED] x=%.2f m  %.5f mm/px\n', ...
                    camLoc, mm_per_px_cam);
            end
        end

    end

    % ==================================================================
    %  4g. Open VideoReader + compute frame window
    % ==================================================================
    if ~skip_flag
        vObj = VideoReader(char(videoPath));

        Fs_cam        = vObj.FrameRate;
        nFrames_total = floor(vObj.Duration * Fs_cam);
        fprintf('  %.1fs | %.1ffps | ~%d frames\n', ...
            vObj.Duration, Fs_cam, nFrames_total);

        frame_start = max(1, round(vid_t_start_this * Fs_cam));
        if vid_t_end_this > 0
            frame_end = min(nFrames_total, round(vid_t_end_this * Fs_cam));
        else
            frame_end = nFrames_total;
        end
        frame_end   = min(frame_end, nFrames_total - 1);
        nFrames_use = frame_end - frame_start + 1;

        fprintf('  Frames %d-%d  (%.1f-%.1fs)\n', ...
            frame_start, frame_end, ...
            (frame_start-1)/Fs_cam, frame_end/Fs_cam);

        if (frame_start-1)/Fs_cam >= vObj.Duration
            fprintf('  [SKIP] frame_start exceeds video duration.\n');
            skip_flag = true;
        end
    end

    % ==================================================================
    %  4h. FIRST-FRAME THRESHOLD PREVIEW
    %  Shows gradient profile + amplitude thresholds + detected interfaces
    %  on frame 1 so the user can verify grad_amp_min_water/ice before
    %  committing to processing all frames.
    %  User clicks "Proceed" or "Skip video".
    % ==================================================================
    if ~skip_flag

        vObj.CurrentTime = (frame_start - 1) / Fs_cam;

        if hasFrame(vObj)
            frame_prev = readFrame(vObj);
            if size(frame_prev,3) == 3; frame_prev = rgb2gray(frame_prev); end

            % Apply preprocessing to improve interface contrast before detection
            frame_prev = wm_cam_preprocess(frame_prev, pp);   

            fh_p = size(frame_prev,1);
            fw_p = size(frame_prev,2)
            xl_p = max(1,    round((strip_x_frac_cam - strip_w_frac_cam/2)*fw_p));
            xr_p = min(fw_p, round((strip_x_frac_cam + strip_w_frac_cam/2)*fw_p));
            yt_p = max(1,    round(search_y_frac_cam(1)*fh_p));
            yb_p = min(fh_p, round(search_y_frac_cam(2)*fh_p));

            strip_p  = double(frame_prev(yt_p:yb_p, xl_p:xr_p));
            prof_p   = imgaussfilt(mean(strip_p,2), vid_grad_smooth);
            grad_p   = abs(diff(prof_p));

            if max(grad_p) > 0
                [pks_p, locs_p] = findpeaks(grad_p, 'SortStr','descend', ...
                    'MinPeakProminence', max(grad_p)*0.05);
            else
                pks_p = []; locs_p = [];
            end

            % Detect with jump_tol=Inf (first frame, no prior)
            [surf_p, ice_p] = pick_best_peak(pks_p, locs_p, ...
                NaN, NaN, ...               % prev positions
                NaN, NaN, ...               % prev amplitudes (NaN = first frame)
                Inf, yt_p, is_ice, ...      % jump_tol, y_top, is_ice
                grad_amp_min_water, grad_amp_min_ice, ...
                grad_amp_max_water, grad_amp_max_ice, ...
                min_sep_ice_px, ...
                amp_jump_tol_frac, ...      % <-- NEW amplitude continuity
                grad_p);                    % <-- NEW gradient vector for HWHM

            % Draw preview figure
            hPrevFig = figure( ...
                'Name',        sprintf('Threshold Preview -- %s', char(videoFile)), ...
                'NumberTitle', 'off', ...
                'Color',       'w');

            axPi = subplot(1,2,1, 'Parent', hPrevFig);
            axPg = subplot(1,2,2, 'Parent', hPrevFig);

            % Left: frame + lines
            imshow(frame_prev, 'Parent', axPi);
            hold(axPi,'on');
            if ~isnan(surf_p)
                yline(axPi, surf_p, 'r-', 'LineWidth', 2, ...
                    'Label', sprintf('Water %.0fpx', surf_p), ...
                    'LabelHorizontalAlignment','right', ...
                    'LabelVerticalAlignment','bottom');
            end
            if is_ice && ~isnan(ice_p)
                yline(axPi, ice_p, 'b-', 'LineWidth', 2, ...
                    'Label', sprintf('Ice %.0fpx', ice_p), ...
                    'LabelHorizontalAlignment','right', ...
                    'LabelVerticalAlignment','top');
            end
            title(axPi, ...
                sprintf('THRESHOLD PREVIEW — frame 1\n%s', char(videoFile)), ...
                'FontSize',8,'Interpreter','none');
            hold(axPi,'off');

            % Right: gradient + threshold lines
            y_pg = (yt_p : yb_p-1)';
            plot(axPg, grad_p, y_pg * mm_per_px_cam, 'k-','LineWidth',1.0);
            set(axPg,'YDir','reverse');
            hold(axPg,'on');
            xline(axPg, grad_amp_min_water, 'r--', 'LineWidth', 1.2, ...
                'Label', sprintf('water min=%.2f', grad_amp_min_water), ...
                'LabelHorizontalAlignment','right');
            xline(axPg, grad_amp_min_ice, 'b--', 'LineWidth', 1.2, ...
                'Label', sprintf('ice min=%.2f', grad_amp_min_ice), ...
                'LabelHorizontalAlignment','right');

            % Show amplitude CEILING lines (solid) on gradient preview
            if isfinite(grad_amp_max_water)
                xline(axPg, grad_amp_max_water, 'r-', 'LineWidth', 1.2, ...
                    'Label', sprintf('water max=%.2f', grad_amp_max_water), ...
                    'LabelHorizontalAlignment','left');
            end
            if isfinite(grad_amp_max_ice)
                xline(axPg, grad_amp_max_ice, 'b-', 'LineWidth', 1.2, ...
                    'Label', sprintf('ice max=%.2f', grad_amp_max_ice), ...
                    'LabelHorizontalAlignment','left');
            end


            if ~isnan(surf_p)
                yline(axPg, surf_p*mm_per_px_cam, 'r-', 'LineWidth',1.5, ...
                    'Label', sprintf('Water %.1fmm', surf_p*mm_per_px_cam), ...
                    'LabelHorizontalAlignment','left', ...
                    'LabelVerticalAlignment','bottom');
            end
            if is_ice && ~isnan(ice_p)
                yline(axPg, ice_p*mm_per_px_cam, 'b-', 'LineWidth',1.5, ...
                    'Label', sprintf('Ice %.1fmm', ice_p*mm_per_px_cam), ...
                    'LabelHorizontalAlignment','left', ...
                    'LabelVerticalAlignment','top');
            end
            xlabel(axPg,'Gradient (a.u.)','FontSize',9);
            ylabel(axPg,'Depth from frame top (mm)','FontSize',9);
            title(axPg, ...
                sprintf('grad\\_amp\\_min: water=%.2f  ice=%.2f', ...
                    grad_amp_min_water, grad_amp_min_ice), ...
                'FontSize',9,'Interpreter','none');
            hold(axPg,'off');

            % Ask user
            choice_prev = questdlg( ...
                sprintf(['%s\n\ngrad_amp_min_water = %.2f\n' ...
                         'grad_amp_min_ice   = %.2f\n\n' ...
                         'Proceed to analyse all frames, or skip this video?'], ...
                    char(videoFile), grad_amp_min_water, grad_amp_min_ice), ...
                'Threshold Preview', 'Proceed', 'Skip video', 'Proceed');

            close(hPrevFig);

            if strcmp(choice_prev,'Skip video') || isempty(choice_prev)
                fprintf('  [SKIP] Skipped after threshold preview: %s\n', ...
                    char(videoFile));
                skip_flag = true;
            end
        end

    end   % threshold preview block

    % ==================================================================
    %  4i. FRAME LOOP
    %  hDynFig opened HERE, guaranteed before the loop, for every video.
    % ==================================================================
    if ~skip_flag

        % Allocate output arrays
       % Output arrays
        surf_px      = NaN(nFrames_use, 1);   % water surface position [px]
        ice_px       = NaN(nFrames_use, 1);   % ice bottom   position [px]
        surf_unc_px_ts = NaN(nFrames_use, 1); % water uncertainty [px] from HWHM
        ice_unc_px_ts  = NaN(nFrames_use, 1); % ice   uncertainty [px] from HWHM
        t_cam          = (0:nFrames_use-1)' / Fs_cam;

        % Carry-forward state: position AND amplitude for continuity filters
        prev_surf_px  = NaN;   % last accepted water position [px]
        prev_ice_px   = NaN;   % last accepted ice   position [px]
        prev_surf_amp = NaN;   % last accepted water peak amplitude [a.u.]
        prev_ice_amp  = NaN;   % last accepted ice   peak amplitude [a.u.]

        % Seek to analysis start (vObj may have advanced during preview)
        vObj.CurrentTime = (frame_start - 1) / Fs_cam;

        % Open live detection figure — named with video filename
        hDynFig = figure( ...
            'Name',        sprintf('Live Detection -- %s', char(videoFile)), ...
            'NumberTitle', 'off', ...
            'Color',       'w');

        % ------------------------------------------------------------------
        for fi = 1:nFrames_use

            if ~hasFrame(vObj); break; end
            frame = readFrame(vObj);
            if size(frame,3) == 3; frame = rgb2gray(frame); end

            % Preprocess: enhance contrast at interfaces before gradient
            frame = wm_cam_preprocess(frame, pp);   

            frame_h = size(frame,1);
            frame_w     = size(frame,2);
            jump_tol_px = peak_jump_tol_frac * frame_h;

            % ROI crop
            x_left  = max(1,       round((strip_x_frac_cam - strip_w_frac_cam/2)*frame_w));
            x_right = min(frame_w, round((strip_x_frac_cam + strip_w_frac_cam/2)*frame_w));
            y_top   = max(1,       round(search_y_frac_cam(1)*frame_h));
            y_bot   = min(frame_h, round(search_y_frac_cam(2)*frame_h));

            strip          = double(frame(y_top:y_bot, x_left:x_right));
            profile_smooth = imgaussfilt(mean(strip,2), vid_grad_smooth);
            grad           = abs(diff(profile_smooth));

            % Peak finding — guard against flat frames
            if max(grad) > 0
                [pks, locs] = findpeaks(grad, ...
                    'SortStr',          'descend', ...
                    'MinPeakProminence', max(grad)*0.05);
            else
                pks  = [];
                locs = [];
            end

            % Interface detection
            [surf_abs, ice_abs, surf_unc_fi, ice_unc_fi] = pick_best_peak( ...
                pks, locs, ...
                prev_surf_px, prev_ice_px, ...       % prev positions
                prev_surf_amp, prev_ice_amp, ...      % prev amplitudes  <-- NEW
                jump_tol_px, y_top, is_ice, ...
                grad_amp_min_water, grad_amp_min_ice, ...
                grad_amp_max_water, grad_amp_max_ice, ...
                min_sep_ice_px, ...
                amp_jump_tol_frac, ...                % <-- NEW
                grad);                                % <-- NEW gradient vector

            % Store positions and per-frame uncertainties
            surf_px(fi)        = surf_abs;
            ice_px(fi)         = ice_abs;
            surf_unc_px_ts(fi) = surf_unc_fi;
            ice_unc_px_ts(fi)  = ice_unc_fi;


            % Update position carry-forward (unchanged logic)
            if ~isnan(surf_px(fi))
                prev_surf_px = surf_px(fi);
                % Also update amplitude: find the amplitude of the accepted
                % water peak by matching the accepted local position in locs_w
                % (pks are still in scope from the findpeaks call above)
                mask_w_fi = (pks >= grad_amp_min_water) & (pks <= grad_amp_max_water);
                pks_w_fi  = pks(mask_w_fi);
                if ~isempty(pks_w_fi)
                    prev_surf_amp = pks_w_fi(1);
                end
            end

            if is_ice && ~isnan(ice_px(fi))
                prev_ice_px = ice_px(fi);
                % Update ice amplitude: find the amplitude of the accepted ice peak
                % by matching accepted absolute position to locs_i candidates
                mask_i_fi = (pks >= grad_amp_min_ice) & (pks <= grad_amp_max_ice);
                pks_i_fi  = pks(mask_i_fi);
                locs_i_fi = locs(mask_i_fi);
                % Match by position: find which qualified ice peak was accepted
                match_idx = find((locs_i_fi + y_top - 1) == ice_px(fi), 1);
                if ~isempty(match_idx)
                    prev_ice_amp = pks_i_fi(match_idx);
                end
            end

            % Live display every 10 frames
            if mod(fi,10) == 0 && isgraphics(hDynFig)

                clf(hDynFig);
                axImg  = subplot(1,2,1,'Parent',hDynFig);
                axGrad = subplot(1,2,2,'Parent',hDynFig);

                same_peak = is_ice && ~isnan(surf_px(fi)) && ...
                            ~isnan(ice_px(fi)) && ...
                            abs(surf_px(fi)-ice_px(fi)) <= 2;

                % Left: frame + interface lines
                imshow(frame,'Parent',axImg);
                hold(axImg,'on');
                if ~isnan(surf_px(fi))
                    yline(axImg, surf_px(fi), 'r-', 'LineWidth',2, ...
                        'Label', sprintf('Water %.0fpx', surf_px(fi)), ...
                        'LabelHorizontalAlignment','right', ...
                        'LabelVerticalAlignment','bottom');
                end
                if is_ice && ~isnan(ice_px(fi))
                    yline(axImg, ice_px(fi), 'b-', 'LineWidth',2, ...
                        'Label', sprintf('Ice %.0fpx', ice_px(fi)), ...
                        'LabelHorizontalAlignment','right', ...
                        'LabelVerticalAlignment','top');
                end
                if same_peak
                    text(axImg, 5, 15, 'Ice~Water (single peak)', ...
                        'Color',[0.8 0.4 0.0],'FontSize',8, ...
                        'FontWeight','bold','BackgroundColor','w');
                end
                title(axImg, ...
                    sprintf('%s\nFrame %d/%d   t=%.2fs', ...
                        char(videoFile), fi, nFrames_use, t_cam(fi)), ...
                    'FontSize',8,'Interpreter','none');
                hold(axImg,'off');

                % Right: gradient profile + thresholds + depth markers
                y_px_grad = (y_top:y_bot-1)';
                plot(axGrad, grad, y_px_grad*mm_per_px_cam, 'k-','LineWidth',1.0);
                set(axGrad,'YDir','reverse');
                hold(axGrad,'on');
                % Amplitude threshold lines (vertical on gradient axis)
                xline(axGrad, grad_amp_min_water, 'r:', 'LineWidth',1.0, ...
                    'Label',sprintf('w\\_min=%.2f',grad_amp_min_water), ...
                    'LabelHorizontalAlignment','right');
                xline(axGrad, grad_amp_min_ice, 'b:', 'LineWidth',1.0, ...
                    'Label',sprintf('i\\_min=%.2f',grad_amp_min_ice), ...
                    'LabelHorizontalAlignment','right');
                % Detected interface depth lines (horizontal on depth axis)
                if ~isnan(surf_px(fi))
                    yline(axGrad, surf_px(fi)*mm_per_px_cam, 'r--','LineWidth',1.5, ...
                        'Label',sprintf('Water %.1fmm',surf_px(fi)*mm_per_px_cam), ...
                        'LabelHorizontalAlignment','left', ...
                        'LabelVerticalAlignment','bottom');
                end
                if is_ice && ~isnan(ice_px(fi))
                    yline(axGrad, ice_px(fi)*mm_per_px_cam, 'b--','LineWidth',1.5, ...
                        'Label',sprintf('Ice %.1fmm',ice_px(fi)*mm_per_px_cam), ...
                        'LabelHorizontalAlignment','left', ...
                        'LabelVerticalAlignment','top');
                end
                xlabel(axGrad,'Gradient (a.u.)','FontSize',9);
                ylabel(axGrad,'Depth from frame top (mm)','FontSize',9);
                title(axGrad,'Vertical intensity gradient','FontSize',9, ...
                    'Interpreter','none');
                hold(axGrad,'off');

                drawnow limitrate;
            end

        end  % frame loop

        % Close live figure when this video is done
        if isgraphics(hDynFig); close(hDynFig); end

        % ==================================================================
        %  4j. Convert pixel positions to metres (zero-mean)
        % ==================================================================
        % ---- Water surface ----
        valid_surf  = ~isnan(surf_px);
        surf_mm     = NaN(size(surf_px));
        surf_mm(valid_surf) = -(surf_px(valid_surf) - mean(surf_px,'omitnan')) ...
            * mm_per_px_cam;
        surf_m = surf_mm / 1000;

        % Convert per-frame position uncertainty from px to metres.
        % The uncertainty is a half-width (symmetric), so no sign flip needed.
        surf_unc_m = surf_unc_px_ts * mm_per_px_cam / 1000;   % [m]  <-- NEW

        % ---- Ice bottom ----
        ice_m_out  = [];
        ice_unc_m  = [];                                        % <-- NEW

        if is_ice && any(~isnan(ice_px))
            valid_ice = ~isnan(ice_px);
            ice_mm    = NaN(size(ice_px));
            ice_mm(valid_ice) = -(ice_px(valid_ice) - mean(ice_px,'omitnan')) ...
                * mm_per_px_cam;
            ice_m_out = ice_mm / 1000;
            ice_unc_m = ice_unc_px_ts * mm_per_px_cam / 1000;  % [m]  <-- NEW
        end

        ice_m_out = [];
        if is_ice && any(~isnan(ice_px))
            valid_ice      = ~isnan(ice_px);
            ice_mm         = NaN(size(ice_px));
            ice_mm(valid_ice) = -(ice_px(valid_ice) - mean(ice_px,'omitnan')) ...
                                 * mm_per_px_cam;
            ice_m_out = ice_mm / 1000;
        end

        if vid_despike_enable
            surf_m = wm_cam_despike(surf_m, vid_despike_thresh_m, round(5*Fs_cam));
            if ~isempty(ice_m_out)
                ice_m_out = wm_cam_despike(ice_m_out, vid_despike_thresh_m, ...
                                            round(5*Fs_cam));
            end
        end

        n_valid_surf = sum(~isnan(surf_m));
        n_valid_ice  = sum(~isnan(ice_m_out));
        fprintf('  Valid frames — water: %d/%d (%.1f%%)   ice: %d/%d (%.1f%%)\n', ...
            n_valid_surf, nFrames_use, 100*n_valid_surf/nFrames_use, ...
            n_valid_ice,  nFrames_use, 100*n_valid_ice /nFrames_use);

        % ==================================================================
        %  4k. Store time series
        % ==================================================================
        camTimeSeries(kCamTS).VideoFile    = videoFile;
        camTimeSeries(kCamTS).AcousticFile = fileName;
        camTimeSeries(kCamTS).t_s          = t_cam;
        camTimeSeries(kCamTS).eta_m        = surf_m;
        camTimeSeries(kCamTS).ice_m        = ice_m_out;
        camTimeSeries(kCamTS).InputAmp_V   = fAmp;
        camTimeSeries(kCamTS).InputFreq_Hz = fFreq;
        camTimeSeries(kCamTS).CamLoc_m    = camLoc;
        camTimeSeries(kCamTS).Fs_cam_Hz   = Fs_cam;
        camTimeSeries(kCamTS).PairRowIdx  = pairRow;
          camTimeSeries(kCamTS).surf_unc_m = surf_unc_m;  
        camTimeSeries(kCamTS).ice_unc_m  = ice_unc_m;    
        kCamTS = kCamTS + 1;

        fprintf('  Stored TS: %d frames  %.2f fps  A=%.2fV  f=%.3fHz  x=%.2fm\n', ...
            nFrames_use, Fs_cam, fAmp, fFreq, camLoc);

        % ==================================================================
        %  4l. Diagnostic wave plot
        % ==================================================================
        hWaveFig = figure( ...
            'Name',        sprintf('Raw Wave -- %s', char(videoFile)), ...
            'NumberTitle', 'off');
        axWave = axes(hWaveFig);
        hold(axWave,'on'); grid(axWave,'on');

        plot(axWave, t_cam, surf_m, 'r-', 'LineWidth',1.0, ...
            'DisplayName','Water \eta(t)');
        if ~isempty(ice_m_out)
            plot(axWave, t_cam, ice_m_out, 'b-', 'LineWidth',1.0, ...
                'DisplayName','Ice \eta(t)');
        end

        xlabel(axWave,'$t$ (s)',    'Interpreter','latex','FontSize',11);
        ylabel(axWave,'$\eta$ (m)', 'Interpreter','latex','FontSize',11);
        title(axWave, ...
            sprintf('%s   A=%.2fV  f=%.3fHz  x=%.2fm', ...
                char(videoFile), fAmp, fFreq, camLoc), ...
            'Interpreter','none','FontSize',10);
        legend(axWave,'show','Location','best', ...
            'Interpreter','none','FontSize',9);

    end  % ~skip_flag (frame loop + post-processing)

    % ==================================================================
    %  Outer catch
    % ==================================================================
    catch ME_loop
        fprintf(2,'\n>>> [ERROR file %d: %s] <<<\n', i, fileName);
        fprintf(2,'>>> %s\n', ME_loop.message);
        if ~isempty(ME_loop.stack)
            fprintf(2,'>>> in %s, line %d\n', ...
                ME_loop.stack(1).name, ME_loop.stack(1).line);
        end
        fprintf('  Skipping. %d TS stored so far.\n', kCamTS-1);
        if isgraphics(hDynFig); close(hDynFig); end
    end

end  % main file loop

close(hWait);
fprintf('\nMain loop complete. %d time series extracted.\n', kCamTS-1);



%% =========================================================
%  SECTION 4b: INTERMEDIATE SAVE
% =========================================================
if mid_save
    disp('--- Section 4b: Intermediate Save ---');
    midOutputDir = fullfile(pwd, ['results_sidecam_' date_str '_MID']);
    if ~exist(midOutputDir,'dir'); mkdir(midOutputDir); end
    fprintf('Output directory: %s\n', midOutputDir);

    nCamTS_saved = 0;
    camTSindex   = table();

    if kCamTS > 1
        fprintf('  Saving %d time-series CSVs...\n', kCamTS-1);
        for iTS = 1:(kCamTS-1)
            ts = camTimeSeries(iTS);
            [~,vidBase,~] = fileparts(char(ts.VideoFile));
            safeBase = regexprep(vidBase,'[\\/:*?"<>| ]','_');

            % Water surface time series
            fn_w = sprintf('CamTS_water_%s_A%.2fV_f%.3fHz_x%.2fm.csv', ...
                safeBase, ts.InputAmp_V, ts.InputFreq_Hz, ts.CamLoc_m);
            % Water surface time series + per-frame position uncertainty
            unc_w = ts.surf_unc_m;
            if isempty(unc_w)
                unc_w = NaN(size(ts.t_s));   % fill with NaN if not computed
            end
            writetable(table(ts.t_s, ts.eta_m, unc_w, ...
                'VariableNames',{'t_s','eta_water_m','eta_water_unc_m'}), ...
                fullfile(midOutputDir, fn_w));
 
            fprintf('    Water: %s\n', fn_w);

            % Ice displacement time series (if available)
            fn_i = '';
            if isfield(ts,'ice_m') && ~isempty(ts.ice_m) && any(~isnan(ts.ice_m))
                fn_i = sprintf('CamTS_ice_%s_A%.2fV_f%.3fHz_x%.2fm.csv', ...
                    safeBase, ts.InputAmp_V, ts.InputFreq_Hz, ts.CamLoc_m);
                % Ice displacement time series + per-frame position uncertainty
                unc_i = ts.ice_unc_m;
                if isempty(unc_i)
                    unc_i = NaN(size(ts.t_s));
                end
                writetable(table(ts.t_s, ts.ice_m, unc_i, ...
                    'VariableNames',{'t_s','eta_ice_m','eta_ice_unc_m'}), ...
                    fullfile(midOutputDir, fn_i));

                fprintf('    Ice:   %s\n', fn_i);
            end

            nCamTS_saved = nCamTS_saved + 1;

            % Index row
            if ~isempty(pairRawTable) && ...
               ~isnan(ts.PairRowIdx) && ts.PairRowIdx <= height(pairRawTable)
                idxRow = pairRawTable(ts.PairRowIdx,:);
                idxRow.wave_TS_water_sidecam = string(fn_w);
                idxRow.wave_TS_ice_sidecam   = string(fn_i);
                idxRow.FrameRate_fps         = ts.Fs_cam_Hz;
            else
                idxRow = table(string(ts.VideoFile), string(ts.AcousticFile), ...
                    ts.InputAmp_V, ts.InputFreq_Hz, ts.CamLoc_m, ...
                    string(fn_w), string(fn_i), ts.Fs_cam_Hz, ...
                    'VariableNames',{'VideoFile','AcousticFile', ...
                    'SetAmplitude_V','SetFrequency_Hz','CameraLocation_m', ...
                    'wave_TS_water_sidecam','wave_TS_ice_sidecam', ...
                    'FrameRate_fps'});
            end

            if isempty(camTSindex); camTSindex = idxRow;
            else; camTSindex = [camTSindex; idxRow]; end %#ok<AGROW>
        end

        idxPath = fullfile(midOutputDir, 'CamTimeSeries_INDEX.csv');
        writetable(camTSindex, idxPath);
        fprintf('  Saved index: %s\n', idxPath);
        fprintf('  Total exported: %d\n', nCamTS_saved);
    else
        fprintf('  [SKIP] No time series to export.\n');
    end

    if save_fig
        allOpenFigs = findall(0,'Type','figure');
        nFigSaved   = 0;
        for kFig = 1:length(allOpenFigs)
            fhMid = allOpenFigs(kFig);
            if ~isgraphics(fhMid); continue; end
            rawName  = get(fhMid,'Name');
            if isempty(rawName); rawName = sprintf('Figure_%d',fhMid.Number); end
            safeName = strtrim(regexprep(rawName,'[\\/:*?"<>|]','_'));
            try
                exportgraphics(fhMid,fullfile(midOutputDir,[safeName '.png']),'Resolution',300);
                exportgraphics(fhMid,fullfile(midOutputDir,[safeName '.pdf']),'ContentType','vector');
                nFigSaved = nFigSaved + 1;
            catch ME_mid
                fprintf('  [WARN] Cannot save "%s": %s\n',safeName,ME_mid.message);
            end
        end
        fprintf('  Saved %d figures.\n', nFigSaved);
    end
    disp('Intermediate save complete.');
end

disp('=== tank_process_sidecam_v4.m finished ===');














