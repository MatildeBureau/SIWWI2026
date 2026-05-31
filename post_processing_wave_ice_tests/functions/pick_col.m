function colName = pick_col(vars, candidates)
% PICK_COL  Find the first matching column name from a list of aliases.
%
%  Used when the index CSV column names may differ between dataset versions
%  (e.g. 'Filename' vs 'file_name' vs 'FileName').  Checks each alias in
%  order and returns the first one found in vars.
%
%  INPUTS
%    vars       — cell array of strings, column names in the table
%    candidates — cell array of candidate alias strings, in priority order
%
%  OUTPUT
%    colName — first element of candidates that appears in vars
%
%  Raises an error if none of the candidates are present.

    for k = 1:length(candidates)
        if ismember(candidates{k}, vars)
            colName = candidates{k};
            return;
        end
    end

    error('None of the candidate column names found in table: %s', ...
        strjoin(candidates, ', '));

end