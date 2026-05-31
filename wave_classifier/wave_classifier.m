% ==========================================================================
%  Le Méhauté Wave Theory Classifier  
%  REFERENCES:
%    Le Méhauté (1976); Zhao, Wang & Liu, Coastal Eng. 188 (2024) 104432.
% ==========================================================================

clear; clc; close all;

%% =========================================================================
%  SECTION 1: USER PARAMETERS
% ==========================================================================

water_depth_m   = 0.3;          % still water depth h  [m]
output_csv_path = 'E:\SIWWI2026\wave_classifier\waves_class.csv';            % set to '' to skip CSV export
output_figures = 'E:\SIWWI2026\wave_classifier\';

% =========================================================================
%  SECTION 2: CSV INPUT PAIRS
% ==========================================================================

csv_pairs = {
    'E:\SIWWI2026\280426\Waves_param_HIGH_280426.csv',  ...
    'E:\SIWWI2026\280426\results_postprocess_REPROCESS2505280426\Results_postprocess_all_280426.csv', ...
    '28/04/26';
    'E:\SIWWI2026\060526\wave_ice_test\Waves_param_HIGH_060526.csv',  ...
    'E:\SIWWI2026\060526\wave_ice_test\results_postprocess_060526\Results_postprocess_060526.csv', ...
    '06/05/26';
    'E:\SIWWI2026\130526\Waves_param_HIGH_130526.csv', ...
    'E:\SIWWI2026\130526\results_postprocess_130526\Results_postprocess_130526.csv', ...
    '13/05/26';
     'E:\SIWWI2026\140526\Waves_param_HIGH_140526.csv', ...
    'E:\SIWWI2026\140526\results_postprocess_140526\Results_postprocess_140526.csv', ...
    '14/05/26';
    'E:\SIWWI2026\200526\Waves_param_HIGH_200526.csv', ...
    'E:\SIWWI2026\200526\results_postprocess_BENCHMARK200526\Results_postprocess_BENCHMARK_200526.csv', ...
    '20/05/26';


};

n_pairs = size(csv_pairs, 1);

% =========================================================================
%  SECTION 3: ICE PRESENCE PER EXPERIMENT
% ==========================================================================

has_ice = false(n_pairs, 1);
for i = 1:n_pairs
    prompt = sprintf('Experiment "%s": was ice present? (y/n): ', csv_pairs{i,3});
    answer = input(prompt, 's');
    has_ice(i) = strcmpi(strtrim(answer), 'y');
    fprintf('  -> %s: ice = %s\n', csv_pairs{i,3}, mat2str(has_ice(i)));
end

% =========================================================================
%  SECTION 4: PHYSICAL CONSTANTS
% ==========================================================================

g = 9.81;
h = water_depth_m;

fprintf('\n--- Physical setup ---\n');
fprintf('  Water depth h = %.4f m\n', h);
fprintf('  g            = %.4f m/s^2\n', g);

% Frequency-matching tolerance (fractional, i.e. 0.12 = 12%).
% This catches the ~5-10% offset between the nominal frequencies stored
% in the wave-params CSV and the actual SetFrequency_Hz logged by the
% wavemaker controller in the results CSV.
FREQ_MATCH_TOL = 0.12;

%% =========================================================================
%  SECTION 5: LOAD PAIRS, COMPUTE Le MÉHAUTÉ COORDINATES
% ==========================================================================

colors_water = lines(n_pairs);
colors_ice   = [0.85 0.10 0.10;
                0.90 0.45 0.00;
                0.75 0.00 0.75;
                0.60 0.20 0.20];

all_results = struct('label',{}, 'has_ice',{}, 'X_pts',{}, 'Y_pts',{});

fprintf('\n=======================================================\n');
fprintf('  COMPUTED Le MEHAUTE COORDINATES\n');
fprintf('=======================================================\n');
fprintf('%-20s %-6s %-10s %-10s %-10s %-10s %-8s %-8s %-8s %-18s\n', ...
    'Label','Ice?','T(s)','H(m)','h/gT2','H/gT2','h/L','H/L','Ur','Zone');
fprintf('%s\n', repmat('-',1,110));

result_rows = {};

for i = 1:n_pairs

    % ------------------------------------------------------------------
    %  BUILD FREQUENCY -> LAMBDA MAP from the wave-params file.
    %  Key insight: use the f_Hz column (nominal wavemaker frequency)
    %  rather than T_s, because the results file stores SetFrequency_Hz
    %  which may differ slightly from 1/T_s.
    % ------------------------------------------------------------------
    wp = readtable(csv_pairs{i,1});

    % All unique (f_Hz, lambda_m) pairs from wave params
    % Round f to 6 dp to avoid floating-point duplicates
    f_wp_all  = round(wp.f_Hz,    6);
    L_wp_all  = wp.lambda_m;
    [f_uniq, idx_uniq] = unique(f_wp_all);
    L_uniq = L_wp_all(idx_uniq);

    % Store as vectors for nearest-neighbour lookup (no containers.Map needed)
    % f_uniq and L_uniq are already sorted by unique()

    % ------------------------------------------------------------------
    %  LOAD RESULTS
    % ------------------------------------------------------------------
    res = readtable(csv_pairs{i,2});
    n_rows = height(res);

    fprintf('\n--- Pair %d: %s  (ice=%s) ---\n', i, csv_pairs{i,3}, mat2str(has_ice(i)));
    fprintf('    Wave-params frequencies available: ');
    fprintf('%.4f ', f_uniq);
    fprintf('Hz\n');
    fprintf('    Results SetFrequency_Hz values:   ');
    f_res_unique = unique(round(res.SetFrequency_Hz, 4));
    fprintf('%.4f ', f_res_unique);
    fprintf('Hz\n');
    fprintf('    Matching tolerance: %.0f%%\n', FREQ_MATCH_TOL*100);

    X_pts = NaN(n_rows,1);
    Y_pts = NaN(n_rows,1);
    skip_count = 0;

    for j = 1:n_rows

        % Measured frequency and period (from FFT — most accurate)
        f_meas = res.MeasuredFrequency_FFT_Hz(j);
        T_j    = 1 / f_meas;

        % Wave HEIGHT = 2 * measured amplitude
        amp_j  = res.MeasuredAmplitude_m(j);
        H_j    = 2 * amp_j;

        % ---- FUZZY MATCH: SetFrequency_Hz -> nearest f in wave params ----
        % We use SetFrequency (the programmed value) for the lambda lookup,
        % because lambda was computed for those nominal frequencies.
        f_set = res.SetFrequency_Hz(j);

        % Find nearest wave-params frequency
        [min_err_abs, idx_match] = min(abs(f_set - f_uniq));
        f_matched = f_uniq(idx_match);
        rel_err   = min_err_abs / f_matched;

        if rel_err > FREQ_MATCH_TOL
            % No acceptable match found — explain why and skip
            fprintf(['    [SKIP] Row %d: f_set=%.4f Hz — nearest wave-param freq is' ...
                     ' %.4f Hz (%.1f%% off, exceeds %.0f%% tolerance). ' ...
                     'No lambda available.\n'], ...
                     j, f_set, f_matched, rel_err*100, FREQ_MATCH_TOL*100);
            skip_count = skip_count + 1;
            continue
        end

        % Retrieve wavelength for the matched frequency
        L_j = L_uniq(idx_match);

        % ---- Le Méhauté coordinates ----
        X_j = h / (g * T_j^2);    % h/(gT^2) — dimensionless depth
        Y_j = H_j / (g * T_j^2);  % H/(gT^2) — dimensionless steepness

        % ---- Dimensionless ratios for zone classification ----
        hL_j = h / L_j;
        HL_j = H_j / L_j;
        Ur_j = HL_j / hL_j^3;     % Ursell number

        % ---- Zone classification (Zhao et al. 2024) ----
        if hL_j > 0.5
            depth_zone = 'Deep';
        elseif hL_j > 0.05
            depth_zone = 'Intermediate';
        else
            depth_zone = 'Shallow';
        end

        if Ur_j > 26
            theory_zone = 'Cnoidal';
        elseif HL_j < 0.0064
            theory_zone = 'Linear';
        elseif HL_j < 0.0472
            theory_zone = 'Stokes-2nd';
        elseif HL_j < 0.0697
            theory_zone = 'Stokes-3rd';
        elseif HL_j < 0.0896
            theory_zone = 'Stokes-4th';
        elseif HL_j < 0.141
            theory_zone = 'Stokes-5th';
        else
            theory_zone = 'BREAKING';
        end
        zone_str = sprintf('%s / %s', depth_zone, theory_zone);

        X_pts(j) = X_j;
        Y_pts(j) = Y_j;

        % Console output
        ice_str = 'No ';
        if has_ice(i), ice_str = 'YES'; end
        fprintf('%-20s %-6s %-10.4f %-10.5f %-10.5f %-10.6f %-8.4f %-8.5f %-8.3f %-18s\n', ...
            csv_pairs{i,3}, ice_str, T_j, H_j, X_j, Y_j, hL_j, HL_j, Ur_j, zone_str);

        result_rows{end+1} = {csv_pairs{i,3}, has_ice(i), T_j, H_j, ...
            X_j, Y_j, hL_j, HL_j, Ur_j, depth_zone, theory_zone};
    end

    fprintf('    => %d rows plotted, %d rows skipped.\n', ...
        sum(~isnan(X_pts)), skip_count);

    valid = ~isnan(X_pts);
    all_results(end+1).label   = csv_pairs{i,3};
    all_results(end).has_ice   = has_ice(i);
    all_results(end).X_pts     = X_pts(valid);
    all_results(end).Y_pts     = Y_pts(valid);
end

fprintf('\n%s\n\n', repmat('-',1,110));
%% =========================================================================
%  SECTIONS 6–8: Le MÉHAUTÉ DIAGRAM
% ==========================================================================
% ---- Colour palette ----
col_black = [0.00 0.00 0.00];
col_zone  = [0.18 0.20 0.55];
col_Ur    = [0.00 0.00 0.00];

% ---- Figure ----
fig = figure('Name','Le Mehaute Diagram','Color','w', ...
    'Units','centimeters','Position',[2 2 23 18]);
ax = axes(fig);
hold(ax,'on');

x_lim = [0.0005, 0.5];
y_lim = [5e-5,   0.05];

% ---- h/L sweep grid ----
hL_vec = logspace(log10(5e-4), log10(3.0), 4000);

% ---- Coordinate transforms ----
% Dispersion relation: h/(gT^2) = (h/L)*tanh(2*pi*h/L)/(2*pi)
tanh_kh = @(hL) tanh(2*pi .* hL);
xc      = @(hL)      hL  .* tanh_kh(hL) / (2*pi);
yc      = @(hL, HL)  HL  .* tanh_kh(hL) / (2*pi);
x_all = xc(hL_vec);

% ---- Breaking curve (Fenton 1990, Eq. 7) ----
HL_break = hL_vec .* ...
    (0.141063*hL_vec.^2 + 0.0095721*hL_vec + 0.0077829) ./ ...
    (hL_vec.^3 + 0.078834*hL_vec.^2 + 0.0317567*hL_vec + 0.0093407);
inbox = @(xv,yv) xv>=x_lim(1) & xv<=x_lim(2) & yv>=y_lim(1) & yv<=y_lim(2);

% ---- Ur=26 boundary ----
HL_Ur26 = 26 * hL_vec.^3;

% =========================================================================
%  (A) BREAKING CRITERION
% =========================================================================
y_brk = yc(hL_vec, HL_break);
m = inbox(x_all, y_brk);
loglog(ax, x_all(m), y_brk(m), '-', 'Color',col_black, 'LineWidth',2.0, ...
    'HandleVisibility','off');

% =========================================================================
%  (B) CNOIDAL/STOKES BOUNDARY  Ur=26
% =========================================================================
HL_cn = min(HL_Ur26, HL_break);
y_cn  = yc(hL_vec, HL_cn);
m = inbox(x_all, y_cn);
loglog(ax, x_all(m), y_cn(m), '-', 'Color',col_black, 'LineWidth',2.0, ...
    'HandleVisibility','off');

% =========================================================================
%  (C) STOKES ORDER BOUNDARY LINES
% =========================================================================
HL_thresholds = [0.0064, 0.0472, 0.0697];
for k = 1:length(HL_thresholds)
    HL_thr  = HL_thresholds(k);
    hL_star = (HL_thr / 26)^(1/3);
    
    HL_k = zeros(size(hL_vec));
    for jj = 1:length(hL_vec)
        if hL_vec(jj) < hL_star
            HL_k(jj) = 26 * hL_vec(jj)^3;
        else
            HL_k(jj) = HL_thr;
        end
    end
    HL_k = min(HL_k, HL_break);
    y_k  = yc(hL_vec, HL_k);
    
    m = inbox(x_all, y_k);
    loglog(ax, x_all(m), y_k(m), '-', 'Color',col_black, 'LineWidth',1.3, ...
        'HandleVisibility','off');
end

% =========================================================================
%  (D) Ur ISO-LINES  (black dashed)
% =========================================================================
% Ur=20 (unchanged)
HL_ur20 = 20 * hL_vec.^3;
y_ur20  = yc(hL_vec, HL_ur20);
draw20  = inbox(x_all, y_ur20) & (HL_ur20 <= HL_break + 1e-9);
if any(draw20)
    loglog(ax, x_all(draw20), y_ur20(draw20), '--', 'Color',col_Ur, ...
        'LineWidth',1.1, 'HandleVisibility','off');
end

% Ur=1 (VISUAL FIX to match the original diagram's termination point)
% We explicitly force the line to end on the breaking curve at x=0.05 
% (the yellow highlighted area) by drawing a straight log-log line from 
% its natural entry point up to the exact intersection target.
HL_ur1_true = 1 * hL_vec.^3;
y_ur1_true  = yc(hL_vec, HL_ur1_true);

x_left_Ur1  = 0.007; 
y_left_Ur1  = interp1(x_all, y_ur1_true, x_left_Ur1, 'linear', 'extrap'); % Bottom entry

x_right_Ur1 = 0.05; % Force termination at x = 0.05
% Find corresponding y on the breaking criterion
hL_right_Ur1   = interp1(x_all, hL_vec, x_right_Ur1, 'linear', 'extrap');
HL_break_right = interp1(hL_vec, HL_break, hL_right_Ur1, 'linear', 'extrap');
y_right_Ur1    = yc(hL_right_Ur1, HL_break_right);

% Create the customized visual line connecting these points
x_ur1_mod = logspace(log10(x_left_Ur1), log10(x_right_Ur1), 200);
y_ur1_mod = logspace(log10(y_left_Ur1), log10(y_right_Ur1), 200);

loglog(ax, x_ur1_mod, y_ur1_mod, '--', 'Color',col_Ur, ...
    'LineWidth',1.1, 'HandleVisibility','off');


% =========================================================================
%  (E) DEPTH-REGIME VERTICAL LINES
% =========================================================================
x_hL005 = xc(0.05);
x_hL05  = xc(0.5);
loglog(ax, [x_hL005 x_hL005], y_lim, '-', 'Color',col_zone, 'LineWidth',1.8, 'HandleVisibility','off');
loglog(ax, [x_hL05  x_hL05],  y_lim, '-', 'Color',col_zone, 'LineWidth',1.8, 'HandleVisibility','off');

% =========================================================================
%  SECTION 7: SCATTER DATA POINTS
% =========================================================================
marker_water = 'o';
marker_ice   = 'd';
markersize   = 8;

for i = 1:length(all_results)
    X_i = all_results(i).X_pts;
    Y_i = all_results(i).Y_pts;
    
    if all_results(i).has_ice
        clr = colors_ice(mod(i-1, size(colors_ice,1))+1, :);
        mkr = marker_ice;
        lbl = sprintf('%s  (ice)', all_results(i).label);
    else
        clr = colors_water(i,:);
        mkr = marker_water;
        lbl = sprintf('%s  (water)', all_results(i).label);
    end
    
    loglog(ax, X_i, Y_i, mkr, ...
        'MarkerSize',markersize, 'Color',clr, 'MarkerFaceColor',clr, ...
        'DisplayName',lbl);
end

% =========================================================================
%  SECTION 8: FORMATTING, LABELS, LEGEND
% =========================================================================
set(ax,'XScale','log','YScale','log','XLim',x_lim,'YLim',y_lim);
set(ax,'XTick',      [0.0005, 0.005, 0.05, 0.5]);
set(ax,'YTick',      [5e-5,   5e-4,  5e-3,  0.05]);
set(ax,'XTickLabel', {'0.0005','0.005','0.05','0.5'});
set(ax,'YTickLabel', {'5E-05','5E-04','5E-03','0.05'});
set(ax,'TickDir','in','TickLength',[0.012 0.012]);
grid(ax,'on'); set(ax,'MinorGridLineStyle','none'); box(ax,'on');

ax.FontSize = 10;
xlabel(ax,'h/gT^2','FontSize',11);
ylabel(ax,'H/gT^2','FontSize',11);
title(ax,"Le Mehaute's diagram - dimensionless axis",'FontSize',12,'FontWeight','normal');

ax.Position(3) = ax.Position(3) - 0.07;

find_y_at_x = @(xv,yv,xtgt) interp1(log10(xv(yv>0 & xv>0)), ...
    log10(yv(yv>0 & xv>0)), log10(xtgt), 'linear','extrap');

% Zone header labels
text(ax,0.00065,0.042,'Shallow water',          'FontSize',8.5,'Color',col_zone,'HorizontalAlignment','left');
text(ax,0.0028, 0.042,'Intermediate water depth','FontSize',8.5,'Color',col_zone,'HorizontalAlignment','left');
text(ax,0.12,   0.042,'Deep water',              'FontSize',8.5,'Color',col_zone,'HorizontalAlignment','left');

% Depth boundary labels

text(ax, x_hL005*1.15, 8e-5, '$h/\lambda = 0.05$', 'Interpreter', 'latex', 'FontSize', 8, 'Color', col_zone, 'Rotation', 90, 'HorizontalAlignment', 'center');
text(ax, x_hL05*1.25, 1.5e-4, '$h/\lambda = 0.5$', 'Interpreter', 'latex', 'FontSize', 8, 'Color', col_zone, 'Rotation', 90, 'HorizontalAlignment', 'center');

% Breaking criterion label
x_brk_lbl = 0.003;
y_brk_v    = yc(hL_vec, HL_break);
y_brk_lbl  = 10^find_y_at_x(x_all, y_brk_v, x_brk_lbl);
text(ax,x_brk_lbl,y_brk_lbl*1.6,'Breaking Criterion','FontSize',8.5,'Color','k','Rotation',46,'HorizontalAlignment','center');

% Cnoidal label
x_cn_lbl = 0.002;
y_cn_v    = yc(hL_vec, HL_cn);
y_cn_lbl  = 10^find_y_at_x(x_all, y_cn_v, x_cn_lbl);
text(ax,x_cn_lbl*0.78,y_cn_lbl*1.5,{'Cnoidal','wave theory'},'FontSize',8.5,'Color','k','FontAngle','italic','Rotation',52,'HorizontalAlignment','center');

% Ur iso-line labels
x_Ur20_lbl = xc(0.08); y_Ur20_lbl = yc(0.08, 20*0.08^3);
text(ax,x_Ur20_lbl*1.1,y_Ur20_lbl*1.3,'U_r = 20','FontSize',8,'Color','k','HorizontalAlignment','left');

% Ur=1 label: aligned with our visually-modified line
x_Ur1_lbl = x_ur1_mod(50);
y_Ur1_lbl = y_ur1_mod(50);
text(ax,x_Ur1_lbl,y_Ur1_lbl*2.5,'U_r = 1','FontSize',8,'Color','k','HorizontalAlignment','left');

% Stokes order labels
x_lbl = 0.15;
y_lin = 10^find_y_at_x(x_all, yc(hL_vec, 0.0064*ones(size(hL_vec))), x_lbl);
y_2nd = 10^find_y_at_x(x_all, yc(hL_vec, 0.0472*ones(size(hL_vec))), x_lbl);
y_3rd = 10^find_y_at_x(x_all, yc(hL_vec, 0.0697*ones(size(hL_vec))), x_lbl);
y_brk_lbl2 = 10^find_y_at_x(x_all, y_brk_v, x_lbl);

text(ax,x_lbl,10^(0.5*(log10(y_lim(1)) +log10(y_lin))),'Linear',   'FontSize',9,'Color','k','HorizontalAlignment','left');
text(ax,x_lbl,10^(0.5*(log10(y_lin)    +log10(y_2nd))),'2nd order','FontSize',9,'Color','k','HorizontalAlignment','left');
text(ax,x_lbl,10^(0.5*(log10(y_2nd)    +log10(y_3rd))),'3rd order','FontSize',9,'Color','k','HorizontalAlignment','left');
text(ax,x_lbl,10^(0.5*(log10(y_3rd)    +log10(y_brk_lbl2))),'4th order','FontSize',9,'Color','k','HorizontalAlignment','left');

lgd = legend(ax, 'Location', 'northwestoutside', 'FontSize', 9, 'Box', 'on');lgd = legend(ax, 'FontSize', 9, 'Box', 'on');
% [left, bottom, width, height]
set(lgd, 'Position', [0.135 0.75 0.15 0.1]);lgd.Title.String = 'Experiments';
hold(ax,'off');


% =========================================================================
%  SECTION 9: SUMMARY STATISTICS
% ==========================================================================
fprintf('=======================================================\n');
fprintf('  SUMMARY STATISTICS\n');
fprintf('=======================================================\n');
for i = 1:length(all_results)
    X_i = all_results(i).X_pts;
    Y_i = all_results(i).Y_pts;
    fprintf('Dataset: %s | Ice: %s\n', all_results(i).label, mat2str(all_results(i).has_ice));
    fprintf('  N points     = %d\n', numel(X_i));
    fprintf('  h/gT^2 range = %.5f  to  %.5f\n', min(X_i), max(X_i));
    fprintf('  H/gT^2 range = %.6f  to  %.6f\n\n', min(Y_i), max(Y_i));
end

%% =========================================================================
%  SECTION 10: CSV EXPORT (optional)
% ==========================================================================
if ~isempty(output_csv_path) && ~isempty(result_rows)
    headers = {'Dataset','Has_Ice','T_s','H_m','h_over_gT2','H_over_gT2', ...
               'h_over_L','H_over_L','Ursell_Ur','Depth_Zone','Theory_Zone'};
    out_df = cell2table(vertcat(result_rows{:}), 'VariableNames', headers);
    writetable(out_df, output_csv_path);
    fprintf('Results saved to: %s\n', output_csv_path);
end

%% =========================================================================
%  SECTION 11: FIGURE EXPORT
% ==========================================================================
output_figures = 'E:\SIWWI2026\wave_classifier\';

% Use fullfile to combine the folder path and the filename
pdf_output_path = fullfile(output_figures, 'lemehaute_diagram.pdf');

pdf_width_cm    = 26;
pdf_height_cm   = 19;
pdf_font_size   = 11;

set(findall(fig,'-property','FontSize'),'FontSize',pdf_font_size);
width_in  = pdf_width_cm  / 2.54;
height_in = pdf_height_cm / 2.54;
set(fig,'PaperUnits','inches','PaperSize',[width_in,height_in], ...
    'PaperPosition',[0,0,width_in,height_in],'PaperPositionMode','manual');

% Save PDF
print(fig, pdf_output_path, '-dpdf', '-r300');
fprintf('Figure saved to PDF: %s\n', pdf_output_path);

% Save PNG (This automatically inherits the correct folder path)
png_output_path = strrep(pdf_output_path, '.pdf', '.png');
print(fig, png_output_path, '-dpng', '-r200');
fprintf('Figure saved to PNG: %s\n', png_output_path);