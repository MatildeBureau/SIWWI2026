function allFiles = wm_select_files()
% WM_SELECT_FILES  Interactively selects one or more folders of CSV data files.
%
%  Asks the user how many folders to process, opens a folder browser for
%  each, collects all *.csv files found, then optionally allows the user
%  to select a subset via a list dialog.
%
%  OUTPUT:
%    allFiles — struct array (same format as dir()) with fields:
%               .name, .folder, and standard dir fields

    numFolders  = str2double(inputdlg('Number of data folders:', '', 1, {'1'}));
    folderPaths = strings(numFolders, 1);

    for i = 1:numFolders
        folderPaths(i) = string(uigetdir(pwd, sprintf('Select Folder %d of %d', i, numFolders)));
        if folderPaths(i) == "0"; error('Folder selection cancelled.'); end
    end

    allFiles = [];
    for i = 1:numFolders
        ff = dir(fullfile(folderPaths(i), '*.csv'));
        for j = 1:length(ff)
            ff(j).folder = char(folderPaths(i));
        end
        allFiles = [allFiles; ff]; %#ok<AGROW>
    end

    modeSel = questdlg('Process all files or select a subset?', '', 'All', 'Select subset', 'All');
    if strcmp(modeSel, 'Select subset')
        [idx, ok] = listdlg('ListString', {allFiles.name}, 'SelectionMode', 'multiple');
        if ~ok; error('File selection cancelled.'); end
        allFiles = allFiles(idx);
    end

    fprintf('Files queued: %d\n', length(allFiles));
end