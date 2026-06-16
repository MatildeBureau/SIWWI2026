# SIWWI 2026 — Wave Theory Classification & Breakup Analysis

This repository contains two MATLAB scripts for post-processing SIWWI wave-tank experimental data. Together they classify all wave conditions on a Le Méhauté diagram and assess the proximity of each ice-covered test to the wave-induced breakup threshold of Voermans et al. (2020).

**Author:** Matilde Bureau, May 2026  
**Project:** SIWWI 2026  


---

## Repository Structure

```
wave_classifier/
├── wave_classifier.m          # Script 1 — Le Méhauté classification + CSV export
├── wave_stats_breakup.m       # Script 2 — Statistics + breakup parameter plots
├── waves_class.csv            # Output of Script 1 — input to Script 2
├── lemehaute_diagram.pdf/.png # Le Méhauté diagram (output of Script 1)
└── README.md                  # This file
```

**Workflow:** run Script 1 first to generate `waves_class.csv`, then run Script 2 on that CSV.

---

## Script 1 — `wave_classifier.m`

### Overview

Classifies all SIWWI wave conditions in the Le Méhauté (1976) diagram, updated with quantitative zone boundaries from Zhao, Wang & Liu (2024). For each experimental result row, it:

1. Matches the logged wavemaker frequency to the nominal wave-parameters table (fuzzy frequency match, then closest-amplitude refinement) to retrieve the correct theoretical wavelength and steepness.
2. Computes the wavelength/wavenumber using the **open-water Airy dispersion relation** for water-only tests, or the **flexural-gravity dispersion relation** (Newton iteration) for ice-covered tests.
3. Computes Le Méhauté coordinates $H/(gT^2)$ and $2a/(gT^2)$, classifies the depth regime and applicable wave theory, and calculates all relevant dimensionless parameters.
4. Plots the diagram with all SIWWI data points overlaid and exports the figure and a summary CSV.

### Features

- **Two-step matching:** frequency match within configurable tolerance (default 12%), then closest set amplitude among candidates — correctly recovers all steepnesses per frequency.
- **Ice vs water dispersion:** open-water tests use pre-computed Airy wavelengths; ice tests solve the flexural-gravity relation iteratively.
- **Consistent $2a$ convention:** y-axis is $2a/(gT^2)$ (wave height, not amplitude), consistent with the Zhao et al. (2024) Table 1 thresholds which are defined on $H/\lambda = 2a/\lambda$.
- **Ice-specific parameters:** $kH$, $kh$, $kL_d$, $h/\lambda$, and the Voermans et al. breakup parameter $\mathcal{I}$ with full uncertainty propagation.
- **Backward-compatible:** gracefully handles missing optional CSV columns (`a_m`, `UncertaintyAmplitude_m`).

### Inputs

Pairs of `.csv` files per experiment, defined in `csv_pairs` at the top of the script:

**Wave Parameters CSV (`Waves_param_HIGH_*.csv`):**

| Column | Description |
|--------|-------------|
| `f_Hz` | Nominal wavemaker frequency [Hz] |
| `T_s` | Nominal wave period [s] |
| `lambda_m` | Open-water wavelength from Airy dispersion relation [m] |
| `ka` | Set wave steepness $ka$ [-] |
| `a_m` | Set wave amplitude [m] (reconstructed from `ka`/`lambda_m` if absent) |

**Results CSV (`Results_postprocess_*.csv`):**

| Column | Description |
|--------|-------------|
| `SetFrequency_Hz` | Programmed frequency logged by wavemaker controller [Hz] |
| `MeasuredFrequency_FFT_Hz` | Frequency measured by FFT of acoustic signal [Hz] |
| `MeasuredAmplitude_m` | Measured wave amplitude $a$ [m] |
| `UncertaintyAmplitude_m` | *(optional)* Per-row amplitude uncertainty [m] |

### Outputs

**`waves_class.csv`** — one row per valid data point:

| Column | Description |
|--------|-------------|
| `Dataset` | Experiment label (date string) |
| `Has_Ice` | Boolean — ice present? |
| `T_s` | Measured period $1/f_\text{meas}$ [s] |
| `T_set` | Set (nominal) period $1/f_\text{set}$ [s] |
| `a_m` | Measured amplitude [m] |
| `H_wave_m` | Wave height $2a$ [m] |
| `H_over_gT2` | Dimensionless depth $H/(gT^2)$ — x-axis |
| `twoa_over_gT2` | Dimensionless wave height $2a/(gT^2)$ — y-axis |
| `H_over_lambda` | Relative water depth $H/\lambda$ [-] |
| `a_over_lambda` | Amplitude steepness $a/\lambda$ [-] |
| `Ursell_Ur` | Ursell number $U_r = (2a/\lambda)/(H/\lambda)^3$ [-] |
| `Depth_Zone` | `Shallow`, `Intermediate`, or `Deep` |
| `Theory_Zone` | `Linear`, `Stokes-2nd` … `Stokes-5th`, `Cnoidal`, or `BREAKING` |
| `lambda_m` | Wavelength [m] (Airy or flexural-gravity) |
| `k_rad_m` | Wavenumber [rad/m] |
| `kH` | Dimensionless water depth $kH$ [-] |
| `kh` | Dimensionless ice thickness $kh$ [-] (NaN: water) |
| `kLd` | Elasticity parameter $kL_d$ [-] (NaN: water) |
| `I_breakup` | Breakup parameter $\mathcal{I}$ [-] (NaN: water) |
| `dI_breakup` | Uncertainty on $\mathcal{I}$ [-] (NaN: water) |
| `h_over_lambda` | Relative ice thickness $h/\lambda$ [-] (NaN: water) |
| `H_over_lambda_water` | Alias of `H_over_lambda` [-] |
| `ka_set` | Matched set steepness $ka$ [-] |

**`lemehaute_diagram.pdf` / `.png`** — log-log Le Méhauté diagram with all experiments as scatter points (circles: water; diamonds: ice), zone boundaries, Ursell iso-lines, and breaking criterion.

---

## Script 2 — `wave_stats_breakup.m`

### Overview

Reads `waves_class.csv` (output of Script 1) and produces two outputs:

1. **Parameter statistics table** — prints min, max, mean and median of all key dimensionless parameters, split by ice vs water, with full context columns ($\lambda$, $T_\text{set}$, $f_\text{set}$, $T_s$, $a$, $ka_\text{set}$) for each statistic.
2. **Four breakup plots** — shows the normalised breakup parameter $\mathcal{I}/\mathcal{I}_{br}$ (Voermans et al. 2020, threshold $\mathcal{I}_{br} = 0.014$) with propagated uncertainty error bars, as a function of steepness and period.

### Statistics

Reports min/max/mean/median (with context) for: $k$, $\lambda$, $H/\lambda$, $a/\lambda$, $kH$, $kh$ (ice only), $kL_d$ (ice only), $h/\lambda$ (ice only), $\mathcal{I}$ (ice only). Artefact rows ($a \approx 0$) are removed before any computation.

### Breakup Plots

The breakup parameter is $\mathcal{I} = ahE/(\sigma_f \lambda^2)$ and is normalised by the empirical threshold $\mathcal{I}_{br} = 0.014$ (Voermans et al. 2020). The dashed red line at $\mathcal{I}/\mathcal{I}_{br} = 1$ marks the predicted breakup onset. Error bars show the quadrature-propagated uncertainty from $\delta a$, $\delta h$, $\delta E$, $\delta\sigma_f$.

Four figures are produced:

| Plot | x-axis | Fixed parameter | Description |
|------|--------|----------------|-------------|
| 1 | $ka_\text{set}$ | single $T_\text{set}$ (user-set) | $\mathcal{I}/\mathcal{I}_{br}$ vs steepness at one period |
| 2 | $T_\text{set}$ [s] | single $ka_\text{set}$ (user-set) | $\mathcal{I}/\mathcal{I}_{br}$ vs period at one steepness |
| 3 | $ka_\text{set}$ | all $T_\text{set}$ (colour-coded) | Overview: all periods on one steepness axis |
| 4 | $T_\text{set}$ [s] | all $ka_\text{set}$ (colour-coded) | Overview: all steepnesses on one period axis |

Plots 1 and 2 use configurable fixed values (`fixed_T_set`, `fixed_ka_set`) and matching tolerances (`tol_T`, `tol_ka`). All four figures are exported as PDF and PNG.

### Inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| `csv_path` | `'waves_class.csv'` | Path to output CSV from Script 1 |
| `I_br_threshold` | `0.014` | Voermans et al. breakup threshold |
| `fixed_T_set` | `0.6` s | Fixed period for Plot 1 |
| `fixed_ka_set` | `0.1` | Fixed steepness for Plot 2 |
| `tol_T` | `0.01` s | Matching tolerance on $T_\text{set}$ |
| `tol_ka` | `0.005` | Matching tolerance on $ka_\text{set}$ |
| `save_fig` | `true` | Save figures to `save_path` |
| `save_path` | *(set in script)* | Output directory for figures |

### Backward Compatibility

If `waves_class.csv` was generated by an older version of Script 1 (missing `T_set` or `dI_breakup` columns), Script 2 prints a warning and falls back gracefully: `T_set` is replaced by `T_s` (fixed-$T$ filtering will be approximate) and error bars are suppressed.

---

## Physical Parameters

Values I have used in both scripts (set at the top of each):

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
| $\delta E$ | — | 1.7 × 10⁹ | Pa |
| $\delta h$ | — | 0.003 | m |
| $\delta\sigma_f$ | — | 1168 × 10³ | Pa |

Derived:
- $D = Eh^3/[12(1-\nu^2)] \approx 1.96 \times 10^{-2}$ N·m
- $L_d = (D/\rho_w g)^{1/4} \approx 0.376$ m

---

## References

- Le Méhauté, B. (1976). *An Introduction to Hydrodynamics and Water Waves*. Springer.
- Zhao, K. & Liu, P.L.-F. (2022). On Stokes wave solutions. *Proc. R. Soc. A*, 478, 20210732.
- Zhao, K., Wang, Y. & Liu, P.L.-F. (2024). A guide for selecting periodic water wave theories. *Coastal Engineering*, 188, 104432.
- Fenton, J.D. (1990). Nonlinear wave theories. *The Sea — Ocean Engineering Science*, 9, 3–25.
- Voermans, J.J. et al. (2020). Experimental evidence for a universal threshold characterizing wave-induced sea ice break-up. *The Cryosphere*, 14, 4265–4278.
