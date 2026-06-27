%% =========================================================
%  ZS_decomposition_v1.m
%
%  PURPOSE
%  -------
%  Decomposes simultaneous wave-gauge measurements in a wave tank into
%  incident (left-travelling) and reflected (right-travelling) wave
%  components using the Zelt & Skjelbreia (1992) weighted least-squares
%  method (hereafter "ZS").  For each experimental condition
%  (wavemaker amplitude × frequency pair), the script produces:
%
%    - Incident amplitude     |a_L|  [m]
%    - Reflected amplitude    |a_R|  [m]
%    - Reflection coefficient R = |a_R| / |a_L|  [-]
%    - Measured wave steepness   ka = k |a_L|     [-]
%    - Associated uncertainty estimates for all quantities above
%    - Diagnostic denominator D of the ZS system  [-]
%    - Spatial amplitude profiles (ZS model vs. sensor data)
%    - Phasor diagram, R vs. frequency, R vs. steepness plots
%
%   ZELT & SKJELBREIA (1992) DECOMPOSITION
%  -------------------------------------------------
%  In a wave tank with one or more partially reflective boundaries,
%  the free-surface elevation at position x and angular frequency ω is
%  modelled as the superposition of a forward-propagating (incident)
%  and backward-propagating (reflected) plane wave:
%
%    η(x, t) = Re{ [a_L exp(+ikx) + a_R exp(-ikx)] exp(-iωt) }
%
%  where:
%    a_L  [m, complex] — complex amplitude of the incident wave
%    a_R  [m, complex] — complex amplitude of the reflected wave
%    k    [rad/m]      — wavenumber, satisfying the linear dispersion relation
%    ω    [rad/s]      — angular frequency, ω = 2π f
%    x    [m]          — distance from the wavemaker (positive toward beach)
%
%  Given P wave-gauge measurements A_j = DFT{η(x_j)}  [m, complex],
%  the system becomes (in matrix form):
%
%    M · c = A     where  M_jp = [exp(+ikx_j),  exp(-ikx_j)]
%                         c    = [a_L; a_R]
%
%  Because P ≥ 2 (over-determined), ZS solve via Weighted Least Squares:
%
%    c = (M^H W M)^{-1} M^H W A
%
%  The weight matrix W = diag(w_1, …, w_P) promotes gauge pairs whose
%  spacing avoids near-integer multiples of λ/2 (which cause rank
%  deficiency).  The ZS weight for gauge p is:
%
%    w_p = Σ_{q≠p}  sin²(k(x_p−x_q)) / [1 + (k(x_p−x_q)/π)²]
%
%  Conditioning is summarised by the scalar denominator:
%
%    D = 4 · Σ_{p>q}  w_p w_q sin²(k(x_p−x_q))
%
%  D → 0 signals near-singularity (gauge spacing ≈ nλ/2 for integer n).
%  Indicator: D < 0.01 → discard; 0.01 ≤ D < 0.50 → use with
%  caution; D ≥ 0.50 → well-conditioned.
%
%  DISPERSION RELATION
%  -------------------
%  The wavenumber k is found by Newton–Raphson iteration on the finite-
%  depth linear dispersion relation:
%
%    F(k) = g k tanh(k H) − ω²  = 0
%
%  where H [m] is the still-water depth and g [m/s²] is gravitational
%  acceleration.  Starting guess: k₀ = ω²/g  (deep-water approximation).
%
%  UNCERTAINTY PROPAGATION
%  -----------------------
%  Three independent error sources are propagated:
%
%  (1) Frequency uncertainty  δf  [Hz]
%      Each DFT bin has width Δf = Fs/N_ss, so the single-bin frequency
%      estimate is uncertain by ±Δf/2.  This propagates to k via:
%        δk = (4π ω / F'(k)) · δf
%      where F'(k) = g[tanh(kH) + kH sech²(kH)] is the dispersion derivative.
%
%  (2) Amplitude uncertainty  σ_A  [m]  (per gauge, added in quadrature)
%      (a) Sideband noise:  σ_A_noise = RMS of DFT spectrum in sideband
%          bins .
%      (b) Calibration noise:  σ_A_calib = √[(Err_a · V_rms)² + Err_b²]
%          where Err_a [m/V] and Err_b [m] are the 1-σ slope/intercept
%          errors from the calibration CSV, and V_rms [V] is the RMS
%          voltage in the steady-state window.
%      Total:  σ_A_total = √(σ_A_noise² + σ_A_calib²)
%
%      These propagate to a_L and a_R through the WLS gain matrix
%      C_gain = (M^H W M)^{-1} M^H W  [dimensionless, 2×P]:
%        δ_aL_ampl = σ_A_max · ‖C_gain(1,:)‖
%        δ_aR_ampl = σ_A_max · ‖C_gain(2,:)‖
%      (conservative bound: use the maximum single-gauge σ_A across all P gauges)
%
%  (3) Sensor position uncertainty  dx_sensor  [m]
%      Each gauge position x_p is known only to within dx_sensor (ruler
%      placement uncertainty).  The sensitivity ∂a_L/∂x_p is estimated
%      by finite difference (step dx_pert):
%        (∂a_L/∂x_p) ≈ [a_L(x_p+dx_pert) − a_L(x_p−dx_pert)] / (2 dx_pert)
%      Assuming uncorrelated position errors of std dx_sensor:
%        δ_aL_pos² = Σ_p |∂a_L/∂x_p|² · dx_sensor²
%
%      Combined amplitude uncertainty in quadrature:
%        δ_aL = √(δ_aL_ampl² + δ_aL_pos²)
%        δ_aR = √(δ_aR_ampl² + δ_aR_pos²)
%
%      Uncertainty on R = |a_R|/|a_L|:
%        δR = R · √[(δ_aR/|a_R|)² + (δ_aL/|a_L|)²]
%
%      Uncertainty on measured steepness ak = k|a_L|:
%        δ(ak) = √[(|a_L| δk)² + (k δ_aL)²]
%
%  INPUT FILES
%  -----------
%  1. Raw acoustic sensor CSVs   — two-column (time [s], voltage [V])
%  2. acoustic_sensors_calib.csv — calibration coefficients per sensor
%       Columns: Mode, Source, Slope_a [m/V], Err_a [m/V],
%                Intercept_b [m], Err_b [m], Uncert_Method
%  3. Metadata_sensors_200526.csv — sensor IDs and x-positions [m]
%  4. Metadata_benchmark_200526.csv — experimental conditions
%       Must include columns: Mode, Acoustic_sensor_filename,
%       Set_f_Hz [Hz], Set_volt_V [V], ka [-]
%
%  OUTPUT
%  ------
%  ZS_Reflection_Results_v5.csv  — one row per condition, all quantities
%  PNG + PDF figures 
%
%  REFERENCE
%  ---------
%  Zelt, J.A. & Skjelbreia, J.E. (1992). Estimating incident and
%  reflected wave fields using an arbitrary number of wave gauges.
%  Proc. 23rd Int. Conf. Coastal Engineering, ASCE, 777–789.
%
%  atilde
%  June 2026
% =========================================================

clear; clc; close all;

%% =========================================================
%  PLOT STYLE
% =========================================================
FS_ax    = 14;   % axis label font size [pt]
FS_tick  = 13;   % tick label font size [pt]
FS_leg   = 11;   % legend font size     [pt]
FS_title = 13;   % subplot title font size [pt]
LW       = 2.0;  % default line width   [pt]
MS       = 9;    % default marker size  [pt]

%% =========================================================
%  SECTION 1 — USER CONFIGURATION
% =========================================================

% ----- File paths -----
raw_data_dir       = 'E:\SIWWI2026\200526\wm_test_results_200526\';
calib_csv          = 'E:\SIWWI2026\200526\acoustic_sensors_calib.csv';
sensor_meta_csv    = 'E:\SIWWI2026\200526\Metadata_sensors_200526.csv';
benchmark_meta_csv = 'E:\SIWWI2026\200526\Metadata_benchmark_200526.csv';
output_dir         = 'E:\SIWWI2026\200526\ZS_test\';

% ----- Acquisition mode -----
acq_mode = 'HIGH';

% ----- Physical constants -----
h_water = 0.3;     % Still-water depth H  [m]
g       = 9.81;    % Gravitational acceleration  [m/s²]

% ----- Steady-state window -----
% The wavemaker takes ~40 s to establish a stationary wave field.
% Only data within [t_start_ss, t_end_ss] are used for the DFT.
t_start_ss = 40;   % Start of steady-state window  [s]
t_end_ss   = 100;  % End   of steady-state window  [s]
%   If t_end_ss > length of record, the full record after t_start_ss is used.

% ----- Windowing -----
% A Hann window reduces spectral leakage from the finite record length.
% Set false to use a rectangular  window instead.
use_hann_window = true;

% ----- Newton–Raphson dispersion solver -----
NR_maxiter = 50;    % Maximum iterations  [-]
NR_tol     = 1e-10; % Convergence tolerance on k  [rad/m]

% ----- Condition grouping tolerances -----
% Conditions with amplitude within amp_tol_group [V] AND frequency
% within freq_tol_group [Hz] of a nominal (A_set, f_set) pair are
% grouped together for the ZS solve.
amp_tol_group  = 0.05;   % Amplitude grouping tolerance  [V]
freq_tol_group = 0.05;   % Frequency grouping tolerance  [Hz]
ka_tol_group   = 0.005;  % Steepness grouping tolerance  [-]


% ----- Sideband noise estimation -----
% The noise floor of the DFT spectrum is estimated from "sideband" bins:
% bins in the range [1, f_max_sb_factor × f_set] that are more than
% n_sb_guard bins away from the signal peak.
n_sb_guard      = 5;    % Guard band around signal peak  [bins]
f_max_sb_factor = 3.0;  % Upper frequency limit as multiple of f_set  [-]
n_sb_min        = 10;   % Minimum number of sideband bins needed;
                        %   if fewer are available, σ_A_noise is set to 0.

% ----- Sensor position uncertainty -----
% 1-σ uncertainty on the physical x-position of each sensor,
% estimated from ruler placement precision.
dx_sensor = 0.05;     % Sensor position uncertainty  [m]  (1-σ)
dx_pert   = 0.001;    % Finite-difference step for WLS sensitivity  [m]
%   dx_pert must be ≪ λ but ≫ numerical noise (~1e-12).

% ----- Flags -----
debug_sensor_plots = false;  % If true: plot raw time series + spectrum per sensor
save_fig     = true;          % If true: export figures to output_dir
save_results = true;          % If true: export results CSV to output_dir

%% =========================================================
%  SECTION 2 — LOAD METADATA AND CALIBRATION
% =========================================================
disp('--- Section 2: Loading metadata and calibration ---');

% ----- 2a. Sensor positions -----
% Metadata_sensors CSV: column 1 = sensor ID (integer 1–6),
%                       column 3 = x-position measured from wavemaker [m].
meta_raw   = readtable(sensor_meta_csv, 'TextType', 'string');
sensor_ids = double(meta_raw{:, 1});  % Sensor numbers [1–6], integer
sensor_x   = double(meta_raw{:, 3});  % x-positions  [m]
n_sensors  = length(sensor_ids);      % Total number of sensors  [-]

fprintf('  Loaded %d sensor positions\n', n_sensors);
for ip = 1:n_sensors
    fprintf('    Sensor%d   x = %.2f m\n', sensor_ids(ip), sensor_x(ip));
end

% ----- 2b. Calibration coefficients + uncertainties -----
% for acoustic sensors, the calibration converts voltage to surface elevation:
%   η [m] = Slope_a [m/V] · V [V] + Intercept_b [m]
%
% Err_a [m/V] and Err_b [m] are the 1-σ uncertainties on Slope_a and
% Intercept_b respectively, derived from the calibration regression.
calib       = readtable(calib_csv, 'TextType', 'string');
calib_slope = NaN(6, 1);   % Calibration slope   a  [m/V]
calib_intc  = NaN(6, 1);   % Calibration intercept b [m]
calib_err_a = NaN(6, 1);   % 1-σ uncertainty on slope      [m/V]
calib_err_b = NaN(6, 1);   % 1-σ uncertainty on intercept  [m]

for ip = 1:6
    src = sprintf('Sensor%d', ip);
    row = strcmp(calib.Mode, acq_mode) & strcmp(calib.Source, src);
    if any(row)
        calib_slope(ip) = calib.Slope_a(row);
        calib_intc(ip)  = calib.Intercept_b(row);
        calib_err_a(ip) = calib.Err_a(row);
        calib_err_b(ip) = calib.Err_b(row);
    else
        warning('No calibration found for mode %s, Sensor%d', acq_mode, ip);
    end
end
fprintf('  Calibration loaded for mode %s\n', acq_mode);

% ----- 2c. Benchmark metadata -----
% The benchmark CSV lists every experimental run.
% Key columns used here:
%   Mode                     — acquisition gain mode (string)
%   Acoustic_sensor_filename — base filename of the raw CSV (no extension)
%   Set_f_Hz                 — commanded wavemaker frequency  [Hz]
%   Set_volt_V               — commanded wavemaker amplitude  [V]  (stroke)
%   ka                       — commanded wave steepness  [-]
bench = readtable(benchmark_meta_csv, 'TextType', 'string');
bench = bench(strcmp(bench.Mode, acq_mode), :);   % keep only current mode
fprintf('  Benchmark metadata: %d rows\n', height(bench));

%% =========================================================
%  SECTION 3 — BUILD FILE LIST
%  For every row in the benchmark metadata, locate the
%  corresponding raw data file and parse the sensor number
%  and x-position from the filename.
% =========================================================
disp('--- Section 3: Building file list ---');

n_bench         = height(bench);
file_paths_all  = strings(n_bench, 1);   % Full path to each raw CSV
file_exists     = false(n_bench, 1);     % True if file was found on disk
parsed_sensor_b = NaN(n_bench, 1);       % Sensor number parsed from filename  [-]
parsed_x_b      = NaN(n_bench, 1);       % x-position parsed from filename  [m]
f_set_b         = NaN(n_bench, 1);       % Commanded frequency from metadata  [Hz]
A_set_b         = NaN(n_bench, 1);       % Commanded amplitude from metadata  [V]
ka_set_b        = NaN(n_bench, 1);       % Commanded steepness from metadata  [-]

for ib = 1:n_bench

    % Build the expected filename 
    base_name = strtrim(bench.Acoustic_sensor_filename(ib));
    fname = base_name + ".csv";
    if endsWith(base_name, '.csv'); fname = base_name; end

    % Search recursively under raw_data_dir first, then flat
    found = dir(fullfile(raw_data_dir, '**', fname));
    if isempty(found); found = dir(fullfile(raw_data_dir, fname)); end

    if ~isempty(found)
        file_paths_all(ib) = fullfile(string(found(1).folder), string(found(1).name));
        file_exists(ib)    = true;
    else
        fprintf('  [NOT FOUND] %s\n', fname);
    end

    % Parse sensor number from filename token '_SensorN_'
    tok_s = regexp(char(base_name), '_Sensor(\d+)_', 'tokens', 'once');
    if ~isempty(tok_s); parsed_sensor_b(ib) = str2double(tok_s{1}); end

    % Parse x-position from filename token '_xXpYm_'  (dots replaced by 'p')
    tok_x = regexp(char(base_name), '_x([\dp]+)m_', 'tokens', 'once');
    if ~isempty(tok_x); parsed_x_b(ib) = str2double(strrep(tok_x{1}, 'p', '.')); end

    % Store set conditions from metadata
    f_set_b(ib)  = bench.Set_f_Hz(ib);    % Commanded frequency  [Hz]
    A_set_b(ib)  = bench.Set_volt_V(ib);  % Commanded amplitude  [V]
    ka_set_b(ib) = bench.ka(ib);           % Commanded steepness  [-]
end
fprintf('  Files found: %d / %d\n', sum(file_exists), n_bench);

%% =========================================================
%  SECTION 4 — GROUP CONDITIONS
%  Each unique (A_set, f_set) pair defines one experimental
%  condition.  All sensor files recorded under the same condition
%  are grouped together so that the ZS solve can use all P gauges
%  simultaneously.
% =========================================================
disp('--- Section 4: Grouping conditions ---');

% Round to avoid floating-point mismatches between nominally equal values
f_rounded = round(f_set_b(file_exists),  4);   % Rounded set frequency  [Hz]
A_rounded = round(A_set_b(file_exists),  3);   % Rounded set amplitude  [V]
ka_b_fe   = ka_set_b(file_exists);              % Set steepness for found files  [-]

conditions = unique([A_rounded, f_rounded], 'rows');  % [n_cond × 2] matrix
n_cond     = size(conditions, 1);
fprintf('  Found %d unique (A_set, f_set) conditions\n', n_cond);

%% =========================================================
%  SECTION 5 — MAIN LOOP: ZS DECOMPOSITION + UNCERTAINTIES
%
%  For each condition (ic):
%    1. Collect all sensor files belonging to that condition.
%    2. Load each raw voltage time series and convert to η [m].
%    3. Window and DFT the steady-state segment to get the
%       complex amplitude A_jp at the commanded frequency.
%    4. Estimate per-gauge amplitude uncertainty σ_A_total.
%    5. Solve the Newton–Raphson dispersion relation for k.
%    6. Build the ZS weight matrix W and denominator D.
%    7. Solve the WLS system for a_L and a_R.
%    8. Propagate uncertainties to δ_aL, δ_aR, δR, δ(ak).
% =========================================================
disp('--- Section 5: ZS decomposition ---');

% ---- Pre-allocate output arrays (one entry per condition) ----
out_A_set    = NaN(n_cond, 1);   % Commanded wavemaker amplitude  [V]
out_f_set    = NaN(n_cond, 1);   % Commanded frequency  [Hz]
out_ka_set   = NaN(n_cond, 1);   % Commanded wave steepness  [-]  (from CSV)
out_f_meas   = NaN(n_cond, 1);   % Median measured frequency across gauges  [Hz]
out_k        = NaN(n_cond, 1);   % Wavenumber from dispersion relation  [rad/m]
out_lambda   = NaN(n_cond, 1);   % Wavelength λ = 2π/k  [m]
out_ak       = NaN(n_cond, 1);   % Measured steepness ak = k|a_L|  [-]  (reference only)
out_aL_mag   = NaN(n_cond, 1);   % Incident wave amplitude |a_L|  [m]
out_aR_mag   = NaN(n_cond, 1);   % Reflected wave amplitude |a_R|  [m]
out_aL_phase = NaN(n_cond, 1);   % Phase of a_L  [rad]
out_aR_phase = NaN(n_cond, 1);   % Phase of a_R  [rad]
out_R        = NaN(n_cond, 1);   % Reflection coefficient R = |a_R|/|a_L|  [-]
out_D        = NaN(n_cond, 1);   % ZS denominator D (conditioning diagnostic)  [-]
out_Ngauge   = NaN(n_cond, 1);   % Number of valid gauges P used in solve  [-]

% Complex amplitudes stored for spatial profile plotting
aL_complex  = NaN(n_cond, 1) + 1i * NaN(n_cond, 1);  % a_L [m, complex]
aR_complex  = NaN(n_cond, 1) + 1i * NaN(n_cond, 1);  % a_R [m, complex]

% Per-gauge amplitude storage for spatial profile scatter points
amp_spatial = NaN(n_cond, n_sensors);  % |A_jp| per sensor per condition  [m]
x_spatial   = NaN(n_cond, n_sensors);  % x-positions used  [m]

% ---- Uncertainty output arrays ----
out_delta_f        = NaN(n_cond, 1);   % 1-σ frequency uncertainty  [Hz]
out_delta_k        = NaN(n_cond, 1);   % 1-σ wavenumber uncertainty  [rad/m]
out_delta_aL       = NaN(n_cond, 1);   % 1-σ uncertainty on |a_L|  [m]
out_delta_aR       = NaN(n_cond, 1);   % 1-σ uncertainty on |a_R|  [m]
out_delta_R        = NaN(n_cond, 1);   % 1-σ uncertainty on R  [-]
out_delta_ak       = NaN(n_cond, 1);   % 1-σ uncertainty on measured ka  [-]
out_sigma_A_median = NaN(n_cond, 1);   % Median total σ_A across gauges  [m]

% Index into the file_exists-filtered arrays
fe_idx = find(file_exists);

% ==============================================================
%  OUTER LOOP: iterate over each unique experimental condition
% ==============================================================
for ic = 1:n_cond

    A_set_c = conditions(ic, 1);   % Commanded amplitude for this condition  [V]
    f_set_c = conditions(ic, 2);   % Commanded frequency for this condition  [Hz]
    out_A_set(ic) = A_set_c;
    out_f_set(ic) = f_set_c;

    % Find which rows in the file_exists subset belong to this condition
    mask_c    = abs(A_rounded - A_set_c) < amp_tol_group & ...
                abs(f_rounded - f_set_c) < freq_tol_group;
    idx_in_fe = find(mask_c);   % indices into the file_exists-filtered arrays

    if length(idx_in_fe) < 2
        % Need at least 2 gauges for an over-determined system
        fprintf('  [SKIP] A=%.3fV f=%.3fHz: only %d file(s)\n', ...
            A_set_c, f_set_c, length(idx_in_fe));
        continue
    end

    % All files in one condition share the same commanded steepness.
    % Use median to guard against rounding artefacts in the CSV.
    ka_vals = ka_b_fe(idx_in_fe);
    out_ka_set(ic) = median(ka_vals);   % Commanded steepness  [-]

    fprintf('\n  Condition %d/%d:  A=%.3fV  f=%.4fHz  ka_set=%.3f\n', ...
        ic, n_cond, A_set_c, f_set_c, out_ka_set(ic));

    % Accumulators for the P valid gauges in this condition
    x_p       = [];   % Sensor x-positions  [m]
    A_jp      = [];   % Complex DFT amplitudes at f_set  [m, complex]
    f_meas_p  = [];   % DFT bin frequency (one per gauge)  [Hz]
    delta_f_p = [];   % Half-bin frequency uncertainty (one per gauge)  [Hz]
    sigma_A_p = [];   % Total per-gauge amplitude uncertainty  [m]

    % ==============================================================
    %  INNER LOOP: iterate over sensor files for this condition
    % ==============================================================
    for ii = 1:length(idx_in_fe)

        ib     = fe_idx(idx_in_fe(ii));
        fpath  = char(file_paths_all(ib));
        sens_n = parsed_sensor_b(ib);   % Sensor number (1–6)  [-]
        x_p_c  = parsed_x_b(ib);        % Sensor x-position  [m]

        % Skip if sensor number or position could not be parsed
        if isnan(sens_n) || isnan(x_p_c); continue; end
        % Skip if sensor number is out of range or calibration is missing
        if sens_n < 1 || sens_n > 6 || isnan(calib_slope(sens_n)); continue; end

        % ----- Load raw voltage time series -----
        try
            raw = readmatrix(fpath, 'FileType', 'delimitedtext');
        catch
            continue
        end
        if size(raw, 2) < 2 || size(raw, 1) < 1000; continue; end

        t_raw = raw(:, 1);   % Time vector  [s]
        V_raw = raw(:, 2);   % Raw voltage  [V]

        % Sampling frequency estimated from mean time step  [Hz = 1/s]
        Fs = 1 / mean(diff(t_raw));

        % ----- Apply calibration: V [V] → η [m] -----
        eta = calib_slope(sens_n) * V_raw + calib_intc(sens_n);   % [m]

        % ----- Steady-state window -----
        t_end_use = t_raw(end);
        if t_end_ss > 0; t_end_use = min(t_end_ss, t_raw(end)); end
        ss = (t_raw >= t_start_ss) & (t_raw <= t_end_use);
        if sum(ss) < round(Fs * 3); continue; end   % need at least 3 s of data

        % Remove mean (DC offset) so the DFT picks up oscillatory part only
        eta_ss = eta(ss) - mean(eta(ss));   % Mean-removed surface elevation  [m]
        V_ss   = V_raw(ss);                  % Voltage in steady-state window  [V]
        N_ss   = length(eta_ss);             % Number of samples in window  [-]

        % ----- Identify the DFT bin closest to f_set -----
        % DFT bin index for frequency f:  k_bin = round(f * N_ss / Fs)
        k_bin = round(f_set_c * N_ss / Fs);          % DFT bin index  [-]
        k_bin = max(1, min(k_bin, floor(N_ss / 2)));  % clamp to valid range

        % Actual frequency of that bin  [Hz]
        f_bin = k_bin * Fs / N_ss;

        % Frequency uncertainty = half the DFT bin width  [Hz]
        delta_f_bin = Fs / (2 * N_ss);

        % ----- Apply Hann window (optional) -----
        % The Hann window is w(n) = 0.5 – 0.5 cos(2πn/(N–1)).
        % N_eff = sum(w) is the effective number of samples, used to
        % normalise the DFT so that |A_jp| ≈ true single-sided amplitude.
        if use_hann_window
            win   = hann(N_ss);       % Hann window coefficients  [-]
            N_eff = sum(win);          % Effective sample count  [-]
        else
            win   = ones(N_ss, 1);
            N_eff = N_ss;
        end
        eta_w = eta_ss .* win;   % Windowed signal  [m]

        % ----- Single-bin DFT at k_bin -----
        % The complex amplitude of the one-sided spectrum at bin k_bin:
        %   A_jp = (2/N_eff) · Σ_{n=0}^{N-1} η_w(n) · exp(-2πi k_bin n / N)
        % Factor 2 gives the one-sided (positive-frequency) amplitude.
        n_vec  = (0:N_ss - 1)';
        e_vec  = exp(-2 * pi * 1i * k_bin .* n_vec / N_ss);
        A_jp_c = (2 / N_eff) * sum(eta_w .* e_vec);   % Complex amplitude  [m]

        % ----- (A) Sideband noise estimate -----
        % Compute the full DFT spectrum and identify "sideband" bins.
        % These are bins in [1, f_max_sb_factor·f_set] that are
        % sufficiently far from the signal peak (guard band ±n_sb_guard).
        % The RMS of sideband amplitudes estimates the noise floor.
        Y_full   = abs(fft(eta_w)) * (2 / N_eff);      % One-sided amplitude spectrum  [m]
        k_max_sb = min(floor(f_max_sb_factor * f_set_c * N_ss / Fs), floor(N_ss / 2));
        k_max_sb = max(k_max_sb, k_bin + n_sb_guard + 1);
        k_all_sb = 1:k_max_sb;
        k_sb     = k_all_sb(abs(k_all_sb - k_bin) > n_sb_guard);  % Sideband bin indices

        if length(k_sb) >= n_sb_min
            sigma_A_noise = rms(Y_full(k_sb + 1));   % Noise amplitude std  [m]
        else
            sigma_A_noise = 0;   % Insufficient sideband bins — treat as zero
        end

        % ----- (B) Calibration uncertainty -----
        %   σ_A_calib = √[(Err_a · V_rms)² + Err_b²]
        %  follows from the calibration law η = a·V + b 
        V_rms         = rms(V_ss - mean(V_ss));   % RMS voltage (AC component)  [V]
        err_a_c       = calib_err_a(sens_n);        % 1-σ slope error  [m/V]
        err_b_c       = calib_err_b(sens_n);        % 1-σ intercept error  [m]
        sigma_A_calib = sqrt((err_a_c * V_rms)^2 + err_b_c^2);   % [m]

        % ----- Total per-gauge amplitude uncertainty  -----
        sigma_A_total = sqrt(sigma_A_noise^2 + sigma_A_calib^2);   % [m]

        % ----- Store this gauge's data -----
        x_p       = [x_p;       x_p_c];           %#ok<AGROW>  [m]
        A_jp      = [A_jp;      A_jp_c];           %#ok<AGROW>  [m, complex]
        f_meas_p  = [f_meas_p;  f_bin];            %#ok<AGROW>  [Hz]
        delta_f_p = [delta_f_p; delta_f_bin];      %#ok<AGROW>  [Hz]
        sigma_A_p = [sigma_A_p; sigma_A_total];    %#ok<AGROW>  [m]

        % Record |A_jp| in the spatial amplitude matrix (indexed by sensor metadata position)
        [~, meta_idx] = min(abs(sensor_x - x_p_c));
        amp_spatial(ic, meta_idx) = abs(A_jp_c);   % [m]
        x_spatial(ic, meta_idx)   = x_p_c;          % [m]

        fprintf(['    Sensor%d x=%4.1fm |A|=%6.3fmm phase=%+6.1fdeg' ...
                 ' f_bin=%.4fHz sA_noise=%.4fmm sA_calib=%.4fmm\n'], ...
            sens_n, x_p_c, abs(A_jp_c) * 1e3, angle(A_jp_c) * 180 / pi, ...
            f_bin, sigma_A_noise * 1e3, sigma_A_calib * 1e3);

        % ----- Optional debug plots -----
        if debug_sensor_plots
            figure('Name', sprintf('Debug S%d A%.2f f%.2f', sens_n, A_set_c, f_set_c));
            subplot(2, 1, 1);
            plot(t_raw(ss), eta_ss * 1e3);
            xlabel('t (s)'); ylabel('\eta (mm)'); grid on;
            title(sprintf('Sensor%d x=%.1fm A=%.2fV f=%.3fHz', ...
                sens_n, x_p_c, A_set_c, f_set_c));
            subplot(2, 1, 2);
            f_ax = (0:floor(N_ss / 2) - 1) * Fs / N_ss;
            plot(f_ax, Y_full(1:floor(N_ss / 2)) * 1e3, 'b');
            hold on;
            if length(k_sb) >= n_sb_min
                plot(k_sb * Fs / N_ss, Y_full(k_sb + 1) * 1e3, 'r.', 'MarkerSize', 4);
            end
            xline(f_bin, 'k--');
            xlabel('f (Hz)'); ylabel('|A| (mm)');
            xlim([0, min(f_max_sb_factor * f_set_c * 1.2, Fs / 2)]);
            legend('spectrum', 'sideband', 'target f'); grid on;
        end

    end   % ---- end inner sensor loop ----

    % Number of valid gauges successfully processed for this condition
    P = length(x_p);   % [-]
    out_Ngauge(ic) = P;

    if P < 2
        fprintf('  [SKIP] Only %d valid sensor(s) — need ≥ 2\n', P);
        continue
    end

    % ---- Frequency and its uncertainty ----
    f_use           = median(f_meas_p);    % Median DFT bin frequency across gauges  [Hz]
    out_f_meas(ic)  = f_use;
    delta_f_use     = median(delta_f_p);   % Conservative: median half-bin width  [Hz]
    out_delta_f(ic) = delta_f_use;
    out_sigma_A_median(ic) = median(sigma_A_p);   % Median total gauge uncertainty  [m]

    % ---- Solve dispersion relation by Newton–Raphson ----
    % Find k such that F(k) = g k tanh(kH) − ω² = 0.
    % Starting guess: deep-water approximation k₀ = ω²/g.
    omega = 2 * pi * f_use;    % Angular frequency  [rad/s]
    k_est = omega^2 / g;       % Initial guess  [rad/m]

    for iter = 1:NR_maxiter
        th    = tanh(k_est * h_water);                      % tanh(kH)  [-]
        F_k   = g * k_est * th - omega^2;                   % F(k)  [m/s²]
        Fp_k  = g * (th + k_est * h_water * (1 - th^2));   % F'(k) [m²/s²]
        k_new = k_est - F_k / Fp_k;                         % Newton step
        if abs(k_new - k_est) < NR_tol; break; end
        k_est = k_new;
    end

    k_c = k_est;            % Converged wavenumber  [rad/m]
    L_c = 2 * pi / k_c;    % Wavelength  [m]
    out_k(ic)      = k_c;
    out_lambda(ic) = L_c;

    % ---- Propagate frequency uncertainty to wavenumber uncertainty ----
    % From implicit differentiation of F(k) = 0:
    %   dk/dω = 2ω / F'(k)
    % δk = |dk/dω| · |dω/df| · δf = (4πω / F'(k)) · δf
    th_c   = tanh(k_c * h_water);
    Fp_k_c = g * (th_c + k_c * h_water * (1 - th_c^2));   % F'(k)  [m²/s²]
    dk_df  = (4 * pi * omega) / Fp_k_c;                     % |dk/df|  [s/m]
    delta_k = dk_df * delta_f_use;                           % 1-σ wavenumber uncertainty  [rad/m]
    out_delta_k(ic) = delta_k;

    fprintf('  k=%.4f rad/m  lambda=%.3fm  kh=%.3f  dk=%.5f rad/m\n', ...
        k_c, L_c, k_c * h_water, delta_k);

    % ---- Compute ZS weights w_p ----
    % w_p quantifies how much information gauge p contributes when
    % combined with all other gauges
    %   w_p = Σ_{q≠p} sin²(k Δx_{pq}) / [1 + (k Δx_{pq}/π)²]
    W_p = zeros(P, 1);   % Weight vector  [-]
    for ip = 1:P
        for iq = 1:P
            if ip == iq; continue; end
            dphi    = k_c * (x_p(ip) - x_p(iq));   % Phase difference k Δx  [rad]
            W_p(ip) = W_p(ip) + sin(dphi)^2 / (1 + (dphi / pi)^2);
        end
    end
    if all(W_p == 0); W_p = ones(P, 1); end   % Fallback: equal weights
    W_mat = diag(W_p);   % Weight matrix  [-]

    % ---- Compute ZS denominator D ----
    % D is a scalar summary of system conditioning.
    % D = 4 · Σ_{p>q} w_p w_q sin²(k(x_p−x_q))
    % D → 0 ⟹ near-singular; D ≥ 0.5 ⟹ well-conditioned.
    D_val = 0;   % [-]
    for ip = 1:P
        for iq = 1:ip - 1
            dphi  = k_c * (x_p(ip) - x_p(iq));
            D_val = D_val + W_p(ip) * W_p(iq) * sin(dphi)^2;
        end
    end
    D_val     = 4 * D_val;
    out_D(ic) = D_val;

    if D_val < 0.01
        fprintf('  D=%.4f  [WARNING: near-singular — result unreliable]\n', D_val);
        continue   % Skip the WLS solve for this condition
    elseif D_val < 0.5
        fprintf('  D=%.4f  [CAUTION: moderately conditioned]\n', D_val);
    else
        fprintf('  D=%.4f  [well-conditioned]\n', D_val);
    end

    % ---- WLS solve: find a_L and a_R ----
    % Model matrix M  [P × 2, complex]:
    %   M_p1 = exp(+ikx_p)  (incident, forward-propagating)
    %   M_p2 = exp(-ikx_p)  (reflected, backward-propagating)
    % WLS normal equations:  (M^H W M) c = M^H W A_jp
    phi_p = k_c * x_p;                         % Phase at each gauge  [rad]
    M     = [exp(+1i * phi_p), exp(-1i * phi_p)];  % Model matrix  [P × 2, complex]
    LHS   = M' * W_mat * M;                    % 2×2 normal equation matrix
    RHS   = M' * W_mat * A_jp;                 % 2×1 right-hand side  [m, complex]
    x_sol = LHS \ RHS;                         % Least-squares solution  [m, complex]

    a_L = x_sol(1);   % Incident (forward) complex amplitude  [m]
    a_R = x_sol(2);   % Reflected (backward) complex amplitude  [m]

    out_aL_mag(ic)   = abs(a_L);        % [m]
    out_aR_mag(ic)   = abs(a_R);        % [m]
    out_aL_phase(ic) = angle(a_L);      % [rad]
    out_aR_phase(ic) = angle(a_R);      % [rad]
    out_R(ic)        = abs(a_R) / abs(a_L);   % Reflection coefficient  [-]
    aL_complex(ic)   = a_L;             % [m, complex] — kept for spatial plots
    aR_complex(ic)   = a_R;             % [m, complex]
    out_ak(ic)       = k_c * abs(a_L);  % Measured wave steepness  [-]  (reference)

    % ---- WLS gain matrix C_gain ----
    % C_gain = (M^H W M)^{-1} M^H W   [2 × P, complex]
    % Used to propagate amplitude uncertainty: δ_aL = σ_A · ‖C_gain(1,:)‖
    C_gain = LHS \ (M' * W_mat);   % [2 × P]

    % ----------------------------------------------------------
    %  UNCERTAINTY SOURCE (A): AMPLITUDE NOISE + CALIBRATION
    %
    %  σ_A_p contains the total per-gauge amplitude uncertainty (noise
    %  + calibration) computed above. 
    %
    %  Assuming gauges are independent (uncorrelated noise), the
    %  contribution to a_L is bounded above by:
    %    δ_aL_ampl ≤ σ_A_max · ‖C_gain(1,:)‖
    % ----------------------------------------------------------
    sigma_A_use   = max(sigma_A_p);                       % [m]
    delta_aL_ampl = sigma_A_use * norm(C_gain(1, :));     % [m]
    delta_aR_ampl = sigma_A_use * norm(C_gain(2, :));     % [m]

    % ----------------------------------------------------------
    %  UNCERTAINTY SOURCE (B): SENSOR POSITION ERRORS
    %
    %  For each gauge p, perturb its x-position by ±dx_pert [m],
    %  re-run the full WLS solve (including recomputing W_p since
    %  the weights also depend on the positions), and compute the
    %  finite-difference derivative:
    %    ∂a_L/∂x_p ≈ [a_L(x_p + δ) − a_L(x_p − δ)] / (2δ)
    %
    %  Assuming independent 1-σ position errors dx_sensor at each gauge:
    %    δ_aL_pos² = Σ_p |∂a_L/∂x_p|² · dx_sensor²
    % ----------------------------------------------------------
    var_aL_pos = 0;   % Running variance accumulator for a_L  [m²]
    var_aR_pos = 0;   % Running variance accumulator for a_R  [m²]

    for ip = 1:P
        % Forward and backward perturbed position arrays
        x_fwd = x_p;  x_fwd(ip) = x_p(ip) + dx_pert;
        x_bwd = x_p;  x_bwd(ip) = x_p(ip) - dx_pert;

        % Recompute weights for the perturbed positions
        Wp_fwd = zeros(P, 1);
        Wp_bwd = zeros(P, 1);
        for ipp = 1:P
            for iqq = 1:P
                if ipp == iqq; continue; end
                dpf = k_c * (x_fwd(ipp) - x_fwd(iqq));
                Wp_fwd(ipp) = Wp_fwd(ipp) + sin(dpf)^2 / (1 + (dpf / pi)^2);
                dpb = k_c * (x_bwd(ipp) - x_bwd(iqq));
                Wp_bwd(ipp) = Wp_bwd(ipp) + sin(dpb)^2 / (1 + (dpb / pi)^2);
            end
        end
        if all(Wp_fwd == 0); Wp_fwd = ones(P, 1); end
        if all(Wp_bwd == 0); Wp_bwd = ones(P, 1); end

        % Build perturbed model matrices and solve WLS
        M_fwd  = [exp(+1i * k_c * x_fwd), exp(-1i * k_c * x_fwd)];
        M_bwd  = [exp(+1i * k_c * x_bwd), exp(-1i * k_c * x_bwd)];
        Wm_fwd = diag(Wp_fwd);
        Wm_bwd = diag(Wp_bwd);

        x_fwd_sol = (M_fwd' * Wm_fwd * M_fwd) \ (M_fwd' * Wm_fwd * A_jp);
        x_bwd_sol = (M_bwd' * Wm_bwd * M_bwd) \ (M_bwd' * Wm_bwd * A_jp);

        % Central finite-difference sensitivities  [m/m = dimensionless in modulus, but complex]
        daL_dxp = (x_fwd_sol(1) - x_bwd_sol(1)) / (2 * dx_pert);   % [m/m]
        daR_dxp = (x_fwd_sol(2) - x_bwd_sol(2)) / (2 * dx_pert);   % [m/m]

        % Accumulate variance  [m²]
        var_aL_pos = var_aL_pos + abs(daL_dxp)^2 * dx_sensor^2;
        var_aR_pos = var_aR_pos + abs(daR_dxp)^2 * dx_sensor^2;
    end

    delta_aL_pos = sqrt(var_aL_pos);   % Position contribution to σ_aL  [m]
    delta_aR_pos = sqrt(var_aR_pos);   % Position contribution to σ_aR  [m]

    % ---- Combine both uncertainty sources in quadrature ----
    delta_aL = sqrt(delta_aL_ampl^2 + delta_aL_pos^2);   % Total 1-σ on |a_L|  [m]
    delta_aR = sqrt(delta_aR_ampl^2 + delta_aR_pos^2);   % Total 1-σ on |a_R|  [m]
    out_delta_aL(ic) = delta_aL;
    out_delta_aR(ic) = delta_aR;

    % ---- Uncertainty on reflection coefficient R = |a_R| / |a_L| ----
    % Standard propagation for a ratio:
    %   δR/R = √[(δ|a_R|/|a_R|)² + (δ|a_L|/|a_L|)²]
    if abs(a_L) > 0 && abs(a_R) > 0
        delta_R = out_R(ic) * sqrt((delta_aR / abs(a_R))^2 + (delta_aL / abs(a_L))^2);
    else
        delta_R = NaN;
    end
    out_delta_R(ic) = delta_R;   % 1-σ on R  [-]

    % ---- Uncertainty on measured steepness ak = k|a_L| ----
    % Standard propagation for a product:
    %   δ(ak) = √[(|a_L| δk)² + (k δ|a_L|)²]
    if isfinite(delta_aL)
        delta_ak = sqrt((abs(a_L) * delta_k)^2 + (k_c * delta_aL)^2);
    else
        delta_ak = NaN;
    end
    out_delta_ak(ic) = delta_ak;   % 1-σ on measured ak  [-]

    fprintf(['  |aL|=%6.3f+/-%.3fmm  |aR|=%6.3f+/-%.3fmm' ...
             '  R=%.4f+/-%.4f  ka_set=%.3f\n'], ...
        abs(a_L) * 1e3, delta_aL * 1e3, abs(a_R) * 1e3, delta_aR * 1e3, ...
        out_R(ic), delta_R, out_ka_set(ic));

end   % ---- end condition loop ----

fprintf('\n  Valid results: %d / %d\n', sum(isfinite(out_R)), n_cond);

%% =========================================================
%  SECTION 6 — OUTPUT TABLE
% =========================================================
disp('--- Section 6: Output table ---');

T_out = table( ...
    out_A_set,           ...   % Commanded amplitude  [V]
    out_f_set,           ...   % Commanded frequency  [Hz]
    out_ka_set,          ...   % Commanded steepness  [-]
    out_f_meas,          ...   % Measured frequency (DFT bin)  [Hz]
    out_delta_f,         ...   % 1-σ frequency uncertainty  [Hz]
    out_k,               ...   % Wavenumber  [rad/m]
    out_delta_k,         ...   % 1-σ wavenumber uncertainty  [rad/m]
    out_lambda,          ...   % Wavelength  [m]
    out_ak,              ...   % Measured steepness k|a_L|  [-]
    out_delta_ak,        ...   % 1-σ uncertainty on measured steepness  [-]
    out_aL_mag,          ...   % Incident amplitude |a_L|  [m]
    out_delta_aL,        ...   % 1-σ uncertainty on |a_L|  [m]
    out_aR_mag,          ...   % Reflected amplitude |a_R|  [m]
    out_delta_aR,        ...   % 1-σ uncertainty on |a_R|  [m]
    out_aL_phase,        ...   % Phase of a_L  [rad]
    out_aR_phase,        ...   % Phase of a_R  [rad]
    out_R,               ...   % Reflection coefficient R = |a_R|/|a_L|  [-]
    out_delta_R,         ...   % 1-σ uncertainty on R  [-]
    out_sigma_A_median,  ...   % Median total amplitude noise floor  [m]
    out_D,               ...   % ZS denominator D (conditioning)  [-]
    out_Ngauge,          ...   % Number of valid gauges used  [-]
    'VariableNames', { ...
    'SetAmplitude_V',        'SetFrequency_Hz',        'SetSteepness_ka', ...
    'MeasFrequency_Hz',      'Unc_Frequency_Hz', ...
    'Wavenumber_radm',       'Unc_Wavenumber_radm',    'Wavelength_m', ...
    'MeasSteepness_ak',      'Unc_MeasSteepness_ak', ...
    'IncidentAmp_m',         'Unc_IncidentAmp_m', ...
    'ReflectedAmp_m',        'Unc_ReflectedAmp_m', ...
    'IncidentPhase_rad',     'ReflectedPhase_rad', ...
    'ReflectionCoeff',       'Unc_ReflectionCoeff', ...
    'NoiseFloor_median_m',   'Denominator_D',          'N_gauges'});

valid_mask = isfinite(out_R);   % Logical mask: true for successfully solved conditions
if any(valid_mask)
    disp(T_out(valid_mask, :));
else
    disp('  No valid results.');
end

%% =========================================================
%  SECTION 7 — PLOTS
%    Plot 1 — R vs commanded amplitude (one line per frequency)
%    Plot 2 — |a_L| and |a_R| vs commanded amplitude (subplots per f)
%    Plot 3 — ZS denominator D vs measured frequency
%    Plot 4 — Spatial amplitude profiles (one figure per frequency)
%    Plot 5 — Phasor diagram for the lowest frequency
%    Plot 6 — R vs commanded frequency (one colour per steepness)
%    Plot 7 — R vs commanded steepness (one colour per frequency)
%
%  The flag skip_167freq lets the user exclude the 1.667 Hz
%  frequency from all plots.  
% =========================================================
disp('--- Section 7: Plotting ---');

% Set true to exclude the near-singular 1.667 Hz condition from all plots
skip_167freq = false;

if skip_167freq
    % Remove 1.667 Hz from the valid mask used to drive all plots
    valid_mask = valid_mask & (abs(out_f_set - 1.667) > 0.05);
end

% Collect the unique set frequencies that have at least one valid result
f_unique = unique(out_f_set(valid_mask));   % [Hz]
n_f      = length(f_unique);               % Number of unique valid frequencies  [-]

if n_f == 0
    disp('  No valid results — skipping plots.');
else
    cmap    = lines(n_f);   % Colour palette: one colour per frequency
    markers = {'o', 's', '^', 'd', 'v', 'p', 'h', '<'};   % Marker cycle

    % -------------------------------------------------------
    %  PLOT 1 — Reflection coefficient R vs commanded amplitude
    %
    %  Each frequency is a separate series.  Error bars show ±δR.
    %  Reference lines at R = 0.10 and R = 0.30 mark
    %  "low-reflection" and "moderate-reflection" thresholds.
    % -------------------------------------------------------
    f1 = figure('Name', 'ZS_R_vs_SetAmplitude', 'Position', [50 50 900 560]);
    ax1 = axes(f1); hold(ax1, 'on'); grid(ax1, 'on');

    for iif = 1:n_f
        f_c = f_unique(iif);   % Current frequency  [Hz]
        sel = abs(out_f_set - f_c) < freq_tol_group & valid_mask;
        if sum(sel) < 1; continue; end

        % Sort by amplitude for visual consistency
        [A_s, si] = sort(out_A_set(sel));
        R_s  = out_R(sel);       R_s  = R_s(si);    % R  [-]
        dR_s = out_delta_R(sel); dR_s = dR_s(si);   % δR [-]

        col = cmap(iif, :);
        mk  = markers{mod(iif - 1, 8) + 1};
        lbl = sprintf('f_{set} = %.3f Hz', f_c);

        if any(isfinite(dR_s))
            errorbar(ax1, A_s, R_s, dR_s, dR_s, mk, 'Color', col, ...
                'LineWidth', LW, 'MarkerSize', MS, 'MarkerFaceColor', col, ...
                'CapSize', 6, 'LineStyle', 'none', 'DisplayName', lbl);
        else
            plot(ax1, A_s, R_s, mk, 'Color', col, 'LineWidth', LW, ...
                'MarkerSize', MS, 'MarkerFaceColor', col, 'LineStyle', 'none', ...
                'DisplayName', lbl);
        end
    end

    yline(ax1, 0.10, 'k:', 'LineWidth', 1.5, 'DisplayName', 'R = 0.10');
    yline(ax1, 0.30, 'k--', 'LineWidth', 1.5, 'DisplayName', 'R = 0.30');
    xlabel(ax1, 'A_{set} (V)',             'FontSize', FS_ax);
    ylabel(ax1, 'R = |a_R| / |a_L|  (-)', 'FontSize', FS_ax);
    legend(ax1, 'show', 'Location', 'best', 'FontSize', FS_leg);
    ax1.FontSize = FS_tick;

    % -------------------------------------------------------
    %  PLOT 2 — Incident and reflected amplitudes vs commanded amplitude
    %
    %  One subplot per frequency.  Blue circles = |a_L| (incident);
    %  red squares = |a_R| (reflected).  Error bars = ±δ_aL, ±δ_aR.
    % -------------------------------------------------------
    n_cols2 = min(n_f, 3);
    n_rows2 = ceil(n_f / n_cols2);
    f2 = figure('Name', 'ZS_aL_aR_vs_SetAmplitude', ...
        'Position', [100 100 420 * n_cols2 340 * n_rows2]);

    for iif = 1:n_f
        f_c = f_unique(iif);
        sel = abs(out_f_set - f_c) < freq_tol_group & valid_mask;
        if sum(sel) < 1; continue; end

        [A_s, si] = sort(out_A_set(sel));
        aL_s  = out_aL_mag(sel)   * 1e3;  aL_s  = aL_s(si);    % |a_L|  [mm]
        aR_s  = out_aR_mag(sel)   * 1e3;  aR_s  = aR_s(si);    % |a_R|  [mm]
        daL_s = out_delta_aL(sel) * 1e3;  daL_s = daL_s(si);   % δ_aL  [mm]
        daR_s = out_delta_aR(sel) * 1e3;  daR_s = daR_s(si);   % δ_aR  [mm]

        ax2 = subplot(n_rows2, n_cols2, iif, 'Parent', f2);
        hold(ax2, 'on'); grid(ax2, 'on');

        colL = [0.15 0.45 0.75];   % Blue for incident
        colR = [0.80 0.20 0.20];   % Red for reflected

        if any(isfinite(daL_s))
            errorbar(ax2, A_s, aL_s, daL_s, daL_s, 'o', 'Color', colL, ...
                'LineWidth', LW, 'MarkerFaceColor', colL, 'MarkerSize', MS, ...
                'CapSize', 5, 'DisplayName', '|a_L| incident');
        else
            plot(ax2, A_s, aL_s, 'o', 'Color', colL, 'LineWidth', LW, ...
                'MarkerFaceColor', colL, 'MarkerSize', MS, 'DisplayName', '|a_L| incident');
        end

        if any(isfinite(daR_s))
            errorbar(ax2, A_s, aR_s, daR_s, daR_s, 's', 'Color', colR, ...
                'LineWidth', LW, 'MarkerFaceColor', colR, 'MarkerSize', MS, ...
                'CapSize', 5, 'DisplayName', '|a_R| reflected');
        else
            plot(ax2, A_s, aR_s, 's', 'Color', colR, 'LineWidth', LW, ...
                'MarkerFaceColor', colR, 'MarkerSize', MS, 'DisplayName', '|a_R| reflected');
        end

        xlabel(ax2, 'A_{set} (V)',                              'FontSize', FS_ax);
        ylabel(ax2, '$\bar{\eta}$ (mm)', 'Interpreter', 'latex','FontSize', FS_ax);
        title(ax2,  sprintf('f_{set} = %.3f Hz', f_c),          'FontSize', FS_title);
        legend(ax2, 'show', 'Location', 'northwest', 'FontSize', FS_leg);
        ax2.FontSize = FS_tick;
    end

    % -------------------------------------------------------
    %  PLOT 3 — ZS denominator D vs measured frequency
    %
    %  D diagnoses the conditioning of the ZS linear system.
    %  D < 0.01 (red dashed line): system is near-singular and
    %  results should be discarded.  This typically occurs when
    %  sensor spacings are near-integer multiples of λ/2.
    %  Marker area is proportional to commanded amplitude,
    %  so denser conditions are visually distinguishable.
    % -------------------------------------------------------
    f3 = figure('Name', 'ZS_Denominator_D', 'Position', [150 150 750 470]);
    ax3 = axes(f3); hold(ax3, 'on'); grid(ax3, 'on');

    for iif = 1:n_f
        f_c = f_unique(iif);
        sel = abs(out_f_set - f_c) < freq_tol_group & isfinite(out_D);
        if ~any(sel); continue; end

        % Marker area proportional to commanded amplitude (visual cue)
        scatter(ax3, out_f_meas(sel), out_D(sel), ...
            50 + 20 * out_A_set(sel), cmap(iif, :), 'filled', ...
            'DisplayName', sprintf('f_{set} = %.3f Hz', f_c));

        % Add horizontal frequency uncertainty bars
        dF = out_delta_f(sel);
        if any(isfinite(dF))
            errorbar(ax3, out_f_meas(sel), out_D(sel), ...
                zeros(sum(sel), 1), zeros(sum(sel), 1), dF, dF, ...
                'LineStyle', 'none', 'Color', cmap(iif, :), 'CapSize', 4, ...
                'HandleVisibility', 'off');
        end
    end

    yline(ax3, 0.01, 'r--', 'LineWidth', 1.5, 'DisplayName', 'D = 0.01  (singular threshold)');
    yline(ax3, 0.50, 'k:',  'LineWidth', 1.2, 'DisplayName', 'D = 0.50  (caution threshold)');
    xlabel(ax3, 'f_{meas} (Hz)', 'FontSize', FS_ax);
    ylabel(ax3, 'D (-)',         'FontSize', FS_ax);
    legend(ax3, 'show', 'Location', 'best', 'FontSize', FS_leg);
    ax3.FontSize = FS_tick;

    % -------------------------------------------------------
    %  PLOT 4 — Spatial amplitude profiles  (one figure per frequency)
    %
    %  For each frequency, each condition (amplitude) is plotted as:
    %    - Solid coloured line: ZS model envelope
    %      |a_L exp(+ikx) + a_R exp(-ikx)|
    %    - Filled circles: measured |A_jp| at each sensor position
    %    - Thin error bars: ±δ_aL (same bound used for all sensors)
    %    - Grey dotted verticals: sensor x-positions
  
    % -------------------------------------------------------
    x_fine     = linspace(0, 14, 1000);   % Spatial axis for model envelope  [m]
    f4_handles = {};                        % Collect figure handles for saving

    for iif = 1:n_f
        f_c  = f_unique(iif);
        sel  = find(abs(out_f_set - f_c) < freq_tol_group & valid_mask);
        if isempty(sel); continue; end

        % Sort by amplitude so colour maps from low to high
        [~, si]  = sort(out_A_set(sel));
        sel_s    = sel(si);
        n_cond_f = length(sel_s);

        cmap4 = turbo(n_cond_f);   % Colour per amplitude condition

        fig_name = sprintf('ZS_SpatialProfiles_f%.3fHz', f_c);
        fig_name = strrep(fig_name, '.', 'p');   % Replace '.' with 'p' for safe filename
        fh4 = figure('Name', fig_name, 'Position', [100 100 1000 420]);
        ax4 = axes(fh4);
        hold(ax4, 'on'); grid(ax4, 'on'); box(ax4, 'on');

        % Step 1: model envelope curves (drawn first so dots sit on top)
        for ias = 1:n_cond_f
            ic_s = sel_s(ias);
            if ~isfinite(aL_complex(ic_s)); continue; end

            k_s = out_k(ic_s);   % Wavenumber for this condition  [rad/m]
            % Spatial amplitude envelope of the standing/progressive wave field
            env = abs(aL_complex(ic_s) * exp(+1i * k_s * x_fine) + ...
                      aR_complex(ic_s) * exp(-1i * k_s * x_fine));   % [m]

            plot(ax4, x_fine, env * 1e3, '-', ...
                'Color',     cmap4(ias, :), ...
                'LineWidth', 1.5, ...
                'DisplayName', sprintf('A = %.2f V', out_A_set(ic_s)));
        end

        % Step 2: grey vertical guide lines at sensor positions
        for ip = 1:n_sensors
            xline(ax4, sensor_x(ip), ':', ...
                'Color',            [0.65 0.65 0.65], ...
                'LineWidth',        0.9, ...
                'HandleVisibility', 'off');
        end

        % Step 3: sensor data with error bars (drawn after lines)
        for ias = 1:n_cond_f
            ic_s = sel_s(ias);
            if ~isfinite(aL_complex(ic_s)); continue; end

            a_m = amp_spatial(ic_s, :);   % Measured amplitudes  [m]
            vp  = isfinite(a_m);           % Valid (non-NaN) sensors
            if ~any(vp); continue; end

            xv  = sensor_x(vp);          % Valid sensor x-positions  [m]
            yv  = a_m(vp) * 1e3;          % Valid amplitudes  [mm]
            dA  = out_delta_aL(ic_s) * 1e3;   % Amplitude uncertainty  [mm]
            col = cmap4(ias, :);

            % Thin error bars (no caps, slightly darker colour)
            if isfinite(dA) && dA > 0
                errorbar(ax4, xv, yv, repmat(dA, sum(vp), 1), ...
                    'LineStyle',        'none', ...
                    'Color',            col * 0.6, ...
                    'LineWidth',        1.2, ...
                    'CapSize',          0, ...
                    'HandleVisibility', 'off');
            end

            % Filled sensor dots (white edge for contrast)
            scatter(ax4, xv, yv, (MS + 4)^2, ...
                'MarkerFaceColor', col, ...
                'MarkerEdgeColor', 'w', ...
                'LineWidth',       1.0, ...
                'HandleVisibility','off');
        end

        xlabel(ax4, 'x  (m)',                        'FontSize', FS_ax);
        ylabel(ax4, '$\bar{\eta}$  (mm)', ...
               'Interpreter', 'latex',               'FontSize', FS_ax);
        title(ax4, sprintf('f_{set} = %.3f Hz', f_c),'FontSize', FS_title + 1);
        legend(ax4, 'show', 'Location', 'northeast', 'FontSize', FS_leg - 1, 'NumColumns', 2);
        ax4.FontSize = FS_tick;
        ax4.XLim     = [0, 14];   % Full tank length  [m]
        ax4.YLim(1)  = 0;          % Amplitude is non-negative

        f4_handles{end + 1} = fh4; %#ok<AGROW>
    end

    % Save spatial profile figures (one PNG + PDF per frequency)
    for ihf = 1:length(f4_handles)
        fh4s  = f4_handles{ihf};
        if ~isgraphics(fh4s, 'figure'); continue; end
        sname4 = strtrim(regexprep(get(fh4s, 'Name'), '[\\/:*?"<>|]', '_'));
        if skip_167freq; sname4 = [sname4 '_fskipped']; end %#ok<AGROW>
        try
            exportgraphics(fh4s, fullfile(output_dir, [sname4 '.png']), 'Resolution', 300);
            exportgraphics(fh4s, fullfile(output_dir, [sname4 '.pdf']), 'ContentType', 'vector');
            fprintf('  Saved: %s\n', sname4);
        catch ME_s4
            fprintf('  [WARN] %s: %s\n', sname4, ME_s4.message);
        end
    end

    % -------------------------------------------------------
    %  PLOT 5 — Phasor diagram (lowest frequency only)
    %
    %  Each condition is shown as two phasors from the origin:
    %    - Solid arrow: a_L (incident complex amplitude)  [mm]
    %    - Dashed arrow: a_R (reflected complex amplitude)  [mm]
    %  Uncertainty circles of radius δ_aL and δ_aR are drawn
    %  around each arrow tip.  The diagram is equal-aspect so
    %  that relative magnitudes and angles are faithfully shown.
    % -------------------------------------------------------
    f_ph   = f_unique(1);   % Lowest valid frequency  [Hz]
    sel_ph = find(abs(out_f_set - f_ph) < freq_tol_group & valid_mask);

    if ~isempty(sel_ph)
        f5 = figure('Name', 'ZS_PhasorDiagram', 'Position', [250 250 650 580]);
        ax5 = axes(f5); hold(ax5, 'on'); grid(ax5, 'on'); axis(ax5, 'equal');
        cmap5 = cool(length(sel_ph));

        for ias = 1:length(sel_ph)
            ic_s = sel_ph(ias);
            if ~isfinite(aL_complex(ic_s)); continue; end

            lbl = sprintf('A = %.2f V', out_A_set(ic_s));

            % Incident phasor (solid)
            quiver(ax5, 0, 0, real(aL_complex(ic_s)) * 1e3, imag(aL_complex(ic_s)) * 1e3, 0, ...
                'Color', cmap5(ias, :), 'LineWidth', LW, 'MaxHeadSize', 0.5, ...
                'DisplayName', ['a_L  ' lbl]);

            % Reflected phasor (dashed)
            quiver(ax5, 0, 0, real(aR_complex(ic_s)) * 1e3, imag(aR_complex(ic_s)) * 1e3, 0, ...
                'Color', cmap5(ias, :), 'LineWidth', LW, 'MaxHeadSize', 0.5, ...
                'LineStyle', '--', 'DisplayName', ['a_R  ' lbl]);

            % Uncertainty circle around a_L tip  [mm]
            dA = out_delta_aL(ic_s) * 1e3;
            if isfinite(dA)
                th_c2 = linspace(0, 2 * pi, 60);
                plot(ax5, real(aL_complex(ic_s)) * 1e3 + dA * cos(th_c2), ...
                         imag(aL_complex(ic_s)) * 1e3 + dA * sin(th_c2), '-', ...
                    'Color', cmap5(ias, :), 'LineWidth', 0.8, 'HandleVisibility', 'off');
            end

            % Uncertainty circle around a_R tip  [mm]
            dA2 = out_delta_aR(ic_s) * 1e3;
            if isfinite(dA2)
                th_c2 = linspace(0, 2 * pi, 60);
                plot(ax5, real(aR_complex(ic_s)) * 1e3 + dA2 * cos(th_c2), ...
                         imag(aR_complex(ic_s)) * 1e3 + dA2 * sin(th_c2), '--', ...
                    'Color', cmap5(ias, :), 'LineWidth', 0.8, 'HandleVisibility', 'off');
            end
        end

        xline(ax5, 0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');
        yline(ax5, 0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');
        xlabel(ax5, 'Re($\bar{\eta}$) (mm)', 'Interpreter', 'latex', 'FontSize', FS_ax);
        ylabel(ax5, 'Im($\bar{\eta}$) (mm)', 'Interpreter', 'latex', 'FontSize', FS_ax);
        title(ax5, sprintf('f_{set} = %.3f Hz', f_ph), 'FontSize', FS_title);
        legend(ax5, 'show', 'Location', 'best', 'FontSize', FS_leg, 'NumColumns', 2);
        ax5.FontSize = FS_tick;
    end

    % -------------------------------------------------------
    %  PLOT 6 — R vs commanded frequency, coloured by steepness
    %
    %  Each colour represents a fixed commanded steepness (ka)_set.
    %  X-axis: f_set [Hz]; Y-axis: R [-].
    %  Error bars: δR on y, δf on x.
    % -------------------------------------------------------
    ka_unique = unique(round(out_ka_set(valid_mask), 4));   % Unique commanded steepnesses  [-]
    n_ka      = length(ka_unique);

    if n_ka == 0
        disp('  [PLOT 6] No steepness values found — skipping.');
    else
        cmap6 = parula(n_ka);
        f6 = figure('Name', 'ZS_R_vs_Frequency_fixedSteepness', ...
            'Position', [300 300 900 560]);
        ax6 = axes(f6); hold(ax6, 'on'); grid(ax6, 'on');

        for iika = 1:n_ka
            ka_c = ka_unique(iika);
            sel6 = valid_mask & abs(out_ka_set - ka_c) < ka_tol_group;
            if sum(sel6) < 1; continue; end

            f_s6  = out_f_set(sel6);       % Commanded frequency  [Hz]
            R_s6  = out_R(sel6);           % Reflection coefficient  [-]
            dR_s6 = out_delta_R(sel6);     % δR  [-]
            df_s6 = out_delta_f(sel6);     % δf  [Hz]

            col6 = cmap6(iika, :);
            mk6  = markers{mod(iika - 1, 8) + 1};
            lbl6 = sprintf('(ka)_{set} = %.2f', ka_c);

            if any(isfinite(dR_s6))
                errorbar(ax6, f_s6, R_s6, dR_s6, dR_s6, df_s6, df_s6, ...
                    mk6, 'Color', col6, 'LineWidth', 1.2, 'MarkerSize', MS, ...
                    'MarkerFaceColor', col6, 'CapSize', 5, 'LineStyle', 'none', ...
                    'DisplayName', lbl6);
            else
                scatter(ax6, f_s6, R_s6, MS^2, col6, 'filled', mk6, 'DisplayName', lbl6);
            end
        end

        yline(ax6, 0.10, 'k:', 'LineWidth', 1.5, 'DisplayName', 'R = 0.10');
        yline(ax6, 0.30, 'k--','LineWidth', 1.5, 'DisplayName', 'R = 0.30');
        xlabel(ax6, 'f_{set}  (Hz)',           'FontSize', FS_ax);
        ylabel(ax6, 'R = |a_R| / |a_L|  (-)', 'FontSize', FS_ax);
        legend(ax6, 'show', 'Location', 'best', 'FontSize', FS_leg);
        ax6.FontSize = FS_tick;
    end

    % -------------------------------------------------------
    %  PLOT 7 — R vs commanded steepness, coloured by frequency
    %
    %  Each colour represents a fixed commanded frequency f_set.
    %  X-axis: (ka)_set [-]; Y-axis: R [-].
    %  Error bars: δR on y only  ((ka)_set has no uncertainty since
    %  it is a directly commanded input value, not derived).
    %  The Stokes wave-breaking limit ka = 0.44 is marked.
    % -------------------------------------------------------
    f7 = figure('Name', 'ZS_R_vs_Steepness_fixedFreq', ...
        'Position', [350 350 900 560]);
    ax7 = axes(f7); hold(ax7, 'on'); grid(ax7, 'on');
    cmap7 = lines(n_f);

    for iif = 1:n_f
        f_c  = f_unique(iif);
        sel7 = abs(out_f_set - f_c) < freq_tol_group & valid_mask;
        if sum(sel7) < 1; continue; end

        ka_s7 = out_ka_set(sel7);     % Commanded steepness  [-]
        R_s7  = out_R(sel7);          % Reflection coefficient  [-]
        dR_s7 = out_delta_R(sel7);    % δR  [-]

        col7 = cmap7(iif, :);
        mk7  = markers{mod(iif - 1, 8) + 1};
        lbl7 = sprintf('f_{set} = %.3f Hz', f_c);

        if any(isfinite(dR_s7))
            errorbar(ax7, ka_s7, R_s7, dR_s7, dR_s7, ...
                mk7, 'Color', col7, 'LineWidth', 1.2, 'MarkerSize', MS, ...
                'MarkerFaceColor', col7, 'CapSize', 5, 'LineStyle', 'none', ...
                'DisplayName', lbl7);
        else
            scatter(ax7, ka_s7, R_s7, MS^2, col7, 'filled', mk7, 'DisplayName', lbl7);
        end
    end

    % Stokes breaking limit: ka = 0.44 (π/7) — theoretical upper bound for
    % regular sinusoidal waves in deep water before onset of wave breaking
    xline(ax7, 0.44, 'r--', 'LineWidth', 1.5, 'DisplayName', 'ka = 0.44 (Stokes limit)');
    yline(ax7, 0.10, 'k:',  'LineWidth', 1.5, 'DisplayName', 'R = 0.10');
    yline(ax7, 0.30, 'k--', 'LineWidth', 1.5, 'DisplayName', 'R = 0.30');
    xlabel(ax7, ' (ka)_{set}  (-)',        'FontSize', FS_ax);
    ylabel(ax7, 'R = |a_R| / |a_L|  (-)', 'FontSize', FS_ax);
    xlim(ax7,  [0, 0.15]);   % Limit x-axis to the experimental range
    legend(ax7, 'show', 'Location', 'best', 'FontSize', FS_leg);
    ax7.FontSize = FS_tick;

end   % if n_f > 0

%% =========================================================
%  SECTION 8 — SAVE RESULTS AND FIGURES
%  All figures are exported as both PNG and PDF
% =========================================================
disp('--- Section 8: Saving ---');

if ~exist(output_dir, 'dir'); mkdir(output_dir); end

% Save results table to CSV
if save_results && any(valid_mask)
    writetable(T_out, fullfile(output_dir, 'ZS_Reflection_Results_v5.csv'));
    fprintf('  CSV saved.\n');
end

% List of named figure handles to save
fig_vars = {'f1', 'f2', 'f3', 'f7'};
if exist('f5', 'var'); fig_vars{end + 1} = 'f5'; end
if exist('f6', 'var'); fig_vars{end + 1} = 'f6'; end
% Note: spatial profile figures (f4_*) are saved inside the plotting loop above.

for isf = 1:length(fig_vars)
    fh = eval(fig_vars{isf});
    if ~isgraphics(fh, 'figure'); continue; end

    % Build a filesystem-safe filename from the figure Name property
    sname = strtrim(regexprep(get(fh, 'Name'), '[\\/:*?"<>|]', '_'));
    if skip_167freq; sname = [sname '_fskipped']; end %#ok<AGROW>

    try
        exportgraphics(fh, fullfile(output_dir, [sname '.png']), 'Resolution', 300);
        exportgraphics(fh, fullfile(output_dir, [sname '.pdf']), 'ContentType', 'vector');
        fprintf('  Saved: %s\n', sname);
    catch ME_s
        fprintf('  [WARN] %s: %s\n', sname, ME_s.message);
    end
end

disp('=== ZS_reflection_analysis_raw_v5.m  finished ===');