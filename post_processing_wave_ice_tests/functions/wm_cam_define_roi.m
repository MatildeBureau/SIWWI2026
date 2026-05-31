%% =========================================================
%  FUNCTION: wm_cam_define_roi
%
%  Interactive ROI definition for one camera location.
%  The user draws a rectangle over the desired analysis region,
%  from which strip_x_frac, strip_w_frac, and search_y_frac are
%  all derived in one step.
%
%    1. First frame displayed with zoom enabled.
%    2. User zooms to the open-water region of interest,
%       then presses Enter to exit zoom mode.
%    3. User draws ONE rectangle over the analysis region:
%         - Horizontal extent  -> strip centre + strip width
%         - Vertical extent    -> top and bottom of search window
%    4. The rectangle is overlaid on the frame for confirmation.
%    5. uiwait dialog shown before returning.
%
%  OUTPUTS (all fractional [0–1], resolution-independent):
%    strip_x_frac  — horizontal centre of the rectangle
%    strip_w_frac  — width  of the rectangle (as fraction of W)
%    search_y_frac — [top, bottom] vertical extent (as fractions of H)
%
%  INPUTS:
%    vObj     — VideoReader object (first frame is used;
%               CurrentTime is reset to 0 internally)
%    camX     — camera x-position [m]  (for figure title)
%    vidFile  — filename string         (for figure title)
% =========================================================
function [strip_x_frac, strip_w_frac, search_y_frac] = ...
        wm_cam_define_roi(vObj, camX, vidFile)

    % ----------------------------------------------------------
    %  Read the first frame.
    %  Reset CurrentTime so the function is position-independent.
    % ----------------------------------------------------------
    vObj.CurrentTime = 0;
    frame = readFrame(vObj);
    if size(frame, 3) == 3
        frame = rgb2gray(frame);   % greyscale for display clarity
    end
    [H, W] = size(frame);

    % ----------------------------------------------------------
    %  Display frame and let the user zoom before drawing.
    %  zoom on / pause / zoom off is the same pattern used in
    %  wm_cam_calibrate (v3): zoom is active until Enter is
    %  pressed, then ginput/getrect can safely collect clicks.
    % ----------------------------------------------------------
    fig = figure('Name', sprintf('ROI Setup | cam x=%.2f m | %s', camX, vidFile));
    imshow(frame);
    title({ ...
        sprintf('ROI SETUP  |  Camera x = %.2f m  |  %s', camX, vidFile), ...
        'Zoom to the open-water region of interest, press ENTER,', ...
        'then DRAW A RECTANGLE over the analysis strip + search window.'}, ...
        'FontSize', 10, 'Interpreter', 'none');

    % --- Zoom-then-Enter  ---
    zoom on;
    pause;        % execution pauses; user zooms then presses Enter
    zoom off;

    % ----------------------------------------------------------
    %  User draws a rectangle.
    %  getrect returns [x_left, y_top, rect_width, rect_height]
    %  all in pixel coordinates of the displayed image.
    % ----------------------------------------------------------
    title({ ...
        sprintf('ROI SETUP  |  Camera x = %.2f m', camX), ...
        'Draw a rectangle over the analysis region, then release the mouse.'}, ...
        'FontSize', 10, 'Interpreter', 'none');

    rect = getrect(fig);   % [x_left, y_top, rect_w, rect_h] in pixels

    % Parse the rectangle into ROI parameters
    x_left   = rect(1);
    y_top    = rect(2);
    rect_w   = rect(3);
    rect_h   = rect(4);

    % Clamp to frame boundaries (getrect can return sub-pixel or
    % out-of-bounds values if the user drags to the frame edge)
    x_left = max(1,   x_left);
    y_top  = max(1,   y_top);
    x_right = min(W,  x_left + rect_w);
    y_bot   = min(H,  y_top  + rect_h);

    % Convert to fractions [0–1]  (resolution-independent)
    strip_x_frac  = ((x_left + x_right) / 2) / W;   % centre of rectangle
    strip_w_frac  = (x_right - x_left)        / W;   % width  of rectangle
    strip_w_frac  = max(strip_w_frac, 0.005);         % floor at 0.5 % of W
    search_y_frac = [y_top / H,  y_bot / H];          % [top, bottom]

    % ----------------------------------------------------------
    %  Overlay the accepted rectangle on the frame so the user
    %  can visually confirm before clicking OK.
    % ----------------------------------------------------------
    hold on;

    % Rectangle outline in yellow
    rectangle('Position', [x_left, y_top, x_right-x_left, y_bot-y_top], ...
        'EdgeColor', 'y', 'LineWidth', 2.0);

    % Vertical centre line of the strip (cyan)
    x_centre_px = strip_x_frac * W;
    line([x_centre_px x_centre_px], [y_top y_bot], ...
        'Color', 'c', 'LineWidth', 1.5, 'LineStyle', '--');

    % Update title to show the derived values
    title({ ...
        sprintf('ROI confirmed  |  strip\\_x=%.3f  strip\\_w=%.3f  search\\_y=[%.3f, %.3f]', ...
            strip_x_frac, strip_w_frac, search_y_frac(1), search_y_frac(2)), ...
        'Click OK in the dialog to proceed to pixel-to-mm calibration.'}, ...
        'FontSize', 10, 'Color', [0.0 0.60 0.0], 'Interpreter', 'none');

    % ----------------------------------------------------------
    %  Confirmation dialog 
    % ----------------------------------------------------------
    uiwait(msgbox( ...
        {'ROI confirmed:', ...
         sprintf('  strip centre  x_frac = %.4f', strip_x_frac), ...
         sprintf('  strip width   w_frac = %.4f', strip_w_frac), ...
         sprintf('  search top    y_frac = %.4f  (pixel %.0f)', search_y_frac(1), y_top), ...
         sprintf('  search bottom y_frac = %.4f  (pixel %.0f)', search_y_frac(2), y_bot), ...
         '', ...
         'Click OK to proceed to pixel-to-mm calibration.'}, ...
        'ROI Confirmed', 'modal'));

    close(fig);

    fprintf('  [ROI] strip_x=%.4f  strip_w=%.4f  search_y=[%.4f, %.4f]\n', ...
        strip_x_frac, strip_w_frac, search_y_frac(1), search_y_frac(2));
end


