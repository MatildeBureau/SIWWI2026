function pp = wm_cam_preprocess_defaults()
% WM_CAM_PREPROCESS_DEFAULTS  Returns default preprocessing parameter struct.
%
%  This struct is the single source of truth for all preprocessing parameters
%  used by wm_cam_preprocess.  
%
%  STEP ENABLE LOGIC
%  Each step is enabled/disabled by the value of its parameter alone —
%  no separate boolean toggle fields are needed:
%    CLAHE   — disabled when clahe_cliplim  = 0
%    Denoise — disabled when denoise_sigma  = 0
%    Sharpen — disabled when sharpen_amount = 0
%    Gamma   — disabled when gamma_val      = 1.0
%
%  FIELDS
%    enable           — master switch: false = return frame unchanged
%    clahe_tiles      — CLAHE tile grid [rows cols] (rarely needs changing)
%    clahe_cliplim    — CLAHE clip limit 0–1  (0 = CLAHE disabled)
%    denoise_sigma    — Gaussian denoise sigma [px]  (0 = disabled)
%    sharpen_radius   — unsharp mask Gaussian radius [px]
%    sharpen_amount   — unsharp mask strength  (0 = sharpen disabled)
%    gamma_val        — power-law gamma exponent  (1.0 = disabled, <1 brightens)
%    grad_amp_min     — per-camera minimum gradient amplitude for detection;
%                       overrides the global grad_amp_min in Section 4f-POST
%    use_strongest_peak — false: pick uppermost valid peak (Nikon side-cam geometry)
%                         true:  pick strongest valid peak (GoPro through-wall geometry)

    pp.enable            = false;  % master switch — false = pass through unchanged
    pp.clahe_tiles       = [8 8];  % CLAHE tile grid
    pp.clahe_cliplim     = 0.00;   % 0 = CLAHE disabled
    pp.denoise_sigma     = 0.0;    % 0 = denoise disabled
    pp.sharpen_radius    = 1.0;    % unsharp mask radius [px]
    pp.sharpen_amount    = 0.0;    % 0 = sharpen disabled
    pp.gamma_val         = 1.0;    % 1.0 = gamma disabled
    pp.grad_amp_min      = 1.5;    % per-camera detection threshold
    pp.use_strongest_peak = false; % detection mode (false = uppermost peak)

end