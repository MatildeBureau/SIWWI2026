%% =========================================================================
%  SIWWI DEFORMATION TRACKING SCRIPT
%  =========================================================================
%  DESCRIPTION:
%    This script performs 2D displacement tracking
%    on a series of grayscale .TIF photographs of one fixed position in the tank.
%
%    Method: Normalised Cross-Correlation (NCC): a small
%    reference "template" patch is selected from the first image, and the
%    script searches for the best matching location of that patch in every
%    subsequent image. The shift in position between frames is converted
%    from pixels to millimetres using a manual calibration step.
%
%    Displacements are tracked separately for images taken with lab
%    lights on vs off.
%    Results can be saved as a displacement plot (.png / .pdf) and as a
%    annotated CSV file containing displacements + experimental metadata.
%
%  WORKFLOW SUMMARY:
%    1. User selects image folder and metadata CSV file
%    2. User chooses images to process (all or manual selection)
%    3. Calibration: user clicks two points of a known distance on image
%    4. Template selection: user draws a rectangle around the feature to track
%    5. Cross-correlation tracking loops over all selected images
%    6. Displacements in X and Y are computed in mm
%    7. Results are plotted and optionally saved
%
%  REQUIRED MATLAB TOOLBOXES:
%    - Image Processing Toolbox  (normxcorr2, imshow, imcrop, rgb2gray)
%
%  INPUT FILES:
%    - A folder of .TIF or .tif images named DSC_XXXX.tif
%    - A CSV metadata file with at least 3 lines:
%        Line 1: variable names (header)
%        Line 2: units
%        Lines 3+: one row per image with fields including Name,
%                  Temperature, WaterHeight, LabLights, etc.
%
%  OUTPUT FILES :
%    - session_metadata.txt  : calibration and session info
%    - displacement_plot.png / .pdf  : displacement vs image number
%    - Tank_deflexion_results.csv    : displacements + metadata per image
%
%  AUTHOR  : Matilde
%  DATES   : 07/04/26 – 08/04/26
%  =========================================================================

clc; clear; close all; 

%% User-controlled save flags
% Set these to true/false to control whether figures and CSV results
% are saved to disk at the end of the script.
save_fig = true;       % Save displacement figures (PNG + PDF)?
save_results = true;   % Save displacement data to CSV?



%% =========================================================================
%  STEP 1 — Load Data and Metadata
%  =========================================================================
disp('--- Step 1: Select Files ---');

% Select image folder 

folderPath = uigetdir(pwd, 'Select the folder containing your .TIF images');
if isequal(folderPath, 0); error('No folder selected.'); end  % User cancelled → abort

%  Select metadata CSV 
[metaName, metaPath] = uigetfile('*.csv', 'Select the metadata CSV');
if isequal(metaName, 0); error('No metadata file selected.'); end 
fullMetaPath = fullfile(metaPath, metaName); % Build the full file path

%  Parse CSV header and units lines manually 

fid = fopen(fullMetaPath);
headerLine = fgetl(fid);   % Line 1: column names
unitsLine  = fgetl(fid);   % Line 2: physical units
fclose(fid);

% Convert the comma-separated header into valid MATLAB variable names
varNames = matlab.lang.makeValidName(strtrim(split(headerLine, ',')));
units    = strtrim(split(unitsLine, ','));  % Keep units as plain strings

% Read the actual data (from line 3 onwards) 
opts = detectImportOptions(fullMetaPath);
opts.DataLines = [3 Inf];        % Skip the header and units lines
opts.VariableNames = varNames;   
metadata = readtable(fullMetaPath, opts); 

% Store units
metadata_units = struct();
for i = 1:length(varNames)
    metadata_units.(varNames{i}) = units{i};
end

%% =========================================================================
%  STEP 2 — Select images to process
%  =========================================================================
disp('--- Step 2: Select Images ---');


answerMode = questdlg('Process all images automatically or select specific images?', ...
    'Mode Selection', 'All', 'Selection', 'All');
if isempty(answerMode); error('Selection cancelled.'); end  % Dialog closed → abort
process_all = strcmp(answerMode, 'All');  % Boolean: true if user chose 'All'

if process_all
    % --- Automatic mode: parse image numbers from metadata 'Name' field ---
    % The Name field typically looks like "DSC_0042" or "DSC__0042".

    cleanMetaNames = strrep(string(metadata.Name), '__', '_');
    parsedNums = zeros(height(metadata), 1);
    for k = 1:height(metadata)
        numStr = regexp(cleanMetaNames(k), '\d+', 'match');  % Extract digits
        if ~isempty(numStr)
            parsedNums(k) = str2double(numStr{1});
        end
    end

    % --- Deduplicate: skip rows where Temperature, WaterHeight, AND LabLights
    %     are identical to the previous row (i.e. no experimental change occurred).
    %     avoids processing redundant frames captured under the same conditions.
    keepIdx = true(height(metadata), 1);
    for k = 2:height(metadata)
        if metadata.Temperature(k) == metadata.Temperature(k-1) && ...
           metadata.WaterHeight(k) == metadata.WaterHeight(k-1) && ...
           strcmp(strtrim(lower(string(metadata.LabLights(k)))), strtrim(lower(string(metadata.LabLights(k-1)))))
            keepIdx(k) = false;  % Mark duplicate rows for exclusion
        end
    end

    % Build the final list of image numbers to process
    targetNumbers = parsedNums(keepIdx);
    targetNumbers(targetNumbers == 0) = [];  % Remove any rows with no valid number
    userInput = {'ALL'};  % Placeholder for later metadata logging

else
    %  Manual mode
    prompt = {'Enter image numbers (comma separated, e.g., 1, 3, 11, 48):'};
    userInput = inputdlg(prompt, 'Image Selection', [1 70], {'1,2,3'});
    if isempty(userInput); error('Selection cancelled.'); end
    targetNumbers = str2num(userInput{1});  % Convert string to numeric array
end

% Ensure targetNumbers is always a row vector for consistent indexing later
targetNumbers = targetNumbers(:)'; 

% =========================================================================
%  Build file path List 
%  =========================================================================
% store only file paths and not images to save memory
% Images are loaded one at a time inside the tracking loop (Step 4).
numImages = length(targetNumbers);
imgPaths      = strings(1, numImages);  % Full path to each image file
metaIndices   = zeros(1, numImages);    % Index into metadata table for each image
allMetaStrings = strings(1, numImages); % Human-readable metadata summary per image
is_ON_array   = false(1, numImages);    % true if lab lights were ON for this image

% List all .tif / .TIF files in the selected folder
files = dir(fullfile(folderPath, '*.tif'));
files = [files; dir(fullfile(folderPath, '*.TIF'))];  
fileNames = string({files.name});

% Normalise metadata names for matching against file names
cleanMetaNames = strrep(string(metadata.Name), '__', '_');

fprintf('Checking file availability...\n');
for i = 1:numImages
    % Build the expected filename pattern, e.g. "DSC_0042" (zero-padded to 4 digits)
    numStr = sprintf('%04d', targetNumbers(i));
    pattern = "DSC_" + numStr;
    
    % Search for a file whose name contains this pattern
    matchIdx = find(contains(fileNames, pattern), 1);
    if isempty(matchIdx)
        warning('Image #%d not found.', targetNumbers(i));
        continue;  % Skip missing images 
    end
    
    % Store the full path to the found image
    fileName = fileNames(matchIdx);
    imgPaths(i) = fullfile(folderPath, fileName);
    
    %  Match image to its metadata row 
    % Strip the .tif extension and look for a matching 'Name' in the metadata table
    cleanFileName = erase(fileName, [".tif",".TIF"]);
    metaIdx = find(strcmp(cleanMetaNames, cleanFileName), 1);
    if isempty(metaIdx), continue; end  % No matching metadata row → skip
    
    metaIndices(i) = metaIdx;
    
    % Determine lighting status (ON or OFF) 

    lightStatus = strtrim(lower(string(metadata.LabLights(metaIdx))));
    is_ON_array(i) = contains(lightStatus, 'on');
    

    % Concatenates all metadata fields (except Name/File) with their values and units.
    metaStr = "";
    for v = 1:length(varNames)
        vName = varNames{v};
        if strcmp(vName, 'Name') || strcmp(vName, 'File'), continue; end  % Skip name fields
        val = metadata.(vName)(metaIdx);
        if iscell(val), valStr = string(val{1}); else, valStr = string(num2str(val)); end
        
        unitStr = string(metadata_units.(vName));
        if unitStr == "" || unitStr == "-" || ismissing(unitStr)
            metaStr = metaStr + string(vName) + ": " + valStr + " | ";
        else
            metaStr = metaStr + string(vName) + ": " + valStr + " " + unitStr + " | ";
        end
    end

    allMetaStrings(i) = extractBefore(metaStr, strlength(metaStr)-2); 
end

%  Remove entries for images that were not found on disk 
validMask = (imgPaths ~= "");
imgPaths       = imgPaths(validMask);
metaIndices    = metaIndices(validMask);
allMetaStrings = allMetaStrings(validMask);
is_ON_array    = is_ON_array(validMask); 
targetNumbers  = targetNumbers(validMask);
numImages      = length(imgPaths);

if numImages == 0, error('No valid images found.'); end

%% =========================================================================
%  STEP 3 — Pixel-to-mm calib
%  =========================================================================
% ask user to click on two points of a known real-world distance
% (e.g. a ruler or reference object visible in the image).

% Load only the first image for calibration 
tempImg = imread(imgPaths(1));
if size(tempImg,3) == 3, tempImg = rgb2gray(tempImg); end  % Convert to grayscale if RGB

figure; imshow(tempImg);
title('Zoom → Enter → click 2 points of a known distance');
zoom on; pause;   % Allow user to zoom in for precision
zoom off; 
[x_cal, y_cal] = ginput(2);  % User clicks exactly 2 points


pixelDist = sqrt(diff(x_cal)^2 + diff(y_cal)^2); 

% Ask user for the real-world distance corresponding to those two points (in cm)
realDist = str2double(inputdlg('Known distance (cm):','Scale',[1 50],{'10'}));

% Compute the scale factor
cm_per_pixel = realDist / pixelDist;

close;  

%% =========================================================================
%  STEP 4 — Select template (Feature to Track)
%  =========================================================================
% user draws a rectangle around a distinctive feature in the first image
% (e.g. a marker, edge, or texture pattern). This patch becomes the
% "template" that will be searched for in all subsequent images.
disp('---  Tracking reference ---');

figure('Name', 'Template Selection');
imshow(tempImg);
title('Zoom > Enter > Draw rectangle > Enter');
zoom on; pause;   % Allow user to zoom in for precise selection
zoom off; 

roi = drawrectangle;  
pause;                % Wait for user to confirm selection (press Enter)

pos = roi.Position;   % Get rectangle position [x, y, width, height]
template = imcrop(tempImg, pos);  % Crop out the template patch
close;

clear tempImg;  % Free memory — we no longer need the first image loaded as a variable

%% =========================================================================
%  STEP 5 — Cross-Correlation tracking
%  =========================================================================
% For each image, use normalised cross-correlation (normxcorr2) to find
% the location in the image that best matches the template patch.
% Sub-pixel refinement can improve accuracy beyond integer-pixel resolution.
disp('---  Tracking Feature ---');

% --- Sub-pixel enhancement method selection ---
% After the integer-pixel peak is found in the correlation map, sub-pixel
% refinement can be used:
%   - None: raw integer location only
%   - Parabolic fit: fits a parabola through the peak and its neighbours
%   - Gaussian fit: fits a Gaussian curve 
subOptions = {'None (Integer Only)', 'Parabolic Fit', 'Gaussian Fit '};
subChoice = listdlg('PromptString', 'Select Sub-pixel Enhancement:', ...
                   'SelectionMode', 'single', 'ListString', subOptions, 'InitialValue', 2);
if isempty(subChoice); subChoice = 1; end  % Default to integer-only if cancelled

%  Progress bar 
hWait = waitbar(0, 'Analysing Images...');

% Pre-allocate arrays for tracked X and Y centre positions (in pixels)
trackX = zeros(1, numImages);
trackY = zeros(1, numImages);

for i = 1:numImages
    fprintf('Analysing Image %d/%d... ', i, numImages);
    waitbar(i/numImages, hWait, sprintf('Analysing Image %d of %d', i, numImages));
    
    %  Load current image from disk 
    currentImg = imread(imgPaths(i));
    if size(currentImg,3) == 3, currentImg = rgb2gray(currentImg); end  % Ensure grayscale
    
    %  Normalised cross-correlation
    % normxcorr2 slides the template over the image and computes a
    % normalised correlation coefficient at every position.
    % The output 'c' has size: (imageHeight + templateHeight - 1) × (imageWidth + templateWidth - 1)
    c = normxcorr2(template, currentImg); 
    
    % Find the pixel location of the maximum correlation (best match)
    [max_c, imax] = max(c(:));                  % max_c = peak value, imax = linear index
    [ypeak, xpeak] = ind2sub(size(c), imax);    % Convert to 2D (row, col) coordinates
    
    % Sub-pixel refinement 
    % Estimate fractional pixel offsets (dx, dy) from the integer peak location
    dx = 0; dy = 0;  % Default: no sub-pixel correction
    
    % Only attempt sub-pixel fitting if the peak is away from the correlation map border
    % (need at least one neighbour on each side)
    if ypeak > 1 && ypeak < size(c,1) && xpeak > 1 && xpeak < size(c,2)
        if subChoice == 2  % --- Parabolic fit ---
            % Fit a 1D parabola through the peak and its immediate neighbours
            % in both X and Y directions. fractional offset is the parabola vertex.
            denomY = 2 * (c(ypeak-1, xpeak) + c(ypeak+1, xpeak) - 2*max_c);
            denomX = 2 * (c(ypeak, xpeak-1) + c(ypeak, xpeak+1) - 2*max_c);
            
            if denomY ~= 0, dy = (c(ypeak-1, xpeak) - c(ypeak+1, xpeak)) / denomY; end
            if denomX ~= 0, dx = (c(ypeak, xpeak-1) - c(ypeak, xpeak+1)) / denomX; end
            
        elseif subChoice == 3  % --- Gaussian fit ---
            % Fit a 1D Gaussian by working in log-space (where a Gaussian becomes a parabola).
            % small epsilon (1e-6) prevents log(0) errors.
            v0   = log(max(1e-6, max_c));
            vy_m = log(max(1e-6, c(ypeak-1, xpeak))); vy_p = log(max(1e-6, c(ypeak+1, xpeak)));
            vx_m = log(max(1e-6, c(ypeak, xpeak-1))); vx_p = log(max(1e-6, c(ypeak, xpeak+1)));
            
            denomY = 2 * (vy_m + vy_p - 2*v0);
            denomX = 2 * (vx_m + vx_p - 2*v0);
            
            if denomY ~= 0, dy = (vy_m - vy_p) / denomY; end
            if denomX ~= 0, dx = (vx_m - vx_p) / denomX; end
        end
    end
    
    %  Convert correlation map peak to image coordinates 
    % normxcorr2 output is larger than the original image by (templateSize - 1).
    % To get the position of the CENTRE of the template in the image,  subtract
    % the template half-size from the peak location (after applying sub-pixel offset).
    yoffSet = (ypeak + dy) - size(template, 1);
    xoffSet = (xpeak + dx) - size(template, 2);
    
    trackX(i) = xoffSet + size(template, 2)/2;  % X centre of matched template
    trackY(i) = yoffSet + size(template, 1)/2;  % Y centre of matched template
    
    %  Free memory before next iteration 
    clear currentImg c; 
    fprintf('Done.\n');
end

delete(hWait);  

%% =========================================================================
%  STEP 6 — Compute displacements
%  =========================================================================
% Displacement = change in tracked position relative to the first image
% in each lighting condition group.
% avoids mixing the two conditions, which may have different
% baseline positions due to image brightness differences.
disp('---  Calculating Displacements ---');

% --- Define resolution error based on tracking method ---
% If sub-pixel fitting was used, error is ~0.1 px ; typical error used 
% in sub-pixel corr algo (Digital Image Correlation).
% If integer-only was used, error is 0.5 px: method only sees a pixel
% center so 'true' position could be anywhere within half a radius
if subChoice == 1
    px_error = 0.5; 
else
    px_error = 0.1; 
end

% Initialise displacement arrays (pixels)
deltaX_px = zeros(1, numImages);
deltaY_px = zeros(1, numImages);

% Find indices for each lighting group
idx_ON  = find(is_ON_array);   % Indices of images with lights ON
idx_OFF = find(~is_ON_array);  % Indices of images with lights OFF

% Compute displacement relative to the first image in each group
if ~isempty(idx_ON)
    deltaX_px(idx_ON) = trackX(idx_ON) - trackX(idx_ON(1));   % X displacement from first ON frame
    deltaY_px(idx_ON) = trackY(idx_ON) - trackY(idx_ON(1));   % Y displacement from first ON frame
end

if ~isempty(idx_OFF)
    deltaX_px(idx_OFF) = trackX(idx_OFF) - trackX(idx_OFF(1)); % X displacement from first OFF frame
    deltaY_px(idx_OFF) = trackY(idx_OFF) - trackY(idx_OFF(1)); % Y displacement from first OFF frame
end

% --- Convert from pixels to millimetres ---
% cm_per_pixel × 10 converts cm → mm
deltaX_mm = (deltaX_px * cm_per_pixel) * 10;
deltaY_mm = (deltaY_px * cm_per_pixel) * 10;

% Convert the pixel resolution error into mm for the error bars
err_mm = px_error * cm_per_pixel * 10;
err_array = err_mm * ones(1, numImages);

%% =========================================================================
%  STEP 7 — Plot Results
%  =========================================================================
% Plot X and Y displacements (in mm) as a function of image number,
% with separate line styles for Lights ON vs Lights OFF conditions.

f4 = figure('Name', 'Deformation Over Time');
hold on; grid on;

if ~isempty(idx_ON)
    errorbar(targetNumbers(idx_ON), deltaX_mm(idx_ON), err_array(idx_ON), ...
        '-ob', 'LineWidth', 1.2, 'DisplayName', 'dX (Lights ON)');
    errorbar(targetNumbers(idx_ON), deltaY_mm(idx_ON), err_array(idx_ON), ...
        '-or', 'LineWidth', 1.2, 'DisplayName', 'dY (Lights ON)');
end

if ~isempty(idx_OFF)
    errorbar(targetNumbers(idx_OFF), deltaX_mm(idx_OFF), err_array(idx_OFF), ...
        '--*c', 'DisplayName', 'dX (Lights OFF)');
    errorbar(targetNumbers(idx_OFF), deltaY_mm(idx_OFF), err_array(idx_OFF), ...
        '--*m', 'DisplayName', 'dY (Lights OFF)');
end

xlabel('Image Number (DSC\_XXXX)');
ylabel('Displacement (mm)'); 
legend('Location', 'best');

%% =========================================================================
%  STEP 8 — Save Results
%  =========================================================================


% --- Build a timestamped results subfolder name ---
% Format: results_DDMMYY_method  (e.g. "results_080426_parabolic")
dateStr = datestr(now, 'ddmmyy');
methodNames = {'integer', 'parabolic', 'gaussian'};
selectedMethod = methodNames{subChoice};
folderName = sprintf('results_%s_%s', dateStr, selectedMethod);
resultsDir = fullfile(folderPath, folderName);  % Full path to results folder

% Create the results directory if it does not already exist
if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
    fprintf('Created new directory: %s\n', resultsDir);
end

% --- Write session metadata to a plain-text file ---
% This logs calibration, method, image selection, and source folder.
infoFile = fullfile(resultsDir, 'session_metadata.txt');
fid_info = fopen(infoFile, 'w');
if fid_info ~= -1
    fprintf(fid_info, '--- Tracking Session Metadata ---\n');
    fprintf(fid_info, 'Date: %s\n', datestr(now, 'dd/mm/yyyy HH:MM:SS'));
    fprintf(fid_info, 'Tracking Method: %s\n', selectedMethod);
    fprintf(fid_info, 'Assumed Resolution Error: %.2f px (%.4f mm)\n', px_error, err_mm);
    fprintf(fid_info, 'Pixel Scale: %.6f cm/pixel\n', cm_per_pixel);  % Calibration scale
    % Log which images were processed
    if process_all
        fprintf(fid_info, 'Images Selected: ALL (Automatically processed loop)\n');
    else
        fprintf(fid_info, 'Images Selected: %s (Manual selection)\n', userInput{1});
    end
    fprintf(fid_info, 'Folder Source: %s\n', folderPath);
    fclose(fid_info);
    fprintf('Session info saved to: %s\n', infoFile);
end

% --- Save displacement figures (PNG and PDF) ---
if save_fig
    disp('--- Saving figures ---');
    % Define output file paths for each figure format
    trackFigPng = fullfile(resultsDir, 'tracking_process.png');
    trackFigPdf = fullfile(resultsDir, 'tracking_process.pdf');
    dispFigPng  = fullfile(resultsDir, 'displacement_plot.png');
    dispFigPdf  = fullfile(resultsDir, 'displacement_plot.pdf');
    
    % Save the displacement plot figure (f4) if it still exists
    if exist('f4', 'var') && isgraphics(f4)
        set(f4, 'PaperPositionMode', 'auto');  % Use screen size for paper output
        saveas(f4, dispFigPng);   % Save as PNG (raster)
        saveas(f4, dispFigPdf);   % Save as PDF (vector, better for publication)
        fprintf('Saved displacement plot to: %s and .pdf\n', dispFigPng);
    end
end

% --- Save displacement data and metadata to CSV ---
if save_results
    disp('--- Saving Results to CSV ---');
    resFilename = fullfile(resultsDir, 'Tank_deflexion_results.csv');
    fid_res = fopen(resFilename, 'w');
    
    % Build the header row: fixed columns first, then all metadata variable names
    % (excluding 'Name' and 'File' which are not useful in the output table)
    baseHeaders = {'Image_Index', 'X_Disp_mm', 'Y_Disp_mm'};
    metaVars = metadata.Properties.VariableNames;
    metaVars(strcmp(metaVars, 'Name') | strcmp(metaVars, 'File')) = [];  % Remove name/file columns
    headers = [baseHeaders, metaVars];
    
    % Build the units row (must have same number of columns as the header)
    unitsRow = {'-', 'mm', 'mm'};  % Units for the 3 fixed columns
    for v = 1:length(metaVars)
        unitsRow{end+1} = metadata_units.(metaVars{v});  % Append unit for each metadata column
    end
    
    % Write header and units rows to CSV
    fprintf(fid_res, '%s\n', strjoin(headers, ','));
    fprintf(fid_res, '%s\n', strjoin(unitsRow, ','));
    
    % --- Write one data row per image ---
    for i = 1:numImages
        % Start with the 3 fixed values: image number, X displacement, Y displacement
        rowData = {num2str(targetNumbers(i)), num2str(deltaX_mm(i)), num2str(deltaY_mm(i))};
        
        % Append the metadata values for this image's row in the metadata table
        for v = 1:length(metaVars)
            val = metadata{metaIndices(i), metaVars{v}};
            % Handle different possible data types uniformly as strings
            if iscell(val)
                valStr = string(val{1});
            elseif isstring(val) || ischar(val)
                valStr = string(val);
            else
                valStr = string(num2str(val));  % Convert numeric to string
            end
            rowData{end+1} = char(valStr);
        end
        % Write the complete row to CSV
        fprintf(fid_res, '%s\n', strjoin(rowData, ','));
    end
    fclose(fid_res);
    fprintf('Saved raw results and metadata to: %s\n', resFilename);
end