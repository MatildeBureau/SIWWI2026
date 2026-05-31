%% =========================================================
%  FUNCTION: wm_cam_detect_surface  (NEW)
%
%  Detects water surface y-position in a single grayscale frame
%  using a horizontal strip average + vertical gradient peak
%  with sub-pixel parabolic refinement.
% =========================================================
function surf_y_px = wm_cam_detect_surface(frame, strip_x_frac, strip_w_frac, ...
                                            search_y_frac, grad_smooth_sigma)
    [H, W] = size(frame);

    x_cen   = round(strip_x_frac * W);
    x_half  = max(1, round(strip_w_frac * W / 2));
    x_lo    = max(1,  x_cen - x_half);
    x_hi    = min(W,  x_cen + x_half);
    strip   = double(frame(:, x_lo:x_hi));
    profile = mean(strip, 2);

    y_lo    = max(1,  round(search_y_frac(1) * H));
    y_hi    = min(H,  round(search_y_frac(2) * H));
    profile_crop = profile(y_lo:y_hi);

    if grad_smooth_sigma > 0
        gauss_len = 2 * ceil(3 * grad_smooth_sigma) + 1;
        gauss_ker = fspecial('gaussian', [gauss_len 1], grad_smooth_sigma);
        profile_sm = imfilter(profile_crop, gauss_ker, 'replicate');
    else
        profile_sm = profile_crop;
    end

    grad = diff(profile_sm);
    [~, peak_local] = max(abs(grad));

    if peak_local < 2 || peak_local > length(grad) - 1
        surf_y_px = NaN;
        return;
    end

    g_m = abs(grad(peak_local - 1));
    g_0 = abs(grad(peak_local));
    g_p = abs(grad(peak_local + 1));

    denom = g_m + g_p - 2*g_0;
    if abs(denom) < eps
        dx = 0;
    else
        dx = 0.5 * (g_m - g_p) / denom;
    end
    dx = max(-0.5, min(0.5, dx));

    surf_y_local  = peak_local + dx;
    surf_y_px     = (y_lo - 1) + surf_y_local;
end

