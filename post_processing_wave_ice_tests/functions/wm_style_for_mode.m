function st = wm_style_for_mode(mStr, modeStyleMap)
% WM_STYLE_FOR_MODE  Returns plot style struct for a given acquisition mode.
%
%  Looks up the mode string in modeStyleMap. If the mode is not recognised,
%  the UNKNOWN style is returned (purple, dotted, triangle marker).
%
%  INPUTS:
%    mStr         — mode string, e.g. 'HIGH', 'LOW' (case-insensitive)
%    modeStyleMap — struct with fields LOW, HIGH, UNKNOWN, each containing:
%                     .color      [r g b]
%                     .linestyle  string
%                     .marker     string
%
%  OUTPUT:
%    st — style struct for the requested mode

    mStr = upper(char(mStr));

    if isfield(modeStyleMap, mStr)
        st = modeStyleMap.(mStr);
    else
        st = modeStyleMap.UNKNOWN;
    end
end