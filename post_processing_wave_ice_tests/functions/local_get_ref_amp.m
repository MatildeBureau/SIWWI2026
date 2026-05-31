function a0 = local_get_ref_amp(refAmp, hasBenchmark, measType, sensorID, xLoc, freq, amp)
% LOCAL_GET_REF_AMP  Look up open-water reference amplitude by string key.
%
%  Builds a lookup key from the measurement type, sensor/location ID,
%  frequency, and voltage, then searches the refAmp struct for a match.
%
%  KEY FORMAT (must match Section 2f of the main script exactly):
%    Acoustic_Sensor -> 'S<sensorID>_f<fTok>_A<vTok>'   e.g. 'S5_f1p67_A0p42'
%    Side_Camera     -> 'C<xTok>_f<fTok>_A<vTok>'       e.g. 'C4p60_f1p67_A0p42'
%
%  TOKEN FORMATTING
%    Frequency — rounded to 2 decimal places, dot replaced with 'p'.
%                Example: 1.6714 Hz -> '1p67'
%    Voltage   — via canonical_volt_token(), which uses a lookup table to
%                handle CSV floating-point drift (e.g. 0.4199... -> '0p42').
%    x-location — rounded to 2 dp, dot replaced with 'p'.
%
%  NOTE: Frequency is formatted to 2 dp here to match the key format used
%  when building refAmp in Section 2f.  Using %.4f would produce '1p6714'
%  and cause all lookups to silently return NaN.
%
%  INPUTS
%    refAmp       — struct with fields named by the key format above
%    hasBenchmark — logical flag; false -> return NaN immediately
%    measType     — "Acoustic_Sensor" or "Side_Camera"
%    sensorID     — integer DAQ channel (for Acoustic_Sensor)
%    xLoc         — along-tank position [m] (for Side_Camera)
%    freq         — set wave frequency [Hz]
%    amp          — set paddle voltage [V]
%
%  OUTPUT
%    a0 — reference amplitude [m], or NaN if not found

    a0 = NaN;
    if ~hasBenchmark; return; end

    % Voltage token — lookup table handles CSV floating-point drift
    vTok = canonical_volt_token(amp);

    % Frequency token — must match Section 2f key builder exactly
    fTok = strrep(sprintf('%.2f', round(freq, 2)), '.', 'p');

    % Build key and look up
    if measType == "Acoustic_Sensor"
        if ~isfinite(sensorID); return; end
        rKey = sprintf('S%d_f%s_A%s', round(sensorID), fTok, vTok);
    else
        if ~isfinite(xLoc); return; end
        xTok = strrep(sprintf('%.2f', xLoc), '.', 'p');
        rKey = sprintf('C%s_f%s_A%s', xTok, fTok, vTok);
    end

    if isfield(refAmp, rKey)
        a0 = refAmp.(rKey);
    end

end