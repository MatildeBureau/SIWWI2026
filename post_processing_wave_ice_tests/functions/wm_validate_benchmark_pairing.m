%% ==========================================================================
%  FUNCTION 3 — wm_validate_benchmark_pairing
%
%  Optional diagnostic — call once after wm_build_refAmp_from_benchmark
%  to verify that every queued file will find a reference.
%
%  INPUT
%    refAmp      — output of wm_build_refAmp_from_benchmark
%    hasBenchmark
%    pairMeta    — table from wm_load_pair_metadata_v2
%    camDataStore — struct from Section 2e
% ==========================================================================
function wm_validate_benchmark_pairing(refAmp, hasBenchmark, pairMeta, camDataStore)
 
    if ~hasBenchmark
        fprintf('  [VALIDATE] No benchmark loaded — skipping.\n');
        return;
    end
 
    fprintf('\n  --- Normalisation Validation ---\n');
    matched = 0;
    total   = 0;
    missing = {};
 
    % ── Acoustic files ────────────────────────────────────────────────────
    if ~isempty(pairMeta)
        for ipm = 1:height(pairMeta)
            fname = char(pairMeta.Acoustic_sensor_filename(ipm));
            sv    = pairMeta.Set_volt_V(ipm);
            sf    = pairMeta.Set_f_Hz(ipm);
 
            % Parse x from filename
            tok = regexp(fname, '_x([\d]+(?:p[\d]+)?)m', 'tokens','once');
            if isempty(tok); total = total+1; continue; end
            x_m = str2double(strrep(tok{1},'p','.'));
 
            total = total + 1;
            [ref_v, ~] = wm_get_ref_amp_numeric(refAmp, hasBenchmark, ...
                             "Acoustic_Sensor", x_m, sf, sv);
            if isfinite(ref_v)
                matched = matched + 1;
            else
                missing{end+1} = sprintf('Acoustic: %s  (x=%.2fm f=%.3fHz V=%.4fV)', ...
                                         fname, x_m, sf, sv); %#ok<AGROW>
            end
        end
    end
 
    % ── Camera files ─────────────────────────────────────────────────────
    if ~isempty(fieldnames(camDataStore))
        camKeys = fieldnames(camDataStore);
        for ick = 1:numel(camKeys)
            cd   = camDataStore.(camKeys{ick});
            total = total + 1;
            [ref_v, ~] = wm_get_ref_amp_numeric(refAmp, hasBenchmark, ...
                             "Side_Camera", cd.CamLoc_m, cd.SetFreq_Hz, cd.SetAmp_V);
            if isfinite(ref_v)
                matched = matched + 1;
            else
                missing{end+1} = sprintf('Camera: %s  (x=%.2fm f=%.3fHz V=%.4fV)', ...
                                         cd.TSfilename, cd.CamLoc_m, ...
                                         cd.SetFreq_Hz, cd.SetAmp_V); %#ok<AGROW>
            end
        end
    end
 
    fprintf('  Successfully paired: %d / %d queued files.\n', matched, total);
    if ~isempty(missing)
        fprintf('  [WARNING] %d files have no benchmark reference:\n', numel(missing));
        for im = 1:numel(missing)
            fprintf('    - %s\n', missing{im});
        end
    else
        fprintf('  All queued files found a matching reference.\n');
    end
    fprintf('  --------------------------------\n');
 
end % wm_validate_benchmark_pairing