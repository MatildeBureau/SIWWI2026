function [surf_out, n_spikes] = wm_cam_despike(surf_m, Fs, win_s, thresh, mode_str)
% WM_CAM_DESPIKE  Removes spike outliers from a camera-derived surface time series.
%
%  Computes a moving-median baseline over a sliding window, then identifies
%  frames where the signal deviates from that baseline by more than a
%  threshold.  Detected spikes are replaced by the local median value.
%
%  Two thresholding modes are supported:
%
%    'absolute' — rejects frames where |signal - median| > thresh [m].
%                 Simple and interpretable; threshold is in physical units.
%                 Use when the noise floor is known and stable.
%
%    'mad'      — rejects frames where |signal - median| > thresh * MAD,
%                 where MAD is the local Median Absolute Deviation.
%                 Automatically adapts to local signal variability, making
%                 it more robust to sections with higher wave activity.
%
%  INPUTS
%    surf_m    — surface position time series [m], column or row vector
%    Fs        — camera frame rate [fps]
%    win_s     — sliding window half-width [s]; window length = round(Fs * win_s)
%    thresh    — threshold value:
%                  'absolute' mode: threshold in metres [m]
%                  'mad'      mode: number of MADs above which a point is a spike
%    mode_str  — 'absolute' or 'mad'
%
%  OUTPUTS
%    surf_out  — despiked time series (spike locations replaced by local median)
%    n_spikes  — number of frames replaced

    % Convert window from seconds to samples (minimum 3 samples)
    win_samples = max(3, round(Fs * win_s));

    % Local median baseline used for both deviation computation and replacement
    med_sig = movmedian(surf_m, win_samples, 'omitnan');

    switch lower(mode_str)

        case 'mad'
            % Dynamic threshold: flag points more than thresh*MAD from median.
            % movmad computes the local Median Absolute Deviation.
            mad_sig = movmad(surf_m, win_samples);
            % Prevent division by zero in flat regions (unlikely to have spikes)
            mad_sig(mad_sig < eps) = median(mad_sig(mad_sig > eps) + eps);
            spike_mask = ~isnan(surf_m) & ...
                         (abs(surf_m - med_sig) > thresh * mad_sig);

        case 'absolute'
            % Fixed threshold: flag points deviating more than thresh [m]
            spike_mask = ~isnan(surf_m) & (abs(surf_m - med_sig) > thresh);

        otherwise
            error('Unknown despike mode: "%s". Use ''mad'' or ''absolute''.', mode_str);
    end

    n_spikes = sum(spike_mask);
    surf_out = surf_m;

    if n_spikes > 0
        % Replace spike samples with the local median value
        surf_out(spike_mask) = med_sig(spike_mask);
        fprintf('  [CAM DESPIKE] %d frames replaced (mode: %s, thresh: %.4f)\n', ...
            n_spikes, mode_str, thresh);
    end

end