function accepted = wm_cam_test_section(vObj, frame_start, nTest, ...
        strip_x_frac, strip_w_frac, search_y_frac, grad_smooth_sigma, ...
        videoFile, is_ice, pp)
% WM_CAM_TEST_SECTION  Interactive surface detection preview figure.
%
%  Displays a grid of up to nTest preprocessed frames with the detected
%  water surface (red) and ice bottom (blue, when is_ice=true) overlaid.
%  A modal dialog then blocks execution until the user accepts or skips
%  the video.
%
%  The preview shows the preprocessed frame (when pp.enable=true) so the
%  user sees exactly what the detection algorithm operates on.  Detection
%  uses no amplitude thresholds and no temporal continuity filters, so
%  all gradient peaks are shown as candidates — this is intentionally
%  more permissive than the main loop.
%
%
%  INPUTS
%    vObj              — VideoReader object (already opened; will be seeked)
%    frame_start       — first frame index to preview (1-based)
%    nTest             — number of frames to show
%    strip_x_frac      — strip centre as fraction of frame width
%    strip_w_frac      — strip width  as fraction of frame width
%    search_y_frac     — [top bottom] ROI boundaries as fractions of frame height
%    grad_smooth_sigma — Gaussian sigma [px] for gradient smoothing
%    videoFile         — string, used for figure title
%    is_ice            — true: detect and show both water (red) and ice (blue)
%    pp                — preprocessing struct from wm_cam_preprocess_defaults()
%                        Pass [] or omit to run without preprocessing.
%
%  OUTPUT
%    accepted — true if user clicked "Accept" (proceed to calibration)
%               false if user clicked "Skip video" or closed the dialog

    % Handle optional pp argument
    if nargin < 10 || isempty(pp)
        pp_use = wm_cam_preprocess_defaults();
        pp_use.enable = false;
    else
        pp_use = pp;
    end

    accepted = true;   % default — overridden by dialog

    % ----------------------------------------------------------------
    %  Figure layout
    % ----------------------------------------------------------------
    nCols = min(nTest, 5);
    nRows = ceil(nTest / nCols);

    fTest = figure( ...
        'Name',        sprintf('Detection Preview -- %s', videoFile), ...
        'NumberTitle', 'off', ...
        'Color',       'w');

    if is_ice
        sgtitle(fTest, ...
            sprintf('Preview %d frames | Red=water | Blue=ice | PP=%s', ...
                nTest, mat2str(pp_use.enable)), ...
            'Interpreter', 'none', 'FontSize', 10);
    else
        sgtitle(fTest, ...
            sprintf('Preview %d frames | Red=water surface | PP=%s', ...
                nTest, mat2str(pp_use.enable)), ...
            'Interpreter', 'none', 'FontSize', 10);
    end

    % Seek to the requested start frame
    vObj.CurrentTime = (frame_start - 1) / vObj.FrameRate;

    for k = 1:nTest

        if ~hasFrame(vObj); break; end

        % Read frame and convert to grayscale
        frame_raw = readFrame(vObj);
        if size(frame_raw, 3) == 3
            frame_raw = rgb2gray(frame_raw);
        end

        % Apply preprocessing pipeline
        frame_proc = wm_cam_preprocess(frame_raw, pp_use);

        [H, W] = size(frame_proc);

        % ROI pixel coordinates
        x_cen  = round(strip_x_frac * W);
        x_half = max(1, round(strip_w_frac * W / 2));
        x_lo   = max(1,   x_cen - x_half);
        x_hi   = min(W,   x_cen + x_half);
        y_lo   = max(1,   round(search_y_frac(1) * H));
        y_hi   = min(H,   round(search_y_frac(2) * H));

        % Compute intensity profile and gradient over the ROI strip
        strip   = double(frame_proc(y_lo:y_hi, x_lo:x_hi));
        prof_sm = imgaussfilt(mean(strip, 2), grad_smooth_sigma);
        grad    = abs(diff(prof_sm));

        % Find gradient peaks — MinPeakProminence suppresses very small bumps
        if max(grad) > 0
            [pks, locs] = findpeaks(grad, 'SortStr', 'descend', ...
                'MinPeakProminence', max(grad) * 0.05);
        else
            pks = []; locs = [];
        end

        % Run detection with no thresholds and no temporal continuity
        % (all 4 outputs captured; uncertainty outputs suppressed with ~)
        [surf_y, ice_y, ~, ~] = pick_best_peak(pks, locs, ...
            NaN, NaN, NaN, NaN, ...     % no prior position or amplitude
            Inf, y_lo, is_ice, ...      % jump_tol=Inf (first-frame mode)
            0, 0, Inf, Inf, ...         % no amplitude thresholds
            0, Inf, grad);              % no separation, no continuity filter

        % Draw subplot
        ax = subplot(nRows, nCols, k, 'Parent', fTest);
        imshow(frame_proc, 'Parent', ax);
        hold(ax, 'on');

        % Water surface — red line
        if ~isnan(surf_y)
            line(ax, [1 W], [surf_y surf_y], 'Color', 'r', 'LineWidth', 1.5);
        end

        % Ice bottom — blue line (only when is_ice=true)
        if is_ice && ~isnan(ice_y)
            line(ax, [1 W], [ice_y ice_y], 'Color', 'b', 'LineWidth', 1.5);
        end

        % Analysis strip — yellow shading
        patch(ax, [x_lo x_hi x_hi x_lo], [1 1 H H], ...
            'y', 'FaceAlpha', 0.12, 'EdgeColor', 'y', 'LineWidth', 1.0);

        % Vertical search window — cyan dashed lines
        line(ax, [1 W], [y_lo y_lo], 'Color', 'c', 'LineStyle', '--', 'LineWidth', 1.0);
        line(ax, [1 W], [y_hi y_hi], 'Color', 'c', 'LineStyle', '--', 'LineWidth', 1.0);

        title(ax, sprintf('Frame %d', frame_start + k - 1), 'FontSize', 8);
        hold(ax, 'off');

    end   % frame loop

    % Flush all graphics before opening the dialog so the user can see
    % the preview while the dialog is on screen
    drawnow;
    figure(fTest);   % bring preview to front

    % ----------------------------------------------------------------
    %  Modal dialog — questdlg always blocks until the user responds
    % ----------------------------------------------------------------
    choice = questdlg( ...
        sprintf(['Detection preview: %s\n\n' ...
                 '  RED    = water surface\n' ...
                 '  BLUE   = ice bottom (is_ice = true)\n' ...
                 '  YELLOW = analysis strip\n' ...
                 '  CYAN   = vertical search window\n\n' ...
                 'Preprocessing enabled: %s\n\n' ...
                 'If detection looks wrong, adjust parameters in\n' ...
                 'Section 1 and re-run.\n\n' ...
                 'Click Accept to proceed to pixel calibration,\n' ...
                 'or Skip to skip this video entirely.'], ...
            videoFile, mat2str(pp_use.enable)), ...
        'Detection Preview', ...
        'Accept', 'Skip video', ...
        'Accept');   % default button

    % Close the preview figure after the user responds
    if isgraphics(fTest)
        close(fTest);
    end

    if strcmp(choice, 'Accept')
        accepted = true;
        fprintf('  [PREVIEW] Accepted — proceeding to calibration.\n');
    else
        % Covers both 'Skip video' and '' (dialog closed with X)
        accepted = false;
        fprintf('  [PREVIEW] Skipped by user.\n');
    end

end