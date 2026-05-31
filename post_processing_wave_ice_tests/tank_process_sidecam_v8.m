%% =========================================================
%  tank_process_sidecam_v8.m
%  SIDE-CAMERA VIDEO ANALYSIS 
%
%  PURPOSE:
%    Processes side-camera videos of the tank and
%    extracts the raw displacement time series eta(t) of the
%    surface that is in contact with air (ie ice when no overwash or water if overwash
%    is present ) from each video.
%
%
%    This script finds the uppermost peak in the vertical intensity gradient (grayscale imgs) 
%    that passes the amplitude window threshold.
%
%  WORKFLOW:
%    1. User configuration of flags and parameters.
%    2. Metadata CSVs are loaded.
%    3. Camera locations are derived from the sensor table.
%    4. Storage structures are initialized.
%    5. Video readability is pre-checked.
%    6. Calibration mode is chosen (per-location or per-video).
%    7. Region of Interest (ROI) and Calibration are set up.
%    8. Main processing loop extracts time series frame-by-frame.
%    9. Intermediate save exports the results to CSV and saves figures.
%
%  OUTPUTS (written to results_sidecam_<DATE>_MID/):
%    - CamTS_<VideoBase>_A<V>V_f<Hz>Hz_x<m>m.csv  (t_s | eta_m | eta_unc_m)
%    - CamTimeSeries_INDEX.csv
%    - All open figures as PNG (300 dpi) and vector PDF.
%
%  DEPENDENCIES:
%    Signal Processing Toolbox  — imgaussfilt(), findpeaks()
%    Image Processing Toolbox   — rgb2gray(), imshow()
%
%  EXTERNAL FUNCTIONS REQUIRED:
%    wm_get_surface_v4.m, wm_cam_test_section_v4.m, wm_cam_preprocess.m,
%    wm_cam_preprocess_defaults.m, wm_cam_define_roi.m, wm_cam_calibrate.m, 
%    wm_cam_despike.m, wm_load_location_metadata.m, wm_load_calibration.m, 
%    wm_build_pairmeta_from_table.m, wm_select_files.m, wm_read_signal.m, 
%    wm_parse_filename.m, wm_lookup_metadata.m, wm_find_video.m, loc_to_key.m
% =========================================================

clear; clc; close all;

%% =========================================================
%  SECTION 1: USER CONFIGURATION
% =========================================================

% --- 1a. SAVING FLAGS ---
save_fig = true;  % if true, exports all open figures to PNG + PDF
mid_save = true;  % if true, saves CSV archive after the main loop

% --- 1b. SAMPLING FREQUENCY ---
Fs_default = 100;  % [Hz] fallback acoustic frequency 

% --- 1c. DATE STRING FOR OUTPUT FOLDER ---
date_str = '280426';  % update each session (DDMMYY)

% --- 1d. STEADY-STATE WINDOW (acoustic only) ---
t_start_sensors = 40; % [s] 
t_end_sensors   = 0;  % [s] 0 = full record from t_start onward

% --- 1e. VIDEO ANALYSIS PARAMETERS ---
vid_grad_smooth            = 3;      % [px] Gaussian sigma for profile smoothing. (Higher = less noise, too high = merges edges).
vid_despike_enable         = false;  % despike the raw surface-position series?
vid_despike_thresh_m       = 0.03;   % [m] absolute threshold for despiking
vid_test_nframes           = 10;     %  number of frames shown in detection preview
vid_show_preview_per_video = false;  %  show detection preview in per-video mode?

% --- 1f. PREPROCESSING PARAMETERS (optional preprocessing if image quality is poor) ---
pp = wm_cam_preprocess_defaults();   

% Override individual fields here to tune detection:
pp.enable         = false; %  enable preprocessing?
pp.clahe_cliplim  = 0.05;  %  contrast limit. Increase if surface edge is invisible (0.03-0.10)
pp.denoise_sigma  = 3.0;   % [px] denoise smoothing. Increase if gradient is noisy (1.0-4.0)
pp.sharpen_amount = 1.0;   %  Increase if interface edge is blurry after denoise
pp.gamma_val      = 0.60;  %  Decrease toward 0.5 to brighten dark regions

% --- 1g. AMPLITUDE WINDOW FOR SURFACE PEAK ---
% Only gradient peaks within [grad_amp_min, grad_amp_max] are valid.
grad_amp_min = 1.5;   % [a.u.] Reject peaks weaker than this. Set to 0 to disable.
grad_amp_max = Inf;   % [a.u.] Reject peaks stronger than this. Set to Inf to disable.

% --- 1h. TEMPORAL CONTINUITY FILTERS ---
% Prevents the algorithm from jumping to false edges between frames.
peak_jump_tol_frac = 0.1;  % [fraction] Max surface displacement between frames as a fraction of ROI height. .
amp_jump_tol_frac  = Inf;  % [fraction] Max change in gradient peak amplitude. Inf = disabled. 

% --- 1i. PER-CAMERA PREPROCESSING PROFILES ---
% Automatically selected based on keywords in the video filename.

% Nikon profile — Good contrast but ice-top gradient is relatively soft.
pp_nikon                = wm_cam_preprocess_defaults();
pp_nikon.enable         = false; 
pp_nikon.clahe_cliplim  = 0.03;  %  gentle lift edge contrast
pp_nikon.denoise_sigma  = 1.0;   % [px] mild denoise (Nikon is already clean)
pp_nikon.sharpen_amount = 0.8;   %  Moderate sharpening to steepen the ice edge
pp_nikon.gamma_val      = 0.85;  %  Slight brightening of dark water region
pp_nikon.grad_amp_min   = 1.5;   % [a.u.] Lower threshold for Nikon's softer gradients


% GoPro water surfaces appear as the strongest gradient peak, not the
% uppermost. (i  had a poor field of view and for high amplitudes it
% wasn't perfectly a side view)
pp_gopro                    = wm_cam_preprocess_defaults();
pp_gopro.enable             = false;
pp_gopro.clahe_cliplim      = 0.08;  % [dimensionless]
pp_gopro.denoise_sigma      = 2.5;   % [px]
pp_gopro.sharpen_amount     = 1.5;   % [dimensionless]
pp_gopro.gamma_val          = 0.55;  % [dimensionless]
pp_gopro.grad_amp_min       = 1.5;   % [a.u.]
pp_gopro.use_strongest_peak = true;  %  Instructs surface finder to pick strongest peak instead of uppermost.

% Default profile 
pp_default = pp;
pp_default.grad_amp_min = grad_amp_min;   

% --- 1j. SELECTIVE VIDEO PROCESSING ---
% To reprocess only specific videos, list their base filenames (no extension) here.
% Set to {} (empty cell) to process all.
vid_filter_list = {}; 


%% =========================================================
%  SECTION 2: FILE & METADATA LOADING
% =========================================================
disp('======================================================');
disp('--- Section 2: File & Metadata Loading ---');

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

% --- 2c. Acoustic-video pairing metadata ---
fprintf('\n[STEP 3/4] Select the EXPERIMENT PAIRING metadata CSV.\n');
fprintf('           (e.g. Metadata_wmice_060526.csv)\n');
fprintf('           Links acoustic CSVs to video files and video trim times.\n\n');

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

% Build working pairMeta from the already-loaded table
pairMeta = wm_build_pairmeta_from_table(pairRawTable);

% --- 2d. Acoustic data folders ---
fprintf('\n[STEP 4/4] Select ACOUSTIC SENSOR DATA folder(s).\n');
fprintf('           Enter the number of folders containing raw_data_*.csv.\n');
fprintf('           NOTE: Sensor data only — video files are asked next.\n\n');
allFiles = wm_select_files();
numFiles = length(allFiles);

% --- 2e. Optional separate video folder ---
fprintf('\n  Are your video files in a different folder from the acoustic CSVs?\n');
addVidFolder = questdlg( ...
    ['Are your video files in a different folder from the acoustic CSVs?' ...
     newline newline ...
     '"Yes" — browse for the video root folder.' newline ...
     '"No"  — videos and acoustic CSVs are in the same folder(s).'], ...
    'Video Folder Location', ...
    'Yes — browse for video folder', ...
    'No  — same folder as acoustic CSVs', ...
    'No  — same folder as acoustic CSVs');

if strcmp(addVidFolder, 'Yes — browse for video folder')
    fprintf('\n  Select the root folder containing your video files.\n\n');
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
%  SECTION 3: DERIVING CAMERA LOCATION
%
%  TWO MODES (auto-detected):
%  MODE A — Camera_loc_m is already in pairing CSV. (Direct copy)
%  MODE B — Camera_loc_m is absent. Sensors are parsed and cross-referenced
%           with the placement table to extract Camera + x_m.
% =========================================================
disp('--- Section 3: Deriving Camera_loc_m from sensor placement ---');

nPairRows      = height(pairMeta);
camLoc_derived = NaN(nPairRows, 1);

hasCamLocInCSV = ismember('Camera_loc_m', pairRawTable.Properties.VariableNames) && ...
                 any(isfinite(double(pairRawTable.Camera_loc_m)));

if hasCamLocInCSV
    % ---- MODE A: use Camera_loc_m from the pairing CSV directly ----
    fprintf('  [MODE A] Camera_loc_m column found in pairing CSV — using directly.\n');
    rawCamLoc = double(pairRawTable.Camera_loc_m);

    for iPM = 1:nPairRows
        vidName = strtrim(string(pairMeta.Video_filename(iPM)));
        if strlength(vidName) == 0; continue; end

        cl = rawCamLoc(iPM);
        if isfinite(cl)
            camLoc_derived(iPM) = cl;
            fprintf('  Row %2d: Camera_loc_m=%.2f m  (from pairing CSV)\n', iPM, cl);
        else
            fprintf('  [WARN] Row %d has a video but Camera_loc_m is NaN in CSV.\n', iPM);
        end
    end

else
    % ---- MODE B: derive from sensor placement table ----
    fprintf('  [MODE B] Camera_loc_m absent from pairing CSV — deriving from sensor table.\n');
    
    for iPM = 1:nPairRows
        vidName = strtrim(string(pairMeta.Video_filename(iPM)));
        if strlength(vidName) == 0; continue; end

        % Parse sensor number from acoustic filename
        acFname = char(pairMeta.Acoustic_sensor_filename(iPM));
        tok     = regexp(acFname, '[Ss]ensor(\d+)', 'tokens', 'once');
        if isempty(tok)
            fprintf('  [WARN] Cannot parse sensor number from: %s\n', acFname);
            continue
        end
        sensorNum = str2double(tok{1});
        
        % Look up sensor in placement table
        locIdx = find(locExpanded.SensorID == sensorNum, 1);
        if isempty(locIdx)
            fprintf('  [WARN] Sensor %d not in placement table (row %d).\n', sensorNum, iPM);
            continue
        end

        % Read Camera field 
        camRaw = locExpanded.Camera(locIdx);
        if isstring(camRaw) && ~ismissing(camRaw)
            camStr = char(camRaw);
        elseif iscell(camRaw) && ~isempty(camRaw{1})
            camStr = char(camRaw{1});
        else
            camStr = '';
        end

        if isempty(camStr)
            fprintf('  [WARN] Row %d has a video but Sensor %d has no Camera entry — skipping.\n', ...
                iPM, sensorNum);
            continue
        end

        camLoc_derived(iPM) = locExpanded.x_m(locIdx);
        fprintf('  Row %2d: Sensor%d -> x_m=%.2f m  (Camera: %s)\n', ...
            iPM, sensorNum, locExpanded.x_m(locIdx), camStr);
    end
end

% Attach derived camera locations to pairMeta
pairMeta.Camera_loc_m = camLoc_derived;
fprintf('Camera_loc_m derived for %d / %d rows with videos.\n\n', ...
    sum(~isnan(camLoc_derived)), nPairRows);


%% =========================================================
%  SECTION 4: INITIALISE STORES
% =========================================================
camCalib_store = struct();

% Single-interface struct: eta_m is the air-contact surface displacement.
% surf_unc_m is the per-frame HWHM position uncertainty [m].
camTimeSeries = struct('VideoFile',   {}, 'AcousticFile', {}, ...
                       't_s',         {}, 'eta_m',        {}, ...
                       'surf_unc_m',  {}, ...
                       'InputAmp_V',  {}, 'InputFreq_Hz', {}, ...
                       'CamLoc_m',    {}, 'Fs_cam_Hz',    {}, ...
                       'PairRowIdx',  {});
kCamTS = 1;


%% =========================================================
%  SECTION 5: VIDEO READABILITY PRE-CHECK
% =========================================================
disp('======================================================');
disp('--- Section 5: Video Readability Pre-Check ---');

fprintf('Checking %d video entries...\n\n', height(pairMeta));
problemVideos = {};
fprintf('%-40s %-30s %-8s %-10s %-12s %s\n', ...
    'Acoustic CSV', 'Video file', 'Found', 'Size(MB)', 'Duration(s)', 'Status');
fprintf('%s\n', repmat('-', 1, 115));

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

    vidDuration = NaN;
    vrOK = false; vrErrMsg = '';
    
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

    if     ~foundFile;                               status = 'NOT FOUND';              isProblem = true;
    elseif isnan(fileSizeMB) || fileSizeMB == 0;     status = 'EMPTY FILE';             isProblem = true;
    elseif ~vrOK;                                    status = sprintf('VR FAIL: %s',   vrErrMsg);   isProblem = true;
    elseif ~frameOK;                                 status = sprintf('READ FAIL: %s', frameErrMsg); isProblem = true;
    else;                                            status = 'OK';                                   isProblem = false;
    end

    fprintf('%-40s %-30s %-8s %-10.2f %-12.2f %s\n', ...
        acousticName, char(vidName), mat2str(foundFile), fileSizeMB, vidDuration, status);
        
    if isProblem
        problemVideos{end+1, 1} = acousticName; %#ok<AGROW>
        problemVideos{end, 2}   = char(vidName);
        problemVideos{end, 3}   = status;
    end
end

fprintf('\n--- PRE-CHECK SUMMARY ---\n');
if isempty(problemVideos)
    fprintf('All videos passed.\n\n');
else
    fprintf('WARNING: %d video(s) failed:\n', size(problemVideos, 1));
    for iPrb = 1:size(problemVideos, 1)
        fprintf('  %-40s %-30s %s\n', ...
            problemVideos{iPrb,1}, problemVideos{iPrb,2}, problemVideos{iPrb,3});
    end
    choice = questdlg( ...
        sprintf('%d video(s) could not be opened. Continue anyway?', size(problemVideos,1)), ...
        'Pre-Check Warning', 'Continue', 'Abort', 'Continue');
        
    if strcmp(choice, 'Abort') || isempty(choice)
        error('Aborted by user after video pre-check.');
    end
    fprintf('Continuing with %d problem video(s).\n\n', size(problemVideos,1));
end


%% =========================================================
%  SECTION 6: CALIBRATION STRATEGY
% =========================================================
disp('======================================================');
disp('--- Section 6: Calibration Strategy ---');
disp('======================================================');
fprintf('\n  "Per location" = one ROI + calibration per camera x-position.\n');
fprintf('    (eg. if camera does not move between videos.\n\n');
fprintf('  "Per video"    = ROI + calibration dialog for EVERY video.\n');


calibModeChoice = questdlg( ...
    ['Choose calibration strategy:' newline newline ...
     '"Per location" = one ROI + calibration per camera x-position.' newline ...
     '"Per video"    = ROI + calibration dialog for every individual video.'], ...
    'Calibration Strategy', 'Per location', 'Per video', 'Per location');
    
if isempty(calibModeChoice); calibModeChoice = 'Per location'; end
calib_per_video = strcmp(calibModeChoice, 'Per video');

if calib_per_video
    fprintf('>>> PER VIDEO mode: preview shown before each calibration dialog.\n\n');
else
    fprintf('>>> PER LOCATION mode: one calibration per camera x-position.\n\n');
end


%% =========================================================
%  SECTION 7: ROI & CALIBRATION SETUP (Per-Location Mode)
%  (Skipped dynamically when calib_per_video = true)
% =========================================================
if ~calib_per_video
    disp('--- Section 7: ROI & Calibration (per-location) ---');
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
            fprintf('  [SKIP] No videos at x=%.2f m\n', camX);
            continue;
        end

        vidNames          = cellstr(pairMeta.Video_filename(rowsForLoc));
        vidNamesAnnotated = cell(size(vidNames));
        
        for iVN = 1:length(vidNames)
            thisVid = strtrim(vidNames{iVN});
            note = '[OK]';
            for iPrb = 1:size(problemVideos, 1)
                if strcmp(problemVideos{iPrb,2}, thisVid)
                    note = sprintf('[PROBLEM: %s]', problemVideos{iPrb,3});
                    break;
                end
            end
            vidNamesAnnotated{iVN} = sprintf('%s  %s', thisVid, note);
        end

        [selIdx, ok] = listdlg('ListString', vidNamesAnnotated, ...
            'SelectionMode', 'single', ...
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
            
        % Step 2: Detection preview before calibration
        fprintf('  Step 2/3 — Detection preview (%d frames) ...\n', vid_test_nframes);
        vObjPrev   = VideoReader(char(vidPathForCalib));
        preview_ok = wm_cam_test_section_v4(vObjPrev, 1, vid_test_nframes, ...
            strip_x_f, strip_w_f, search_y_f, vid_grad_smooth, ...
            char(vidFileForCalib), pp);
        clear vObjPrev;
        
        if ~preview_ok
            fprintf('  [SKIP] Preview rejected — skipping calibration for x=%.2f m\n', camX);
            continue;
        end

        % Step 3: Pixel-to-mm calibration
        fprintf('  Step 3/3 — Pixel-to-mm calibration ...\n');
        vObjCalib2   = VideoReader(char(vidPathForCalib));
        calib_result = wm_cam_calibrate(vObjCalib2);

        camCalib_store.(locKey).mm_per_px     = calib_result.mm_per_px;
        camCalib_store.(locKey).strip_x_frac  = strip_x_f;
        camCalib_store.(locKey).strip_w_frac  = strip_w_f;
        camCalib_store.(locKey).search_y_frac = search_y_f;
        camCalib_store.(locKey).done          = true;
        fprintf('  Stored: mm_per_px=%.5f  strip_x=%.3f  strip_w=%.3f  search_y=[%.3f %.3f]\n', ...
            calib_result.mm_per_px, strip_x_f, strip_w_f, search_y_f(1), search_y_f(2));
    end
end

fprintf('\nPre-loop calibration setup complete.\n\n');


%% =========================================================
%  SECTION 8: MAIN PROCESSING LOOP
% =========================================================
set(groot, 'defaultTextInterpreter',          'none');
set(groot, 'defaultAxesTickLabelInterpreter', 'none');
set(groot, 'defaultLegendInterpreter',        'none');

disp('======================================================');
disp('--- Section 8: Main Processing Loop ---');
disp('======================================================');

% ---------------------------------------------------------
%  CHECKPOINT SYSTEM
%  If a script run is interrupted (e.g. Ctrl+C), it saves a 
%  checkpoint so processing can resume where it left off.
% ---------------------------------------------------------
checkpointFile = fullfile(pwd, ...                                    
    sprintf('checkpoint_sidecam_%s.mat', date_str));
i_start = 1;   % default: start from the beginning                   

if exist(checkpointFile, 'file')                                      
    fprintf('\n[CHECKPOINT] Found: %s\n', checkpointFile);
    ckpt = load(checkpointFile, 'last_completed_i', ...               
        'kCamTS', 'camTimeSeries', 'camCalib_store');
    
    fprintf('  Last completed file index : %d / %d\n', ...           
        ckpt.last_completed_i, numFiles);
    fprintf('  Time series stored so far : %d\n', ckpt.kCamTS - 1);

    resumeChoice = questdlg( ...                                      
        sprintf(['Checkpoint found from a previous run.\n\n' ...      
                 'Last completed file : %d / %d\n' ...     
                 'Time series stored  : %d\n\n' ...                  
                 'Resume, or restart from scratch?'], ...             
            ckpt.last_completed_i, numFiles, ckpt.kCamTS - 1), ...   
        'Resume?', 'Resume', 'Restart from scratch', 'Resume');

    if strcmp(resumeChoice, 'Resume')                                  
        % Determine offset rewind in case last file was partially processed
        k_rewind_str = inputdlg( ...         
            {sprintf(['Resume from file %d.\n\n' ...                  
                      'Rewind offset k  (0 = resume exactly where\n' ...
                      'stopped;  positive = redo last k videos).\n\n'...
                      'Recommended: 0 unless the last video was\n' ...
                      'only partially processed.'], ...               
                      ckpt.last_completed_i)}, ...                    
            'Rewind offset', 1, {'0'});

        if isempty(k_rewind_str)                                      
            k_rewind = 0;
        else                                                          
            k_rewind = max(0, round(str2double(k_rewind_str{1})));
        end                                                           

        % Restore state from checkpoint                 
        kCamTS         = ckpt.kCamTS;
        camTimeSeries  = ckpt.camTimeSeries;
        camCalib_store = ckpt.camCalib_store;

        % Rewind counter and trim struct by k_rewind entries         
        kCamTS = max(1, kCamTS - k_rewind);
        if k_rewind > 0 && length(camTimeSeries) >= kCamTS            
            camTimeSeries = camTimeSeries(1 : kCamTS - 1);
        end                                                           

        i_start = max(1, ckpt.last_completed_i + 1 - k_rewind);
        fprintf('[CHECKPOINT] Resuming from file %d (rewind=%d).\n\n',...
            i_start, k_rewind);
    else                                                              
        fprintf('[CHECKPOINT] Restarting from scratch.\n\n');
        % i_start stays 1; kCamTS and camTimeSeries carry over from Section 4   
    end                                                               
end                     

% Safety guard: ensure stores exist if Section 4 was skipped
if ~exist('kCamTS', 'var')
    warning('kCamTS not found — Section 4 may not have run. Reinitialising to 1.');
    kCamTS = 1;
    camTimeSeries = struct('VideoFile',   {}, 'AcousticFile', {}, ...
        't_s',         {}, 'eta_m',        {}, ...
        'surf_unc_m',  {}, ...
        'InputAmp_V',  {}, 'InputFreq_Hz', {}, ...
        'CamLoc_m',    {}, 'Fs_cam_Hz',    {}, ...
        'PairRowIdx',  {});
end

hWait = waitbar(0, 'Processing files...');

% Ensures checkpoint is safely written if script is interrupted
cleanupObj = onCleanup(@() evalin('base', ...
    sprintf(['if exist(''kCamTS'',''var'') && exist(''last_completed_i'',''var'');' ...
             'save(''%s'', ''last_completed_i'', ''kCamTS'', ' ...
             '''camTimeSeries'', ''camCalib_store'');' ...
             'fprintf(''[CHECKPOINT] Saved on interrupt at file %%d.\\n'', last_completed_i);' ...
             'end'], checkpointFile)));
             
last_completed_i = i_start - 1;

% Pre-loop state configuration defaults
grad_amp_min_this       = grad_amp_min;   
use_strongest_peak_this = false;
pp_this                 = pp_default;

for i = i_start:numFiles   

    % Try/Catch per file ensures single bad files don't crash the batch.
    try

    skip_flag = false;
    hDynFig   = gobjects(1); % invalid handle placeholder

    % ==================================================================
    %  8a. Progress bar + filename parsing
    % ==================================================================
    if isgraphics(hWait)
        waitbar(i / numFiles, hWait, ...
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
        fprintf('\nFILE: %s\n  Mode=%s  Fs=%d  Ch=%d  Date=%s  A=%.3fV  f=%.3fHz\n', ...
            fileName, fMode, Fs, fChannel, fDate, fAmp, fFreq);
    end

    % ==================================================================
    %  8b. Read acoustic signal (time vector only, for metadata)
    % ==================================================================
    if ~skip_flag
        [t, ~, ~, readOK] = wm_read_signal(fullPath, Fs); %#ok<ASGLU>
        if ~readOK
            fprintf('  [SKIP] Cannot read: %s\n', fileName);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  8c. Location metadata lookup
    % ==================================================================
    if ~skip_flag
        metaIdx = wm_lookup_metadata(locExpanded, fChannel, fDate);
        if isempty(metaIdx)
            fprintf('  [SKIP] No metadata for Ch=%d Date=%s\n', fChannel, fDate);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  8d. Pairing metadata lookup
    % ==================================================================
    if ~skip_flag
        [~, fileBase, ~] = fileparts(fileName);
        pairRow  = find(strcmp(string(pairMeta.Acoustic_sensor_filename), fileBase), 1);
        hasVideo = ~isempty(pairRow) && ...
                   strlength(strtrim(string(pairMeta.Video_filename(pairRow)))) > 0;
                   
        if ~hasVideo
            fprintf('  [SKIP] No video paired for: %s\n', fileName);
            skip_flag = true;
        end

        % Selective filter processing
        if ~skip_flag && ~isempty(vid_filter_list)
            [~, vidBase_this, ~] = fileparts(char(pairMeta.Video_filename(pairRow)));
            vidBase_this = strtrim(vidBase_this);
            if ~any(strcmp(vid_filter_list, vidBase_this))
                fprintf('  [SKIP] Not in vid_filter_list: %s\n', vidBase_this);
                skip_flag = true;
            end
        end
    end

    % ==================================================================
    %  8e. Extract pairing info & Find Video
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
            
        locKey_cam = loc_to_key(camLoc);
        videoPath  = wm_find_video(videoFile, allFiles, numFiles);
        if videoPath == ""
            fprintf('  [SKIP] Video not found on disk: %s\n', videoFile);
            skip_flag = true;
        end
    end

    % ==================================================================
    %  8f. Calibration Validation (per-video or per-location)
    % ==================================================================
    if ~skip_flag

        if calib_per_video
            fprintf('  [PER-VIDEO CALIB] Starting for: %s\n', char(videoFile));
            fprintf('  Step 1/3 — ROI definition ...\n');
            vObjRoi = VideoReader(char(videoPath));
            [strip_x_frac_cam, strip_w_frac_cam, search_y_frac_cam] = ...
                wm_cam_define_roi(vObjRoi, camLoc, videoFile);
            clear vObjRoi;

            if vid_show_preview_per_video
                fprintf('  Step 2/3 — Detection preview (%d frames)...\n', vid_test_nframes);
                vObjPrev = VideoReader(char(videoPath));
                preview_accepted = wm_cam_test_section_v4(vObjPrev, 1, vid_test_nframes, ...
                    strip_x_frac_cam, strip_w_frac_cam, search_y_frac_cam, ...
                    vid_grad_smooth, char(videoFile), pp_default);
                clear vObjPrev;
                
                if ~preview_accepted
                    fprintf('  [SKIP] Preview rejected by user: %s\n', char(videoFile));
                    skip_flag = true;
                end
            else
                fprintf('  Step 2/3 — Preview SKIPPED (vid_show_preview_per_video=false).\n');
            end

            if ~skip_flag
                fprintf('  Step 3/3 — Pixel-to-mm calibration ...\n');
                vObjCalib    = VideoReader(char(videoPath));
                calib_result = wm_cam_calibrate(vObjCalib);
                mm_per_px_cam = calib_result.mm_per_px;
                clear vObjCalib;
                
                camCalib_store.(locKey_cam).mm_per_px     = mm_per_px_cam;
                camCalib_store.(locKey_cam).strip_x_frac  = strip_x_frac_cam;
                camCalib_store.(locKey_cam).strip_w_frac  = strip_w_frac_cam;
                camCalib_store.(locKey_cam).search_y_frac = search_y_frac_cam;
                camCalib_store.(locKey_cam).done          = true;
                fprintf('  [PER-VIDEO CALIB] Done: %.5f mm/px\n', mm_per_px_cam);
            end

        else
            if ~isfield(camCalib_store, locKey_cam) || ~camCalib_store.(locKey_cam).done
                fprintf('  [SKIP] No calibration for x=%.2f m (key=%s).\n', ...
                    camLoc, locKey_cam);
                skip_flag = true;
            else
                mm_per_px_cam     = camCalib_store.(locKey_cam).mm_per_px;
                strip_x_frac_cam  = camCalib_store.(locKey_cam).strip_x_frac;
                strip_w_frac_cam  = camCalib_store.(locKey_cam).strip_w_frac;
                search_y_frac_cam = camCalib_store.(locKey_cam).search_y_frac;
                fprintf('  [CALIB LOADED] x=%.2f m  %.5f mm/px\n', camLoc, mm_per_px_cam);
            end
        end

    end

    % ==================================================================
    %  8g. Camera-Specific Profiling Setup
    %  Configures amplitude thresholds and peak logic depending on camera type.
    % ==================================================================
    if ~skip_flag
        vidNameLower = lower(char(videoFile));
        
        if contains(vidNameLower, 'gopro')
            pp_this = pp_gopro;
            fprintf('  [PREPROC] GoPro profile selected.\n');
        elseif contains(vidNameLower, 'nikon')
            pp_this = pp_nikon;
            fprintf('  [PREPROC] Nikon profile selected.\n');
        else
            pp_this = pp_default;
            fprintf('  [PREPROC] Default profile (no camera keyword in filename).\n');
        end

        if isfield(pp_this, 'grad_amp_min') && isfinite(pp_this.grad_amp_min)
            grad_amp_min_this = pp_this.grad_amp_min;
        else
            grad_amp_min_this = grad_amp_min;
        end
        fprintf('  [PREPROC] grad_amp_min       : %.2f\n', grad_amp_min_this);
        
        if isfield(pp_this, 'use_strongest_peak')
            use_strongest_peak_this = pp_this.use_strongest_peak;
        else
            use_strongest_peak_this = false;
        end
        fprintf('  [PREPROC] use_strongest_peak : %s\n', mat2str(use_strongest_peak_this));
    end   

    % ==================================================================
    %  8h. Frame Window Configuration
    % ==================================================================
    if ~skip_flag
        vObj = VideoReader(char(videoPath));
        Fs_cam        = vObj.FrameRate;
        nFrames_total = floor(vObj.Duration * Fs_cam);
        
        fprintf('  %.1fs | %.1f fps | ~%d frames\n', ...
            vObj.Duration, Fs_cam, nFrames_total);
            
        frame_start = max(1, round(vid_t_start_this * Fs_cam));
        if vid_t_end_this > 0
            frame_end = min(nFrames_total, round(vid_t_end_this * Fs_cam));
        else
            frame_end = nFrames_total;
        end
        
        frame_end   = min(frame_end, nFrames_total - 1);
        nFrames_use = frame_end - frame_start + 1;

        fprintf('  Frames %d-%d  (%.1f-%.1f s)\n', ...
            frame_start, frame_end, ...
            (frame_start - 1) / Fs_cam, frame_end / Fs_cam);
            
        if (frame_start - 1) / Fs_cam >= vObj.Duration
            fprintf('  [SKIP] frame_start exceeds video duration.\n');
            skip_flag = true;
        end
    end

    % ==================================================================
    %  8i. First-Frame Threshold Preview
    % ==================================================================
    if ~skip_flag

        vObj.CurrentTime = (frame_start - 1) / Fs_cam;
        
        if hasFrame(vObj)
            frame_prev = readFrame(vObj);
            if size(frame_prev, 3) == 3; frame_prev = rgb2gray(frame_prev); end

            frame_prev = wm_cam_preprocess(frame_prev, pp_this);
            fh_p = size(frame_prev, 1);
            fw_p = size(frame_prev, 2);
            
            xl_p = max(1,    round((strip_x_frac_cam - strip_w_frac_cam/2) * fw_p));
            xr_p = min(fw_p, round((strip_x_frac_cam + strip_w_frac_cam/2) * fw_p));
            yt_p = max(1,    round(search_y_frac_cam(1) * fh_p));
            yb_p = min(fh_p, round(search_y_frac_cam(2) * fh_p));

            strip_p  = double(frame_prev(yt_p:yb_p, xl_p:xr_p));
            prof_p   = imgaussfilt(mean(strip_p, 2), vid_grad_smooth);
            grad_p   = abs(diff(prof_p));

            if max(grad_p) > 0
                [pks_p, locs_p] = findpeaks(grad_p, 'SortStr', 'descend', ...
                    'MinPeakProminence', max(grad_p) * 0.05);
            else
                pks_p = []; locs_p = [];
            end

            [surf_p, ~] = wm_get_surface_v4(pks_p, locs_p, ...
                NaN, NaN, ...
                Inf, yt_p, ...
                grad_amp_min_this, grad_amp_max, ...
                Inf, grad_p, ...
                use_strongest_peak_this);

            % Render Diagnostic figure
            hPrevFig = figure( ...
                'Name',        sprintf('Threshold Preview -- %s', char(videoFile)), ...
                'NumberTitle', 'off', 'Color', 'w');

            axPi = subplot(1, 2, 1, 'Parent', hPrevFig);
            axPg = subplot(1, 2, 2, 'Parent', hPrevFig);

            imshow(frame_prev, 'Parent', axPi); hold(axPi, 'on');
            if ~isnan(surf_p)
                yline(axPi, surf_p, 'r-', 'LineWidth', 2, ...
                    'Label',  sprintf('Surface %.0f px', surf_p), ...
                    'LabelHorizontalAlignment', 'right', ...
                    'LabelVerticalAlignment',   'bottom');
            end
            title(axPi, sprintf('THRESHOLD PREVIEW — frame 1\n%s', char(videoFile)), ...
                'FontSize', 8, 'Interpreter', 'none');
            hold(axPi, 'off');

            y_pg = (yt_p : yb_p - 1)';
            plot(axPg, grad_p, y_pg * mm_per_px_cam, 'k-', 'LineWidth', 1.2);
            set(axPg, 'YDir', 'reverse'); hold(axPg, 'on');
            
            xline(axPg, grad_amp_min_this, 'r--', 'LineWidth', 1.2, ...
                'Label', sprintf('min=%.2f', grad_amp_min_this), ...   
                'LabelHorizontalAlignment', 'right');
                
            if isfinite(grad_amp_max)
                xline(axPg, grad_amp_max, 'r-', 'LineWidth', 1.2, ...
                    'Label', sprintf('max=%.2f', grad_amp_max), ...
                    'LabelHorizontalAlignment', 'left');
            end

            if ~isnan(surf_p)
                yline(axPg, surf_p * mm_per_px_cam, 'r-', 'LineWidth', 1.5, ...
                    'Label', sprintf('Surface %.1f mm', surf_p * mm_per_px_cam), ...
                    'LabelHorizontalAlignment', 'left', ...
                    'LabelVerticalAlignment',   'bottom');
            end

            xlabel(axPg, 'Gradient (a.u.)', 'FontSize', 9);
            ylabel(axPg, 'Depth from frame top (mm)', 'FontSize', 9);
            title(axPg, ...
                sprintf('Amplitude window: [%.2f, %s]  [camera-specific]', ...
                    grad_amp_min_this, ...                             
                    ternary_str(isfinite(grad_amp_max), sprintf('%.2f', grad_amp_max), 'Inf')), ...
                'FontSize', 9, 'Interpreter', 'none');
            hold(axPg, 'off');

            drawnow;

            choice_prev = questdlg( ...
                sprintf(['%s\n\n' ...
                         'grad_amp_min = %.2f  [camera-specific]\n' ...
                         'grad_amp_max = %s\n\n' ...
                         'red line =  detected air-contact surface.\n' ...
                         'Proceed to analyse all frames, or skip this video?'], ...
                    char(videoFile), grad_amp_min_this, ...            
                    ternary_str(isfinite(grad_amp_max), sprintf('%.2f', grad_amp_max), 'Inf')), ...
                'Threshold Preview', 'Proceed', 'Skip video', 'Proceed');
                
            close(hPrevFig);

            if strcmp(choice_prev, 'Skip video') || isempty(choice_prev)
                fprintf('  [SKIP] Skipped after threshold preview: %s\n', char(videoFile));
                skip_flag = true;
            end
        end
    end   

    % ==================================================================
    %  8j. MAIN FRAME LOOP
    % ==================================================================
    if ~skip_flag

        surf_px        = NaN(nFrames_use, 1);
        surf_unc_px_ts = NaN(nFrames_use, 1);
        t_cam          = (0 : nFrames_use - 1)' / Fs_cam;
        
        prev_surf_px  = NaN;
        prev_surf_amp = NaN;

        vObj.CurrentTime = (frame_start - 1) / Fs_cam;
        
        hDynFig = figure( ...
            'Name',        sprintf('Live Detection -- %s', char(videoFile)), ...
            'NumberTitle', 'off', 'Color', 'w');
            
        for fi = 1:nFrames_use

            if ~hasFrame(vObj); break; end
            frame = readFrame(vObj);
            if size(frame, 3) == 3; frame = rgb2gray(frame); end

            frame = wm_cam_preprocess(frame, pp_this);
            frame_h = size(frame, 1);
            frame_w = size(frame, 2);

            x_left  = max(1,       round((strip_x_frac_cam - strip_w_frac_cam/2) * frame_w));
            x_right = min(frame_w, round((strip_x_frac_cam + strip_w_frac_cam/2) * frame_w));
            y_top   = max(1,       round(search_y_frac_cam(1) * frame_h));
            y_bot   = min(frame_h, round(search_y_frac_cam(2) * frame_h));

            % Establish adaptive displacement filter thresholds
            roi_height_px = y_bot - y_top;

            if ismember('ka', pairMeta.Properties.VariableNames) && ...
               ~isnan(pairMeta.ka(pairRow)) && isfinite(pairMeta.ka(pairRow))
                ka_this = pairMeta.ka(pairRow);
            else
                ka_this = NaN;
            end

            if ~isnan(ka_this) && ka_this > 0.07
                jump_tol_px = 0.40 * roi_height_px; % High Steepness allowed displacement
            elseif ~isnan(ka_this) && ka_this > 0.04
                jump_tol_px = 0.25 * roi_height_px; % Moderate Steepness allowed displacement
            else
                jump_tol_px = 0.15 * roi_height_px; % Low steepness allowed displacement
            end

            strip          = double(frame(y_top:y_bot, x_left:x_right));
            profile_smooth = imgaussfilt(mean(strip, 2), vid_grad_smooth);
            grad           = abs(diff(profile_smooth));
            
            if max(grad) > 0
                [pks, locs] = findpeaks(grad, ...
                    'SortStr',          'descend', ...
                    'MinPeakProminence', max(grad) * 0.05);
            else
                pks  = []; locs = [];
            end

            [surf_abs_fi, surf_unc_fi] = wm_get_surface_v4( ...
                pks, locs, ...
                prev_surf_px,  prev_surf_amp, ...
                jump_tol_px,   y_top, ...
                grad_amp_min_this,  grad_amp_max, ...
                amp_jump_tol_frac, ...
                grad, ...
                use_strongest_peak_this);

            surf_px(fi)        = surf_abs_fi;
            surf_unc_px_ts(fi) = surf_unc_fi;

            % Update continuity history registers
            if ~isnan(surf_abs_fi)
                prev_surf_px = surf_abs_fi;
                mask_valid = (pks >= grad_amp_min_this) & (pks <= grad_amp_max);
                pks_valid  = pks(mask_valid);
                locs_valid = locs(mask_valid);
                abs_locs   = locs_valid + y_top - 1;
                match_idx  = find(abs_locs == surf_abs_fi, 1);
                
                if ~isempty(match_idx)
                    prev_surf_amp = pks_valid(match_idx);
                end
            end

            % Update Live display graph
            if mod(fi, 10) == 0 && isgraphics(hDynFig)

                clf(hDynFig);
                axImg  = subplot(1, 2, 1, 'Parent', hDynFig);
                axGrad = subplot(1, 2, 2, 'Parent', hDynFig);

                imshow(frame, 'Parent', axImg); hold(axImg, 'on');
                
                if ~isnan(surf_px(fi))
                    yline(axImg, surf_px(fi), 'r-', 'LineWidth', 2, ...
                        'Label', sprintf('Surface %.0f px', surf_px(fi)), ...
                        'LabelHorizontalAlignment', 'right', ...
                        'LabelVerticalAlignment',   'bottom');
                end
                
                title(axImg, ...
                    sprintf('%s\nFrame %d/%d   t=%.2f s', ...
                        char(videoFile), fi, nFrames_use, t_cam(fi)), ...
                    'FontSize', 8, 'Interpreter', 'none');
                hold(axImg, 'off');

                y_px_grad = (y_top : y_bot - 1)';
                plot(axGrad, grad, y_px_grad * mm_per_px_cam, 'k-', 'LineWidth', 1.0);
                set(axGrad, 'YDir', 'reverse'); hold(axGrad, 'on');
                
                xline(axGrad, grad_amp_min_this, 'r:', 'LineWidth', 1.0, ...
                    'Label', sprintf('min=%.2f', grad_amp_min_this), ...
                    'LabelHorizontalAlignment', 'right');
                    
                if isfinite(grad_amp_max)
                    xline(axGrad, grad_amp_max, 'r-', 'LineWidth', 1.0, ...
                        'Label', sprintf('max=%.2f', grad_amp_max), ...
                        'LabelHorizontalAlignment', 'left');
                end
                
                if ~isnan(surf_px(fi))
                    yline(axGrad, surf_px(fi) * mm_per_px_cam, 'r--', 'LineWidth', 1.5, ...
                        'Label', sprintf('Surface %.1f mm', surf_px(fi) * mm_per_px_cam), ...
                        'LabelHorizontalAlignment', 'left', ...
                        'LabelVerticalAlignment',   'bottom');
                end

                xlabel(axGrad, 'Gradient (a.u.)', 'FontSize', 9);
                ylabel(axGrad, 'Depth from frame top (mm)', 'FontSize', 9);
                title(axGrad, 'Vertical intensity gradient', 'FontSize', 9, ...
                    'Interpreter', 'none');
                hold(axGrad, 'off');

                drawnow limitrate;

                % Write mid-loop checkpoints
                if mod(fi, 500) == 0                                  
                    try                                          
                        save(checkpointFile, 'last_completed_i', ... 
                            'kCamTS', 'camTimeSeries', ...           
                            'camCalib_store');                        
                    catch; end                                        
                end                                         
            end
        end  

        if isgraphics(hDynFig); close(hDynFig); end

        % ==================================================================
        %  8k. Post-hoc Median Outlier Removal
        % ==================================================================
        if any(~isnan(surf_px))

            median_win   = round(Fs_cam * 1.0);
            mad_thresh   = 4.0;
            median_win   = max(median_win, 5);
            half_win     = floor(median_win / 2);
            surf_px_filt = surf_px;
            n_outliers   = 0;

            for fi_med = 1:nFrames_use
                win_lo     = max(1,           fi_med - half_win);
                win_hi     = min(nFrames_use, fi_med + half_win);
                local_vals = surf_px(win_lo:win_hi);
                local_vals = local_vals(~isnan(local_vals));
                
                if numel(local_vals) < 3; continue; end

                local_med = median(local_vals);
                local_mad = median(abs(local_vals - local_med));
                if local_mad < 0.5; local_mad = 0.5; end

                if ~isnan(surf_px(fi_med)) && ...
                        abs(surf_px(fi_med) - local_med) > mad_thresh * local_mad
                    surf_px_filt(fi_med) = NaN;
                    n_outliers = n_outliers + 1;
                end
            end

            surf_px = surf_px_filt;
            if n_outliers > 0
                fprintf('  [Median filter] Removed %d outlier frame(s) (%.1f%%).\n', ...
                    n_outliers, 100 * n_outliers / nFrames_use);
            end
        end

        % ==================================================================
        %  8l. Coordinate System Conversion
        %  Pixel scale to physical distance conversion
        % ==================================================================
        valid_surf = ~isnan(surf_px);
        surf_mm    = NaN(size(surf_px));
        surf_mm(valid_surf) = -(surf_px(valid_surf) - mean(surf_px, 'omitnan')) * mm_per_px_cam;
        surf_m     = surf_mm / 1000;
        surf_unc_m = surf_unc_px_ts * mm_per_px_cam / 1000;
        
        if vid_despike_enable
            surf_m = wm_cam_despike(surf_m, vid_despike_thresh_m, round(5 * Fs_cam));
        end

        n_valid_surf = sum(~isnan(surf_m));
        fprintf('  Valid frames: %d/%d (%.1f%%)\n', ...
            n_valid_surf, nFrames_use, 100 * n_valid_surf / nFrames_use);
            
        % ==================================================================
        %  8m. Global Array Storage
        % ==================================================================
        camTimeSeries(kCamTS).VideoFile    = videoFile;
        camTimeSeries(kCamTS).AcousticFile = fileName;
        camTimeSeries(kCamTS).t_s          = t_cam;
        camTimeSeries(kCamTS).eta_m        = surf_m;
        camTimeSeries(kCamTS).surf_unc_m   = surf_unc_m;
        camTimeSeries(kCamTS).InputAmp_V   = fAmp;
        camTimeSeries(kCamTS).InputFreq_Hz = fFreq;
        camTimeSeries(kCamTS).CamLoc_m    = camLoc;
        camTimeSeries(kCamTS).Fs_cam_Hz   = Fs_cam;
        camTimeSeries(kCamTS).PairRowIdx  = pairRow;
        kCamTS = kCamTS + 1;

        fprintf('  Stored TS: %d frames  %.2f fps  A=%.2fV  f=%.3fHz  x=%.2fm\n', ...
            nFrames_use, Fs_cam, fAmp, fFreq, camLoc);
            
        % ==================================================================
        %  8n. Generate Static Analytical Plot
        % ==================================================================
        hWaveFig = figure( ...
            'Name',        sprintf('Raw Wave -- %s', char(videoFile)), ...
            'NumberTitle', 'off');
        axWave = axes(hWaveFig);
        hold(axWave, 'on'); grid(axWave, 'on');

        plot(axWave, t_cam, surf_m, 'r-', 'LineWidth', 1.0, ...
            'DisplayName', 'Air-contact surface $\eta(t)$' );
            
        xlabel(axWave, '$t$ (s)',    'Interpreter', 'latex', 'FontSize', 11);
        ylabel(axWave, '$\eta$ (m)', 'Interpreter', 'latex', 'FontSize', 11);
        title(axWave, ...
            sprintf('%s   A=%.2fV  f=%.3fHz  x=%.2fm', ...
                char(videoFile), fAmp, fFreq, camLoc), ...
            'Interpreter', 'none', 'FontSize', 10);
        legend(axWave, 'show', 'Location', 'best', ...
            'Interpreter', 'none', 'FontSize', 9);
            
    end  % skip loop frame processor 

    catch ME_loop
        fprintf(2, '\n>>> [ERROR file %d: %s] <<<\n', i, fileName);
        fprintf(2, '>>> %s\n', ME_loop.message);
        if ~isempty(ME_loop.stack)
            fprintf(2, '>>> in %s, line %d\n', ...
                ME_loop.stack(1).name, ME_loop.stack(1).line);
        end
        
        nStored = 0;
        if exist('kCamTS', 'var'); nStored = kCamTS - 1; end          
        fprintf('  Skipping. %d TS stored so far.\n', nStored);
        if isgraphics(hDynFig); close(hDynFig); end

        try                                                            
            save(checkpointFile, 'last_completed_i', 'kCamTS', ...    
                 'camTimeSeries', 'camCalib_store');
            fprintf('  [CHECKPOINT] Saved after error (last=%d).\n', ...
                last_completed_i);
        catch; end                                                     
    end

    last_completed_i = i;
    if mod(i, 5) == 0 || i == numFiles                                 
        try                                                       
            save(checkpointFile, 'last_completed_i', 'kCamTS', ...    
                'camTimeSeries', 'camCalib_store');
            fprintf('  [CHECKPOINT] Saved at file %d/%d.\n', i, numFiles);
        catch ME_ckpt                                                  
            fprintf('  [WARN] Checkpoint save failed: %s\n', ...      
              ME_ckpt.message);                                      
        end                                                            
    end                 

end  % Main Batch loop terminator

close(hWait);
fprintf('\nMain loop complete. %d time series extracted.\n', kCamTS - 1);

if exist(checkpointFile, 'file')                                      
    delete(checkpointFile);
    fprintf('[CHECKPOINT] Deleted (run completed cleanly).\n');
end                                                                    


%% =========================================================
%  SECTION 9: INTERMEDIATE SAVE AND EXPORT
% =========================================================
if mid_save
    disp('--- Section 9: Intermediate Save and Export ---');
    midOutputDir = fullfile(pwd, ['results_sidecam_' date_str '_MID']);
    
    if ~exist(midOutputDir, 'dir'); mkdir(midOutputDir); end
    fprintf('Output directory: %s\n', midOutputDir);
    
    nCamTS_saved = 0;
    camTSindex   = table();

    if kCamTS > 1
        fprintf('  Saving %d time-series CSVs...\n', kCamTS - 1);
        
        for iTS = 1:(kCamTS - 1)
            ts = camTimeSeries(iTS);
            [~, vidBase, ~] = fileparts(char(ts.VideoFile));
            safeBase = regexprep(vidBase, '[\\/:*?"<>| ]', '_');

            fn = sprintf('CamTS_%s_A%.2fV_f%.3fHz_x%.2fm.csv', ...
                safeBase, ts.InputAmp_V, ts.InputFreq_Hz, ts.CamLoc_m);

            unc = ts.surf_unc_m;
            if isempty(unc)
                unc = NaN(size(ts.t_s));
            end

            writetable(table(ts.t_s, ts.eta_m, unc, ...
                'VariableNames', {'t_s', 'eta_m', 'eta_unc_m'}), ...
                fullfile(midOutputDir, fn));

            fprintf('    Saved: %s\n', fn);
            nCamTS_saved = nCamTS_saved + 1;

            if ~isempty(pairRawTable) && ...
               ~isnan(ts.PairRowIdx) && ts.PairRowIdx <= height(pairRawTable)
                idxRow = pairRawTable(ts.PairRowIdx, :);
                idxRow.wave_TS_sidecam = string(fn);
                idxRow.FrameRate_fps   = ts.Fs_cam_Hz;
            else
                idxRow = table(string(ts.VideoFile), string(ts.AcousticFile), ...
                    ts.InputAmp_V, ts.InputFreq_Hz, ts.CamLoc_m, ...
                    string(fn), ts.Fs_cam_Hz, ...
                    'VariableNames', {'VideoFile', 'AcousticFile', ...
                    'SetAmplitude_V', 'SetFrequency_Hz', 'CameraLocation_m', ...
                    'wave_TS_sidecam', 'FrameRate_fps'});
            end

            if isempty(camTSindex)
                camTSindex = idxRow;
            else
                camTSindex = [camTSindex; idxRow]; %#ok<AGROW>
            end
        end

        idxPath = fullfile(midOutputDir, 'CamTimeSeries_INDEX.csv');
        writetable(camTSindex, idxPath);
        fprintf('  Saved index: %s\n', idxPath);
        fprintf('  Total exported: %d\n', nCamTS_saved);
    else
        fprintf('  [SKIP] No time series to export.\n');
    end

    if save_fig
        allOpenFigs = findall(0, 'Type', 'figure');
        nFigSaved   = 0;
        for kFig = 1:length(allOpenFigs)
            fhMid = allOpenFigs(kFig);
            if ~isgraphics(fhMid); continue; end
            rawName  = get(fhMid, 'Name');
            if isempty(rawName); rawName = sprintf('Figure_%d', fhMid.Number); end
            safeName = strtrim(regexprep(rawName, '[\\/:*?"<>|]', '_'));
            try
                exportgraphics(fhMid, fullfile(midOutputDir, [safeName '.png']), 'Resolution', 300);
                exportgraphics(fhMid, fullfile(midOutputDir, [safeName '.pdf']), 'ContentType', 'vector');
                nFigSaved = nFigSaved + 1;
            catch ME_mid
                fprintf('  [WARN] Cannot save "%s": %s\n', safeName, ME_mid.message);
            end
        end
        fprintf('  Saved %d figures.\n', nFigSaved);
    end
    disp('Intermediate save complete.');
end

disp('=== tank_process_sidecam.m finished ===');


%% =========================================================
%  LOCAL UTILITY FUNCTION
% =========================================================
function s = ternary_str(cond, a, b)
% TERNARY_STR  Return string a if cond is true, else b.
%  Used inline to format Inf gracefully in dialog messages.
    if cond; s = a; else; s = b; end
end