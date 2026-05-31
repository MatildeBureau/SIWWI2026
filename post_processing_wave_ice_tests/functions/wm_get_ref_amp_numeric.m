function [ref_amp_m, ref_sem_m] = wm_get_ref_amp_numeric( ...
        refAmp, hasBenchmark, mtype, x_loc, freq_Hz, volt_V)
% WM_GET_REF_AMP_NUMERIC  Look up open-water reference amplitude by numeric proximity.
%
%  Searches the refAmp struct array (built by wm_build_refAmp_from_benchmark)
%  for the entry whose measurement type, tank position, frequency, and voltage
%  best match the supplied values, subject to tolerance windows.
%
%  Among all entries within tolerance, the one with the closest voltage is
%  returned.  This handles rare cases where two conditions both fall within
%  tolerance (picks the better match).
%
%  TOLERANCES
%    x_tol    = 0.05 m   — position tolerance
%    freq_tol = 0.01 Hz  — frequency tolerance
%    volt_tol = 0.03 V   — voltage tolerance
%
%  INPUTS
%    refAmp       — struct array from wm_build_refAmp_from_benchmark
%    hasBenchmark — logical flag (false = no benchmark loaded, always return NaN)
%    mtype        — "Acoustic_Sensor" or "Side_Camera"
%    x_loc        — sensor/camera along-tank position [m]
%    freq_Hz      — set wave frequency [Hz]
%    volt_V       — set paddle voltage [V]
%
%  OUTPUTS
%    ref_amp_m  — reference open-water amplitude [m], NaN if not found
%    ref_sem_m  — standard error of the mean of that reference [m], 0 if single replicate

    ref_amp_m = NaN;
    ref_sem_m = 0;

    if ~hasBenchmark || isempty(refAmp); return; end

    % Tolerance windows — chosen to be strictly between the actual
    % measurement spread and the gap to the nearest other condition
    X_TOL    = 0.05;   % [m]
    FREQ_TOL = 0.01;   % [Hz]
    VOLT_TOL = 0.03;   % [V]

    best_dist = Inf;
    best_idx  = -1;

    for ir = 1:numel(refAmp)
        r = refAmp(ir);

        % Measurement type must match exactly
        if ~strcmp(r.mtype, char(mtype)); continue; end

        % All three numeric conditions must be within tolerance
        if abs(r.x_m     - x_loc)   > X_TOL;    continue; end
        if abs(r.freq_Hz - freq_Hz) > FREQ_TOL;  continue; end
        if abs(r.volt_V  - volt_V)  > VOLT_TOL;  continue; end

        % Prefer the entry with the closest voltage
        dist = abs(r.volt_V - volt_V);
        if dist < best_dist
            best_dist = dist;
            best_idx  = ir;
        end
    end

    if best_idx > 0
        ref_amp_m = refAmp(best_idx).amp_m;
        ref_sem_m = refAmp(best_idx).amp_sem_m;
    end

end