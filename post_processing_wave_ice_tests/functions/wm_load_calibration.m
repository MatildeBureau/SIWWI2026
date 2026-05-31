function calData = wm_load_calibration()
% WM_LOAD_CALIBRATION  Loads acoustic sensor calibration table from CSV.
%
%  Prompts the user to select a CSV file containing V->m calibration
%  coefficients for each sensor and mode (LOW / HIGH).
%
%  Expected columns (read by wm_apply_calibration):
%    Source     — sensor name string, e.g. 'Sensor1'
%    Mode       — 'LOW' or 'HIGH'
%    Slope_a    — multiplicative calibration coefficient
%    Intercept_b— additive calibration offset
%
%  OUTPUT:
%    calData — raw table as read from CSV

    [f, p] = uigetfile('*.csv', 'Select Calibration CSV');
    if isequal(f, 0); error('No calibration CSV selected.'); end

    calData = readtable(fullfile(p, f), 'VariableNamingRule', 'preserve');
    fprintf('Calibration rows loaded: %d\n', height(calData));
end