function pairMeta = wm_load_pair_metadata_v2()
% WM_LOAD_PAIR_METADATA_V2  Load experiment pairing CSV via file dialog.
%
%  Prompts the user to select a Metadata_wmice_*.csv file that pairs each
%  acoustic sensor CSV with its corresponding side-camera video and stores
%  test conditions (set voltage, set frequency, video time window).
%
%  Columns are read by name so the CSV is robust to column reordering.
%  Missing optional columns are filled with safe defaults.
%
%  Blank vid_t_start_s / vid_t_end_s cells are replaced with 0, which
%  instructs the main loop to use the full video record.
%
%  OUTPUT
%    pairMeta — table with columns:
%      Acoustic_sensor_filename  — string, CSV filename (no path)
%      Video_filename            — string, video filename (no path)
%      Set_volt_V                — set paddle voltage [V]
%      Set_f_Hz                  — set wave frequency [Hz]
%      Mode                      — acquisition mode 'HIGH' | 'LOW'
%      vid_t_start_s             — video analysis start time [s] (0 = from start)
%      vid_t_end_s               — video analysis end time   [s] (0 = to end)
%      wave_time_series_sidecam  — path to pre-processed camera time-series CSV
%      Camera_loc_m              — camera x-position [m] (filled later in Section 2b)

    [f, p] = uigetfile('*.csv', ...
        '[STEP 3/4] Select Experiment Pairing CSV (Metadata_wmice_*.csv)');
    if isequal(f, 0); error('No pairing CSV selected.'); end

    raw  = readtable(fullfile(p, f), 'VariableNamingRule', 'preserve');
    vars = raw.Properties.VariableNames;
    fprintf('Pairing CSV columns: %s\n', strjoin(vars, ', '));

    pairMeta = table();

    % Required string columns
    pairMeta.Acoustic_sensor_filename = string(strtrim(string(raw.Acoustic_sensor_filename)));
    pairMeta.Video_filename           = string(strtrim(string(raw.Video_filename)));

    % Numeric test condition columns — default to NaN if absent
    pairMeta.Set_volt_V = get_num(raw, vars, 'Set_volt_V', NaN);
    pairMeta.Set_f_Hz   = get_num(raw, vars, 'Set_f_Hz',   NaN);

    % Acquisition mode string
    pairMeta.Mode = get_str(raw, vars, 'Mode', 'HIGH');

    % Video time window: replace non-finite (blank) values with 0
    ts = get_num(raw, vars, 'vid_t_start_s', 0);
    ts(~isfinite(ts)) = 0;
    pairMeta.vid_t_start_s = ts;

    te = get_num(raw, vars, 'vid_t_end_s', 0);
    te(~isfinite(te)) = 0;
    pairMeta.vid_t_end_s = te;

    % Optional pre-processed camera time-series path (blank = not available)
    pairMeta.wave_time_series_sidecam = get_str(raw, vars, 'wave_time_series_sidecam', '');

    % Camera position is derived later in Section 2b
    pairMeta.Camera_loc_m = NaN(height(raw), 1);

    fprintf('Pairing metadata loaded: %d rows.\n', height(pairMeta));

    % ------------------------------------------------------------------
    %  Local helpers — read a column by name with a fallback default
    % ------------------------------------------------------------------
    function v = get_num(raw, vars, col, def)
        if ismember(col, vars)
            v = double(raw.(col));
        else
            v = repmat(def, height(raw), 1);
            fprintf('  [INFO] Column "%s" not found — default %.4g\n', col, def);
        end
    end

    function v = get_str(raw, vars, col, def)
        if ismember(col, vars)
            v = string(strtrim(string(raw.(col))));
        else
            v = repmat(string(def), height(raw), 1);
            fprintf('  [INFO] Column "%s" not found — default "%s"\n', col, def);
        end
    end

end