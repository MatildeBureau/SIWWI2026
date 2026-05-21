% =========================================================================
%  three_pt_test_data_reading_v4.m
% =========================================================================
%
%  PURPOSE:
%    Reads raw force/displacement/time data from a  3-point bending
%    test, performs zeroing of the force signal if needed, fits the linear loading
%    region to extract stiffness, and computes flexural strength (sigma_f)
%    and  elastic modulus (E) with uncertainty estimates.
%
%  WORKFLOW:
%    1. User provides the test filename (no extension).
%    2. Script looks up sample geometry, speed, and uncertainties from a
%       shared metadata CSV file.
%    3. Raw data is read from the SIWWI .txt format via read_siwwi_txt().
%    4. Force is zeroed if needed by subtracting the first data point (if non-zero).
%       Displacement is not zeroed.
%    5. A linear fit over a user-defined fraction of peak force gives the
%       loading stiffness k (N/m).
%    6. Flexural strength and modulus are computed from beam theory.
%    7. Results are printed, plotted, and optionally saved.
%
%
%  Computations (all SI units ):
% L = span, F = peak force,  w = sample width, b = sample thickness
%    Beam theory for a simply-supported beam under central point load:
%      delta = F * L^3 / (48 * E * I)   where I = w*b^3/12
%    Rearranging for stiffness k = F/delta:
%      k = 48 * E * I / L^3 = 48 * E * (w*b^3/12) / L^3
%        = 4 * E * w * b^3 / L^3
%    So:
%      E = k * L^3 / (4 * w * b^3)          [Pa if k in N/m, dims in m]
%
%    Flexural strength (maximum fibre stress at peak load):
%      sigma_f = 3 * F_max * L / (2 * w * b^2)  [Pa]
%
%  AUTHOR : Matilde
%  DATE   : 230426
% =========================================================================
clear; clc; close all;
%% =========================================================================
%  SECTION 1 — USER INPUT
% =========================================================================
% Test filename, must match the 'Filename' column
% in the metadata CSV exactly.
filename = 'sample3_x9m';


% Choose which SIWWI column to use as the displacement signal for the
% stiffness fit and all force-vs-displacement plots.
% Options:
%   'Displacement' — col 4 ( default)
%   'Extension'    — col 2

x_col_choice = 'Extension';  
%% =========================================================================
%  SECTION 2 — CONFIGURATION & PATHS
% =========================================================================
date = '060526';   %  for output subfolder and file-naming


% --- Machine format ---
machine_case = 'siwwi';   % 'instron' or 'siwwi'

% --- File paths ---
data_dir  = 'C:/Users/mbureau/OneDrive - The University of Melbourne/Desktop/SIWWI2026/3pt_bending_tests/060526/';

%  Dynamic file extension based on machine_case

if strcmpi(machine_case, 'instron')
    file1 = fullfile(data_dir, [filename, '.csv']);
elseif strcmpi(machine_case, 'siwwi')
    file1 = fullfile(data_dir, [filename, '.txt']);
else
    error('[ADDED v4] Unknown machine_case: ''%s''. Use ''instron'' or ''siwwi''.', machine_case);
end

% Path to the shared metadata CSV (columns: w,s,b,Type,Filename,Speed,T,Date,uw,us,ub)
meta_csv  = fullfile(data_dir, 'metadata_icetests_060526.csv');

% Output directory: .../results/<date>/<filename>/
%  Append machine_case to savePath directory name

savePath  = fullfile(data_dir, 'results', date, [filename, '_', machine_case]);

% --- Save flags ---
savefig   = true;   % Save figures as .png and .pdf
save_mech = true;   % Save mechanical results table as .csv

% --- Physical constants ---
g     = 9.81;   % m/s^2
%% =========================================================================
%  SECTION 3 — LOAD METADATA FROM CSV
% =========================================================================
%  The metadata CSV has two header rows: row 1 = column names, row 2 = units.
%  Data starts on row 3. 
fprintf('--- Loading metadata from CSV ---\n');


raw = readcell(meta_csv);

% Row 1: column headers; Row 2: units; Rows 3+: data
headers = raw(1, :);   % {'w','s','b','Type','Filename','Speed','T','Date','uw','us','ub'}
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
b_mm = getNum('b');    % beam thicness [mm]
w = w_mm / 1000;       % [m]
L = s_mm / 1000;       % [m]  L = support span
b = b_mm / 1000;       % [m]

% --- Measurement uncertainties (mm -> m) ---
dw = getNum('uw') / 1000;   % [m]
dL = getNum('us') / 1000;   % [m]  uncertainty on span (column 'us')
db = getNum('ub') / 1000;   % [m]

% --- Machine speed ---
% CSV speed is in mm/min; convert to mm/s for display
speed_mmmin = getNum('Speed');
set_speed_mms = speed_mmmin / 60;   % [mm/s]

% --- Sample type and temperature ---
sample_type = string(data_rows{row_idx, find(strcmpi(headers, 'Type'))});
T_celsius   = getNum('T');
fprintf('  Sample   : %s (%s)\n', filename, sample_type);
fprintf('  w = %.1f mm,  L (span) = %.1f mm,  b = %.1f mm\n', w_mm, s_mm, b_mm);
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
        %Error check for instron vs extension
        if strcmpi(x_col_choice, 'Extension')
            error('[ADDED v4] ERROR: ''Extension'' is not allowed for the instron machine. Please use ''Displacement'' for x_col_choice.');
        end
        
        % Instron CSV: 2-row header, columns = [time, disp, force]
       
        meta_raw = readcell(file1, 'Range', '1:2');
        uTime  = meta_raw{2, 1};
        uDisp  = meta_raw{2, 2};
        uForce = meta_raw{2, 3};
  
        
        data   = readmatrix(file1, 'NumHeaderLines', 2);
        time1  = data(:, 1);
        disp1  = data(:, 2); 
        force1 = data(:, 3);
        
    case 'siwwi'
        uTime  = 's';
        uForce = 'N';

        uDisp  = [x_col_choice, ' (mm)'];
        [time1, disp1, force1] = read_siwwi_txt(file1, x_col_choice);
    otherwise
        error('Unknown machine_case: ''%s''. Use ''instron'' or ''siwwi''.', machine_case);
end
fprintf('  Loaded %d data points.\n\n', length(time1));
%% =========================================================================
%  SECTION 5 — FORCE ZEROING
%  Displacement is not zeroed.
%  Force is zeroed only if the first point deviates from zero. in this case > subtract the first force point from all force data.
% =========================================================================
fprintf('--- Force zeroing ---\n');
f_raw  = force1;
d_raw  = disp1;    
t_raw  = time1;
F_first = f_raw(1);   

% Tolerance: if first point is within 0.5% of full-scale, treat as zero
tol_zero = 0.005 * max(abs(f_raw));
if abs(F_first) <= tol_zero
 
    force_z = f_raw;
    fprintf('  First force point = %.4f N  → within tolerance (%.4f N). No zeroing applied.\n\n', F_first, tol_zero);
elseif F_first > tol_zero

    force_z = f_raw - F_first;
    fprintf('  First force point = %.4f N  → added negative offset to zero force initially.\n\n', F_first);
else
  
    force_z = f_raw - F_first;
    fprintf('  First force point = %.4f N  → added positive offset to zero force initially.\n\n', F_first);
end

disp_z = d_raw;
time_z = t_raw;
%% =========================================================================
%  SECTION 6 — UNIT CONVERSION TO SI
%  Internally all calculations use SI units (N, m, Pa).
%  Plotting uses original machine units (N, mm) for readability.
% =========================================================================

if contains(lower(uForce), 'kn')   
    f_N = force_z * 1000;   % kN -> N
else
    f_N = force_z;           % already in N
end

if contains(lower(uDisp), 'mm')
    d_m = disp_z / 1000;    % mm -> m
else
    d_m = disp_z;            % already in m
end
%% =========================================================================
%  SECTION 7 — RAW PLOTS 
% =========================================================================
fprintf('--- Generating raw data plots ---\n');
fig1 = figure('Name', ['Force_vs_', x_col_choice]);   
plot(disp_z, force_z, 'bx', 'DisplayName', sample_name);   
xlabel(uDisp, 'FontWeight', 'bold');   
ylabel(['Force (', uForce, ')'],       'FontWeight', 'bold');

legend('show', 'Location', 'best');
grid on;
fig2 = figure('Name', [x_col_choice, '_vs_Time']);   
plot(time_z, disp_z, 'bx', 'DisplayName', sample_name);   
xlabel(['Time (', uTime, ')'],          'FontWeight', 'bold');
ylabel(uDisp, 'FontWeight', 'bold');   

legend('show', 'Location', 'best');
grid on;
fig3 = figure('Name', 'Force_vs_Time');
plot(time_z, force_z, 'bx', 'DisplayName', sample_name);  
xlabel(['Time (', uTime, ')'],    'FontWeight', 'bold');
ylabel(['Force (', uForce, ')'], 'FontWeight', 'bold');

legend('show', 'Location', 'best');
grid on;
%% =========================================================================
%  SECTION 8 — MECHANICAL ANALYSIS
% =========================================================================
fprintf('--- Mechanical Analysis ---\n\n');

fit_range = [0.1, 1]; % linear fit boundaries, fraction of max force


%  Peak force
[F_max_N, idx_max] = max(f_N);    % F_max in N
d_peak_m  = d_m(idx_max);         % displacement at peak, in m
d_peak_mm = disp_z(idx_max);      %  mm (for display)
fprintf('  Peak force : %.3f N  at disp = %.3f mm\n', F_max_N, d_peak_mm);



% Linear fit to extract stiffness k [N/m]

F_lo = fit_range(1) * F_max_N;
F_hi = fit_range(2) * F_max_N;

% only search within the loading phase (indices 1 to idx_max); prevents post-peak drop points from ruining the fit
idx_window = find(f_N(1:idx_max) >= F_lo & f_N(1:idx_max) <= F_hi);

xw = d_m(idx_window);
yw = f_N(idx_window);

best_R2 = -Inf;
best_idx = idx_window;


min_pts = max(15, round(0.5 * length(idx_window))); % tunable min points for fit

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

% link the best indices found by the loop to the rest of the script
idx_fit = best_idx;

% slope (k_fit)

[p, S] = polyfit(d_m(idx_fit), f_N(idx_fit), 1);
k_fit = p(1);    

% uncertainty 
x_fit    = d_m(idx_fit);
SSx      = sum((x_fit - mean(x_fit)).^2);
se_resid = S.normr / sqrt(S.df);
dk       = se_resid / sqrt(SSx); 

if length(idx_fit) < 5
    warning('Fewer than 5 points in fit range.');
end


% actual speed from fit > safety check only
%  Linear fit of displacement(mm) vs time(s) over the same loading region
p_speed   = polyfit(time_z(idx_fit), disp_z(idx_fit), 1);
act_speed = p_speed(1);   % [mm/s]
fprintf('  Actual speed : %.4f mm/s  (set: %.4f mm/s)\n', act_speed, set_speed_mms);

%  Flexural strength 
%  sigma_f = 3 * F * L / (2 * w * b^2)
%  All inputs in SI (N, m) → result in Pa → convert to kPa
%
%  Derivation: for a simply-supported beam with central point load F,
%  the maximum bending moment is M = F*L/4.
%  Maximum fibre stress: sigma = M * (b/2) / I  where I = w*b^3/12
%  => sigma = (F*L/4) * (b/2) / (w*b^3/12) = 3*F*L / (2*w*b^2)   

sigma_f_Pa  = (3 * F_max_N * L) / (2 * w * b^2);
sigma_f_kPa = sigma_f_Pa / 1000;

% Uncertainty propagation :
%   d(sigma_f)/sigma_f = sqrt( (dF/F)^2 + (dL/L)^2 + (dw/w)^2 + (2*db/b)^2 )

dF = 0.5;   % force measurement uncertainty [N] 

rel_sigma = sqrt( (dF/F_max_N)^2 + (dL/L)^2 + (dw/w)^2 + (2*db/b)^2 );
d_sigma_kPa = rel_sigma * sigma_f_kPa;

% elastic modulus ----
%  From beam theory:  k = 4 * E * w * b^3 / L^3
%  Therefore:         E = k * L^3 / (4 * w * b^3)

E_Pa  = (k_fit * L^3) / (4 * w * b^3);
E_MPa = E_Pa / 1e6;
E_GPa = E_Pa / 1e9;


% Uncertainty propagation:
%   d(E)/E = sqrt( (dk/k)^2 + (3*dL/L)^2 + (dw/w)^2 + (3*db/b)^2 )

rel_E  = sqrt( (dk/k_fit)^2 + (3*dL/L)^2 + (dw/w)^2 + (3*db/b)^2 );
dE_MPa = rel_E * E_MPa;
dE_GPa = rel_E * E_GPa;


%  Geometry ratios (ITTC recommendations) 
L_b = L / b;   % span-to-thickness ratio; ITTC: 5–7
w_b = w / b;   % width-to-thickness ratio; ITTC: 2–3

R2 = 1 - (S.normr^2 / sum((f_N(idx_fit) - mean(f_N(idx_fit))).^2));
fprintf('  Fit R^2 = %.5f\n', R2);

%% =========================================================================
%  SECTION 9 — PRINT RESULTS
% =========================================================================
fprintf('\n========== RESULTS: %s ==========\n', sample_name);
fprintf('  Temperature       : %.1f °C\n',        T_celsius);
fprintf(['  Dimensions        : w=%.1' ...
    'f mm, L=%.1f mm, b=%.1f mm\n'], w*1000, L*1000, b*1000);
fprintf('  L/b ratio         : %.2f  (ITTC rec: 5–7)\n',  L_b);
fprintf('  w/b ratio         : %.2f  (ITTC rec: 2–3)\n',  w_b);
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


filename_clean = strrep(filename, '_', '\_');

%  Plot zeroed force vs raw displacement 
plot(disp_z, force_z, 'bx', 'DisplayName', 'Raw Data');   
hold on;

% Peak marker 
plot([d_peak_mm, d_peak_mm], [0, max(force_z)], 'k--', 'LineWidth', 2, ...
     'DisplayName', sprintf('Peak Force = %.1f N', F_max_N));

%Fit range bounds

if contains(lower(uForce), 'kn')
    F_lo_plot = F_lo / 1000;   % N -> kN for overlay on kN plot
    F_hi_plot = F_hi / 1000;
else
    F_lo_plot = F_lo;          % already in N
    F_hi_plot = F_hi;
end

% Fitted line overlaid on the data
d_fit_mm  = linspace(disp_z(idx_fit(1)), disp_z(idx_fit(end)), 100);
d_fit_m   = d_fit_mm / 1000;
f_fit_N   = k_fit * d_fit_m + p(2);   % polyfit: y = p(1)*x + p(2), result in N

% Convert fitted force back to machine units for overlay
if contains(lower(uForce), 'kn')
    f_fit_plot = f_fit_N / 1000;   % N -> kN
else
    f_fit_plot = f_fit_N;          % already in N
end


fit_str = sprintf('Linear Fit  \nE = %.1f GPa, R^2 = %.5f', ...
                  E_GPa, R2);

plot(d_fit_mm, f_fit_plot, 'r-', 'LineWidth', 2, 'DisplayName', fit_str);
hold off;

xlabel(uDisp, 'FontWeight', 'bold');   
ylabel(['Force ', uForce, ], 'FontWeight', 'bold');
grid on;

% Legend Box 
lgd = legend('show', 'Location', 'best');
title(lgd, filename_clean);

%% =========================================================================
%  SECTION 11 — SAVE OUTPUT FILES
% =========================================================================

% Create output directory if needed
if (savefig || save_mech) && ~exist(savePath, 'dir')
    mkdir(savePath);
end


if savefig

    fprintf('--- Saving figures to: %s ---\n', savePath);

    % Get all currently open figure handles
    open_figs = findall(0, 'Type', 'figure');

    
    [~, idx_sort] = sort([open_figs.Number]);
    open_figs = open_figs(idx_sort);

    for iFig = 1:length(open_figs)

        fig_handle = open_figs(iFig);

    
        fig_name = fig_handle.Name;

        % Fallback if figure has no Name property
        if isempty(fig_name)
            fig_name = sprintf('figure_%d', fig_handle.Number);
        end

      
        fig_name = lower(fig_name);
        fig_name = strrep(fig_name, ' ', '_');
        fig_name = strrep(fig_name, '-', '_');

        
        fig_filename = sprintf('%s_%s_%s', ...
                               date, machine_case, fig_name);

        base_file = fullfile(savePath, fig_filename);

     
        % PNG
   
        exportgraphics(fig_handle, ...
                       [base_file '.png'], ...
                       'Resolution', 300);

    
        % PDF
 
        exportgraphics(fig_handle, ...
                       [base_file '.pdf'], ...
                       'ContentType', 'vector');

        fprintf('  Saved: %s (.png & .pdf)\n', fig_filename);

    end

    fprintf('\n');

end


%  save mech results table as csv

if save_mech

    results.Filename         = filename;
    results.SampleType       = char(sample_type);

    results.Temperature_C    = T_celsius;

    results.w_mm             = w * 1000;
    results.L_mm             = L * 1000;
    results.b_mm             = b * 1000;

    results.L_b_ratio        = L_b;
    results.w_b_ratio        = w_b;

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

    results.E_MPa            = E_MPa;
    results.dE_MPa           = dE_MPa;

    results.E_GPa            = E_GPa;
    results.dE_GPa           = dE_GPa;

    results.R2               = R2;


    resTable = struct2table(results);

    out_csv = fullfile(savePath, ...
              [filename '_mech_props.csv']);

    writetable(resTable, out_csv);

    fprintf('--- Results saved: %s ---\n', out_csv);

end
%% =========================================================================
%  func
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
%   x_col_choice — string selecting which column to return as
%                  disp_out. Accepted values:
%                    'Displacement' — col 4 
%                    'Extension'    — col 2 
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
    % Assign force and time 
    force_out = C{1};   % Load [N]
    time_out  = C{7};   % Time [s]
    % Select x-axis column based on user choice.
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
    fprintf(' Time (s) | Load (N)  | %s (mm)\n', x_col_choice);  
    fprintf('-----------------------------------\n');
    for idx = 1:min(5, length(time_out))
        fprintf(' %8.4f | %9.4f | %9.4f\n', time_out(idx), force_out(idx), disp_out(idx));
    end
    fprintf('-----------------------------------\n\n');
end