%% =========================================================
% disp rel solver
% =========================================================
function k_out = deal_solve_k(omega, H, D, rho_w, g, use_ice)
% Solve the dispersion relation for wave number k via Newton-Raphson.
%   Open water : omega^2 = g k tanh(kH)
%   Ice cover  : omega^2 = g k tanh(kH) (1 + D k^4 / (rho_w g))
    k_out = omega^2 / g;   % deep-water initial guess
    for it = 1:200
        th = tanh(k_out * H);
        if use_ice
            alpha = D * k_out^4 / (rho_w * g);
            Fv    = omega^2 - g * k_out * th * (1 + alpha);
            dF    = -g*th*(1+alpha) - g*k_out*(1-th^2)*H*(1+alpha) ...
                    - g*k_out*th*4*D*k_out^3/(rho_w*g);
        else
            Fv = omega^2 - g * k_out * th;
            dF = -g*th - g*k_out*(1-th^2)*H;
        end
        kn = k_out - Fv/dF;
        if kn <= 0; kn = k_out/2; end
        if abs(kn - k_out)/k_out < 1e-10; break; end
        k_out = kn;
    end
end