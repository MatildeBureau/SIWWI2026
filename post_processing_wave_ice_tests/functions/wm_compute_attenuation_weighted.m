function [alpha, A0, R2, delta_alpha, delta_A0, xFit, ampFit] = ...
        wm_compute_attenuation_weighted(xLocs, amps, delta_A)
% WM_COMPUTE_ATTENUATION_WEIGHTED  Fits exponential spatial decay A(x) = A0 * exp(-alpha*x).
%
%  Uses weighted log-linear regression (weights = (A/dA)^2) to fit the
%  model ln(A) = ln(A0) - alpha*x to the measured amplitudes.
%  Requires at least 2 valid data points.
%
%  INPUTS:
%    xLocs   — sensor x-positions [m]
%    amps    — measured wave amplitudes [m]
%    delta_A — amplitude uncertainties [m]
%
%  OUTPUTS:
%    alpha       — spatial attenuation rate [m^-1]
%    A0          — extrapolated amplitude at x=0 [m]
%    R2          — weighted R^2 of the log-linear fit
%    delta_alpha — uncertainty on alpha [m^-1]
%    delta_A0    — uncertainty on A0 [m]
%    xFit        — x vector for the fitted curve (50 points)
%    ampFit      — fitted amplitude curve A0*exp(-alpha*xFit)

    % Remove invalid / non-positive points
    valid = ~isnan(amps) & amps > 0 & ~isnan(delta_A) & delta_A > 0;
    x_v   = xLocs(valid);
    a_v   = amps(valid);
    d_v   = delta_A(valid);

    xFit = linspace(min(xLocs), max(xLocs), 50);

    if sum(valid) < 2
        alpha       = NaN;
        A0          = NaN;
        R2          = NaN;
        delta_alpha = NaN;
        delta_A0    = NaN;
        ampFit      = NaN(size(xFit));
        return;
    end

    % Weighted log-linear regression
    ln_a  = log(a_v);
    w     = (a_v ./ d_v).^2;   % inverse-variance weights

    S     = sum(w);
    Sx    = sum(w .* x_v);
    Sxx   = sum(w .* x_v.^2);
    Sy    = sum(w .* ln_a);
    Sxy   = sum(w .* x_v .* ln_a);
    Delta = S * Sxx - Sx^2;

    p1 = (S * Sxy  - Sx * Sy)  / Delta;   % slope  = -alpha
    p0 = (Sxx * Sy - Sx * Sxy) / Delta;   % intercept = ln(A0)

    alpha = -p1;
    A0    = exp(p0);

    % Uncertainties (from weighted least-squares covariance)
    delta_alpha = sqrt(S   / Delta);
    delta_A0    = A0 * sqrt(Sxx / Delta);

    % Weighted R^2
    ln_fit  = p1 .* x_v + p0;
    ln_mean = sum(w .* ln_a) / S;
    R2      = 1 - sum(w .* (ln_a - ln_fit).^2) / ...
                  max(sum(w .* (ln_a - ln_mean).^2), eps);

    ampFit = A0 * exp(-alpha * xFit);
end