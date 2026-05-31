function [t, rawMat, Fs_t, ok] = wm_read_signal(fullPath, Fs)
% WM_READ_SIGNAL  Reads a raw acoustic sensor CSV file.
%
%  The CSV is expected to have:
%    Column 1 — time vector [s]
%    Columns 2+ — raw voltage signal(s) [V]
%
%  INPUTS:
%    fullPath — full path to the CSV file
%    Fs       — expected sampling frequency [Hz] (from filename parsing)
%
%  OUTPUTS:
%    t      — time vector [s]
%    rawMat — matrix of raw voltage signals (one column per channel)
%    Fs_t   — actual sampling frequency computed from time vector [Hz]
%    ok     — true if read succeeded, false on error

    ok = true;
    try
        data = readtable(fullPath, 'VariableNamingRule', 'preserve');
    catch ME
        fprintf('  [ERROR reading file] %s\n', ME.message);
        t = []; rawMat = []; Fs_t = NaN; ok = false;
        return;
    end

    t      = data{:, 1};
    rawMat = data{:, 2:end};
    Fs_t   = 1 / mean(diff(t));
end