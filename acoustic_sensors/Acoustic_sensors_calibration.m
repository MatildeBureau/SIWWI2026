% Acoustic sensors calibration
% -------------------------------------------------------------------------
% Processes calibration data for 6 acoustic sensors and  two 
%  modes (Low = 50 Hz sampling frequency, High = 100Hz). Performs individual linear fits for 
% each sensor and then calculates statistics over the whole set of sensors as an ensemble for each mode.
%
% Methods:
% 1. Monte Carlo Simulation: Propagate uncertainties from
%    raw data to fitting params.
% 2. Ensemble Statistics: Collection of sensors =  statistical serie to determine variability 
%    over the whole sensors set.
% -------------------------------------------------------------------------

% ---  General  ---
folder_path = './';            % directory containing the .csv files
save_fig = true;                % save figure if true
save_results = true;            % save results if true
results_filename = 'acoustic_sensors_calib.csv';

num_sensors = 6;                % nb of sensors
modes = {'low', 'high'};       
mode_markers = {'o', 's'};      

% Monte Carlo: 
% run the fit 5000 times with random noise to see how slope/intercept 
% fluctuate > estimate uncertainty.
num_trials = 5000; 

% ---  Plotting & storage initialization ---
fig = figure('Name', 'SIWWI Calibration', 'Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 1000, 700]);
hold on; grid on;
sensor_colors = lines(num_sensors); 

master_table = table();             
x_label_str = ''; y_label_str = ''; 
h_master_lines = gobjects(length(modes), 1); 

% ---  Processing ---
for m = 1:length(modes)
    mode_name = modes{m};
    current_marker = mode_markers{m};
    
    % temporary storage for ensemble calculations
    sensor_slopes = zeros(num_sensors, 1);
    sensor_intercepts = zeros(num_sensors, 1);
    sensor_da_prop = zeros(num_sensors, 1); 
    sensor_db_prop = zeros(num_sensors, 1);
    all_V = []; all_d = []; 
    
    for s = 1:num_sensors
        % filename (e.g., sensor1_low.csv)
        filename = fullfile(folder_path, sprintf('sensor%d_%s.csv', s, mode_name));
        if ~isfile(filename), continue; end % Skip if file is missing
        
        % Axis Labels 
        if isempty(x_label_str)
            fid = fopen(filename, 'r'); 
            h_q = strsplit(fgetl(fid), ','); % Quantities
            h_u = strsplit(fgetl(fid), ','); % Units
            fclose(fid);
            x_label_str = sprintf('%s (%s)', strtrim(h_q{1}), strtrim(h_u{1}));
            y_label_str = sprintf('%s (m)', strtrim(h_q{3})); 
        end
        
        % Load data (V = Voltage, d = Distance)
        data = readmatrix(filename, 'NumHeaderLines', 2);
        V = data(:, 1);     V_err = data(:, 2);
        d = data(:, 3)*1e-2; d_err = data(:, 4)*1e-2; %  cm to m
        
        % store data points for this mode ; determine plot range
        all_V = [all_V; V]; all_d = [all_d; d];
        
     
        % Monte  Carlo
   
        % add random Gaussian noise prop to measured errors.
        a_t = zeros(num_trials, 1); b_t = zeros(num_trials, 1);
        for i = 1:num_trials
            % perturbate data within its error bars and linear fit
            p = polyfit(V + randn(size(V)).*V_err, d + randn(size(d)).*d_err, 1);
            a_t(i) = p(1); % Sim slope
            b_t(i) = p(2); % Sim intercept
        end
        
        % final parameter = mean of trials
        % uncertainty = stdv of trials.
        sensor_slopes(s) = mean(a_t);
        sensor_intercepts(s) = mean(b_t);
        sensor_da_prop(s) = std(a_t);
        sensor_db_prop(s) = std(b_t);
        
        % plot
        errorbar(V, d, d_err, d_err, V_err, V_err, 'LineStyle', 'none', ...
            'Color', sensor_colors(s,:), 'CapSize', 2, 'HandleVisibility', 'off');
        
    
        scatter(V, d, 45, sensor_colors(s,:), current_marker, 'LineWidth', 1.0, ...
            'MarkerFaceAlpha', 0.3, 'HandleVisibility', 'off');
        
        % results table
        row = table({upper(mode_name)}, {sprintf('Sensor%d', s)}, ...
            sensor_slopes(s), sensor_da_prop(s), sensor_intercepts(s), sensor_db_prop(s), ...
            {'MonteCarlo_Propagated'}, 'VariableNames', {'Mode', 'Source', 'Slope_a', 'Err_a', 'Intercept_b', 'Err_b', 'Uncert_Method'});
        master_table = [master_table; row];
    end
    

    % Ensemble statistics

    valid_idx = sensor_slopes ~= 0; % only include found sensors
    
    % avg on all sensors fit params
    mode_a = mean(sensor_slopes(valid_idx)); 
    mode_b = mean(sensor_intercepts(valid_idx));
    
    % total uncertainty:
    % take the maximum of:
    % 1. avg precision of individual sensors (propagated error).
    % 2. variation between sensors (stdv of ensemble).

    err_a = max(mean(sensor_da_prop(valid_idx)), std(sensor_slopes(valid_idx), 'omitnan'));
    err_b = max(mean(sensor_db_prop(valid_idx)), std(sensor_intercepts(valid_idx), 'omitnan'));
    
  
    V_fit_range = linspace(min(all_V), max(all_V), 100);
    all_fits = zeros(num_sensors, length(V_fit_range));
    for s = 1:num_sensors
        if sensor_slopes(s) ~= 0
            all_fits(s, :) = sensor_slopes(s) * V_fit_range + sensor_intercepts(s);
        else
            all_fits(s, :) = nan;
        end
    end
    
    ribbon_top = max(all_fits, [], 1, 'omitnan');
    ribbon_bottom = min(all_fits, [], 1, 'omitnan');
    fill([V_fit_range, fliplr(V_fit_range)], [ribbon_top, fliplr(ribbon_bottom)], ...
        [0.9 0.9 0.9], 'FaceAlpha', 0.5, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    
    % --- Plot  ensemble line ---
    l_style = '-'; if strcmp(mode_name, 'high'), l_style = '--'; end
    h_master_lines(m) = plot(V_fit_range, mode_a * V_fit_range + mode_b, 'Color', [0.1 0.1 0.1], ...
        'LineStyle', l_style, 'LineWidth', 2.5, ...
        'DisplayName', sprintf('Mode ensemble %s (a=%.3f, b=%.3f)', upper(mode_name), mode_a, mode_b));
    
    
    ensemble_row = table({upper(mode_name)}, {'Mode_ensemble'}, ...
        mode_a, err_a, mode_b, err_b, {'Max(Prop,Rep)'}, ...
        'VariableNames', {'Mode', 'Source', 'Slope_a', 'Err_a', 'Intercept_b', 'Err_b', 'Uncert_Method'});
    master_table = [master_table; ensemble_row];
end

% ---  formatting & saving ---

h_sens = gobjects(num_sensors, 1);
for s = 1:num_sensors
    h_sens(s) = scatter(NaN, NaN, 40, sensor_colors(s,:), 'o', 'Filled');
end
h_modes = [scatter(NaN, NaN, 40, 'k', 'o'); scatter(NaN, NaN, 40, 'k', 's')];


labels_master = cell(length(modes), 1);
for k = 1:length(modes)
    labels_master{k} = get(h_master_lines(k), 'DisplayName');
end
legend_handles = [h_sens; h_modes; h_master_lines];
legend_labels = [arrayfun(@(x) sprintf('Sensor %d', x), 1:num_sensors, 'UniformOutput', false), ...
                 {'Low', 'High'}, ...
                 labels_master{1}, labels_master{2}];

legend(legend_handles, legend_labels, 'Location', 'northeastoutside', 'FontSize', 8);
xlabel(x_label_str, 'FontWeight', 'bold'); 
ylabel(y_label_str, 'FontWeight', 'bold');

% Save Outputs
if save_fig
    set(fig, 'PaperPositionMode', 'auto');
    saveas(fig, 'acoustic_sensors_calib.png');
    print(fig, 'acoustic_sensors_calib.pdf', '-dpdf', '-bestfit');
    fprintf('Saved: acoustic_sensors_calib.png and .pdf\n');
end

if save_results
    writetable(master_table, results_filename);
    fprintf('\n--- Results Table Generated ---\n');
    disp(master_table);
end