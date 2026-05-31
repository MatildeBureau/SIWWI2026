function [surf_abs, ice_abs, surf_unc_px, ice_unc_px, ice_template_out] = ...
        pick_best_peak(pks, locs, ...
        prev_surf_px,   prev_ice_px, ...
        prev_surf_amp,  prev_ice_amp, ...
        jump_tol_px,    y_top,        is_ice, ...
        grad_amp_min_water, grad_amp_min_ice, ...
        grad_amp_max_water, grad_amp_max_ice, ...
        min_sep_px, ...
        amp_jump_tol_frac, ...
        grad_vec, ...
        ice_jump_tol_px, ...
        ice_template_in, ...
        max_upward_jump_px)
% PICK_BEST_PEAK  Detects water surface and ice bottom from gradient peaks.
%
%  Handles two physical geometries:
%    Open water (is_ice=false) — detects only the water surface.
%    Ice-covered  (is_ice=true) — detects both the water surface and the
%    ice bottom edge, maintaining temporal continuity via a multi-stage
%    tracking strategy for each interface independently.
%
% =========================================================================
%  PHYSICAL LOGIC
% =========================================================================
%  Water surface detection uses a simple displacement filter: the strongest
%  amplitude-valid peak is accepted unless it jumped further than
%  jump_tol_px from the previous accepted position.
%
%  Ice bottom detection is harder because the ice-bottom gradient peak is
%  typically weaker than the water-surface peak and sits among multiple
%  noise peaks of similar amplitude.  Three strategies are applied in order:
%
%  STAGE 1 — First frame / tracking disabled:
%    (a) Filter by amplitude window and minimum separation from water.
%    (b) Find the maximum amplitude among remaining candidates.
%    (c) Accept all candidates within amp_first_frac (30%) of that maximum.
%    (d) Pick the DEEPEST (largest pixel index) among those.
%    Rationale: the real ice bottom is always deeper than middle noise
%    peaks.  Selecting deepest among near-max-amplitude avoids locking
%    onto a noise peak that happens to be slightly stronger.
%
%  STAGE 2 — Tracked window (prior position known):
%    Restricts the search to within ice_jump_tol_px of the previous
%    accepted ice position, then scores each candidate as a weighted
%    combination of:
%      w_loc * location proximity to previous position
%      w_amp * amplitude similarity to previous frame amplitude
%      w_cor * gradient shape correlation with saved template snippet
%    The highest-scoring candidate is accepted.
%
%  STAGE 3 — Re-acquisition after tracking loss:
%    Identical to Stage 1 (deepest among near-max-amplitude).  Used when
%    Stage 2 finds no candidates in the tracking window.
%
%  After ice detection, two additional vetoes are applied:
%    Upward-jump veto: rejects ice detections that jump shallower than
%    the previous position by more than max_upward_jump_px.
%    Separation check: ensures the final ice position is at least
%    min_sep_px below the accepted water surface.
%
% =========================================================================
%  INPUTS
% =========================================================================
%  pks                — peak amplitudes from findpeaks [descending order]
%  locs               — ROI-local peak positions (row indices)
%  prev_surf_px       — last accepted water surface position [absolute px]
%                       NaN on first frame
%  prev_ice_px        — last accepted ice bottom position [absolute px]
%                       NaN on first frame or tracking disabled
%  prev_surf_amp      — last accepted water gradient amplitude; NaN = unknown
%  prev_ice_amp       — last accepted ice gradient amplitude;  NaN = unknown
%  jump_tol_px        — max displacement for water surface [px]
%  y_top              — top row of ROI in full frame [px]
%  is_ice             — true: detect ice bottom; false: water surface only
%  grad_amp_min_water — minimum gradient amplitude for water candidates
%  grad_amp_min_ice   — minimum gradient amplitude for ice candidates
%  grad_amp_max_water — maximum gradient amplitude for water candidates (Inf = off)
%  grad_amp_max_ice   — maximum gradient amplitude for ice candidates (Inf = off)
%  min_sep_px         — minimum required pixel separation between water and ice
%  amp_jump_tol_frac  — max fractional amplitude change for water surface (Inf = off)
%  grad_vec           — full gradient vector over ROI for HWHM uncertainty
%  ice_jump_tol_px    — max displacement for ice bottom [px] (Inf = tracking off)
%  ice_template_in    — gradient snippet from previous frame for correlation ([])
%  max_upward_jump_px — max pixels ice can jump shallower per frame (Inf = off)
%
% =========================================================================
%  OUTPUTS
% =========================================================================
%  surf_abs         — water surface position [absolute px], NaN if not detected
%  ice_abs          — ice bottom position    [absolute px], NaN if not detected
%  surf_unc_px      — water position HWHM uncertainty [px]
%  ice_unc_px       — ice position   HWHM uncertainty [px]
%  ice_template_out — gradient snippet around accepted ice peak (for next frame)

    % ================================================================
    %  TUNING PARAMETERS
    % ================================================================

    % Tracking window scoring weights (must sum to 1.0)
    w_loc = 0.50;   % weight for location proximity to previous position
    w_amp = 0.30;   % weight for amplitude similarity to previous amplitude
    w_cor = 0.20;   % weight for gradient shape correlation with template

    % Template half-width [px] for gradient shape correlation
    template_half_width = 10;

    % First-frame amplitude tolerance: accept all ice candidates within
    % this fraction of the maximum amplitude, then pick the deepest.
    % Increase toward 0.50 if the real ice-bottom peak is much weaker
    % than noise; decrease to 0.15 for cleaner gradient profiles.
    amp_first_frac = 0.30;

    % ================================================================
    %  Default optional arguments
    % ================================================================
    if nargin < 12 || isempty(grad_amp_max_water); grad_amp_max_water = Inf; end
    if nargin < 13 || isempty(grad_amp_max_ice);   grad_amp_max_ice   = Inf; end
    if nargin < 14 || isempty(min_sep_px);         min_sep_px         = 0;   end
    if nargin < 15 || isempty(amp_jump_tol_frac);  amp_jump_tol_frac  = Inf; end
    if nargin < 16 || isempty(grad_vec);           grad_vec           = [];  end
    if nargin < 17 || isempty(ice_jump_tol_px);    ice_jump_tol_px    = Inf; end
    if nargin < 18 || isempty(ice_template_in);    ice_template_in    = [];  end
    if nargin < 19 || isempty(max_upward_jump_px); max_upward_jump_px = Inf; end

    % ----------------------------------------------------------------
    %  Initialise outputs
    % ----------------------------------------------------------------
    surf_abs         = NaN;
    ice_abs          = NaN;
    surf_unc_px      = NaN;
    ice_unc_px       = NaN;
    ice_template_out = [];

    pks  = pks(:);
    locs = locs(:);
    if min(length(pks), length(locs)) == 0; return; end

    % ================================================================
    %  Amplitude-windowed candidate lists (water and ice independently)
    % ================================================================
    mask_w = (pks >= grad_amp_min_water) & (pks <= grad_amp_max_water);
    mask_i = (pks >= grad_amp_min_ice)   & (pks <= grad_amp_max_ice);

    pks_w  = pks(mask_w);   locs_w = locs(mask_w);
    pks_i  = pks(mask_i);   locs_i = locs(mask_i);

    nW = length(pks_w);
    nI = length(pks_i);

    % ================================================================
    %  OPEN-WATER MODE — single surface detection
    % ================================================================
    if ~is_ice
        if nW > 0
            cand_abs = locs_w(1) + y_top - 1;   % strongest water candidate
            surf_abs = chk_disp(cand_abs, prev_surf_px, jump_tol_px);
            if ~isnan(surf_abs)
                surf_unc_px = hwhm_uncertainty(grad_vec, locs_w(1));
            end
        end
        return;
    end

    % ================================================================
    %  ICE MODE — detect water surface then ice bottom
    % ================================================================
    if nW == 0 && nI == 0; return; end

    % ----------------------------------------------------------------
    %  Water surface detection — displacement filter on strongest peak
    % ----------------------------------------------------------------
    water_ref_px = NaN;   % reference position for ice spatial separation

    if nW > 0
        surf_cand_loc = locs_w(1);
        surf_abs_cand = surf_cand_loc + y_top - 1;
        surf_abs = chk_disp(surf_abs_cand, prev_surf_px, jump_tol_px);

        if ~isnan(surf_abs)
            surf_unc_px  = hwhm_uncertainty(grad_vec, surf_cand_loc);
            water_ref_px = surf_abs;          % use accepted position
        else
            water_ref_px = surf_abs_cand;     % fallback: candidate position
        end
    end

    if nI == 0; return; end

    % ----------------------------------------------------------------
    %  Spatial separation filter: ice candidates must be at least
    %  min_sep_px below the water reference position.
    %  Applied once here; re-checked after final selection below.
    % ----------------------------------------------------------------
    abs_locs_i = locs_i + y_top - 1;

    if ~isnan(water_ref_px) && min_sep_px > 0
        sep_ok = (abs_locs_i - water_ref_px) >= min_sep_px;
    else
        sep_ok = true(size(abs_locs_i));
    end

    pks_sep  = pks_i(sep_ok);
    locs_sep = locs_i(sep_ok);
    abs_sep  = abs_locs_i(sep_ok);
    nSep     = length(pks_sep);

    if nSep == 0; return; end

    % ================================================================
    %  STAGE 1 / 3 — Deepest among near-max-amplitude candidates
    %
    %  Selects the deepest (largest row index) candidate from the set
    %  of candidates whose amplitude is within amp_first_frac of the
    %  maximum amplitude across all separation-valid candidates.
    %
    %  The real ice bottom is always deeper than middle noise peaks.
    %  Requiring "deepest among near-max" avoids locking onto shallower
    %  noise peaks that happen to be marginally stronger.
    % ================================================================
    function [best_abs, best_loc, best_unc] = pick_deepest_near_max()
        best_abs = NaN;  best_loc = NaN;  best_unc = NaN;
        if isempty(pks_sep); return; end

        max_amp  = max(pks_sep);
        near_max = pks_sep >= max_amp * (1 - amp_first_frac);

        abs_near  = abs_sep(near_max);
        locs_near = locs_sep(near_max);
        if isempty(abs_near); return; end

        [best_abs, idx] = max(abs_near);   % deepest candidate
        best_loc        = locs_near(idx);
        best_unc        = hwhm_uncertainty(grad_vec, best_loc);
    end

    % ================================================================
    %  STAGE 2 — Tracked window with combined location/amplitude/shape score
    %
    %  Only searches within ice_jump_tol_px of the previous ice position.
    %  Scores each candidate on three criteria and picks the highest score.
    % ================================================================
    function [best_abs, best_loc, best_unc] = pick_tracked()
        in_window = abs(abs_sep - prev_ice_px) <= ice_jump_tol_px;
        pks_win   = pks_sep(in_window);
        locs_win  = locs_sep(in_window);
        abs_win   = abs_sep(in_window);
        nWin      = length(pks_win);

        best_abs = NaN;  best_loc = NaN;  best_unc = NaN;
        if nWin == 0; return; end

        scores = zeros(nWin, 1);
        for kk = 1:nWin
            % Location proximity score [0, 1]
            loc_score = max(0, 1 - abs(abs_win(kk) - prev_ice_px) / ice_jump_tol_px);

            % Amplitude similarity score [0, 1]
            if ~isnan(prev_ice_amp) && prev_ice_amp > 0
                amp_score = 1 - min(1, abs(pks_win(kk) - prev_ice_amp) / prev_ice_amp);
            else
                amp_score = 0.5;   % no prior — neutral score
            end

            % Gradient shape correlation score [0, 1]
            cor_score = 0;
            if ~isempty(ice_template_in) && ~isempty(grad_vec) && w_cor > 0
                hw = template_half_width;
                i1 = locs_win(kk) - hw;
                i2 = locs_win(kk) + hw;
                if i1 >= 1 && i2 <= length(grad_vec)
                    snippet   = grad_vec(i1:i2);
                    cor_score = max(0, norm_xcorr_zerollag(snippet, ice_template_in));
                end
            end

            scores(kk) = w_loc * loc_score + w_amp * amp_score + w_cor * cor_score;
        end

        [~, bk]  = max(scores);
        best_abs = abs_win(bk);
        best_loc = locs_win(bk);
        best_unc = hwhm_uncertainty(grad_vec, best_loc);
    end

    % ================================================================
    %  EXECUTE ICE DETECTION
    % ================================================================
    chosen_loc = NaN;

    if isnan(prev_ice_px) || isinf(ice_jump_tol_px)
        % Stage 1: first frame or tracking disabled
        [ice_abs, chosen_loc, ice_unc_px] = pick_deepest_near_max();
    else
        % Stage 2: tracked window
        [ice_abs, chosen_loc, ice_unc_px] = pick_tracked();

        if isnan(ice_abs)
            % Stage 3: re-acquisition after tracking loss
            [ice_abs, chosen_loc, ice_unc_px] = pick_deepest_near_max();
        end
    end

    % ================================================================
    %  UPWARD JUMP VETO
    %  Rejects detections where the ice jumped shallower than the previous
    %  position by more than max_upward_jump_px.  This blocks spurious
    %  upward jumps to the upper ice surface during overwash events.
    %  Set max_upward_jump_px generously (e.g. 2x ice_jump_tol_px) so
    %  legitimate wave-trough upward motion is not rejected.
    % ================================================================
    if ~isnan(ice_abs) && ~isnan(prev_ice_px) && ~isinf(max_upward_jump_px)
        upward_move = prev_ice_px - ice_abs;   % positive = moved shallower
        if upward_move > max_upward_jump_px
            ice_abs    = NaN;
            chosen_loc = NaN;
            ice_unc_px = NaN;
        end
    end

    % ================================================================
    %  FINAL MINIMUM-SEPARATION CHECK
    %  Explicitly verify the accepted ice position is at least min_sep_px
    %  below the accepted water surface.  Catches the rare case where
    %  tracking converges the ice peak onto the water peak location.
    % ================================================================
    if ~isnan(ice_abs) && ~isnan(surf_abs) && min_sep_px > 0
        if (ice_abs - surf_abs) < min_sep_px
            ice_abs    = NaN;
            chosen_loc = NaN;
            ice_unc_px = NaN;
        end
    end

    % ================================================================
    %  EXTRACT GRADIENT TEMPLATE for next-frame tracking correlation
    % ================================================================
    if ~isnan(ice_abs) && ~isempty(grad_vec) && ~isnan(chosen_loc)
        hw = template_half_width;
        i1 = chosen_loc - hw;
        i2 = chosen_loc + hw;
        if i1 >= 1 && i2 <= length(grad_vec)
            ice_template_out = grad_vec(i1:i2);
        end
    end

end   % <<< end pick_best_peak


% ====================================================================
%  LOCAL HELPER FUNCTIONS
% ====================================================================

function unc_px = hwhm_uncertainty(grad_vec, peak_loc)
% Estimate position uncertainty [px] via half-width at half-maximum.
% Minimum returned value is 0.5 px (half-pixel floor).
    unc_px = 0.5;
    if isempty(grad_vec) || isempty(peak_loc) || isnan(peak_loc) || ...
       peak_loc < 1 || peak_loc > length(grad_vec); return; end
    half_max = grad_vec(peak_loc) / 2;
    li = peak_loc;
    while li > 1 && grad_vec(li-1) > half_max;  li = li - 1; end
    ri = peak_loc;
    while ri < length(grad_vec) && grad_vec(ri+1) > half_max; ri = ri + 1; end
    unc_px = max(0.5, (ri - li) / 2);
end

function out = chk_disp(cand_abs, prev_px, tol_px)
% Accept cand_abs if within tol_px of prev_px, or if prev_px is unknown.
    if isnan(prev_px) || abs(cand_abs - prev_px) <= tol_px
        out = cand_abs;
    else
        out = NaN;
    end
end

function r = norm_xcorr_zerollag(a, b)
% Normalised zero-lag cross-correlation coefficient in [-1, 1].
    r = 0;
    if isempty(a) || isempty(b); return; end
    na = length(a);  nb = length(b);
    if na ~= nb
        n  = min(na, nb);
        ha = floor(na/2);  hb = floor(nb/2);
        a  = a(max(1, ha-floor(n/2)+1) : min(na, ha+ceil(n/2)));
        b  = b(max(1, hb-floor(n/2)+1) : min(nb, hb+ceil(n/2)));
        if length(a) ~= length(b)
            n2 = min(length(a), length(b));
            a  = a(1:n2);  b = b(1:n2);
        end
    end
    a = a(:) - mean(a);
    b = b(:) - mean(b);
    denom = norm(a) * norm(b);
    if denom < 1e-12; return; end
    r = dot(a, b) / denom;
end