function [fmeas_fft, f_vec, P1] = wm_fft_frequency(sig, Fs_t, fSet, freqTol)
% WM_FFT_FREQUENCY  Identifies the dominant wave frequency via single-sided FFT.
%
%  Computes the single-sided amplitude spectrum of the input signal and
%  finds the peak within a tolerance band around the set frequency fSet.
%  If no FFT bins fall within the band, the global spectral peak is used
%  instead (with a warning).
%
%  INPUTS:
%    sig     — signal vector (already filtered / windowed as desired)
%    Fs_t    — actual sampling frequency [Hz]
%    fSet    — set (expected) wave frequency [Hz]
%    freqTol — fractional tolerance for peak search (e.g. 0.10 = ±10%)
%
%  OUTPUTS:
%    fmeas_fft — measured peak frequency [Hz]
%    f_vec     — frequency axis of the single-sided spectrum [Hz]
%    P1        — single-sided amplitude spectrum

    N     = length(sig);
    X     = fft(sig);
    P2    = abs(X / N);
    P1    = P2(1:floor(N/2) + 1);
    P1(2:end-1) = 2 * P1(2:end-1);   % correct for one-sided representation
    f_vec = Fs_t * (0:floor(N/2)) / N;

    % Search band around the set frequency
    band = (f_vec >= fSet * (1 - freqTol)) & (f_vec <= fSet * (1 + freqTol));

    if any(band)
        Ps = P1;
        Ps(~band) = 0;
        [~, mi] = max(Ps);
    else
        % Fallback: global peak (skip DC bin at index 1)
        [~, mi] = max(P1(2:end));
        mi = mi + 1;
        fprintf('  [WARN] No FFT bins in tolerance band — global spectral peak used\n');
    end

    fmeas_fft = f_vec(mi);
    fprintf('  FFT: f_meas = %.4f Hz\n', fmeas_fft);
end