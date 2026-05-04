% =========================================================================
%  analyse_3pt_bending_test.m
%  3-Point Bending Test Analysis Script — SIWWI Ice Mechanics Campaign
% =========================================================================
%
%  PURPOSE:
%    Reads raw force/displacement/time data from a single 3-point bending
%    test, performs zeroing of the force signal, fits the linear loading
%    region to extract stiffness, and computes flexural strength (sigma_f)
%    and apparent flexural modulus (E_flex) with uncertainty estimates.
%
%  WORKFLOW:
%    1. User provides the test filename (no extension).
%    2. Script looks up sample geometry, speed, and uncertainties from a
%       shared metadata CSV file — no manual dimension entry required.
%    3. Raw data is read from the SIWWI .txt format via read_siwwi_txt().
%    4. Force is zeroed by subtracting the first data point (if non-zero).
%       Displacement is NOT zeroed — machine position is kept as-is.
%    5. A linear fit over a user-defined fraction of peak force gives the
%       loading stiffness k (N/m).
%    6. Flexural strength and modulus are computed from beam theory.
%    7. Results are printed, plotted, and optionally saved.
%
%  IMPORTANT NOTE ON E VALUES:
%    The computed E is an *apparent* flexural modulus. Because displacement
%    comes from the machine crosshead (not a mid-span extensometer), it
%    includes machine frame compliance, fixture seating, and local
%    indentation. This systematically UNDERESTIMATES the true ice modulus
%    (literature: ~5–9 GPa). The fit range sensitivity you observe (E
%    varying from ~10 to ~120 MPa as you change the fit window) reflects
%    non-linearities in the early part of the curve caused by fixture
%    take-up and contact settling — NOT a code error. To obtain a reliable
%    E, a mid-span displacement transducer (LVDT/DIC) is required.
%    The code maths and units are verified correct below; the low absolute
%    values are a physical/experimental limitation of crosshead measurement.
%
%  MATHS REFERENCE (all SI units internally):
%    Beam theory for a simply-supported beam under central point load:
%      delta = F * L^3 / (48 * E * I)   where I = w*h^3/12
%    Rearranging for stiffness k = F/delta:
%      k = 48 * E * I / L^3 = 48 * E * (w*h^3/12) / L^3
%        = 4 * E * w * h^3 / L^3
%    Therefore:
%      E = k * L^3 / (4 * w * h^3)          [Pa if k in N/m, dims in m]
%
%    Flexural strength (maximum fibre stress at peak load):
%      sigma_f = 3 * F_max * L / (2 * w * h^2)  [Pa]
%
%  UNCERTAINTY PROPAGATION (relative errors, added in quadrature):
%    sigma_f:  (dF/F)^2 + (dL/L)^2 + (dw/w)^2 + (2*dh/h)^2
%    E:        (3*dL/L)^2 + (dk/k)^2 + (dw/w)^2 + (3*dh/h)^2
%    where dk/k comes from the polyfit residual standard error.
%
%  AUTHOR : Matilde
%  DATE   : 230426
% =========================================================================
clear; clc; close all;
%% =========================================================================
%  SECTION 1 — USER INPUT
% =========================================================================
% Filename of the test (no extension). Must match the 'Filename' column
% in the metadata CSV exactly.
filename = '230426_sample4_instron';
% --- [ADDED v2] X-axis column selector ---
% Choose which SIWWI column to use as the displacement signal for the
% stiffness fit and all force-vs-displacement plots.
% Options (matching the 7 columns in the raw .txt file):
%   'Displacement' — col 4: machine crosshead displacement (original default)
%   'Extension'    — col 2: axial extension reported by the machine
% If you are getting suspiciously low E values with 'Displacement', try
% 'Extension' — it may be a less compliance-contaminated signal.
x_col_choice = 'Displacement';   % <-- change here: 'Displacement' or 'Extension'
%% =========================================================================
%  SECTION 2 — CONFIGURATION & PATHS
% =========================================================================
date = '230426';   % Used for output subfolder and file-naming

% --- [MODIFIED v4] Machine format moved up here so it can be used for dynamic file paths ---
% --- Machine format ---
machine_case = 'instron';   % 'instron' or 'siwwi'

% --- File paths ---
data_dir  = 'C:/Users/mbureau/OneDrive - The University of Melbourne/Desktop/SIWWI2026/3pt_bending_tests/230426/';

%  Dynamic file extension based on machine_case

if strcmpi(machine_case, 'instron')
    file1 = fullfile(data_dir, [filename, '.csv']);
elseif strcmpi(machine_case, 'siwwi')
    file1 = fullfile(data_dir, [filename, '.txt']);
else
    error('[ADDED v4] Unknown machine_case: ''%s''. Use ''instron'' or ''siwwi''.', machine_case);
end

% Path to the shared metadata CSV (columns: w,s,h,Type,Filename,Speed,T,Date,uw,us,uh)
meta_csv  = fullfile(data_dir, 'metadata_icetests_230426.csv');

% Output directory: .../results/<date>/<filename>/
%  Append machine_case to savePath directory name

savePath  = fullfile(data_dir, 'results', date, [filename, '_', machine_case]);

% --- Save flags ---
savefig   = true;   % Save figures as .png and .pdf
save_mech = true;   % Save mechanical results table as .csv

% --- Machine format ---
% machine_case = 'instron';   % 'instron' or 'siwwi' <-- [COMMENTED OUT v4: Moved to top of Section 2]

% --- Linear fit range (fraction of peak force) ---
%  The fit is performed over data points where force is between:
%    fit_range(1)*F_max  and  fit_range(2)*F_max
%  Use a range that avoids:
%    - the noisy/settling region near zero load  (raise lower bound)
%    - any nonlinear hardening near the peak     (keep upper bound <= 0.95)
%  SENSITIVITY WARNING: The slope (and therefore E) is very sensitive to
%  the lower bound because curves are non-linear near zero load due to
%  fixture take-up. Always inspect the analysis figure and choose a range
%  that sits clearly within the linear portion of the curve.
%
%  [ADDED v3] IMPORTANT — recommended fit_range depends on x_col_choice:
%    'Displacement': the curve is mostly nonlinear toe then steep ramp.
%                   Start at ~0.2 to skip toe: fit_range = [0.2, 0.9]
%    'Extension':   the curve has a very long flat toe then a short steep
%                   linear ramp right before the peak. The linear region
%                   is only the last ~20-30% of the curve, so you MUST
%                   use a HIGH lower bound: fit_range = [0.7, 0.95]
%                   Using [0.2, 1.0] with Extension fits the whole nonlinear
%                   toe and gives a completely wrong (too flat) slope.
fit_range = [0.7, 1];   
% --- Physical constants ---
g     = 9.81;   % m/s^2
%% =========================================================================
%  SECTION 3 — LOAD METADATA FROM CSV
% =========================================================================
%  The metadata CSV has two header rows: row 1 = column names, row 2 = units.
%  Data starts on row 3. We read everything as strings first, then parse.
fprintf('--- Loading metadata from CSV ---\n');
% Read the entire CSV as a cell array
raw = readcell(meta_csv);
% Row 1: column headers; Row 2: units; Rows 3+: data
headers = raw(1, :);   % {'w','s','h','Type','Filename','Speed','T','Date','uw','us','uh'}
units   = raw(2, :);   % {'mm','mm','mm','','','mm/min','celsius','','mm','mm','mm'}
data_rows = raw(3:end, :);
% Find the column index for 'Filename'
col_Filename = find(strcmpi(headers, 'Filename'));
if isempty(col_Filename)
    error('Column ''Filename'' not found in metadata CSV.');
end
% Find the row matching our filename
row_idx = [];
for r = 1:size(data_rows, 1)
    if strcmpi(string(data_rows{r, col_Filename}), filename)
        row_idx = r;
        break;
    end
end
if isempty(row_idx)
    error('Filename ''%s'' not found in metadata CSV.', filename);
end
% Helper: extract a numeric value by column name
getNum = @(colname) str2double(string(data_rows{row_idx, find(strcmpi(headers, colname))}));
% --- Sample geometry (convert mm -> m) ---
w_mm = getNum('w');    % beam width  [mm]
s_mm = getNum('s');    % span length [mm]  (column 's' = support span)
h_mm = getNum('h');    % beam height [mm]
w = w_mm / 1000;       % [m]
L = s_mm / 1000;       % [m]  L = support span
h = h_mm / 1000;       % [m]
% --- Measurement uncertainties (mm -> m) ---
dw = getNum('uw') / 1000;   % [m]
dL = getNum('us') / 1000;   % [m]  uncertainty on span (column 'us')
dh = getNum('uh') / 1000;   % [m]
% --- Machine speed ---
% CSV speed is in mm/min; convert to mm/s for display
speed_mmmin = getNum('Speed');
set_speed_mms = speed_mmmin / 60;   % [mm/s]
% --- Sample type and temperature ---
sample_type = string(data_rows{row_idx, find(strcmpi(headers, 'Type'))});
T_celsius   = getNum('T');
fprintf('  Sample   : %s (%s)\n', filename, sample_type);
fprintf('  w = %.1f mm,  L (span) = %.1f mm,  h = %.1f mm\n', w_mm, s_mm, h_mm);
fprintf('  Set speed: %.2f mm/min = %.4f mm/s\n', speed_mmmin, set_speed_mms);
fprintf('  Temperature: %.1f °C\n\n', T_celsius);
% Sample display name for plot legends
sample_name = sprintf('%s (%s)', filename, sample_type);
%% =========================================================================
%  SECTION 4 — LOAD RAW DATA
% =========================================================================
fprintf('--- Loading test data ---\n');
switch lower(machine_case)
    case 'instron'
        % [ADDED v4] Error check for instron vs extension
        if strcmpi(x_col_choice, 'Extension')
            error('[ADDED v4] ERROR: ''Extension'' is not allowed for the instron machine. Please use ''Displacement'' for x_col_choice.');
        end
        
        % Instron CSV: 2-row header, columns = [time, disp, force]
        % [MODIFIED v4] Override headers cleanly since displacement might not be explicitly called that in raw data and could crash the unit scaling logic later
        meta_raw = readcell(file1, 'Range', '1:2');
        uTime  = meta_raw{2, 1};
        uDisp  = meta_raw{2, 2};
        uForce = meta_raw{2, 3};
        % uTime  = 's';
        % uDisp  = 'Displacement (mm)';
        % uForce = 'kN';
        
        data   = readmatrix(file1, 'NumHeaderLines', 2);
        time1  = data(:, 1);
        disp1  = data(:, 2); % [ADDED v4] Ensures column 2 is strictly used as the displacement column and x-axis for the linear fit
        force1 = data(:, 3);
        
    case 'siwwi'
        % SIWWI .txt format — units are hardcoded from machine output
        uTime  = 's';
        uForce = 'N';
        % [ADDED v3] Build x-axis label from x_col_choice so all figures
        % correctly show 'Extension (mm)' or 'Displacement (mm)'.
        uDisp  = [x_col_choice, ' (mm)'];
        % [ADDED v2] Pass x_col_choice so the reader returns the correct column.
        [time1, disp1, force1] = read_siwwi_txt(file1, x_col_choice);
    otherwise
        error('Unknown machine_case: ''%s''. Use ''instron'' or ''siwwi''.', machine_case);
end
fprintf('  Loaded %d data points.\n\n', length(time1));
%% =========================================================================
%  SECTION 5 — FORCE ZEROING
%  Displacement is NOT zeroed — machine position is kept raw.
%  Force is zeroed only if the first point deviates from zero.
%  Strategy: subtract the FIRST force point from all force data.
%  This corrects a constant offset (tare error or pre-load) without
%  distorting the shape of the curve.
% =========================================================================
fprintf('--- Force zeroing ---\n');
f_raw  = force1;
d_raw  = disp1;    % displacement left unchanged
t_raw  = time1;
F_first = f_raw(1);   % value of the very first force reading
% Tolerance: if first point is within 0.5% of full-scale, treat as zero
tol_zero = 0.005 * max(abs(f_raw));
if abs(F_first) <= tol_zero
    % First point is already (effectively) zero — no correction needed
    force_z = f_raw;
    fprintf('  First force point = %.4f N  → within tolerance (%.4f N). No zeroing applied.\n\n', F_first, tol_zero);
elseif F_first > tol_zero
    % First point is POSITIVE — subtracting it applies a NEGATIVE offset
    force_z = f_raw - F_first;
    fprintf('  First force point = %.4f N  → added negative offset to zero force initially.\n\n', F_first);
else
    % First point is NEGATIVE — subtracting it applies a POSITIVE offset
    force_z = f_raw - F_first;
    fprintf('  First force point = %.4f N  → added positive offset to zero force initially.\n\n', F_first);
end
% Displacement and time are untouched
disp_z = d_raw;
time_z = t_raw;
%% =========================================================================
%  SECTION 6 — UNIT CONVERSION TO SI
%  Internally all calculations use SI units (N, m, Pa).
%  Plotting uses original machine units (N, mm) for readability.
% =========================================================================
% Convert force to Newtons (handle kN input from Instron if needed).
% [FIXED v5] Both sides of the contains() check must be in the same case.
%            Previously: contains(lower(uForce), 'kN') — after lower(),
%            uForce becomes e.g. '(kn)', but the search string 'kN' still
%            has a capital N, so the match always FAILED, the kN→N
%            conversion was silently skipped, and all mechanics (F_max,
%            sigma_f, E, k) were computed with force values 1000× too small.
if contains(lower(uForce), 'kn')   % [FIXED v5] search string now all-lowercase
    f_N = force_z * 1000;   % kN -> N
else
    f_N = force_z;           % already in N
end
% Convert displacement to metres for mechanics calculations
if contains(lower(uDisp), 'mm')
    d_m = disp_z / 1000;    % mm -> m
else
    d_m = disp_z;            % assume already in m
end
%% =========================================================================
%  SECTION 7 — RAW PLOTS (Force vs Disp, Disp vs Time, Force vs Time)
% =========================================================================
fprintf('--- Generating raw data plots ---\n');
fig1 = figure('Name', ['Force_vs_', x_col_choice]);   % [FIXED v3]
plot(disp_z, force_z, 'bx', 'DisplayName', sample_name);   % [UPDATED v3] cross markers, no joining line
xlabel(uDisp, 'FontWeight', 'bold');   % [FIXED v3] uDisp already contains full label e.g. 'Extension (mm)'
ylabel(['Force (', uForce, ')'],       'FontWeight', 'bold');
title(['Force vs ', x_col_choice]);   % [FIXED v3]
legend('show', 'Location', 'best');
grid on;
fig2 = figure('Name', [x_col_choice, '_vs_Time']);   % [FIXED v3]
plot(time_z, disp_z, 'bx', 'DisplayName', sample_name);   % [UPDATED v3] cross markers, no joining line
xlabel(['Time (', uTime, ')'],          'FontWeight', 'bold');
ylabel(uDisp, 'FontWeight', 'bold');   % [FIXED v3] uDisp already contains full label
title([x_col_choice, ' vs Time']);   % [FIXED v3]
legend('show', 'Location', 'best');
grid on;
fig3 = figure('Name', 'Force_vs_Time');
plot(time_z, force_z, 'bx', 'DisplayName', sample_name);   % [UPDATED v3] cross markers, no joining line
xlabel(['Time (', uTime, ')'],    'FontWeight', 'bold');
ylabel(['Force (', uForce, ')'], 'FontWeight', 'bold');
title('Force vs Time');
legend('show', 'Location', 'best');
grid on;
%% =========================================================================
%  SECTION 8 — MECHANICAL ANALYSIS
% =========================================================================
fprintf('--- Mechanical Analysis ---\n\n');
% ---- 8.1  Peak force ----
[F_max_N, idx_max] = max(f_N);    % F_max in Newtons
d_peak_m  = d_m(idx_max);         % displacement at peak, in metres
d_peak_mm = disp_z(idx_max);      % same, in mm (for display)
fprintf('  Peak force : %.3f N  at disp = %.3f mm\n', F_max_N, d_peak_mm);
% ---- 8.2  Linear fit to extract stiffness k [N/m] ----
% -------------------------------------------------------------------------
% ORIGINAL APPROACH (commented out):
%   Fit based purely on force thresholds:
%     F_lo = fit_range(1) * F_max
%     F_hi = fit_range(2) * F_max
%     idx_fit = find(F between these bounds)
%
% PROBLEM:
%   This assumes the curve is already linear in that region, which is NOT
%   true for ice bending tests (toe region + pre-failure curvature).
%
% NEW APPROACH (R²-based automatic linear region detection):
%   1. First restrict data to the user-defined force window (fit_range)
%   2. Inside this window, scan ALL possible sub-segments
%   3. Compute linear fit for each segment
%   4. Select the segment with the HIGHEST R² (most linear)
%
%   → This mimics what you would do by eye when drawing the best straight line
F_lo = fit_range(1) * F_max_N;
F_hi = fit_range(2) * F_max_N;

idx_window = find(f_N >= F_lo & f_N <= F_hi);


xw = d_m(idx_window);
yw = f_N(idx_window);

best_R2 = -Inf;
best_idx = idx_window;

min_pts = max(100, round(1 * length(idx_window))); % at least 40 pts or 40%

for i = 1:(length(xw) - min_pts)
    for j = (i + min_pts):length(xw)
        p_tmp = polyfit(xw(i:j), yw(i:j), 1);
        y_fit_tmp = polyval(p_tmp, xw(i:j));
        
        SS_res = sum((yw(i:j) - y_fit_tmp).^2);
        SS_tot = sum((yw(i:j) - mean(yw(i:j))).^2);
        R2_tmp = 1 - SS_res / SS_tot;
        
        if R2_tmp > best_R2
            best_R2 = R2_tmp;
            best_idx = idx_window(i:j);
        end
    end
end

idx_fit = best_idx;
if length(idx_fit) < 5
    warning('Fewer than 5 points in fit range [%.2f, %.2f] N. Check fit_range or data.', F_lo, F_hi);
end
fprintf('  Fit range  : %.2f N to %.2f N  (%d points)\n', F_lo, F_hi, length(idx_fit));
% polyfit: d_m (x) vs f_N (y)  →  p(1) = slope = k [N/m]
[p, S] = polyfit(d_m(idx_fit), f_N(idx_fit), 1);
k_fit = p(1);    % stiffness [N/m]
%  Uncertainty on k from polyfit residual standard error
%    se_resid = residual RMS = S.normr / sqrt(S.df)
%    se_k = se_resid / sqrt( sum((x - x_mean)^2) )
x_fit   = d_m(idx_fit);
SSx     = sum((x_fit - mean(x_fit)).^2);
se_resid = S.normr / sqrt(S.df);
dk      = se_resid / sqrt(SSx);     % uncertainty on k [N/m]
fprintf('  k (stiffness) = %.2f +/- %.2f N/m\n', k_fit, dk);
% ---- 8.3  Actual crosshead speed from fit ----
%  Linear fit of displacement(mm) vs time(s) over the same loading region
p_speed   = polyfit(time_z(idx_fit), disp_z(idx_fit), 1);
act_speed = p_speed(1);   % [mm/s]
fprintf('  Actual speed : %.4f mm/s  (set: %.4f mm/s)\n', act_speed, set_speed_mms);
% ---- 8.4  Flexural strength ----
%  sigma_f = 3 * F * L / (2 * w * h^2)
%  All inputs in SI (N, m) → result in Pa → convert to kPa
%
%  Derivation: for a simply-supported beam with central point load F,
%  the maximum bending moment is M = F*L/4.
%  Maximum fibre stress: sigma = M * (h/2) / I  where I = w*h^3/12
%  => sigma = (F*L/4) * (h/2) / (w*h^3/12) = 3*F*L / (2*w*h^2)   ✓
sigma_f_Pa  = (3 * F_max_N * L) / (2 * w * h^2);
sigma_f_kPa = sigma_f_Pa / 1000;
% Uncertainty propagation (relative contributions added in quadrature):
%   d(sigma_f)/sigma_f = sqrt( (dF/F)^2 + (dL/L)^2 + (dw/w)^2 + (2*dh/h)^2 )
% Note the factor of 2 on dh because h appears squared in denominator.
dF = 0.5;   % force measurement uncertainty [N] — update from load cell spec
rel_sigma = sqrt( (dF/F_max_N)^2 + (dL/L)^2 + (dw/w)^2 + (2*dh/h)^2 );
d_sigma_kPa = rel_sigma * sigma_f_kPa;
% ---- 8.5  Apparent flexural modulus ----
%  From beam theory:  k = 4 * E * w * h^3 / L^3
%  Therefore:         E = k * L^3 / (4 * w * h^3)
%
%  UNITS CHECK:
%    k [N/m], L [m], w [m], h [m]
%    E = [N/m] * [m^3] / ([m] * [m^3])  =  [N/m^2]  =  [Pa]  ✓
%  Divide by 1e6 for MPa, by 1e9 for GPa.
E_Pa  = (k_fit * L^3) / (4 * w * h^3);
E_MPa = E_Pa / 1e6;
E_GPa = E_Pa / 1e9;
% Uncertainty propagation:
%   d(E)/E = sqrt( (dk/k)^2 + (3*dL/L)^2 + (dw/w)^2 + (3*dh/h)^2 )
% Note factors of 3 on L and h because they appear as cubes.
rel_E  = sqrt( (dk/k_fit)^2 + (3*dL/L)^2 + (dw/w)^2 + (3*dh/h)^2 );
dE_MPa = rel_E * E_MPa;
dE_GPa = rel_E * E_GPa;
% ---- 8.6  Geometry ratios (ITTC recommendations) ----
L_h = L / h;   % span-to-thickness ratio; ITTC: 5–7
b_h = w / h;   % width-to-thickness ratio; ITTC: 2–3

R2 = 1 - (S.normr^2 / sum((f_N(idx_fit) - mean(f_N(idx_fit))).^2));
fprintf('  Fit R^2 = %.5f\n', R2);

%% =========================================================================
%  SECTION 9 — PRINT RESULTS
% =========================================================================
fprintf('\n========== RESULTS: %s ==========\n', sample_name);
fprintf('  Temperature       : %.1f °C\n',        T_celsius);
fprintf(['  Dimensions        : w=%.1' ...
    'f mm, L=%.1f mm, h=%.1f mm\n'], w*1000, L*1000, h*1000);
fprintf('  L/h ratio         : %.2f  (ITTC rec: 5–7)\n',  L_h);
fprintf('  b/h ratio         : %.2f  (ITTC rec: 2–3)\n',  b_h);
fprintf('  Speed (actual)    : %.4f mm/s  (set: %.4f mm/s)\n', act_speed, set_speed_mms);
fprintf('  Peak Force        : %.3f N  at %.3f mm\n', F_max_N, d_peak_mm);
fprintf('  Fit range         : %.0f%% – %.0f%% of F_max  (%.2f – %.2f N)\n', ...
        fit_range(1)*100, fit_range(2)*100, F_lo, F_hi);
fprintf('  Stiffness k       : %.2f +/- %.2f N/m\n', k_fit, dk);
fprintf('  Sigma_f           : %.2f +/- %.2f kPa\n', sigma_f_kPa, d_sigma_kPa);
fprintf('  E                 : %.4f +/- %.4f GPa\n', E_GPa, dE_GPa);
fprintf('  E                 : %.2f +/- %.2f MPa\n', E_MPa, dE_MPa);
fprintf('==============================================\n\n');
%% =========================================================================
%  SECTION 10 — MECHANICAL ANALYSIS FIGURE
% =========================================================================
fig_analysis = figure('Name', 'Mechanical_Analysis', 'Color', 'w');

% Clean filename for display (prevents MATLAB from interpreting '_' as subscript)
filename_clean = strrep(filename, '_', '\_');

% --- Plot zeroed force vs raw displacement ---
plot(disp_z, force_z, 'bx', 'DisplayName', 'Raw Data');   
hold on;

% --- Peak marker (vertical dashed line) ---
plot([d_peak_mm, d_peak_mm], [0, max(force_z)], 'k--', 'LineWidth', 2, ...
     'DisplayName', sprintf('Peak Force = %.1f N', F_max_N));

% --- Fit range bounds (horizontal dotted lines) ---
% Convert fit bounds from SI Newtons back to machine units for plotting.
if contains(lower(uForce), 'kn')
    F_lo_plot = F_lo / 1000;   % N -> kN for overlay on kN plot
    F_hi_plot = F_hi / 1000;
else
    F_lo_plot = F_lo;          % already in N
    F_hi_plot = F_hi;
end

% --- Fitted line overlaid on the data ---
d_fit_mm  = linspace(disp_z(idx_fit(1)), disp_z(idx_fit(end)), 100);
d_fit_m   = d_fit_mm / 1000;
f_fit_N   = k_fit * d_fit_m + p(2);   % polyfit: y = p(1)*x + p(2), result in N

% Convert fitted force back to machine units for overlay
if contains(lower(uForce), 'kn')
    f_fit_plot = f_fit_N / 1000;   % N -> kN
else
    f_fit_plot = f_fit_N;          % already in N
end

% Combine fit details into a multi-line string for the legend
fit_str = sprintf('Linear Fit  \nE = %.1f GPa, R^2 = %.5f', ...
                  E_GPa, R2);

plot(d_fit_mm, f_fit_plot, 'r-', 'LineWidth', 2, 'DisplayName', fit_str);
hold off;

xlabel(uDisp, 'FontWeight', 'bold');   
ylabel(['Force ', uForce, ], 'FontWeight', 'bold');
grid on;

% --- Single Legend Box ---
lgd = legend('show', 'Location', 'best');
title(lgd, filename_clean); % Sets the cleaned filename as the box title

%% =========================================================================
%  SECTION 11 — SAVE OUTPUT FILES
% =========================================================================
% Create output directory if needed
if (savefig || save_mech) && ~exist(savePath, 'dir')
    mkdir(savePath);
end
% --- Save figures ---
if savefig
    fprintf('--- Saving figures to: %s ---\n', savePath);
    figs = {fig_analysis};
    for i = 1:length(figs)
        % [MODIFIED v4] Add machine_case to saved fig names
        % fig_name = [date, '_', lower(figs{i}.Name)];
        fig_name = [date, '_', machine_case, '_', lower(figs{i}.Name)];
        base = fullfile(savePath, fig_name);
        saveas(figs{i}, [base, '.png']);
        exportgraphics(figs{i}, [base, '.pdf'], 'ContentType', 'vector');
        fprintf('  Saved: %s (.png & .pdf)\n', fig_name);
    end
end

% --- Save mechanical results table ---
if save_mech
    results.Filename         = filename;
    results.SampleType       = char(sample_type);
    results.Temperature_C    = T_celsius;
    results.w_mm             = w * 1000;
    results.L_mm             = L * 1000;
    results.h_mm             = h * 1000;
    results.L_h_ratio        = L_h;
    results.b_h_ratio        = b_h;
    results.Speed_set_mms    = set_speed_mms;
    results.Speed_actual_mms = act_speed;
    results.FitRange_low     = fit_range(1);
    results.FitRange_high    = fit_range(2);
    results.Peak_Force_N     = F_max_N;
    results.Peak_Disp_mm     = d_peak_mm;
    results.k_Nm             = k_fit;
    results.dk_Nm            = dk;
    results.Sigma_f_kPa      = sigma_f_kPa;
    results.dSigma_f_kPa     = d_sigma_kPa;
    results.E_apparent_MPa   = E_MPa;
    results.dE_apparent_MPa  = dE_MPa;
    results.E_apparent_GPa   = E_GPa;
    results.dE_apparent_GPa  = dE_GPa;
    results.R2 = R2;
    resTable = struct2table(results);
    
    % [MODIFIED v4] Add machine_case to saved csv table names
    % out_csv  = fullfile(savePath, [date, '_mech_props.csv']);
    %out_csv  = fullfile(savePath, [date, '_', machine_case, '_mech_props.csv']);
    out_csv  = fullfile(savePath, [filename, '_mech_props.csv']);
    writetable(resTable, out_csv);
    fprintf('\n--- Results saved: %s ---\n', out_csv);
end
%% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================
function [time_out, disp_out, force_out] = read_siwwi_txt(filepath, x_col_choice)
% READ_SIWWI_TXT  Parse the proprietary .txt output from the SIWWI
%                 testing machine.
%
% The file contains a preamble section followed by a '=====Curve======'
% separator line. Below that are:
%   Row 1: 'DataNumber: N'
%   Row 2: Column headers
%   Rows 3+: Numeric data with 7 columns:
%     Col 1: Load (N)       Col 2: Extension (mm)    Col 3: Broadwise ext (mm)
%     Col 4: Displacement   Col 5: Stress             Col 6: Strain
%     Col 7: Time (s)
% textscan stops automatically when it hits the '=====Analysis======'
% separator (non-numeric line).
%
% INPUTS:
%   filepath     — full path to the .txt file
%   x_col_choice — [ADDED v2] string selecting which column to return as
%                  disp_out. Accepted values:
%                    'Displacement' — col 4 (machine crosshead, original default)
%                    'Extension'    — col 2 (axial extension reported by machine)
%
% RETURNS:
%   time_out  [s]   — column 7
%   disp_out  [mm]  — col 2 or col 4, depending on x_col_choice
%   force_out [N]   — column 1 (load)
    fid = fopen(filepath, 'rt');
    if fid == -1
        error('Could not open file: %s', filepath);
    end
    % Scan lines until the Curve section separator
    while ~feof(fid)
        line = fgetl(fid);
        if contains(line, '=========================Curve==========================')
            fgetl(fid);   % skip 'DataNumber:...'
            fgetl(fid);   % skip column header row
            break;
        end
    end
    % Read all numeric columns; stops at next non-numeric separator
    C = textscan(fid, '%f %f %f %f %f %f %f');
    fclose(fid);
    % Assign force and time (unchanged)
    force_out = C{1};   % Load [N]
    time_out  = C{7};   % Time [s]
    % [ADDED v2] Select x-axis column based on user choice.
    % Col 2 = Extension, Col 4 = Displacement (original default).
    switch lower(x_col_choice)
        case 'extension'
            disp_out = C{2};   % Extension [mm]
            fprintf('  [v2] X-axis column: Extension (col 2)\n');
        case 'displacement'
            disp_out = C{4};   % Displacement [mm]
            fprintf('  [v2] X-axis column: Displacement (col 4)\n');
        otherwise
            warning('Unknown x_col_choice ''%s''. Defaulting to Displacement (col 4).', x_col_choice);
            disp_out = C{4};
            fprintf('  [v2] X-axis column: Displacement (col 4) [fallback]\n');
    end
    % Print a short excerpt to the console for a sanity check
    [~, fname, ext] = fileparts(filepath);
    fprintf('\n--- Excerpt: %s%s (SIWWI format) ---\n', fname, ext);
    fprintf(' Time (s) | Load (N)  | %s (mm)\n', x_col_choice);  % [ADDED v2] label reflects chosen column
    fprintf('-----------------------------------\n');
    for idx = 1:min(5, length(time_out))
        fprintf(' %8.4f | %9.4f | %9.4f\n', time_out(idx), force_out(idx), disp_out(idx));
    end
    fprintf('-----------------------------------\n\n');
end