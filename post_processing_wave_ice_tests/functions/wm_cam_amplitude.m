function [A_cam, delta_A] = wm_cam_amplitude(sig_cam, Fs_cam, fmeas_cam, mm_per_px, mean_pos_unc_m)
% WM_CAM_AMPLITUDE  Estimates wave amplitude from a camera surface time series.
%
%  Detects crests and troughs in the signal and computes:
%    A_cam = (mean(crests) - mean(troughs)) / 2
%
%  The uncertainty delta_A combines three independent sources in quadrature:
%    1. Statistical spread of crest heights:   SE_crest  = std(crests) / sqrt(N_c)
%    2. Statistical spread of trough depths:   SE_trough = std(troughs) / sqrt(N_t)
%    3. Physical position uncertainty:         sigma_pos  from HWHM of gradient peak
%       Propagated through A = (crest - trough)/2 as sigma_pos / sqrt(2)
%       (crest and trough position errors are independent, so they add in quadrature
%       under the factor of 1/2: 0.5 * sqrt(sigma^2 + sigma^2) = sigma / sqrt(2))
%
%  Combined:
%    delta_A = sqrt( (SE_crest/2)^2 + (SE_trough/2)^2 + (sigma_pos/sqrt(2))^2 )
%    floored at sigma_pos so the reported uncertainty is never smaller than
%    the physical detection limit.
%
%  INPUTS
%    sig_cam        — surface position time series [m]
%    Fs_cam         — camera frame rate [fps]
%    fmeas_cam      — measured wave frequency [Hz], used to set minimum peak separation
%    mm_per_px      — calibration factor [mm/px], used to compute the fallback
%                     noise floor (0.2 px) when mean_pos_unc_m is not supplied
%    mean_pos_unc_m — (optional) mean per-frame HWHM position uncertainty [m]
%                     from pick_best_peak / wm_get_surface_v4.
%                     If omitted or empty, falls back to 0.2 px * mm_per_px.
%
%  OUTPUTS
%    A_cam   — wave amplitude [m]
%    delta_A — combined uncertainty [m]

    % Minimum crest-to-crest or trough-to-trough separation [samples]
    min_sep = max(1, round(0.5 * Fs_cam / fmeas_cam));

    % ----------------------------------------------------------------
    %  Detect crests and troughs
    %  Use findpeaks with a minimum distance guard.  Fall back to
    %  derivative sign-change detection if findpeaks is unavailable.
    % ----------------------------------------------------------------
    try
        [crest_vals, ~]  = findpeaks( sig_cam, 'MinPeakDistance', min_sep);
        [trough_vals, ~] = findpeaks(-sig_cam, 'MinPeakDistance', min_sep);
        trough_vals = -trough_vals;
    catch
        d = diff(sig_cam);
        crest_idx   = find(d(1:end-1) > 0 & d(2:end) < 0) + 1;
        trough_idx  = find(d(1:end-1) < 0 & d(2:end) > 0) + 1;
        crest_vals  = sig_cam(crest_idx);
        trough_vals = sig_cam(trough_idx);
    end

    % ----------------------------------------------------------------
    %  Position uncertainty — use supplied value or fallback to 0.2 px
    % ----------------------------------------------------------------
    if nargin >= 5 && ~isempty(mean_pos_unc_m) && isfinite(mean_pos_unc_m)
        sigma_pos = mean_pos_unc_m;   % physically motivated from HWHM
    else
        sigma_pos = (0.2 * mm_per_px) / 1000;   % 0.2 px fallback
    end

    N_c = length(crest_vals);
    N_t = length(trough_vals);

    if N_c < 1 || N_t < 1
        fprintf('  [CAM AMP] No crests/troughs found — returning NaN\n');
        A_cam   = NaN;
        delta_A = sigma_pos;
        return;
    end

    mean_crest  = mean(crest_vals);
    mean_trough = mean(trough_vals);
    A_cam       = (mean_crest - mean_trough) / 2;

    % Statistical spread of crest and trough levels
    SE_crest  = (N_c >= 2) * std(crest_vals)  / sqrt(max(N_c, 2));
    SE_trough = (N_t >= 2) * std(trough_vals) / sqrt(max(N_t, 2));

    % Propagate position uncertainty: A = (c - t)/2, so each position
    % uncertainty contributes sigma_pos/sqrt(2) to the amplitude error
    delta_A_pos = sigma_pos / sqrt(2);

    % Combine all three sources in quadrature; floor at sigma_pos
    delta_A = max( ...
        sqrt((SE_crest/2)^2 + (SE_trough/2)^2 + delta_A_pos^2), ...
        sigma_pos);

    fprintf('  [CAM AMP] N_c=%d N_t=%d  A_cam=%.5f m  delta_A=%.5f m\n', ...
        N_c, N_t, A_cam, delta_A);

end