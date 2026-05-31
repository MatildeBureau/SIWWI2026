function frame_out = wm_cam_preprocess(frame_in, pp)
% WM_CAM_PREPROCESS  Enhances a grayscale frame before interface detection.
%
%  Applies a configurable four-step pipeline to suppress background texture
%  noise and sharpen the contrast at phase interfaces (water surface, ice top),
%  making gradient peaks more reliably detectable.
%
%  PIPELINE ORDER
%    1. CLAHE   — local contrast enhancement: boosts dim interfaces that
%                 have low contrast relative to the bright water body.
%                 Skipped when clahe_cliplim = 0.
%
%    2. Denoise — Gaussian spatial smoothing: suppresses pixel-level speckle,
%                 tank-wall texture, and water surface turbulence that generate
%                 false gradient peaks.  Applied before gradient computation.
%                 Skipped when denoise_sigma = 0.
%
%    3. Sharpen — Unsharp masking: recovers edge sharpness after the denoise
%                 blur so that the interface gradient peak remains distinct.
%                 Skipped when sharpen_amount = 0.
%
%    4. Gamma   — Power-law intensity remap: gamma < 1 compresses bright
%                 regions and expands dark ones, lifting dim ice features
%                 relative to the bright water surface.
%                 Skipped when gamma_val = 1.0.
%
%  All intermediate processing is done in double precision [0, 1] to avoid
%  uint8 clipping artefacts.  Output is returned as uint8.
%
%  INPUTS
%    frame_in — grayscale frame, uint8 (H x W)
%    pp       — parameter struct from wm_cam_preprocess_defaults(), fields:
%                 enable, clahe_tiles, clahe_cliplim,
%                 denoise_sigma, sharpen_radius, sharpen_amount, gamma_val
%
%  OUTPUT
%    frame_out — preprocessed grayscale frame, uint8 (same size as frame_in)
%
%  See also: wm_cam_preprocess_defaults, adapthisteq, imgaussfilt, imsharpen

    % Master switch — if disabled, pass frame through unchanged
    if ~pp.enable
        frame_out = frame_in;
        return;
    end

    % Work in double [0, 1] throughout to avoid clipping
    img = double(frame_in) / 255.0;

    % ================================================================
    %  STEP 1: CLAHE (Contrast Limited Adaptive Histogram Equalisation)
    %
    %  Boosts local contrast within spatial tiles, making low-contrast
    %  interfaces (e.g. ice top against grey water) visible to the gradient.
    %  Increase clahe_cliplim toward 0.10 if the edge is still invisible.
    % ================================================================
    if pp.clahe_cliplim > 0
        if isfield(pp, 'clahe_tiles')
            tiles = pp.clahe_tiles;
        else
            tiles = [8 8];
        end
        img_u8 = uint8(img * 255);
        img_eq = adapthisteq(img_u8, ...
                     'NumTiles',     tiles, ...
                     'ClipLimit',    pp.clahe_cliplim, ...
                     'Distribution', 'uniform');
        img = double(img_eq) / 255.0;
    end

    % ================================================================
    %  STEP 2: Gaussian Denoise
    %
    %  A mild spatial blur before gradient computation suppresses
    %  sub-feature noise while preserving spatially coherent interface
    %  edges (which are consistent across many columns of the strip).
    %  Increase denoise_sigma toward 3.0 if the gradient is still ragged;
    %  too large a value will smear the ice and water edges together.
    % ================================================================
    if pp.denoise_sigma > 0
        img = imgaussfilt(img, pp.denoise_sigma);
    end

    % ================================================================
    %  STEP 3: Unsharp Masking (Sharpening)
    %
    %  Subtracts a blurred copy of the image to amplify edge contrast
    %  without re-introducing pixel noise.  Applied after denoising to
    %  keep the interface gradient peak sharp and narrow.
    % ================================================================
    if pp.sharpen_amount > 0
        if isfield(pp, 'sharpen_radius')
            s_radius = pp.sharpen_radius;
        else
            s_radius = 1.0;
        end
        img_u8 = uint8(img * 255);
        img_sh = imsharpen(img_u8, ...
                     'Radius', s_radius, ...
                     'Amount', pp.sharpen_amount);
        img = double(img_sh) / 255.0;
    end

    % ================================================================
    %  STEP 4: Gamma Remapping
    %
    %  Applies a power-law transform: out = in^gamma.
    %  gamma < 1 brightens dark regions (lifts ice features relative to
    %  the bright water surface).  gamma = 1.0 skips this step entirely.
    %  Typical range: 0.60–0.80 for ice-covered tank imagery.
    % ================================================================
    if pp.gamma_val ~= 1.0
        img = max(0, min(1, img));   % clamp before power to avoid complex output
        img = img .^ pp.gamma_val;
    end

    % Clamp and return as uint8
    img       = max(0, min(1, img));
    frame_out = uint8(img * 255);

end