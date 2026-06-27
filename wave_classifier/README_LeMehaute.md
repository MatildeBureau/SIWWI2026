# SIWWI 2026 — Wave Theory Classification & Breakup Analysis

This repository contains two MATLAB scripts for post-processing SIWWI wave-tank experimental data. Together they classify all wave conditions on a Le Méhauté diagram, assess the proximity of each ice-covered test to the wave-induced breakup threshold of Voermans et al. (2020), and plot the ice-modified wavelength ratio relative to open-water predictions.

**Author:** Matilde , May–June 2026  


---

## Repository Structure

```
wave_classifier/
├── wave_classifier_v1.m        # Script 1 — Le Méhauté classification + CSV export
├── wave_stats_fracture_plots.m # Script 2 — Statistics + breakup + wavelength-ratio plots
├── waves_class.csv             # Output of Script 1 — input to Script 2
├── lemehaute_diagram.pdf/.png  # Le Méhauté diagram (output of Script 1)
└── README.md                   # This file
```

**Workflow:** run Script 1 first to generate `waves_class.csv`, then run Script 2 on that CSV.

---

## Script 1 — `wave_classifier_v1.m`

### Overview

Classifies all SIWWI wave conditions on the Le Méhauté (1976) diagram, using quantitative zone boundaries from Zhao, Wang & Liu (2024). For each experimental result row it:

1. **Matches** the logged wavemaker frequency to the nominal wave-parameters table (fuzzy frequency match within `FREQ_MATCH_TOL`, default 12%, then closest-amplitude refinement) to retrieve the correct theoretical wavelength and steepness for that specific commanded condition.
2. **Computes the wavenumber** using the open-water Airy dispersion relation for water-only tests, or the flexural-gravity dispersion relation (Newton–Raphson iteration) for ice-covered tests.
3. **Computes Le Méhauté coordinates** $H/(gT^2)$ and $2a/(gT^2)$, classifies the depth regime and applicable wave theory, and calculates all relevant dimensionless parameters.
4. **Computes the wavelength ratio** $\lambda_\mathrm{m} / \lambda_\mathrm{set}$ (ice-modified wavelength over open-water set wavelength) with propagated uncertainty, for ice tests.
5. **Plots the diagram** with all SIWWI data points overlaid and exports the figure and a summary CSV.

Ice presence is determined **interactively at runtime**: the script prompts `y/n` for each experiment pair.

### Dispersion relations

**Water tests** use the pre-computed open-water Airy wavelength from the wave-parameters CSV directly (no iteration needed).

**Ice tests** solve the flexural-gravity dispersion relation by Newton–Raphson:

$$\omega^2 = gk \tanh(kH) \left(1 + \frac{D k^4}{\rho_w g}\right)$$

where $D = Eh^3/[12(1-\nu^2)]$ [N·m] is the flexural rigidity and $L_d = (D/\rho_w g)^{1/4}$ [m] is the elastic length. The solver is implemented as a local function `solve_k_dispersion(omega, H, D, rho_w, g, k0)` and converges to a relative tolerance of $10^{-10}$.

### Zone classification

**Depth regime** ($H/\lambda$ thresholds):

| $H/\lambda$ | Zone |
|---|---|
| > 0.5 | Deep |
| 0.05 – 0.5 | Intermediate |
| < 0.05 | Shallow |

**Wave theory** ($H/\lambda$ thresholds from Zhao et al. 2024, Table 1, all defined on wave height $H = 2a$):

| $H/\lambda$ | Theory |
|---|---|
| $U_r > 26$ | Cnoidal |
| < 0.0064 | Linear |
| 0.0064 – 0.0472 | Stokes 2nd order |
| 0.0472 – 0.0697 | Stokes 3rd order |
| 0.0697 – 0.0896 | Stokes 4th order |
| 0.0896 – 0.141 | Stokes 5th order |
| > 0.141 | BREAKING |

The Ursell number is $U_r = (H/\lambda) / (H/\lambda)^3 = 1/(H/\lambda)^2 \cdot (H/\lambda) = (2a/\lambda) / (H/\lambda)^3$.

### Breakup parameter and uncertainty

The Voermans et al. (2020) breakup parameter is:

$$\mathcal{I} = \frac{a \, h \, E}{\sigma_f \, \lambda^2}$$

Uncertainty propagation (quadrature sum of relative errors):

$$\frac{\delta\mathcal{I}}{\mathcal{I}} = \sqrt{\left(\frac{\delta a}{a}\right)^2 + \left(\frac{\delta h}{h}\right)^2 + \left(\frac{\delta E}{E}\right)^2 + \left(\frac{\delta \sigma_f}{\sigma_f}\right)^2}$$

where $\delta a$ is read per-row from `UncertaintyAmplitude_m` in the results CSV (falls back to 0 if column absent), and $\delta E$, $\delta h$, $\delta \sigma_f$ are hardcoded at the top of the script.

### Wavelength ratio and its uncertainty

For ice tests, the script computes:

$$r = \frac{\lambda_\mathrm{ice}}{\lambda_\mathrm{set,ow}}$$

where $\lambda_\mathrm{ice}$ is the flexural-gravity wavelength at the measured frequency and $\lambda_\mathrm{set,ow}$ is the open-water wavelength from the wave-parameters table. The uncertainty $\delta r$ is estimated by **finite difference**: the flexural-gravity dispersion is re-solved at $E+\delta E$ and $h+\delta h$ independently, and the resulting shifts in $k$ are combined in quadrature:

$$\frac{\delta r}{r} = \frac{\sqrt{(k_{E+\delta E} - k)^2 + (k_{h+\delta h} - k)^2}}{k}$$

### Inputs

Pairs of `.csv` files per experiment, defined in the `csv_pairs` cell array at the top of the script (3 columns: wave-parameters path, results path, label string).

**Wave Parameters CSV (`Waves_param_HIGH_*.csv`):**

| Column | Description |
|---|---|
| `f_Hz` | Nominal wavemaker frequency [Hz] |
| `T_s` | Nominal wave period [s] |
| `lambda_m` | Open-water wavelength (Airy dispersion relation) [m] |
| `ka` | Set wave steepness $ka$ [-] |
| `a_m` | *(optional)* Set wave amplitude [m]; reconstructed as $ka / k$ if absent |

**Results CSV (`Results_postprocess_*.csv`):**

| Column | Description |
|---|---|
| `SetFrequency_Hz` | Programmed frequency logged by wavemaker controller [Hz] |
| `MeasuredFrequency_FFT_Hz` | Frequency measured by FFT of acoustic signal [Hz] |
| `MeasuredAmplitude_m` | Measured wave amplitude $a$ [m] |
| `UncertaintyAmplitude_m` | *(optional)* Per-row amplitude uncertainty $\delta a$ [m] |

### Outputs

**`waves_class.csv`** — one row per valid matched data point:

| Column | Unit | Description |
|---|---|---|
| `Dataset` | — | Experiment label (date string from `csv_pairs`) |
| `Has_Ice` | — | Boolean — ice present? |
| `T_s` | s | Measured period $1/f_\mathrm{meas}$ |
| `T_set` | s | Nominal set period $1/f_\mathrm{set}$ |
| `a_m` | m | Measured amplitude |
| `H_wave_m` | m | Wave height $2a$ |
| `H_over_gT2` | — | Le Méhauté x-coordinate $H/(gT^2)$ |
| `twoa_over_gT2` | — | Le Méhauté y-coordinate $2a/(gT^2)$ |
| `H_over_lambda` | — | Relative water depth $H/\lambda$ |
| `a_over_lambda` | — | Amplitude steepness $a/\lambda$ |
| `Ursell_Ur` | — | Ursell number $U_r = (2a/\lambda)/(H/\lambda)^3$ |
| `Depth_Zone` | — | `Shallow`, `Intermediate`, or `Deep` |
| `Theory_Zone` | — | `Linear`, `Stokes-2nd` … `Stokes-5th`, `Cnoidal`, or `BREAKING` |
| `lambda_m` | m | Wavelength (Airy for water; flexural-gravity for ice) |
| `k_rad_m` | rad/m | Wavenumber |
| `kH` | — | Dimensionless water depth $kH$ |
| `kh` | — | Dimensionless ice thickness $kh$ (NaN: water) |
| `kLd` | — | Elasticity parameter $kL_d$ (NaN: water) |
| `I_breakup` | — | Breakup parameter $\mathcal{I}$ (NaN: water) |
| `dI_breakup` | — | Uncertainty on $\mathcal{I}$ (NaN: water) |
| `h_over_lambda` | — | Relative ice thickness $h/\lambda$ (NaN: water) |
| `H_over_lambda_water` | — | Alias of `H_over_lambda` |
| `ka_set` | — | Matched set steepness |
| `f_set_Hz` | Hz | Matched set frequency |
| `lambda_open_water_set_m` | m | Open-water wavelength at set frequency (from wave-parameters CSV) |
| `lambda_ratio_ice_over_setwater` | — | $\lambda_\mathrm{ice} / \lambda_\mathrm{set,ow}$ (NaN: water) |
| `d_lambda_ratio_ice_over_setwater` | — | Uncertainty on wavelength ratio (NaN: water) |

**`lemehaute_diagram.pdf` / `.png`** — log-log Le Méhauté diagram  with:
- All experimental data as scatter points (circles: water; diamonds: ice), coloured by experiment date
- Zone boundaries from Zhao et al. (2024)
- Breaking criterion curve from Fenton (1990)
- Cnoidal/Stokes boundary ($U_r = 26$)
- Ursell iso-lines $U_r = 1$ and $U_r = 20$
- Depth-regime vertical lines at $H/\lambda = 0.05$ and $H/\lambda = 0.5$

### Configuration (Script 1)

All user-editable parameters are at the top of the script.

| Parameter | Default | Unit | Description |
|---|---|---|---|
| `water_depth_m` | 0.3 | m | Still-water depth $H$ |
| `output_csv_path` | *(path)* | — | Full path for output `waves_class.csv` |
| `output_figures` | *(path)* | — | Directory for figure export |
| `csv_pairs` | *(cell array)* | — | One row per experiment: `{wave_params_path, results_path, label}` |
| `FREQ_MATCH_TOL` | 0.12 | — | Relative frequency matching tolerance (12%) |
| `E_ice` | 2.1 × 10⁹ | Pa | Young's modulus of ice |
| `rho_ice` | 895 | kg/m³ | Ice density |
| `h_ice` | 0.01 | m | Ice sheet thickness |
| `nu_ice` | 0.33 | — | Poisson's ratio of ice |
| `rho_w` | 1000 | kg/m³ | Water density |
| `sigma_f` | 1985 × 10³ | Pa | Ice flexural strength |
| `dE_ice` | 1.7 × 10⁹ | Pa | 1-σ uncertainty on Young's modulus |
| `dh_ice` | 0.003 | m | 1-σ uncertainty on ice thickness |
| `dsigma_f` | 1168 × 10³ | Pa | 1-σ uncertainty on flexural strength |

---

## Script 2 — `wave_stats_fracture_plots.m`

### Overview

Reads `waves_class.csv` (output of Script 1) and produces three outputs:

1. **Parameter statistics table** — prints min, max, mean and median of all key dimensionless parameters, split by ice vs water, with full context columns ($\lambda$, $T_\mathrm{set}$, $f_\mathrm{set}$, $T_s$, $a$, $ka_\mathrm{set}$) printed alongside each statistic for quick identification of the corresponding experimental condition.
2. **Four breakup plots** — shows the normalised breakup parameter $\mathcal{I}/\mathcal{I}_{br}$ (Voermans et al. 2020, threshold $\mathcal{I}_{br} = 0.014$) with propagated uncertainty error bars, as a function of steepness and period.
3. **Two wavelength-ratio plots** — shows $\lambda_\mathrm{ice}/\lambda_\mathrm{set,ow}$ with error bars as a function of frequency and steepness. These are only produced if `waves_class.csv` contains the columns `lambda_ratio_ice_over_setwater` and `d_lambda_ratio_ice_over_setwater` (i.e., generated by the current version of Script 1).

Artefact rows where $a \approx 0$ (threshold $10^{-10}$ m) are removed before any computation or plotting.


### Statistics

Reports min/max/mean/median for the following parameters:

| Parameter | Ice only? |
|---|---|
| $k$ [rad/m] | No |
| $\lambda$ [m] | No |
| $H/\lambda$ (water depth / wavelength) | No |
| $H/\lambda_\mathrm{water}$ (alias) | No |
| $a/\lambda$ | No |
| $kH$ | No |
| $kh$ | **Yes** |
| $kL_d$ | **Yes** |
| $h/\lambda$ | **Yes** |
| $\mathcal{I}$ (breakup parameter) | **Yes** |

For mean and median, the row nearest the computed value is reported as context (labelled `[nearest row]`).

### Breakup plots

The normalised breakup parameter $\mathcal{I}/\mathcal{I}_{br}$ is plotted for ice rows only. The dashed red line at $\mathcal{I}/\mathcal{I}_{br} = 1$ marks the predicted breakup onset. Error bars show the quadrature-propagated uncertainty $\delta\mathcal{I}/\mathcal{I}_{br}$ read directly from `dI_breakup` in the CSV.

| Plot | Filename | x-axis | Colour/series | Description |
|---|---|---|---|---|
| 1 | `I_vs_ka_fixed_T_{T}s.pdf/.png` | $(ka)_\mathrm{set}$ | single series | Fixed $T_\mathrm{set}$ = `fixed_T_set` |
| 2 | `I_vs_T_fixed_ka_{ka}.pdf/.png` | $T_\mathrm{set}$ [s] | single series | Fixed $(ka)_\mathrm{set}$ = `fixed_ka_set` |
| 3 | `I_vs_ka_fixed_T.pdf/.png` | $(ka)_\mathrm{set}$ | one colour per $T_\mathrm{set}$ | All periods overlaid |
| 4 | `I_vs_T_fixed_ka.pdf/.png` | $T_\mathrm{set}$ [s] | one colour per $(ka)_\mathrm{set}$ | All steepnesses overlaid |

Plots 1 and 2 filter using configurable fixed values (`fixed_T_set`, `fixed_ka_set`) with tolerances `tol_T` and `tol_ka`. If no matching data are found, the plot is created with an informative title and the available values are printed to the Command Window.


### Wavelength-ratio plots

These plots are only produced if `waves_class.csv` was generated by the current version of `wave_classifier_v1.m` (i.e., includes the columns `f_set_Hz`, `lambda_open_water_set_m`, `lambda_ratio_ice_over_setwater`, `d_lambda_ratio_ice_over_setwater`). If these columns are absent, a warning is printed and Plots 5–6 are skipped.

| Plot | Filename | x-axis | Colour/series | Description |
|---|---|---|---|---|
| 5 | `lambda_ratio_vs_fset_by_ka.pdf/.png` | $f_\mathrm{set}$ [Hz] | one colour per $(ka)_\mathrm{set}$ | $\lambda_\mathrm{ice}/\lambda_\mathrm{set,ow}$ vs frequency |
| 6 | `lambda_ratio_vs_ka_by_fset.pdf/.png` | $(ka)_\mathrm{set}$ | one colour per $f_\mathrm{set}$ | $\lambda_\mathrm{ice}/\lambda_\mathrm{set,ow}$ vs steepness |

Both plots show error bars from `d_lambda_ratio_ice_over_setwater`. 

### Configuration (Script 2)

| Parameter | Default | Unit | Description |
|---|---|---|---|
| `csv_path` | `'waves_class.csv'` | — | Path to input CSV from Script 1 |
| `I_br_threshold` | 0.014 | — | Voermans et al. (2020) breakup threshold $\mathcal{I}_{br}$ |
| `fixed_T_set` | 0.6 | s | Fixed set period for Plot 1 |
| `fixed_ka_set` | 0.1 | — | Fixed set steepness for Plot 2 |
| `tol_T` | 0.01 | s | Matching tolerance on $T_\mathrm{set}$ |
| `tol_ka` | 0.005 | — | Matching tolerance on $(ka)_\mathrm{set}$ |
| `save_fig` | `true` | — | Export all figures |
| `save_path` | *(path)* | — | Output directory for figures |

### Backward compatibility

If `waves_class.csv` was generated by an older version of Script 1 (missing `T_set`, `dI_breakup`, or the wavelength-ratio columns), Script 2 prints a warning and falls back gracefully:
- `T_set` absent → replaced by `T_s` (fixed-$T$ filtering becomes approximate)
- `dI_breakup` absent → error bars suppressed on all breakup plots
- Wavelength-ratio columns absent → Plots 5–6 skipped entirely

---

## Physical Parameters

Used in both scripts (set at the top of each):

| Parameter | Symbol | Value | Unit |
|---|---|---|---|
| Still-water depth | $H$ | 0.30 | m |
| Gravity | $g$ | 9.81 | m/s² |
| Ice thickness | $h$ | 0.01 | m |
| Young's modulus | $E$ | 2.1 × 10⁹ | Pa |
| Poisson's ratio | $\nu$ | 0.33 | — |
| Ice density | $\rho_i$ | 895 | kg/m³ |
| Water density | $\rho_w$ | 1000 | kg/m³ |
| Flexural strength | $\sigma_f$ | 1985 × 10³ | Pa |
| $\delta E$ | — | 1.7 × 10⁹ | Pa |
| $\delta h$ | — | 0.003 | m |
| $\delta \sigma_f$ | — | 1168 × 10³ | Pa |

Derived quantities:

$$D = \frac{Eh^3}{12(1-\nu^2)} \approx 1.96 \times 10^{-2} \ \mathrm{N \cdot m}$$

$$L_d = \left(\frac{D}{\rho_w g}\right)^{1/4} \approx 0.376 \ \mathrm{m}$$


## References

- Le Méhauté, B. (1976). *An Introduction to Hydrodynamics and Water Waves*. Springer.
- Fenton, J.D. (1990). Nonlinear wave theories. *The Sea — Ocean Engineering Science*, 9, 3–25.
- Zhao, K., Wang, Y. & Liu, P.L.-F. (2024). A guide for selecting periodic water wave theories. *Coastal Engineering*, 188, 104432.
- Voermans, J.J. et al. (2020). Experimental evidence for a universal threshold characterizing wave-induced sea ice break-up. *The Cryosphere*, 14, 4265–4278.
