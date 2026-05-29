% =========================================================================
%  mean_ice_modulus_and_strength.m
% =========================================================================
%
%  PURPOSE:
%    This script loops on all values found for Young's Modulus (E) and 
%    Flexural Strength (Sigma), along with their associated measurement 
%    uncertainties (dE, dSigma), and returns the mean values and estimated 
%    uncertainties.
%    Source files ; .csv outputs, eg '230426_1_siwwi_mech_props.csv'.
%    1. Prompts the user for the number of files to process.
%    2. Opens a graphical file selector for the user to pick the CSVs.
%    3. Extracts 'E' and 'Sigma' (and uncertainties) from each file.
%    4. Calculates the mean and standard deviation of the sample sets.
%    5. Determines the "Retained Uncertainty" by comparing the 
%       statistical scatter (stdv) against the maximum experimental
%       uncertainty (max dE / max dSigma) across the files.
%
%  OUTPUTS:
%    Prints Mean, Stdv, Max uncertainty, and the final retained uncertainty 
%    for both properties to the console.
%
% =========================================================================
clear; clc;

%% 1. FILE SELECTION
numToSelect = input('How many CSV files would you like to select? ');
if isempty(numToSelect) || numToSelect < 1
    error('Invalid number of files entered.');
end

% Open file selector with MultiSelect enabled
[files, path] = uigetfile('*.csv', 'Select the results CSV files', 'MultiSelect', 'on');
if isequal(files, 0)
    error('File selection cancelled.');
end

% Convert to cell array if only one file was selected
if ischar(files)
    files = {files};
end

actualNum = length(files);
if actualNum ~= numToSelect
    fprintf('Note: You selected %d files. Proceeding with %d.\n', actualNum, actualNum);
end

% Initialize arrays to store values based on actual selection
E_list = zeros(actualNum, 1);
dE_list = zeros(actualNum, 1);
Sigma_list = zeros(actualNum, 1);
dSigma_list = zeros(actualNum, 1);

%% 2. DATA LOADING
fprintf('\n--- Loading Data ---\n');
for i = 1:actualNum
    fullPath = fullfile(path, files{i});
    data = readtable(fullPath);
    
    varNames = data.Properties.VariableNames;
    
    % --- Young Modulus Columns ---
    colE_idx = find(strcmp(varNames, 'E_GPa'));
    if isempty(colE_idx)
        colE_idx = find(strcmp(varNames, 'E_apparent_GPa'));
    end
    
    colDE_idx = find(strcmp(varNames, 'dE_GPa'));
    if isempty(colDE_idx)
        colDE_idx = find(strcmp(varNames, 'dE_apparent_GPa'));
    end
    
    if isempty(colE_idx) || isempty(colDE_idx)
        error(['Could not find compatible columns "E_GPa" or ' ...
               '"E_apparent_GPa" (same for dE) in file: %s'], files{i});
    end

    % --- Flexural Strength Columns ---
    colSig_idx = find(strcmp(varNames, 'Sigma_f_kPa'));
    colDSig_idx = find(strcmp(varNames, 'dSigma_f_kPa'));

    if isempty(colSig_idx) || isempty(colDSig_idx)
        error('Could not find compatible columns "Sigma_f_kPa" or "dSigma_f_kPa" in file: %s', files{i});
    end
    
    % Extract values
    E_list(i)  = data{1, colE_idx};
    dE_list(i) = data{1, colDE_idx};
    Sigma_list(i) = data{1, colSig_idx};
    dSigma_list(i) = data{1, colDSig_idx};
    
    fprintf('  [%d/%d] %s: E = %.4f, dE = %.4f | Sigma = %.2f, dSigma = %.2f\n', ...
        i, actualNum, files{i}, E_list(i), dE_list(i), Sigma_list(i), dSigma_list(i));
end

%% 3. STATS
% --- Young's Modulus (E) ---
mean_E = mean(E_list);
stdv_E = std(E_list);
max_dE = max(dE_list);
retained_uncertainty_E = max(stdv_E, max_dE);

% --- Flexural Strength (Sigma) ---
mean_Sigma = mean(Sigma_list);
stdv_Sigma = std(Sigma_list);
max_dSigma = max(dSigma_list);
retained_uncertainty_Sigma = max(stdv_Sigma, max_dSigma);

%% 4. RESULTS
fprintf('\n==============================================\n');
fprintf('                ICE PROPERTIES                \n');
fprintf('==============================================\n');
fprintf(' Number of samples      : %d\n\n', actualNum);

fprintf(' --- Young''s Modulus (E) ---\n');
fprintf(' Mean E                 : %.4f GPa\n', mean_E);
fprintf(' Stdv E                 : %.4f GPa\n', stdv_E);
fprintf(' Max dE                 : %.4f GPa\n', max_dE);
fprintf(' Retained Uncertainty   : %.4f GPa\n\n', retained_uncertainty_E);

fprintf(' --- Flexural Strength (Sigma_f) ---\n');
fprintf(' Mean Sigma             : %.2f kPa\n', mean_Sigma);
fprintf(' Stdv Sigma             : %.2f kPa\n', stdv_Sigma);
fprintf(' Max dSigma             : %.2f kPa\n', max_dSigma);
fprintf(' Retained Uncertainty   : %.2f kPa\n', retained_uncertainty_Sigma);
fprintf('==============================================\n\n');