function sig_out = wm_filter_signal_v2(sig_in, Fs, mode, fc_lp, fmeas_fft, bp_frac, bp_order, fileName)
% WM_FILTER_SIGNAL_V2  Applies low-pass or bandpass Butterworth filter to a signal.
%
%  Two modes are available:
%
%  'lowpass'  — Single low-pass filter at cutoff fc_lp [Hz].
%               fc_lp must be > fmeas_fft (the wave frequency).
%               A warning is printed if fc_lp < 1.2 * fmeas_fft.
%
%  'bandpass' — Zero-phase bandpass filter built as separate high-pass
%               and low-pass stages.
%               Passband: fmeas_fft * [1-bp_frac, 1+bp_frac]
%               Both stages use forward-backward (zero-phase) filtering
%               via sosfilt applied twice (flip-filter-flip).
%               If the output contains NaN/Inf, falls back to input signal.
%
%  INPUTS:
%    sig_in    — input signal vector
%    Fs        — sampling frequency [Hz]
%    mode      — 'lowpass' | 'bandpass'
%    fc_lp     — low-pass cutoff [Hz]  (lowpass mode only)
%    fmeas_fft — measured wave frequency [Hz]  (used for bandpass centre)
%    bp_frac   — fractional half-bandwidth for bandpass (e.g. 0.8 = ±80%)
%    bp_order  — Butterworth filter order per stage
%    fileName  — filename string (used in warning/error messages only)
%
%  OUTPUT:
%    sig_out — filtered signal vector

    switch lower(mode)

        case 'lowpass'
            if fc_lp <= fmeas_fft
                error(['LP cutoff fc=%.3fHz <= fmeas=%.4fHz for:\n  %s\n' ...
                       'Increase fc_lp in Section 1c.'], fc_lp, fmeas_fft, fileName);
            end
            if fc_lp < 1.2 * fmeas_fft
                fprintf('  [WARN] fc_lp (%.3fHz) < 1.2 x fmeas (%.4fHz)\n', fc_lp, fmeas_fft);
            end
            [b, a]  = butter(4, fc_lp / (Fs / 2));
            sig_out = filtfilt(b, a, sig_in);
            fprintf('  FILTER: lowpass at %.3f Hz\n', fc_lp);

        case 'bandpass'
            fc_hp    = fmeas_fft * (1 - bp_frac);
            fc_lp_bp = fmeas_fft * (1 + bp_frac);
            fc_hp    = max(fc_hp,    0.001);
            fc_lp_bp = min(fc_lp_bp, Fs/2 * 0.99);
            nyq      = Fs / 2;

            % High-pass stage (zero-phase via forward-backward sosfilt)
            Wn_hp      = max(fc_hp / nyq, 1e-4);
            [z1,p1,k1] = butter(bp_order, Wn_hp, 'high');
            sos1       = zp2sos(z1, p1, k1);
            tmp        = sosfilt(sos1, sig_in);
            tmp        = sosfilt(sos1, tmp(end:-1:1));
            tmp        = tmp(end:-1:1);

            % Low-pass stage (zero-phase via forward-backward sosfilt)
            Wn_lp      = min(fc_lp_bp / nyq, 0.9999);
            [z2,p2,k2] = butter(bp_order, Wn_lp, 'low');
            sos2       = zp2sos(z2, p2, k2);
            sig_out    = sosfilt(sos2, tmp);
            sig_out    = sosfilt(sos2, sig_out(end:-1:1));
            sig_out    = sig_out(end:-1:1);

            if any(~isfinite(sig_out))
                fprintf('  [WARN] Bandpass output NaN/Inf — falling back to de-meaned input\n');
                sig_out = sig_in;
            end
            fprintf('  FILTER: bandpass [%.3f, %.3f] Hz\n', fc_hp, fc_lp_bp);

        otherwise
            error('Unknown filterMode: "%s". Use ''lowpass'' or ''bandpass''.', mode);
    end
end