function vidPath = wm_find_video(vidName, allFiles, numFiles)
% WM_FIND_VIDEO  Finds a video file on disk, tolerating missing extensions.
%
%  The pairing CSV stores video filenames without a file extension.
%  On disk the files may be .MOV, .mp4, .avi, .MP4, .mov, etc.
%  This function tries the bare name first, then appends common
%  video extensions one by one until a match is found.
%
%  INPUTS:
%    vidName  — filename string from the CSV (with or without extension).
%               Can be a MATLAB string or char array.
%    allFiles — struct array returned by dir(), as built in Section 2d
%               of tank_process_sidecam.m. Each element must have
%               fields .folder and .name.
%    numFiles — length(allFiles)
%
%  OUTPUT:
%    vidPath  — full resolved path (string) if a match is found,
%               or "" (empty string) if no match is found.
%
%  EXTENSIONS TRIED (in order):
%    bare name (no extension added), .MOV, .mov, .MP4, .mp4,
%    .avi, .AVI, .MTS, .mts, .m4v, .M4V
%
%  EXAMPLE:
%    vidPath = wm_find_video('060526_x4p6_f1p67_ak0p03_nikon', ...
%                             allFiles, numFiles);
%    % Returns e.g. 'C:\data\cam\060526_x4p6_f1p67_ak0p03_nikon.MOV'
%    % even though the CSV entry had no extension.

    % Extensions to try, in order of likelihood.
    % The bare name (no extension appended) is always tried first.
    extsToTry = {'', '.MOV', '.mov', '.MP4', '.mp4', ...
                 '.avi', '.AVI', '.MTS', '.mts', '.m4v', '.M4V'};

    % Initialise output to empty — returned if nothing is found
    vidPath = "";

    % Convert input to char for string operations
    vidNameChar = char(vidName);

    for iExt = 1:length(extsToTry)

        % Build candidate filename: bare name + this extension attempt
        candName = [vidNameChar extsToTry{iExt}];

        % Search all folders known to the script (acoustic + video folders)
        for fi = 1:numFiles
            candidate = fullfile(allFiles(fi).folder, candName);
            if exist(candidate, 'file')
                % Match found — return immediately with the full path
                vidPath = string(candidate);
                return;
            end
        end

    end
    % If we reach here, no match was found across all extensions and folders.
    % vidPath remains "" — the caller is responsible for handling this.

end