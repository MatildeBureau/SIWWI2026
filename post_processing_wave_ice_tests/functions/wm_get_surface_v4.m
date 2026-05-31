function [surf_abs, surf_unc_px] = wm_get_surface_v4( ...
        pks, locs, ...
        prev_surf_px, ...
        prev_surf_amp, ...
        jump_tol_px, ...
        y_top, ...
        grad_amp_min, ...
        grad_amp_max, ...
        amp_jump_tol_frac, ...
        grad_vec, ...
        use_strongest_peak)
% WM_GET_SURFACE_V4  Detects a single air-contact interface from gradient peaks.
%
%  Identifies the interface currently in contact with air — either the ice
%  top surface or the open-water surface, depending on the experimental state.
%  Only one interface is detected per call (use pick_best_peak for the
%  two-interface ice/water case).
%
% =========================================================================
%  DETECTION MODES
% =========================================================================
%  use_strongest_peak = false  [default — Nikon side-camera geometry]
%    Picks the UPPERMOST amplitude-valid peak (smallest pixel row index).
%    Correct when the target surface is near the top of the ROI and
%    spurious edges (tank frame, wires) are weaker or absent.
%
%  use_strongest_peak = true   [GoPro through-wall geometry]
%    Picks the STRONGEST amplitude-valid peak (largest gradient amplitude).
%    Correct when the water surface always produces the dominant intensity
%    transition regardless of position, while spurious edges above it
%    are weaker.
%
% =========================================================================
%  DETECTION ALGORITHM — PRIMARY + PROGRESSIVE FALLBACKS
% =========================================================================
%  PRIMARY (strict):
%    1. Amplitude window filter: keep peaks in [grad_amp_min, grad_amp_max].
%    2. Pick uppermost or strongest peak according to mode.
%    3. Displacement continuity: |position - prev| <= jump_tol_px.
%    4. Amplitude continuity:    |amp/prev_amp - 1| <= amp_jump_tol_frac.
%
%  FALLBACK 1 — amplitude continuity disabled:
%    Retry without the amplitude continuity filter.  Handles frames where
%    peak strength changes at wave crests due to foam or lighting variation.
%
%  FALLBACK 2 — doubled jump tolerance, amplitude continuity disabled:
%    Retry with 2x jump_tol_px.  Handles fast-moving surfaces at high
%    steepness or frequency where the surface legitimately moves further
%    than expected between consecutive frames.
%
%  FALLBACK 3 — closest valid peak to previous position:
%    Accept the amplitude-window peak spatially closest to the last known
%    position, regardless of distance.  Only applied when prev_surf_px is
%    known.  Guarantees a detection whenever any valid peak exists.
%
%  The only condition that returns NaN is when NO peak survives the
%  amplitude window — meaning there is genuinely no detectable edge in the ROI.
%
% =========================================================================
%  INPUTS
% =========================================================================
%  pks               — peak amplitudes [descending order from findpeaks]
%  locs              — ROI-local peak row indices from findpeaks
%  prev_surf_px      — accepted surface position in previous frame [absolute px]
%                      NaN on first frame (disables displacement filter)
%  prev_surf_amp     — accepted gradient amplitude in previous frame
%                      NaN on first frame (disables amplitude filter)
%  jump_tol_px       — max displacement between frames [px] (primary attempt)
%  y_top             — top row of ROI in the full frame [px] (used for
%                      converting ROI-local indices to absolute frame coords)
%  grad_amp_min      — minimum gradient amplitude (0 = no lower bound)
%  grad_amp_max      — maximum gradient amplitude (Inf = no upper bound)
%  amp_jump_tol_frac — max fractional amplitude change between frames
%                      (Inf = disabled)
%  grad_vec          — full gradient vector over ROI for HWHM uncertainty
%                      estimation (pass [] to skip, returns 0.5 px)
%  use_strongest_peak — (optional, default false)
%                       false: pick uppermost valid peak
%                       true:  pick strongest valid peak
%
% =========================================================================
%  OUTPUTS
% =========================================================================
%  surf_abs     — detected surface row [absolute px in full frame]
%                 NaN only when no peak survives the amplitude window
%  surf_unc_px  — position uncertainty [px] estimated via HWHM of gradient
%                 peak; minimum 0.5 px (half-pixel subpixel floor)

    % Default optional arguments
    if nargin < 7  || isempty(grad_amp_min);       grad_amp_min       = 0;     end
    if nargin < 8  || isempty(grad_amp_max);       grad_amp_max       = Inf;   end
    if nargin < 9  || isempty(amp_jump_tol_frac);  amp_jump_tol_frac  = Inf;   end
    if nargin < 10 || isempty(grad_vec);           grad_vec           = [];    end
    if nargin < 11 || isempty(use_strongest_peak); use_strongest_peak = false; end

    surf_abs    = NaN;
    surf_unc_px = NaN;

    pks  = pks(:);
    locs = locs(:);
    if isempty(pks) || isempty(locs); return; end

    % ================================================================
    %  STEP 1 — Amplitude window filter.
    %  If nothing survives, there is genuinely no detectable edge.
    % ================================================================
    amp_ok    = (pks >= grad_amp_min) & (pks <= grad_amp_max);
    pks_filt  = pks(amp_ok);
    locs_filt = locs(amp_ok);

    if isempty(pks_filt); return; end

    % Convert all valid candidates to absolute frame coordinates
    abs_locs_filt = locs_filt + y_top - 1;

    % ================================================================
    %  PRIMARY ATTEMPT
    % ================================================================
    [surf_abs, surf_unc_px, ~] = try_accept( ...
        pks_filt, locs_filt, abs_locs_filt, ...
        prev_surf_px, prev_surf_amp, ...
        jump_tol_px, amp_jump_tol_frac, ...
        grad_vec, use_strongest_peak);

    if ~isnan(surf_abs); return; end

    % ================================================================
    %  FALLBACK 1 — disable amplitude continuity filter
    % ================================================================
    if isfinite(amp_jump_tol_frac)
        [surf_abs, surf_unc_px, ~] = try_accept( ...
            pks_filt, locs_filt, abs_locs_filt, ...
            prev_surf_px, prev_surf_amp, ...
            jump_tol_px, Inf, ...
            grad_vec, use_strongest_peak);

        if ~isnan(surf_abs); return; end
    end

    % ================================================================
    %  FALLBACK 2 — double jump tolerance, amplitude continuity off
    % ================================================================
    [surf_abs, surf_unc_px, ~] = try_accept( ...
        pks_filt, locs_filt, abs_locs_filt, ...
        prev_surf_px, prev_surf_amp, ...
        jump_tol_px * 2, Inf, ...
        grad_vec, use_strongest_peak);

    if ~isnan(surf_abs); return; end

    % ================================================================
    %  FALLBACK 3 — closest valid peak to previous position (last resort)
    % ================================================================
    if ~isnan(prev_surf_px)
        dist_to_prev = abs(abs_locs_filt - prev_surf_px);
        [~, closest_idx] = min(dist_to_prev);

        surf_abs    = abs_locs_filt(closest_idx);
        surf_unc_px = hwhm_uncertainty(grad_vec, locs_filt(closest_idx));
    end

end   % <<< end wm_get_surface_v4


% ====================================================================
%  LOCAL HELPER: TRY_ACCEPT
%
%  Attempts to find one valid peak subject to displacement and amplitude
%  continuity filters.  Evaluates candidates in mode-specific order
%  (uppermost-first or strongest-first) and returns the first that passes.
%  Returns NaN if no candidate passes all active filters.
% ====================================================================
function [surf_abs, surf_unc_px, accepted_idx] = try_accept( ...
        pks_filt, locs_filt, abs_locs_filt, ...
        prev_surf_px, prev_surf_amp, ...
        jump_tol_px, amp_jump_tol_frac, ...
        grad_vec, use_strongest_peak)

    surf_abs     = NaN;
    surf_unc_px  = NaN;
    accepted_idx = [];

    % Determine evaluation order
    if use_strongest_peak
        [~, sort_idx] = sort(pks_filt, 'descend');     % strongest first
    else
        [~, sort_idx] = sort(abs_locs_filt, 'ascend'); % uppermost first
    end

    for si = 1:length(sort_idx)
        idx      = sort_idx(si);
        cand_abs = abs_locs_filt(idx);
        cand_amp = pks_filt(idx);
        cand_loc = locs_filt(idx);

        % Displacement continuity check
        if ~isnan(prev_surf_px)
            if abs(cand_abs - prev_surf_px) > jump_tol_px
                continue;
            end
        end

        % Amplitude continuity check
        if ~isnan(prev_surf_amp) && isfinite(amp_jump_tol_frac)
            rel_change = abs(cand_amp - prev_surf_amp) / max(prev_surf_amp, 1e-9);
            if rel_change > amp_jump_tol_frac
                continue;
            end
        end

        % Candidate passed all active filters — accept
        surf_abs     = cand_abs;
        surf_unc_px  = hwhm_uncertainty(grad_vec, cand_loc);
        accepted_idx = idx;
        return;
    end

end


% ====================================================================
%  LOCAL HELPER: HWHM-BASED POSITION UNCERTAINTY
%
%  Estimates position uncertainty from the half-width at half-maximum
%  of the gradient peak.  A sharp interface produces a narrow peak
%  (small uncertainty); a diffuse interface produces a broad peak
%  (larger uncertainty).  Minimum returned value is 0.5 px.
% ====================================================================
function unc_px = hwhm_uncertainty(grad_vec, peak_loc)

    unc_px = 0.5;   % half-pixel floor

    if isempty(grad_vec)  || isempty(peak_loc) || ...
       isnan(peak_loc)    || peak_loc < 1      || ...
       peak_loc > length(grad_vec)
        return;
    end

    half_max = grad_vec(peak_loc) / 2;

    li = peak_loc;
    while li > 1 && grad_vec(li - 1) > half_max
        li = li - 1;
    end

    ri = peak_loc;
    while ri < length(grad_vec) && grad_vec(ri + 1) > half_max
        ri = ri + 1;
    end

    unc_px = max(0.5, (ri - li) / 2);

end