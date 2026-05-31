function [fMode, fChannel, fDate, fAmp, fFreq, Fs, ok] = wm_parse_filename(fileName, Fs_default)
% WM_PARSE_FILENAME  Parses acquisition parameters from a standardised filename.
%
%  Extracts test condition metadata encoded in the filename using the
%  underscore-delimited convention used throughout the SIWWI campaign.
%
%  EXPECTED FILENAME FORMAT (>= 8 underscore-delimited parts):
%    raw_data_<MODE>_<LABEL><N>_<LOC>_<DDMMYY>_a[k]<AMP>_f<FREQ>[.csv]
%
%  Part 7 — amplitude field — supports two sub-formats:
%    'ak<VAL>' — wave steepness (ka) encoding.  fAmp is returned as NaN
%                because the steepness value is not a paddle voltage.
%                Example: ak0p03 -> NaN
%    'a<VAL>'  — direct paddle voltage.  Decoded normally.
%                Examples: a0p42 -> 0.42 V,  a4 -> 4.0 V
%
%  Decimal points are encoded as 'p' throughout (e.g. '1p66' = 1.66 Hz).
%
%  EXAMPLES
%    raw_data_HIGH_Sensor6_x9p4m_060526_a0p42_f1p66.csv  -> fAmp=0.42, fFreq=1.66
%    raw_data_HIGH_Sensor3_x4p6m_060526_ak0p03_f1p67.csv -> fAmp=NaN, fFreq=1.67
%    raw_data_HIGH_Sensor6_x9p4m_280426_a4_f1.csv        -> fAmp=4.0, fFreq=1.0
%
%  INPUTS
%    fileName   — filename string (with or without directory path)
%    Fs_default — fallback sampling frequency [Hz] if mode is unrecognised
%
%  OUTPUTS
%    fMode    — acquisition mode string: 'HIGH' | 'LOW' | ...
%    fChannel — sensor channel number (integer)
%    fDate    — date string 'DDMMYY'
%    fAmp     — set paddle voltage [V]; NaN when 'ak' prefix is used
%    fFreq    — set wave frequency [Hz]
%    Fs       — sampling frequency [Hz] inferred from mode
%               HIGH -> 100 Hz, LOW -> 50 Hz, otherwise Fs_default
%    ok       — true if parsing succeeded, false if filename is malformed

    ok = true;

    % Strip directory path, keep basename + extension
    [~, baseName, ext] = fileparts(fileName);
    fullBase = [baseName ext];

    fParts = strsplit(fullBase, '_');
    if length(fParts) < 8
        ok       = false;
        fMode    = '';
        fChannel = NaN;
        fDate    = '';
        fAmp     = NaN;
        fFreq    = NaN;
        Fs       = Fs_default;
        fprintf('[SKIP] Bad filename (needs >= 8 underscore-delimited parts): %s\n', fileName);
        return;
    end

    fMode    = upper(string(fParts{3}));
    fChannel = str2double(regexprep(fParts{4}, '[A-Za-z]', ''));
    % Part 5 is the location label (e.g. x9p4m) — not used here
    fDate    = string(fParts{6});

    % Part 7: amplitude field — detect steepness prefix 'ak'
    ampStr = char(fParts{7});
    if strncmpi(ampStr, 'ak', 2)
        % Steepness encoding: amplitude is not a paddle voltage
        fAmp = NaN;
    else
        % Direct voltage: strip leading 'a', decode 'p' as decimal point
        ampNum = strrep(regexprep(ampStr, '^[Aa]', ''), 'p', '.');
        fAmp   = str2double(ampNum);
    end

    % Part 8: frequency field — strip leading 'f', decode 'p', strip '.csv'
    freqStr = strrep(strrep(strrep(fParts{8}, 'f', ''), '.csv', ''), 'p', '.');
    fFreq   = str2double(freqStr);

    % Infer sampling frequency from acquisition mode
    switch fMode
        case 'LOW',  Fs = 50;
        case 'HIGH', Fs = 100;
        otherwise,   Fs = Fs_default;
    end

end