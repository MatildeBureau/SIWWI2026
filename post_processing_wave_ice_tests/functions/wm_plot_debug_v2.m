function wm_plot_debug_v2(t, sig_cal_raw, sig_cal, sig_full_proc, ...
                          t_ss, sig_proc_ss, env, ameas, ...
                          n_spikes, despike_en, method, fileName, ...
                          t_start, filterEnable, filterMode)
% WM_PLOT_DEBUG_V2  Two-panel diagnostic figure for acoustic and camera signals.
%
%  TOP PANEL — full time record:
%    Grey         : raw calibrated signal (sig_cal_raw)
%    Cyan solid   : despiked signal (sig_cal), shown when despiking was
%                   enabled AND actually changed something relative to raw.
%    Cyan dotted  : shown when despiking was requested but no spikes found
%                   (identical to raw; dotted to indicate it is not missing).
%    Orange       : filtered signal (sig_full_proc), when filterEnable=true.
%    Green dashed : vertical lines marking the steady-state window boundaries.
%
%  BOTTOM PANEL — steady-state (SS) window only:
%    Orange : bandpass-filtered SS signal (sig_proc_ss)
%    Black  : Hilbert envelope (when method='envelope')
%    Red dashed : mean amplitude level (ameas)
%
%  INPUTS
%    t            — full time vector [s]
%    sig_cal_raw  — raw calibrated signal before despiking
%    sig_cal      — despiked signal (= sig_cal_raw if despike_en=false)
%    sig_full_proc — filtered full-record signal
%    t_ss         — time vector for the steady-state window
%    sig_proc_ss  — filtered signal over the steady-state window
%    env          — Hilbert envelope over SS window ([] if method~='envelope')
%    ameas        — estimated amplitude [m]
%    n_spikes     — number of spikes removed (used in legend label)
%    despike_en   — true if despiking was requested
%    method       — 'envelope' or 'rms'
%    fileName     — string used in figure title
%    t_start      — legacy argument (unused; kept for call-site compatibility)
%    filterEnable — true if bandpass filter was applied
%    filterMode   — filter mode string, e.g. 'bandpass'

    % Determine whether despiking actually changed anything.
    % Using a direct array comparison is more reliable than checking n_spikes,
    % which may not be counted consistently by all despike function variants.
    sig_was_despiked = despike_en && ...
                       (length(sig_cal) == length(sig_cal_raw)) && ...
                       any(sig_cal ~= sig_cal_raw);

    % ----------------------------------------------------------------
    %  TOP PANEL — full time record
    % ----------------------------------------------------------------
    fDeb   = figure('Name', sprintf('[%s]', fileName));
    ax_top = subplot(2, 1, 1);
    hold(ax_top, 'on');
    grid(ax_top, 'on');

    % Layer 1: raw signal (grey, behind everything)
    plot(ax_top, t, sig_cal_raw, ...
        'Color',     [0.75 0.75 0.75], ...
        'LineWidth', 0.7, ...
        'DisplayName', 'Raw');

    % Layer 2: despiked signal (cyan), shown whenever despiking changed something.
    % Previously this was gated on ~filterEnable, which hid it when filtering
    % was also active.  Now shown regardless of whether filtering is active.
    if sig_was_despiked
        plot(ax_top, t, sig_cal, ...
            'Color',     [0.00 0.70 0.70], ...
            'LineWidth', 1.0, ...
            'DisplayName', sprintf('Despiked (%d removed)', n_spikes));
    elseif despike_en
        % Despiking was requested but no spikes were found — show dotted
        % so the user knows the trace is present, just identical to raw
        plot(ax_top, t, sig_cal, ...
            'Color',     [0.00 0.70 0.70], ...
            'LineWidth', 1.0, ...
            'LineStyle', ':', ...
            'DisplayName', 'Despiked = raw');
    end

    % Layer 3: filtered full-record signal (orange), drawn on top
    if filterEnable
        plot(ax_top, t, sig_full_proc, ...
            'Color',     [0.85 0.33 0.10], ...
            'LineWidth', 1.2, ...
            'DisplayName', sprintf('Filtered (%s)', filterMode));
    end

    % Steady-state window boundary markers (green dashed verticals)
    if ~isempty(t_ss)
        xline(ax_top, t_ss(1), ...
            'Color',     [0.10 0.60 0.10], ...
            'LineStyle', '--', ...
            'LineWidth', 1.2, ...
            'DisplayName', sprintf('start %.0f s', t_ss(1)));
        xline(ax_top, t_ss(end), ...
            'Color',     [0.10 0.60 0.10], ...
            'LineStyle', '--', ...
            'LineWidth', 1.2, ...
            'DisplayName', sprintf('end %.0f s', t_ss(end)));
    end

    legend(ax_top, 'show', 'Location', 'northeast', ...
        'FontSize', 8, 'Interpreter', 'none');
    ylabel(ax_top, '$\eta$ (m)', 'Interpreter', 'latex', 'FontSize', 11);

    if filterEnable
        title(ax_top, ...
            sprintf('Debug [filter=%s] -- %s', filterMode, fileName), ...
            'Interpreter', 'none', 'FontSize', 10);
    else
        title(ax_top, ...
            sprintf('Debug [No filter] -- %s', fileName), ...
            'Interpreter', 'none', 'FontSize', 10);
    end

    % ----------------------------------------------------------------
    %  BOTTOM PANEL — steady-state window only
    % ----------------------------------------------------------------
    ax_bot = subplot(2, 1, 2);
    hold(ax_bot, 'on');
    grid(ax_bot, 'on');

    % Filtered SS signal
    plot(ax_bot, t_ss, sig_proc_ss, ...
        'Color',     [0.85 0.33 0.10], ...
        'LineWidth', 1.2, ...
        'DisplayName', 'Filtered');

    % Amplitude marker — method-dependent
    switch lower(method)
        case 'rms'
            yline(ax_bot, ameas, 'r--', ...
                'LineWidth', 1.5, ...
                'Label',    sprintf('+A_{rms}=%.4fm', ameas), ...
                'LabelHorizontalAlignment', 'left');

        case 'envelope'
            if ~isempty(env)
                plot(ax_bot, t_ss, env, ...
                    'k', 'LineWidth', 1.5, 'DisplayName', 'Envelope');
                yline(ax_bot, ameas, 'r--', ...
                    'LineWidth', 1.5, 'HandleVisibility', 'off');
            end
    end

    legend(ax_bot, 'show', 'Location', 'best', ...
        'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax_bot, '$t$ (s)',    'Interpreter', 'latex', 'FontSize', 11);
    ylabel(ax_bot, '$\eta$ (m)', 'Interpreter', 'latex', 'FontSize', 11);

    if ~isempty(t_ss)
        title(ax_bot, ...
            sprintf('SS window: t=[%.0f, %.0f] s', t_ss(1), t_ss(end)), ...
            'Interpreter', 'none', 'FontSize', 9);
    end

    % Link x-axes so zooming/panning one panel affects the other
    linkaxes([ax_top, ax_bot], 'x');

end