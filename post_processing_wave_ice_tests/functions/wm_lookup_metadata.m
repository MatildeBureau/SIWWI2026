function metaIdx = wm_lookup_metadata(locExpanded, fChannel, fDate)
% WM_LOOKUP_METADATA  Find row index in locExpanded matching a DAQ channel.
%
%  If the locExpanded table contains a non-empty 'Date' column, the lookup
%  is restricted to rows whose Date matches fDate (allows per-day channel
%  reassignment across campaigns).  Otherwise all dates are accepted and
%  only the channel number is matched.
%
%  INPUTS
%    locExpanded — table from wm_load_location_metadata
%    fChannel    — DAQ channel number (integer)
%    fDate       — date string 'DDMMYY' parsed from the filename
%
%  OUTPUT
%    metaIdx — row index (or indices) satisfying the match condition.
%              Empty if no match found.

    % Detect whether a populated Date column is present in the table
    colExists = ismember('Date', locExpanded.Properties.VariableNames);
    hasDate   = colExists && any(locExpanded.Date ~= "");

    if hasDate
        % Match on both channel AND date (per-day sensor reassignment)
        metaIdx = find(locExpanded.Channel == fChannel & ...
                       locExpanded.Date    == fDate);
    else
        % No date column — match on channel only
        metaIdx = find(locExpanded.Channel == fChannel);
    end

end