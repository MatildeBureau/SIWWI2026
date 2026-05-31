function locExpanded = wm_load_location_metadata()
% WM_LOAD_LOCATION_METADATA  Load sensor placement CSV via file dialog.
%
%  Prompts the user to select a sensor placement CSV (e.g.
%  Metadata_sensors_DDMMYY.csv) and returns a table describing the physical
%  position and DAQ channel of each sensor, plus optional camera assignments.
%
%  EXPECTED COLUMN ORDER (by position, not by name):
%    Col 1 — Sensor number (integer)
%    Col 2 — DAQ channel  (integer)
%    Col 3 — x-position   [m]
%    Col 4 — Camera name  (string, blank = no camera)   [optional]
%    Col 5 — Date         (string DDMMYY, for per-day reassignment) [optional]
%
%  Numeric columns are extracted safely whether readtable returns them as
%  double arrays or as string/cell arrays (common with mixed/blank fields).
%
%  OUTPUT
%    locExpanded — table with columns:
%      SensorID  — sensor number
%      Channel   — DAQ channel
%      x_m       — along-tank position [m]
%      Camera    — camera name string  ("" if none)
%      Date      — date string         ("" if column absent)
%      HasCamera — logical flag, true when Camera is non-empty

    [f, p] = uigetfile('*.csv', ...
        '[STEP 1/4] Select Sensor Placement CSV (e.g. Metadata_sensors_DDMMYY.csv)');
    if isequal(f, 0); error('No sensor placement CSV selected.'); end

    % Read with preserved column names; TextType string avoids cell arrays
    raw  = readtable(fullfile(p, f), ...
        'VariableNamingRule', 'preserve', ...
        'TextType',           'string');
    vars = raw.Properties.VariableNames;

    if length(vars) < 3
        error('Sensor placement CSV must have at least 3 columns: Sensor, Channel, x_m.');
    end

    % ------------------------------------------------------------------
    %  Safe numeric extraction — handles both double and string columns
    % ------------------------------------------------------------------
    function v = to_num(col)
        if isnumeric(col)
            v = double(col);
        else
            v = str2double(string(col));
        end
    end

    locExpanded          = table();
    locExpanded.SensorID = to_num(raw.(vars{1}));
    locExpanded.Channel  = to_num(raw.(vars{2}));
    locExpanded.x_m      = to_num(raw.(vars{3}));

    % Camera name (column 4, optional)
    if length(vars) >= 4
        locExpanded.Camera = strtrim(string(raw.(vars{4})));
    else
        locExpanded.Camera = repmat("", height(raw), 1);
    end

    % Date (column 5, optional — enables per-day channel reassignment)
    if length(vars) >= 5
        locExpanded.Date = strtrim(string(raw.(vars{5})));
    else
        locExpanded.Date = repmat("", height(raw), 1);
    end

    % Convenience flag
    locExpanded.HasCamera = strlength(locExpanded.Camera) > 0;

    % Warn if any numeric columns contain NaN (indicates parsing failure)
    if any(isnan(locExpanded.SensorID))
        warning('wm_load_location_metadata: %d NaN(s) in SensorID column.', ...
            sum(isnan(locExpanded.SensorID)));
    end
    if any(isnan(locExpanded.Channel))
        warning('wm_load_location_metadata: %d NaN(s) in Channel column.', ...
            sum(isnan(locExpanded.Channel)));
    end
    if any(isnan(locExpanded.x_m))
        warning('wm_load_location_metadata: %d NaN(s) in x_m column.', ...
            sum(isnan(locExpanded.x_m)));
    end

    fprintf('Sensor placement loaded: %d sensors, %d with cameras.\n', ...
        height(locExpanded), sum(locExpanded.HasCamera));
    disp(locExpanded);

end