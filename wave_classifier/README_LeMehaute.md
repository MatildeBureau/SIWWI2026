# Le Méhauté Wave Theory Classifier
This script classifies experimental wave data into valid wave theories based on the Le Méhauté (1976) diagram. It takes nominal wave parameters and post-processed results, computes the necessary dimensionless variables, classifies each wave condition, and plots them on a reproduced Le Méhauté diagram.

**Author:** Matilde, May 2026  
**Project:** SIWWI 2026

---

## Features

- **Frequency Matching:** Uses a fuzzy-matching algorithm (configurable tolerance, default 12%) to map the programmed wavemaker frequency (`SetFrequency_Hz`) to the nominal frequency (`f_Hz`), correctly retrieving the theoretical wavelength for each condition.
- **Amplitude Matching:** Among all wave-parameter rows passing the frequency match, selects the row whose set amplitude `a_set` is closest to the measured amplitude to correctly resolves all steepnesses (`ka`) per frequency.
- **Ice Tagging:** Prompts the user via the console to specify whether ice was present for each experimental dataset. Ice and water tests use distinct visual markers on the plot and distinct dispersion relations for wavelength computation (see below).
- **Wavelength / Wavenumber Computation:**
  - *Open-water tests:* The wavelength is read directly from the wave-parameters CSV (`lambda_m`), which was pre-computed from the open-water Airy dispersion relation $\omega^2 = gk\tanh(kH)$ at the nominal frequency.
  - *Ice-covered tests:* The wavelength is solved iteratively (Newton's method, up to 200 iterations, convergence $< 10^{-10}$) from the **flexural-gravity dispersion relation**:
$$\omega^2 = gk\tanh(kH)\left(1 + \frac{Dk^4}{\rho_w g}\right)$$
where $D = Eh^3 / [12(1-\nu^2)]$ is the ice flexural rigidity, $H$ is the still-water depth, and $\rho_w$ is water density. The open-water wavelength at the matched frequency is used as the Newton initialisation $k_0$.
- **Le Méhauté Coordinates:** Computes dimensionless depth $H/(gT^2)$ (x-axis) and dimensionless wave height $2a/(gT^2)$ (y-axis), consistent with the wave-height-based ($2a = H_\text{wave}$) thresholds of Zhao et al. (2024).
- **Zone Classification:** Categorises each data point by:
  - *Depth regime:* Shallow ($H/\lambda < 0.05$), Intermediate ($0.05 < H/\lambda < 0.5$), Deep ($H/\lambda > 0.5$).
  - *Wave theory:* Linear, Stokes 2nd–5th order, Cnoidal ($U_r > 26$), or Breaking. Thresholds are the deep-water $2a/\lambda$ limits from Zhao et al. (2024) Table 1, based on the crest-contribution ratio $R_n \geq 1\%$ criterion of Zhao & Liu (2022). The Ursell number is $U_r = (2a/\lambda)/(H/\lambda)^3$.
- **Ice-specific Dimensionless Parameters** (computed for ice tests only):
  - $kH$: dimensionless water depth
  - $kh$: dimensionless ice thickness
  - $kL_d$: elasticity parameter, where $L_d = (D/\rho_w g)^{1/4}$ is the flexural length scale
  - $h/\lambda$: relative ice thickness (thin-plate validity check: $h/\lambda \ll 1$)
  - $\mathcal{I} = ah E / (\sigma_f \lambda^2)$: Voermans et al. (2020) breakup parameter, with uncertainty $\delta\mathcal{I}/\mathcal{I} = \sqrt{(\delta a/a)^2 + (\delta h/h)^2 + (\delta E/E)^2 + (\delta\sigma_f/\sigma_f)^2}$ propagated in quadrature. Per-row amplitude uncertainty $\delta a$ is read from `UncertaintyAmplitude_m` in the results CSV if present.
- **Plotting:** Generates a log-log Le Méhauté diagram with:
  - Breaking limit curve (Fenton 1990, Eq. 7)
  - Cnoidal/Stokes boundary ($U_r = 26$)
  - Stokes order boundaries ($2a/\lambda =$ 0.0064, 0.0472, 0.0697 deep-water asymptotes)
  - $U_r$ iso-lines ($U_r = 1$, $U_r = 20$)
  - Depth-regime vertical boundaries ($H/\lambda = 0.05$, $H/\lambda = 0.5$)
  - Scatter points for all experiments, coloured and shaped by dataset and ice presence
- **Export:** Saves classification results to a `.csv` and the diagram as high-resolution PDF and PNG.

---

## Inputs

The script takes pairs of `.csv` files for each experiment, specified in `csv_pairs` (Section 2). Ensure your input tables contain the following columns:

**1. Wave Parameters CSV (`Waves_param_HIGH_*.csv`):**

| Column | Description |
|--------|-------------|
| `f_Hz` | Nominal wavemaker frequency [Hz] |
| `T_s` | Nominal wave period [s] |
| `lambda_m` | Theoretical open-water wavelength [m] (pre-computed from Airy dispersion relation) |
| `ka` | Set wave steepness $ka$ [-] |
| `a_m` | Set wave amplitude [m] (used for amplitude matching; reconstructed from `ka` and `lambda_m` if absent) |

**2. Results Post-Processing CSV (`Results_postprocess_*.csv`):**

| Column | Description |
|--------|-------------|
| `SetFrequency_Hz` | Programmed wavemaker frequency logged by controller [Hz] |
| `MeasuredFrequency_FFT_Hz` | Measured dominant frequency from FFT of acoustic signal [Hz] |
| `MeasuredAmplitude_m` | Measured wave amplitude $a$ [m] (script uses $2a$ as wave height for diagram) |
| `UncertaintyAmplitude_m` | *(optional)* Per-row amplitude uncertainty [m], used in $\mathcal{I}$ uncertainty propagation |

---

## Outputs

### CSV (`waves_class.csv`)

One row per valid data point, with the following columns:

| Column | Description |
|--------|-------------|
| `Dataset` | Experiment label (date string) |
| `Has_Ice` | Boolean — ice present? |
| `T_s` | Measured period $1/f_\text{meas}$ [s] |
| `T_set` | Set (nominal) period $1/f_\text{set}$ [s] |
| `a_m` | Measured amplitude [m] |
| `H_wave_m` | Wave height $2a$ [m] |
| `H_over_gT2` | Dimensionless depth $H/(gT^2)$ — x-axis coordinate |
| `twoa_over_gT2` | Dimensionless wave height $2a/(gT^2)$ — y-axis coordinate |
| `H_over_lambda` | Relative water depth $H/\lambda$ [-] |
| `a_over_lambda` | Wave amplitude steepness $a/\lambda$ [-] |
| `Ursell_Ur` | Ursell number $U_r = (2a/\lambda)/(H/\lambda)^3$ [-] |
| `Depth_Zone` | Depth regime: `Shallow`, `Intermediate`, or `Deep` |
| `Theory_Zone` | Wave theory: `Linear`, `Stokes-2nd`, ..., `Stokes-5th`, `Cnoidal`, or `BREAKING` |
| `lambda_m` | Wavelength used [m] (open-water or flexural-gravity, depending on ice flag) |
| `k_rad_m` | Wavenumber [rad/m] |
| `kH` | Dimensionless water depth $kH$ [-] |
| `kh` | Dimensionless ice thickness $kh$ [-] (NaN for water tests) |
| `kLd` | Elasticity parameter $kL_d$ [-] (NaN for water tests) |
| `I_breakup` | Breakup parameter $\mathcal{I}$ [-] (NaN for water tests) |
| `dI_breakup` | Uncertainty on $\mathcal{I}$ [-] (NaN for water tests) |
| `h_over_lambda` | Relative ice thickness $h/\lambda$ [-] (NaN for water tests) |
| `H_over_lambda_water` | Relative water depth $H/\lambda$ [-] (alias of `H_over_lambda`) |
| `ka_set` | Set steepness $ka$ from wave-params match [-] |

### Figure (`lemehaute_diagram.pdf` / `.png`)

Log-log Le Méhauté diagram with all SIWWI experiments overlaid as scatter points. Water tests: circles. Ice tests: diamonds. 

---

## Physical Parameters

Ice and water parameters are set in the script header (Section — Physical Constants). I have used:

| Parameter | Symbol | Value | Unit |
|-----------|--------|-------|------|
| Still-water depth | $H$ | 0.30 | m |
| Gravity | $g$ | 9.81 | m/s² |
| Ice thickness | $h$ | 0.01 | m |
| Young's modulus | $E$ | 2.1 × 10⁹ | Pa |
| Poisson's ratio | $\nu$ | 0.33 | — |
| Ice density | $\rho_i$ | 895 | kg/m³ |
| Water density | $\rho_w$ | 1000 | kg/m³ |
| Flexural strength | $\sigma_f$ | 1985 × 10³ | Pa |
| Uncertainty on $E$ | $\delta E$ | 1.7 × 10⁹ | Pa |
| Uncertainty on $h$ | $\delta h$ | 0.003 | m |
| Uncertainty on $\sigma_f$ | $\delta\sigma_f$ | 1168 × 10³ | Pa |

Derived:
- Flexural rigidity: $D = Eh^3 / [12(1-\nu^2)] \approx 1.96 \times 10^{-2}$ N·m
- Flexural length: $L_d = (D/\rho_w g)^{1/4} \approx 0.376$ m

---

## References

- Le Méhauté, B. (1976). *An Introduction to Hydrodynamics and Water Waves*. Springer, Berlin, Heidelberg.
- Zhao, K. & Liu, P.L.-F. (2022). On Stokes wave solutions. *Proceedings of the Royal Society A*, 478, 20210732.
- Zhao, K., Wang, Y. & Liu, P.L.-F. (2024). A guide for selecting periodic water wave theories — Le Méhauté (1976)'s graph revisited. *Coastal Engineering*, 188, 104432.
- Fenton, J.D. (1990). Nonlinear wave theories. *The Sea — Ocean Engineering Science*, 9, 3–25.
- Voermans, J.J. et al. (2020). Experimental evidence for a universal threshold characterizing wave-induced sea ice break-up. *The Cryosphere*, 14, 4265–4278.
