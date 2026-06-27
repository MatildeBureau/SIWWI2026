% ==========================================================================
%  Le Méhauté Wave Theory Classifier 
%  REFERENCES:
%    Le Méhauté (1976); Zhao, Wang & Liu, Coastal Eng. 188 (2024) 104432.
%  ------------------------------------------------------------------
% Reproduces Le Méhauté's diagram and places all SIWWI tests as scatter
% points.
%


clear; clc; close all;

%% =========================================================================
%   USER PARAMETERS
% ==========================================================================
water_depth_m   = 0.3; %m

output_csv_path = 'E:\SIWWI2026\wave_classifier\waves_class.csv';
output_figures  = 'E:\SIWWI2026\wave_classifier\';

% =========================================================================
%  CSV INPUT PAIRS
% =========================================================================
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
%  ICE PRESENCE PER EXPERIMENT
% =========================================================================
has_ice = false(n_pairs, 1);
for i = 1:n_pairs
    prompt = sprintf('Experiment "%s": was ice present? (y/n): ', csv_pairs{i,3});
    answer = input(prompt, 's');
    has_ice(i) = strcmpi(strtrim(answer), 'y');
    fprintf('  -> %s: ice = %s\n', csv_pairs{i,3}, mat2str(has_ice(i)));
end

% =========================================================================
% PHYSICAL CONSTANTS
% =========================================================================
g       = 9.81;
H_water = water_depth_m;

% --- Ice parameters ---
E_ice   = 2.1e9; %Pa
rho_ice = 895; %kg/m3
h_ice   = 0.01; %m , ice thickness
nu_ice  = 0.33; % Poisson
rho_w   = 1000; % kg/m3
sigma_f = 1985e3; % measured flexural strength for ice, Pa

% --- Uncertainties ---
dE_ice   = 1.7e9;      % uncertainty on Young's modulus [Pa]
dh_ice   = 0.003;      % uncertainty on ice thickness [m]     
dsigma_f = 1168e3;      % uncertainty on flexural strength [Pa] 
% da (amplitude uncertainty) is read per-row from UncertaintyAmplitude_m in the results CSV

D_flex = E_ice * h_ice^3 / (12 * (1 - nu_ice^2)); % flexural modulus
L_d    = (D_flex / (rho_w * g))^0.25; % flexural length

% Flexural rigidity at E_ice+dE_ice and at h_ice+dh_ice (one parameter
% perturbed at a time). Used to propagate uncertainty on the ice-modified
% wavelength/wavenumber via finite differences (see lambda_ratio below).
D_flex_Eplus = (E_ice + dE_ice) * h_ice^3            / (12 * (1 - nu_ice^2));
D_flex_hplus = E_ice            * (h_ice + dh_ice)^3 / (12 * (1 - nu_ice^2));

fprintf('\n--- Physical setup ---\n');
fprintf('  Water depth H       = %.4f m\n', H_water);
fprintf('  g                   = %.4f m/s^2\n', g);
fprintf('  Ice thickness h     = %.4f m\n', h_ice);
fprintf('  Flexural rigidity D = %.4e N.m\n', D_flex);
fprintf('  Elastic length L_d  = %.4f m\n', L_d);
fprintf('  dE / E              = %.1f%%\n', dE_ice/E_ice*100);
fprintf('  dh / h              = %.1f%%\n', dh_ice/h_ice*100);
fprintf('  dsigma_f / sigma_f  = %.1f%%\n', dsigma_f/sigma_f*100);

% Frequency-matching tolerance
FREQ_MATCH_TOL = 0.12;

% =========================================================================
%   LOAD PAIRS, COMPUTE Le MÉHAUTÉ COORDINATES
% =========================================================================
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
    'Label','Ice?','T(s)','a(m)','H/gT2','2a/gT2','H/L','a/L','Ur','Zone');
fprintf('%s\n', repmat('-',1,110));

result_rows = {};

for i = 1:n_pairs
    wp = readtable(csv_pairs{i,1});

    % Required columns
    f_wp_full  = round(wp.f_Hz, 6);   % nominal frequency [Hz]
    L_wp_full  = wp.lambda_m;          % set wavelength [m]
    T_wp_full  = wp.T_s;               % set period [s]

    if ismember('ka', wp.Properties.VariableNames)
        ka_wp_full = wp.ka;
    else
        ka_wp_full = NaN(size(f_wp_full));
        warning('Column "ka" not found in %s. Filled with NaNs.', csv_pairs{i,1});
    end

    if ismember('a_m', wp.Properties.VariableNames)
        a_set_wp_full = wp.a_m;        % set amplitude [m]
    else
        % Reconstruct set amplitude from ka and k = 2*pi/lambda
        k_wp_full     = 2*pi ./ L_wp_full;
        a_set_wp_full = ka_wp_full ./ k_wp_full;
    end

    % frequencies (for diagnostic print only)
    f_uniq_diag = unique(round(f_wp_full, 4));

    % ------------------------------------------------------------------
    %  LOAD RESULTS
    % ------------------------------------------------------------------
    res = readtable(csv_pairs{i,2});
    n_rows = height(res);

    fprintf('\n--- Pair %d: %s  (ice=%s) ---\n', i, csv_pairs{i,3}, mat2str(has_ice(i)));
    fprintf('    Wave-params frequencies available: ');
    fprintf('%.4f ', f_uniq_diag);
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
        % ---------------------------------------------------------------
        %  Measured frequency, period, amplitude
        % ---------------------------------------------------------------
        f_meas  = res.MeasuredFrequency_FFT_Hz(j);
        T_j     = 1 / f_meas;
        omega_j = 2 * pi * f_meas;

        a_j = res.MeasuredAmplitude_m(j);
        % Per-row amplitude uncertainty from the results CSV
        if ismember('UncertaintyAmplitude_m', res.Properties.VariableNames)
            da_j = res.UncertaintyAmplitude_m(j);
        else
            da_j = 0;   % fallback if column absent
        end
   
        H_j = 2 * a_j;

        % ---------------------------------------------------------------
        %  Frequency match: find all wave-params rows whose
        %  f_Hz is within tolerance of SetFrequency_Hz.
        % ---------------------------------------------------------------
        f_set = res.SetFrequency_Hz(j);

        freq_err_rel = abs(f_set - f_wp_full) ./ f_wp_full;
        freq_cands   = find(freq_err_rel <= FREQ_MATCH_TOL);

        if isempty(freq_cands)
            [min_err_abs, idx_closest] = min(abs(f_set - f_wp_full));
            f_closest = f_wp_full(idx_closest);
            rel_err   = min_err_abs / f_closest;
            fprintf(['    [SKIP] Row %d: f_set=%.4f Hz — nearest wave-param freq is' ...
                     ' %.4f Hz (%.1f%% off, exceeds %.0f%% tolerance). ' ...
                     'No lambda available.\n'], ...
                     j, f_set, f_closest, rel_err*100, FREQ_MATCH_TOL*100);
            skip_count = skip_count + 1;
            continue
        end

        % ---------------------------------------------------------------
        %   Amplitude match: among frequency candidates, pick
        %  the row whose set amplitude a_set is closest to a_m.
        %  This resolves which steepness (ka) was actually commanded.
        % ---------------------------------------------------------------
        a_set_cands = a_set_wp_full(freq_cands);
        [~, best_local] = min(abs(a_set_cands - a_j));
        idx_match = freq_cands(best_local);

        % Retrieve metadata for matched row
        L_j_set   = L_wp_full(idx_match);
        ka_set_j  = ka_wp_full(idx_match);
        T_set_j   = T_wp_full(idx_match);
        f_set_j   = 1 / T_set_j;    % set/nominal frequency [Hz]

        % ---------------------------------------------------------------
        %  Wavelength/wave number
        % ---------------------------------------------------------------
        if ~has_ice(i) % water case wavelength has been derived using open-water disp rel already
            L_j = L_j_set;
            k_j = 2 * pi / L_j;
        else
            % Solve flexural-gravity dispersion iteratively in ice case
            k_j = solve_k_dispersion(omega_j, H_water, D_flex, rho_w, g, 2*pi/L_j_set);
            L_j = 2 * pi / k_j;
        end

        % ---------------------------------------------------------------
        %  Le Méhauté coordinates
        % ---------------------------------------------------------------
        X_j = H_water / (g * T_j^2);
        Y_j = 2*a_j     / (g * T_j^2);

        hL_j = H_water / L_j;
        aL_j = a_j / L_j;
        HL_j = H_j / L_j;
        Ur_j = HL_j / hL_j^3;

        % ---- Zone classification ----
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

        % ---- Dimensionless ice / elastic parameters ----
        kH_j             = k_j * H_water;
        H_over_lambda_j  = H_water / L_j;

        if has_ice(i)
            kh_j            = k_j * h_ice;
            kLd_j           = k_j * L_d;
            I_br_j          = (a_j * h_ice * E_ice) / (sigma_f * L_j^2);
            % ---- Uncertainty propagation  ----
            % dI/I = sqrt( (da/a)^2 + (dh/h)^2 + (dE/E)^2 + (dsigma/sigma)^2 )
            if a_j > 0
                rel_da = da_j      / a_j;
            else
                rel_da = 0;
            end
            dI_br_j = I_br_j * sqrt( rel_da^2 + (dh_ice/h_ice)^2 ...
                + (dE_ice/E_ice)^2 + (dsigma_f/sigma_f)^2 );
            h_over_lambda_j = h_ice / L_j;

            % ---- Ice-modified vs. open-water-set wavelength ratio ----
            %   lambda_ratio = lambda_ice(measured) / lambda_ow(set)
            %   Uncertainty comes only from E_ice/h_ice (the dispersion
            %   relation does not depend on wave amplitude), estimated by
            %   re-solving the flexural-gravity relation at E_ice+dE_ice
            %   and h_ice+dh_ice (one at a time) and combining the
            %   resulting shifts in k in quadrature.
            k_Eplus = solve_k_dispersion(omega_j, H_water, D_flex_Eplus, rho_w, g, k_j);
            k_hplus = solve_k_dispersion(omega_j, H_water, D_flex_hplus, rho_w, g, k_j);
            rel_dlambda_j = sqrt((k_Eplus - k_j)^2 + (k_hplus - k_j)^2) / k_j;

            lambda_ratio_j   = L_j / L_j_set;
            d_lambda_ratio_j = lambda_ratio_j * rel_dlambda_j;
        else
            kh_j             = NaN;
            kLd_j             = NaN;
            I_br_j            = NaN;
            h_over_lambda_j   = NaN;
            dI_br_j           = NaN;
            lambda_ratio_j    = NaN;
            d_lambda_ratio_j  = NaN;
        end

        X_pts(j) = X_j;
        Y_pts(j) = Y_j;

        ice_str = 'No ';
        if has_ice(i), ice_str = 'YES'; end
        fprintf('%-20s %-6s %-10.4f %-10.5f %-10.5f %-10.6f %-8.4f %-8.5f %-8.3f %-18s\n', ...
            csv_pairs{i,3}, ice_str, T_j, a_j, X_j, Y_j, hL_j, aL_j, Ur_j, zone_str);

        % Append row — f_set_j, L_j_set, lambda_ratio_j, d_lambda_ratio_j are the new columns
        result_rows{end+1} = {csv_pairs{i,3}, has_ice(i), T_j, T_set_j, a_j, H_j, ...
            X_j, Y_j, hL_j, aL_j, Ur_j, depth_zone, theory_zone, ...
            L_j, k_j, kH_j, kh_j, kLd_j, I_br_j, dI_br_j, h_over_lambda_j, H_over_lambda_j, ka_set_j, ...
            f_set_j, L_j_set, lambda_ratio_j, d_lambda_ratio_j};
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
%  Le MÉHAUTÉ DIAGRAM
% =========================================================================
col_black = [0.00 0.00 0.00];
col_zone  = [0.18 0.20 0.55];
col_Ur    = [0.00 0.00 0.00];

fig = figure('Name','Le Mehaute Diagram','Color','w', ...
    'Units','centimeters','Position',[2 2 23 18]);
ax = axes(fig);
hold(ax,'on');

x_lim = [0.0005, 0.5];
y_lim = [5e-5,   0.05];

hL_vec = logspace(log10(5e-4), log10(3.0), 4000);

tanh_kh = @(hL) tanh(2*pi .* hL);
xc      = @(hL)      hL  .* tanh_kh(hL) / (2*pi);
yc      = @(hL, HL)  HL  .* tanh_kh(hL) / (2*pi);
x_all   = xc(hL_vec);

% Breaking curve (Fenton 1990)
HL_break = hL_vec .* ...
    (0.141063*hL_vec.^2 + 0.0095721*hL_vec + 0.0077829) ./ ...
    (hL_vec.^3 + 0.078834*hL_vec.^2 + 0.0317567*hL_vec + 0.0093407);
inbox = @(xv,yv) xv>=x_lim(1) & xv<=x_lim(2) & yv>=y_lim(1) & yv<=y_lim(2);

HL_Ur26 = 26 * hL_vec.^3;

% (A) Breaking criterion
y_brk = yc(hL_vec, HL_break);
m = inbox(x_all, y_brk);
loglog(ax, x_all(m), y_brk(m), '-', 'Color',col_black, 'LineWidth',2.0, 'HandleVisibility','off');

% (B) Cnoidal/Stokes boundary Ur=26
HL_cn = min(HL_Ur26, HL_break);
y_cn  = yc(hL_vec, HL_cn);
m = inbox(x_all, y_cn);
loglog(ax, x_all(m), y_cn(m), '-', 'Color',col_black, 'LineWidth',2.0, 'HandleVisibility','off');

% (C) Stokes order boundaries
HL_thresholds = [0.0064, 0.0472, 0.0697];
for k = 1:length(HL_thresholds)
    HL_thr  = HL_thresholds(k);
    hL_star = (HL_thr / 26)^(1/3);
    HL_k    = zeros(size(hL_vec));
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
    loglog(ax, x_all(m), y_k(m), '-', 'Color',col_black, 'LineWidth',1.3, 'HandleVisibility','off');
end

% (D) Ur iso-lines
HL_ur20 = 20 * hL_vec.^3;
y_ur20  = yc(hL_vec, HL_ur20);
draw20  = inbox(x_all, y_ur20) & (HL_ur20 <= HL_break + 1e-9);
if any(draw20)
    loglog(ax, x_all(draw20), y_ur20(draw20), '--', 'Color',col_Ur, 'LineWidth',1.1, 'HandleVisibility','off');
end

HL_ur1_true = 1 * hL_vec.^3;
y_ur1_true  = yc(hL_vec, HL_ur1_true);
x_left_Ur1  = 0.007;
y_left_Ur1  = interp1(x_all, y_ur1_true, x_left_Ur1, 'linear', 'extrap');
x_right_Ur1 = 0.05;
hL_right_Ur1   = interp1(x_all, hL_vec, x_right_Ur1, 'linear', 'extrap');
HL_break_right = interp1(hL_vec, HL_break, hL_right_Ur1, 'linear', 'extrap');
y_right_Ur1    = yc(hL_right_Ur1, HL_break_right);
x_ur1_mod = logspace(log10(x_left_Ur1), log10(x_right_Ur1), 200);
y_ur1_mod = logspace(log10(y_left_Ur1), log10(y_right_Ur1), 200);
loglog(ax, x_ur1_mod, y_ur1_mod, '--', 'Color',col_Ur, 'LineWidth',1.1, 'HandleVisibility','off');

% (E) Depth-regime vertical lines
x_hL005 = xc(0.05);
x_hL05  = xc(0.5);
loglog(ax, [x_hL005 x_hL005], y_lim, '-', 'Color',col_zone, 'LineWidth',1.8, 'HandleVisibility','off');
loglog(ax, [x_hL05  x_hL05],  y_lim, '-', 'Color',col_zone, 'LineWidth',1.8, 'HandleVisibility','off');


% =========================================================================
%  SCATTER DATA POINTS
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
    loglog(ax, X_i, Y_i, mkr, 'MarkerSize',markersize, 'Color',clr, ...
        'MarkerFaceColor',clr, 'DisplayName',lbl);
end

% =========================================================================
%  FORMATTING
% =========================================================================
set(ax,'XScale','log','YScale','log','XLim',x_lim,'YLim',y_lim);
set(ax,'XTick',      [0.0005, 0.005, 0.05, 0.5]);
set(ax,'YTick',      [5e-5,   5e-4,  5e-3,  0.05]);
set(ax,'XTickLabel', {'0.0005','0.005','0.05','0.5'});
set(ax,'YTickLabel', {'5E-05','5E-04','5E-03','0.05'});
set(ax,'TickDir','in','TickLength',[0.012 0.012]);
grid(ax,'on'); set(ax,'MinorGridLineStyle','none'); box(ax,'on');
ax.FontSize = 14;
xlabel(ax,'$H/gT^2$','Interpreter','latex','FontSize',13);
ylabel(ax,'$2a/gT^2$', 'Interpreter','latex','FontSize',13);
ax.Position(3) = ax.Position(3) - 0.07;

find_y_at_x = @(xv,yv,xtgt) interp1(log10(xv(yv>0 & xv>0)), ...
    log10(yv(yv>0 & xv>0)), log10(xtgt), 'linear','extrap');

text(ax,0.00065,0.042,'Shallow water',           'FontSize',12,'Color',col_zone,'HorizontalAlignment','left');
text(ax,0.0028, 0.042,'Intermediate water depth', 'FontSize',12,'Color',col_zone,'HorizontalAlignment','left');
text(ax,0.12,   0.042,'Deep water',               'FontSize',12,'Color',col_zone,'HorizontalAlignment','left');
text(ax, x_hL005*1.15, 8e-5, '$H/\lambda = 0.05$', 'Interpreter','latex','FontSize',10,'Color',col_zone,'Rotation',90,'HorizontalAlignment','center');
text(ax, x_hL05*1.25, 1.5e-4, '$H/\lambda = 0.5$', 'Interpreter','latex','FontSize',10,'Color',col_zone,'Rotation',90,'HorizontalAlignment','center');

x_brk_lbl = 0.003;
y_brk_v    = yc(hL_vec, HL_break);
y_brk_lbl  = 10^find_y_at_x(x_all, y_brk_v, x_brk_lbl);
text(ax,x_brk_lbl*1.4,y_brk_lbl*1.8,'Breaking Criterion','FontSize',12,'Color','k','Rotation',42,'HorizontalAlignment','center');

x_cn_lbl = 0.002;
y_cn_v    = yc(hL_vec, HL_cn);
y_cn_lbl  = 10^find_y_at_x(x_all, y_cn_v, x_cn_lbl);
text(ax,x_cn_lbl*0.74,y_cn_lbl*1.5,{'Cnoidal','wave theory'},'FontSize',12,'Color','k','FontAngle','italic','Rotation',52,'HorizontalAlignment','center');

x_Ur20_lbl = xc(0.08); y_Ur20_lbl = yc(0.08, 20*0.08^3);
text(ax,x_Ur20_lbl*1.1,y_Ur20_lbl*1.3,'U_r = 20','FontSize',10,'Color','k','HorizontalAlignment','left');
x_Ur1_lbl = x_ur1_mod(50); y_Ur1_lbl = y_ur1_mod(50);
text(ax,x_Ur1_lbl,y_Ur1_lbl*2.5,'U_r = 1','FontSize',10,'Color','k','HorizontalAlignment','left');

x_lbl = 0.15;
y_lin     = 10^find_y_at_x(x_all, yc(hL_vec, 0.0064*ones(size(hL_vec))), x_lbl);
y_2nd     = 10^find_y_at_x(x_all, yc(hL_vec, 0.0472*ones(size(hL_vec))), x_lbl);
y_3rd     = 10^find_y_at_x(x_all, yc(hL_vec, 0.0697*ones(size(hL_vec))), x_lbl);
y_brk_lbl2 = 10^find_y_at_x(x_all, y_brk_v, x_lbl);
text(ax,x_lbl,10^(0.5*(log10(y_lim(1)) +log10(y_lin))), 'Linear',    'FontSize',12,'Color','k','HorizontalAlignment','left');
text(ax,x_lbl,10^(0.5*(log10(y_lin)    +log10(y_2nd))), '2nd order', 'FontSize',12,'Color','k','HorizontalAlignment','left');
text(ax,x_lbl,10^(0.5*(log10(y_2nd)    +log10(y_3rd))), '3rd order', 'FontSize',12,'Color','k','HorizontalAlignment','left');
text(ax,x_lbl,10^(0.5*(log10(y_3rd)    +log10(y_brk_lbl2))),'4th order','FontSize',12,'Color','k','HorizontalAlignment','left');

lgd = legend(ax, 'FontSize', 10, 'Box', 'on');
set(lgd, 'Position', [0.135 0.75 0.15 0.1]);
lgd.Title.String = 'Experiments';
hold(ax,'off');

% =========================================================================
%   SUMMARY 
% =========================================================================
fprintf('=======================================================\n');
fprintf('  SUMMARY STATISTICS\n');
fprintf('=======================================================\n');
for i = 1:length(all_results)
    X_i = all_results(i).X_pts;
    Y_i = all_results(i).Y_pts;
    fprintf('Dataset: %s | Ice: %s\n', all_results(i).label, mat2str(all_results(i).has_ice));
    fprintf('  N points       = %d\n', numel(X_i));
    fprintf('  H/gT^2 range   = %.5f  to  %.5f\n', min(X_i), max(X_i));
    fprintf('  2a/gT^2 range   = %.6f  to  %.6f\n\n', min(Y_i), max(Y_i));
end

%% =========================================================================
%  CSV EXPORT
% =========================================================================
if ~isempty(output_csv_path) && ~isempty(result_rows)
   
    headers = {'Dataset','Has_Ice','T_s','T_set','a_m','H_wave_m', ...
           'H_over_gT2','twoa_over_gT2', ...
           'H_over_lambda','a_over_lambda','Ursell_Ur', ...
           'Depth_Zone','Theory_Zone', ...
           'lambda_m','k_rad_m','kH','kh','kLd', ...
           'I_breakup','dI_breakup','h_over_lambda','H_over_lambda_water','ka_set', ...
           'f_set_Hz','lambda_open_water_set_m', ...
           'lambda_ratio_ice_over_setwater','d_lambda_ratio_ice_over_setwater'};
    out_df = cell2table(vertcat(result_rows{:}), 'VariableNames', headers);
    writetable(out_df, output_csv_path);
    fprintf('Results saved to: %s\n', output_csv_path);
end

% =========================================================================
%  FIGURE EXPORT
% =========================================================================
pdf_output_path = fullfile(output_figures, 'lemehaute_diagram.pdf');
pdf_width_cm  = 26;
pdf_height_cm = 19;
pdf_font_size = 11;

set(findall(fig,'-property','FontSize'),'FontSize',pdf_font_size);
width_in  = pdf_width_cm  / 2.54;
height_in = pdf_height_cm / 2.54;
set(fig,'PaperUnits','inches','PaperSize',[width_in,height_in], ...
    'PaperPosition',[0,0,width_in,height_in],'PaperPositionMode','manual');

print(fig, pdf_output_path, '-dpdf', '-r300');
fprintf('Figure saved to PDF: %s\n', pdf_output_path);

png_output_path = strrep(pdf_output_path, '.pdf', '.png');
print(fig, png_output_path, '-dpng', '-r200');
fprintf('Figure saved to PNG: %s\n', png_output_path);

%% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function k = solve_k_dispersion(omega, H_water, D_flex, rho_w, g, k0)
% Newton-Raphson solver for the flexural-gravity dispersion relation
%   omega^2 = g k tanh(kH) (1 + D_flex k^4 / (rho_w g))
% Set D_flex = 0 to recover the plain open-water (linear/Airy) relation
%   omega^2 = g k tanh(kH).
% k0 is the initial guess (e.g. 2*pi/L_j_set, or a previously-solved k for
% perturbation studies).

    k_iter = k0;
    for iter_fg = 1:200
        th     = tanh(k_iter * H_water);
        sech2  = 1 - th^2;
        alpha  = D_flex * k_iter^4 / (rho_w * g);
        F_val  = omega^2 - g * k_iter * th * (1 + alpha);
        dF_dk  = -g * th * (1 + alpha) ...
                 - g * k_iter * sech2 * H_water * (1 + alpha) ...
                 - g * k_iter * th * 4 * D_flex * k_iter^3 / (rho_w * g);
        k_new  = k_iter - F_val / dF_dk;
        if k_new <= 0, k_new = k_iter / 2; end
        if abs(k_new - k_iter) / k_iter < 1e-10, break; end
        k_iter = k_new;
    end
    k = k_iter;
end