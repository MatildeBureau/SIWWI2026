%  FUNCTION  — wm_build_refAmp_from_benchmark
%
% Build reference amplitudes structure to normalize measured amplitudes.
%
%  INPUT
%    benchTable  — table read from the benchmark Results_postprocess CSV
%                  (must contain: Measurement, SensorLocation_m,
%                   SetFrequency_Hz, SetAmplitude_V, MeasuredAmplitude_m)
%
%  OUTPUT
%    refAmp      — struct array; each element has fields:
%                    .x_m        sensor/camera location [m]
%                    .freq_Hz    set frequency [Hz]
%                    .volt_V     set amplitude [V]
%                    .amp_m      mean reference amplitude [m]
%                    .amp_sem_m  standard error of mean (0 if n=1)
%                    .n          number of benchmark replicates
%                    .mtype      'Acoustic_Sensor' or 'Side_Camera'
%    hasBenchmark — logical, true if at least one valid row was loaded
% ==========================================================================
function [refAmp, hasBenchmark] = wm_build_refAmp_from_benchmark(benchTable)
 
    hasBenchmark = false;
    refAmp       = struct('x_m',{}, 'freq_Hz',{}, 'volt_V',{}, ...
                          'amp_m',{}, 'amp_sem_m',{}, 'n',{}, 'mtype',{});
 
    % ── Column presence check ────────────────────────────────────────────
    required = {'Measurement','SensorLocation_m','SetFrequency_Hz', ...
                'SetAmplitude_V','MeasuredAmplitude_m'};
    missing  = setdiff(required, benchTable.Properties.VariableNames);
    if ~isempty(missing)
        warning('wm_build_refAmp_from_benchmark: benchmark CSV missing columns: %s', ...
                strjoin(missing,', '));
        return;
    end
 
    % ── Accumulation buffers (cell of vectors for online mean/variance) ──
    % Key: [x_m, freq_Hz, volt_V, mtype_idx]  where mtype_idx 1=Acoustic 2=Camera
    acc_keys = zeros(0, 4);   % Nx4
    acc_vals = {};             % cell of double vectors
 
    for ib = 1:height(benchTable)
 
        bType = string(benchTable.Measurement(ib));
        bAmp  = benchTable.MeasuredAmplitude_m(ib);
        bFreq = benchTable.SetFrequency_Hz(ib);
        bSetV = benchTable.SetAmplitude_V(ib);
        bX    = benchTable.SensorLocation_m(ib);
 
        % Skip invalid rows
        if ~isfinite(bAmp) || bAmp <= 0; continue; end
        if ~isfinite(bFreq) || ~isfinite(bSetV) || ~isfinite(bX); continue; end
 
        mtype_idx = 0;
        if bType == "Acoustic_Sensor";  mtype_idx = 1; end
        if bType == "Side_Camera";      mtype_idx = 2; end
        if mtype_idx == 0; continue; end   % skip unknown measurement types
 
        % Check whether this (x, f, V, type) combination already exists
        key_row = [bX, bFreq, bSetV, mtype_idx];
        found   = false;
        for ik = 1:size(acc_keys,1)
            if isequal(acc_keys(ik,:), key_row)
                acc_vals{ik}(end+1) = bAmp; %#ok<AGROW>
                found = true;
                break;
            end
        end
        if ~found
            acc_keys(end+1,:) = key_row; %#ok<AGROW>
            acc_vals{end+1}   = bAmp;
        end
 
    end % ib
 
    if isempty(acc_keys)
        warning('wm_build_refAmp_from_benchmark: no valid rows found in benchmark CSV.');
        return;
    end
 
    % ── Convert accumulated sums to mean ± SEM ───────────────────────────
    mtypes = {'Acoustic_Sensor','Side_Camera'};
    for ik = 1:size(acc_keys,1)
        vals = acc_vals{ik};
        n    = numel(vals);
        mu   = mean(vals);
        sem  = 0;
        if n > 1
            sem = std(vals,0) / sqrt(n);   % sample std / sqrt(n) = SEM
        end
 
        refAmp(end+1).x_m       = acc_keys(ik,1);    %#ok<AGROW>
        refAmp(end).freq_Hz     = acc_keys(ik,2);
        refAmp(end).volt_V      = acc_keys(ik,3);
        refAmp(end).amp_m       = mu;
        refAmp(end).amp_sem_m   = sem;
        refAmp(end).n           = n;
        refAmp(end).mtype       = mtypes{acc_keys(ik,4)};
    end
 
    hasBenchmark = true;
    fprintf('  Benchmark dictionary built: %d unique reference entries.\n', numel(refAmp));
 
    % ── Print table for verification (mirrors old console output) ────────
    fprintf('  Loading reference values into lookup table:\n');
    for ik = 1:numel(refAmp)
        r = refAmp(ik);
        if strcmp(r.mtype,'Acoustic_Sensor')
            tag = sprintf('x=%.2fm', r.x_m);
        else
            tag = sprintf('CAM_x=%.2fm', r.x_m);
        end
        fprintf('    Ref: %s f=%.2fHz A=%.3fV = %.6f m  (n=%d, SEM=%.6f m)\n', ...
            tag, r.freq_Hz, r.volt_V, r.amp_m, r.n, r.amp_sem_m);
    end
 
end % wm_build_refAmp_from_benchmark