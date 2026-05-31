function [sig_cal, ok] = wm_apply_calibration(rawSig, calData, sensorID, fMode)
% WM_APPLY_CALIBRATION  Converts raw voltage signal to metres using sensor calibration.
%
%  Looks up the calibration row matching sensorID and fMode in calData,
%  applies the linear conversion:
%      sig_cal = rawSig * Slope_a + Intercept_b
%  then removes the mean.
%
%  INPUTS:
%    rawSig   — raw voltage signal vector [V]
%    calData  — calibration table (from wm_load_calibration)
%               must have columns: Source, Mode, Slope_a, Intercept_b
%    sensorID — integer sensor ID
%    fMode    — mode string: 'HIGH' | 'LOW'
%
%  OUTPUTS:
%    sig_cal — calibrated, de-meaned signal [m]
%    ok      — true if calibration row found, false otherwise

    calName = sprintf('Sensor%d', sensorID);
    calRow  = find(strcmp(string(calData.Source), calName) & ...
                   strcmp(upper(string(calData.Mode)), char(fMode)), 1);

    if isempty(calRow)
        fprintf('  [SKIP] No calibration found for %s [%s]\n', calName, fMode);
        sig_cal = [];
        ok      = false;
        return;
    end

    ok      = true;
    sig_cal = rawSig * calData.Slope_a(calRow) + calData.Intercept_b(calRow);
    sig_cal = sig_cal - mean(sig_cal);   % remove DC offset / mean water level
end