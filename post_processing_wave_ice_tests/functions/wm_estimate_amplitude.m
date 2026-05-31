function [ameas, env, delta_A] = wm_estimate_amplitude(sig, method, fmeas_fft, Fs, env_smooth_periods)
% WM_ESTIMATE_AMPLITUDE  Estimate wave amplitudes from a filtered signal.
%
%  Two methods are available:
%
%  'rms'      — RMS amplitude: A = sqrt(2) * std(sig)
%               Exact for a pure sinusoid. Uncertainty = std / sqrt(N-1).
%
%  'envelope' — Hilbert envelope: A = mean of smoothed |hilbert(sig)|
%               The envelope is smoothed with a moving average over
%               env_smooth_periods wave periods to reduce ripple.
%               Uncertainty = std(env) / sqrt(N_eff), where N_eff is
%               the number of independent smoothing windows.
%
%  INPUTS:
%    sig                — filtered signal vector [m]
%    method             — 'rms' | 'envelope'
%    fmeas_fft          — measured wave frequency [Hz] (used for smoothing window)
%    Fs                 — sampling frequency [Hz]
%    env_smooth_periods — envelope smoothing window length [wave periods]
%
%  OUTPUTS:
%    ameas   — estimated wave amplitude [m]
%    env     — smoothed Hilbert envelope ([] for RMS method)
%    delta_A — amplitude uncertainty [m]

    env = [];

    switch lower(method)
        case 'rms'
            s       = std(sig);
            ameas   = sqrt(2) * s;
            delta_A = s / sqrt(length(sig) - 1);
            fprintf('  RMS amp: %.5f m  (unc: %.5f m)\n', ameas, delta_A);

        case 'envelope'
            env_raw    = abs(hilbert(sig));
            smooth_win = max(1, round(env_smooth_periods * Fs / fmeas_fft));
            env        = movmean(env_raw, smooth_win);
            ameas      = mean(env);
            N_eff      = max(1, floor(length(env) / smooth_win));
            delta_A    = std(env) / sqrt(N_eff);
            fprintf('  Env amp: %.5f m  (unc: %.5f m,  N_eff=%d)\n', ameas, delta_A, N_eff);

        otherwise
            error('Unknown amplitudeMethod: "%s". Use ''rms'' or ''envelope''.', method);
    end
end


