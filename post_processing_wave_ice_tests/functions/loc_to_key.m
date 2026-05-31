function key = loc_to_key(camX)
% LOC_TO_KEY  Converts a camera x-position [m] to a valid MATLAB fieldname.
%
%  MATLAB struct fieldnames cannot contain dots or minus signs.
%  This function encodes the decimal point as 'p' and prepends 'x'.
%
%  Examples:
%    loc_to_key(4.60)  ->  'x4p60'
%    loc_to_key(1.00)  ->  'x1p00'
%    loc_to_key(0.5)   ->  'x0p50'
%
%  INPUT:
%    camX — camera x-position [m], scalar double
%
%  OUTPUT:
%    key  — valid MATLAB fieldname string (char)

    key = sprintf('x%s', strrep(sprintf('%.2f', camX), '.', 'p'));
end