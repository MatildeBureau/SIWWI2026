function [sig_out, n_spikes] = wm_despike_v2(sig_in, Fs, win_s, thresh, mode_str)
% WM_DESPIKE_V2  Removes spikes from a signal using a rolling window detector.
%
%  Two detection modes are supported:
%
%  'mad'      — MAD (Median Absolute Deviation) based detection.
%               A sample is flagged as a spike if:
%                 |sig - local_median| > thresh * local_MAD
%               thresh is typically 3–5 × MAD.
%
%  'absolute' — Absolute threshold detection.
%               A sample is flagged if |sig| > thresh [m].
%
%  Detected spikes are replaced by the local rolling median.
%
%  INPUTS:
%    sig_in   — input signal vector [m or V]
%    Fs       — sampling frequency [Hz]
%    win_s    — rolling window length [s]
%    thresh   — detection threshold (× MAD for 'mad', [m] for 'absolute')
%    mode_str — 'mad' | 'absolute'
%
%  OUTPUTS:
%    sig_out  — despiked signal (spikes replaced by local median)
%    n_spikes — number of samples replaced

    win_des = max(3, round(Fs * win_s));
    med_sig = movmedian(sig_in, win_des);

    switch lower(mode_str)
        case 'mad'
            mad_sig = movmad(sig_in, win_des);
            % Avoid division by zero in flat regions
            mad_sig(mad_sig < eps) = median(mad_sig(mad_sig > eps) + eps);
            spike_mask = abs(sig_in - med_sig) > thresh * mad_sig;

        case 'absolute'
            spike_mask = abs(sig_in) > thresh;

        otherwise
            error('Unknown despike_mode: "%s". Use ''mad'' or ''absolute''.', mode_str);
    end

    n_spikes = sum(spike_mask);
    sig_out  = sig_in;

    if n_spikes > 0
        sig_out(spike_mask) = med_sig(spike_mask);
        fprintf('  [DESPIKE-%s] %d samples replaced (%.1f%%)\n', ...
            upper(mode_str), n_spikes, 100 * n_spikes / length(sig_in));
    end
end