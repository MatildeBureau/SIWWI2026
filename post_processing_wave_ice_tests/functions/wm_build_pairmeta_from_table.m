function pairMeta = wm_build_pairmeta_from_table(raw)
% WM_BUILD_PAIRMETA_FROM_TABLE  Build working pairMeta table from a raw readtable result.
%
%  Reads all columns by name so the function is robust to CSV column reordering.
%  Missing optional columns are filled with safe defaults and a console message
%  is printed.  Blank vid_t_start_s / vid_t_end_s cells are set to 0 (meaning
%  "use the full record" in the main loop).
%
%  The Acoustic_sensor_filename column has its .csv extension stripped if
%  present, ensuring consistent matching regardless of whether the CSV was
%  written with or without the extension.
%
%  INPUT
%    raw — table returned by readtable() on a Metadata_wmice_*.csv file
%
%  OUTPUT
%    pairMeta — table with columns:
%      Acoustic_sensor_filename  — string, base filename without .csv
%      Video_filename            — string
%      Set_volt_V                — set paddle voltage [V]
%      Set_f_Hz                  — set wave frequency [Hz]
%      Mode                      — 'HIGH' | 'LOW'
%      T_degC                    — water temperature [°C]
%      vid_t_start_s             — video analysis start [s]  (0 = from start)
%      vid_t_end_s               — video analysis end   [s]  (0 = to end)
%      wave_time_series_sidecam  — path to pre-processed camera time-series CSV
%      Camera_loc_m              — camera x-position [m]  (filled later in Section 2b)

    vars = raw.Properties.VariableNames;

    % Validate that the two required columns are present
    for k = 1:2
        req = {'Acoustic_sensor_filename', 'Video_filename'};
        if ~ismember(req{k}, vars)
            error('Pairing CSV missing required column: "%s".', req{k});
        end
    end

    pairMeta = table();

    % Strip trailing .csv from acoustic filenames so matching is consistent
    pairMeta.Acoustic_sensor_filename = ...
        string(strtrim(regexprep(string(raw.Acoustic_sensor_filename), '\.csv$', '')));
    pairMeta.Video_filename = ...
        string(strtrim(string(raw.Video_filename)));

    % Numeric test condition columns
    pairMeta.Set_volt_V = gc_dbl(raw, vars, 'Set_volt_V', NaN);
    pairMeta.Set_f_Hz   = gc_dbl(raw, vars, 'Set_f_Hz',   NaN);
    pairMeta.T_degC     = gc_dbl(raw, vars, 'T_degC',     NaN);

    % Acquisition mode string
    pairMeta.Mode = gc_str(raw, vars, 'Mode', 'HIGH');

    % Video time window: replace non-finite (blank cell) values with 0
    ts = gc_dbl(raw, vars, 'vid_t_start_s', 0);
    ts(~isfinite(ts)) = 0;
    pairMeta.vid_t_start_s = ts;

    te = gc_dbl(raw, vars, 'vid_t_end_s', 0);
    te(~isfinite(te)) = 0;
    pairMeta.vid_t_end_s = te;

    % Optional camera time-series path
    pairMeta.wave_time_series_sidecam = ...
        gc_str(raw, vars, 'wave_time_series_sidecam', '');

    % Camera position is filled later in Section 2b
    pairMeta.Camera_loc_m = NaN(height(raw), 1);

    fprintf('Pairing metadata built: %d rows.\n', height(pairMeta));

end


% ======================================================================
%  LOCAL HELPERS — read a column by name with a fallback default value
% ======================================================================

function v = gc_dbl(raw, vars, col, def)
% Read a numeric column; return a column of def if column is absent.
    if ismember(col, vars)
        v = double(raw.(col));
    else
        v = repmat(def, height(raw), 1);
        fprintf('  [INFO] Column "%s" missing — default %.4g\n', col, def);
    end
end

function v = gc_str(raw, vars, col, def)
% Read a string column; return a column of def if column is absent.
    if ismember(col, vars)
        v = string(strtrim(string(raw.(col))));
    else
        v = repmat(string(def), height(raw), 1);
        fprintf('  [INFO] Column "%s" missing — default "%s"\n', col, def);
    end
end