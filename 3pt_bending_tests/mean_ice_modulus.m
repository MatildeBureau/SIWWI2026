% =========================================================================
%  mean_ice_modulus.m
% =========================================================================
%
%  PURPOSE:
%    This script loops on all values found for Young's Modulus (E) and its associated 
%    measurement uncertainties (dE) and 
%    returns the mean value and an estimated uncertainty.
%    Source files ; .csv outputs, eg '230426_1_siwwi_mech_props.csv'.

%    1. Prompts the user for the number of files to process.
%    2. Opens a graphical file selector for the user to pick the CSVs.
%    3. Extracts 'E_apparent_GPa' and 'dE_apparent_GPa' from each file.
%    4. Calculates the mean and standard deviation of the 
%       sample set.
%    5. Determines the "Retained Uncertainty" by comparing the 
%       statistical scatter (stdv) against the maximum experimental
%       uncertainty (max dE) across the files.
%
%  OUTPUTS:
%    Prints Mean E, Stdv E, Max dE, and the final retained uncertainty 
%    to the MATLAB Command Window.
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

%% 2. DATA LOADING
fprintf('\n--- Loading Data ---\n');
for i = 1:actualNum
    fullPath = fullfile(path, files{i});
    data = readtable(fullPath);
    
    % USE STRCMP FOR EXACT MATCHING 
    % This prevents 'E_apparent_GPa' from matching 'dE_apparent_GPa'
    colE_idx  = find(strcmp(data.Properties.VariableNames, 'E_apparent_GPa'));
    colDE_idx = find(strcmp(data.Properties.VariableNames, 'dE_apparent_GPa'));
    
    if isempty(colE_idx) || isempty(colDE_idx)
        error('Could not find exact columns "E_apparent_GPa" or "dE_apparent_GPa" in file: %s', files{i});
    end
    
    % Extract values
    E_list(i) = data{1, colE_idx};
    dE_list(i) = data{1, colDE_idx};
    
    fprintf('  [%d/%d] %s: E = %.4f, dE = %.4f\n', i, actualNum, files{i}, E_list(i), dE_list(i));
end

%% 3. STATISTICAL COMPUTATION
mean_E = mean(E_list);
stdv_E = std(E_list);
max_dE = max(dE_list);

% Uncertainty Logic:
% Retain the largest between the scatter of the results (stdv) 
% and the individual measurement uncertainties (max_dE).
retained_uncertainty = max(stdv_E, max_dE);

%% 4. DISPLAY RESULTS
fprintf('\n==============================================\n');
fprintf('          ICE PROPERTIES             \n');
fprintf('==============================================\n');
fprintf(' Number of samples  : %d\n', actualNum);
fprintf(' Mean E             : %.4f GPa\n', mean_E);
fprintf(' Stdv E             : %.4f GPa\n', stdv_E);
fprintf(' Max dE             : %.4f GPa\n', max_dE);
fprintf('----------------------------------------------\n');
fprintf(' Uncertainty: %.4f GPa\n', retained_uncertainty);
fprintf('==============================================\n\n');