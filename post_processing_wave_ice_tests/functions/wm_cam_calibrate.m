%% =========================================================
%  FUNCTION: wm_cam_calibrate 
%
%  Interactive pixel-to-mm calibration.
%  1. Display first frame.
%  2. User zooms to reference object, presses Enter.
%  3. User clicks two points of known distance.
%  4. User enters the real distance in cm.
% =========================================================
function camCalib = wm_cam_calibrate(vObj)
    fprintf('  [CAM CALIB] Starting pixel-to-mm calibration...\n');

    vObj.CurrentTime = 0;
    frame = readFrame(vObj);
    if size(frame,3) == 3; frame = rgb2gray(frame); end

    fig = figure('Name','Camera Calibration — click 2 reference points');
    imshow(frame);
    title({'CALIBRATION: Zoom in on reference distance, press Enter, then click 2 points.', ...
           'Example: click both ends of a ruler graduation.'}, 'FontSize',10);
    zoom on; pause;
    zoom off;

    [x_cal, y_cal] = ginput(2);
    close(fig);

    pixelDist = sqrt(diff(x_cal)^2 + diff(y_cal)^2);
    fprintf('  [CAM CALIB] Pixel distance between clicked points: %.2f px\n', pixelDist);

    real_cm = str2double(inputdlg( ...
        'Enter the real distance between the two clicked points (cm):', ...
        'Camera Calibration', [1 60], {'10'}));

    if isnan(real_cm) || real_cm <= 0
        error('Invalid calibration distance. Please re-run and enter a positive value.');
    end

    mm_per_px          = (real_cm * 10) / pixelDist;
    camCalib.mm_per_px = mm_per_px;
    camCalib.done      = true;

    fprintf('  [CAM CALIB] Result: %.5f mm/px  (= %.5f px/mm)\n', mm_per_px, 1/mm_per_px);
end


