function wm_plot_fft_debug(f_vec, P1, fmeas_fft, fSet, freqTol, fileName, ...
        filterEnable, filterMode, bp_frac)
% WM_PLOT_FFT_DEBUG   FFT amplitude spectrum plot with harmonic annotation.
%
%  Produces a single figure showing the single-sided amplitude spectrum with:
%    — Grey shaded tolerance band [±freqTol] around the set frequency
%    — Magenta dashed lines for bandpass filter cutoffs (when active)
%    — Black dashed vertical: set frequency fSet
%    — Red solid vertical:    detected peak frequency fmeas_fft
%    — Blue curve:            amplitude spectrum P1 (drawn last, on top)
%    — Red dot:               peak amplitude at fmeas_fft
%    — Coloured triangles:    detected harmonics (2f, 3f, 4f) with
%                             relative amplitude labels in percent
%
%  DRAW ORDER
%  Background patches and vertical lines are drawn first so the blue
%  spectrum curve and markers always sit on top and remain readable.
%
%  HARMONIC ANNOTATION
%  For h = 2, 3, 4: searches a ±freqTol band around h * fmeas_fft.
%  If a peak is found above 1% of the fundamental amplitude, a coloured
%  triangle marker and a percentage label are added.  Only the first
%  detected harmonic receives a legend entry to keep the legend uncluttered.
%
%  INPUTS
%    f_vec        — frequency vector [Hz]
%    P1           — single-sided amplitude spectrum [m or a.u.]
%    fmeas_fft    — detected fundamental frequency [Hz]
%    fSet         — set (target) wave frequency [Hz]
%    freqTol      — fractional search tolerance, e.g. 0.10 = ±10%
%    fileName     — string, used in figure title
%    filterEnable — logical, true if bandpass filtering was applied
%    filterMode   — string: 'bandpass' | 'lowpass'
%    bp_frac      — bandpass half-bandwidth fraction, e.g. 0.90

    fSpec = figure('Name', sprintf('FFT Spectrum DEBUG: %s', fileName));
    ax    = axes(fSpec);
    hold(ax, 'on');
    grid(ax, 'on');

    % Y-axis range — 25% headroom for text annotations
    ylims = [0, max(P1) * 1.25];

    % ----------------------------------------------------------------
    %  1. Grey search-tolerance band (drawn first — behind everything)
    %     This is the ±freqTol window around fSet in which the peak search
    %     is performed to find fmeas_fft.
    % ----------------------------------------------------------------
    f_lo_tol = fSet * (1 - freqTol);
    f_hi_tol = fSet * (1 + freqTol);

    patch(ax, ...
        [f_lo_tol f_hi_tol f_hi_tol f_lo_tol], ...
        [ylims(1)  ylims(1)  ylims(2)  ylims(2)], ...
        [0.85 0.85 0.85], ...
        'FaceAlpha', 0.40, ...
        'EdgeColor', 'none', ...
        'DisplayName', sprintf('Search band +/- %.0f%%', freqTol * 100));

    % ----------------------------------------------------------------
    %  2. Bandpass filter cutoff lines (magenta dashed)
    %     Label strings are built with sprintf separately — xline()
    %     does not accept 'Interpreter' as a trailing argument.
    % ----------------------------------------------------------------
    if filterEnable && strcmpi(filterMode, 'bandpass')
        fc_hp = fmeas_fft * (1 - bp_frac);
        fc_lp = fmeas_fft * (1 + bp_frac);

        label_hp = sprintf('BP low cut (%.1f%%, %.3f Hz)',  bp_frac * 100, fc_hp);
        label_lp = sprintf('BP high cut (%.1f%%, %.3f Hz)', bp_frac * 100, fc_lp);

        xline(ax, fc_hp, 'm--', 'LineWidth', 0.8, 'DisplayName', label_hp);
        xline(ax, fc_lp, 'm--', 'LineWidth', 0.8, 'DisplayName', label_lp);
    end

    % ----------------------------------------------------------------
    %  3. Set-frequency vertical line (black dashed)
    % ----------------------------------------------------------------
    label_fset = sprintf('f_set = %.4f Hz', fSet);
    xline(ax, fSet, 'k--', 'LineWidth', 0.8, 'DisplayName', label_fset);

    % ----------------------------------------------------------------
    %  4. Measured frequency vertical line (red solid)
    % ----------------------------------------------------------------
    label_fmeas = sprintf('f_meas = %.4f Hz', fmeas_fft);
    xline(ax, fmeas_fft, 'r-', 'LineWidth', 0.8, 'DisplayName', label_fmeas);

    % ----------------------------------------------------------------
    %  5. Amplitude spectrum — drawn LAST so it sits on top of all lines
    % ----------------------------------------------------------------
    plot(ax, f_vec, P1, ...
        'Color',     [0.00 0.35 0.75], ...
        'LineWidth', 2.0, ...
        'DisplayName', 'Amplitude spectrum');

    % ----------------------------------------------------------------
    %  6. Red filled circle on the detected fundamental peak
    % ----------------------------------------------------------------
    in_band   = (f_vec(:) >= f_lo_tol) & (f_vec(:) <= f_hi_tol);
    P1_col    = P1(:);
    [peak_amp, ~] = max(P1_col .* in_band);

    if peak_amp > 0
        scatter(ax, fmeas_fft, peak_amp, 80, 'r', 'filled', ...
            'HandleVisibility', 'off');
    end

    % ----------------------------------------------------------------
    %  7. Harmonic annotation (2f, 3f, 4f)
    %
    %  For each harmonic h = 2, 3, 4:
    %    — Search ±freqTol around h * fmeas_fft
    %    — If peak amplitude > 1% of fundamental, plot a coloured triangle
    %      and annotate with "Hh: XX.X%"
    %  Only the first detected harmonic receives a legend entry.
    % ----------------------------------------------------------------
    harmonic_colors = [ ...
        0.85 0.45 0.00;   % 2f — dark orange
        0.10 0.60 0.10;   % 3f — dark green
        0.55 0.00 0.75];  % 4f — purple

    noise_floor = peak_amp * 0.01;   % 1% of fundamental amplitude
    first_harmonic_in_legend = false;

    for h = [2 3 4]
        target_f = fmeas_fft * h;

        band_lo   = target_f * (1 - freqTol);
        band_hi   = target_f * (1 + freqTol);
        band_mask = (f_vec >= band_lo) & (f_vec <= band_hi);

        if ~any(band_mask); continue; end

        [h_amp, li] = max(P1_col(band_mask));
        if h_amp < noise_floor; continue; end

        band_idx = find(band_mask);
        h_freq   = f_vec(band_idx(li));
        rel_pct  = (h_amp / peak_amp) * 100;
        hColor   = harmonic_colors(h - 1, :);

        if ~first_harmonic_in_legend
            scatter(ax, h_freq, h_amp, 90, hColor, '^', 'filled', ...
                'DisplayName', 'Harmonics (detected)');
            first_harmonic_in_legend = true;
        else
            scatter(ax, h_freq, h_amp, 90, hColor, '^', 'filled', ...
                'HandleVisibility', 'off');
        end

        text(ax, h_freq, h_amp + 0.03 * ylims(2), ...
            sprintf('%df: %.1f%%', h, rel_pct), ...
            'Color',               hColor, ...
            'FontSize',            8, ...
            'FontWeight',          'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'bottom', ...
            'Clipping',            'on');
    end

    % ----------------------------------------------------------------
    %  Axes formatting
    %  x-axis extends to 5x the set frequency so harmonics are visible.
    %  Legend Interpreter='none' prevents underscores in filenames from
    %  being interpreted as subscript commands.
    % ----------------------------------------------------------------
    ylim(ax, ylims);
    xlim(ax, [0, min(max(f_vec), 5 * fSet)]);

    legend(ax, 'show', ...
        'Location',    'northeast', ...
        'FontSize',    9, ...
        'Interpreter', 'none');

    xlabel(ax, 'f (Hz)',          'Interpreter', 'none', 'FontSize', 11);
    ylabel(ax, 'Amplitude (a.u)', 'Interpreter', 'none', 'FontSize', 11);
    title(ax,  sprintf('FFT Spectrum -- %s', fileName), ...
        'Interpreter', 'none', 'FontSize', 10);

end