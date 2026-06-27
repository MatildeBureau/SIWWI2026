# ZS_decomposition_v1.m

**Wave tank incident/reflected amplitude decomposition via Zelt & Skjelbreia method (1992)**

---

## Overview

This script decomposes simultaneous wave-gauge records in a wave tank into **incident** (wavemaker-propagating) and **reflected** (beach-returning) wave components using the weighted least-squares method of Zelt & Skjelbreia (1992), hereafter "ZS".

For each experimental condition (commanded frequency × amplitude pair) it outputs:

| Quantity | Symbol | Unit |
|---|---|---|
| Incident wave amplitude | \|a_L\| | m |
| Reflected wave amplitude | \|a_R\| | m |
| Reflection coefficient | R = \|a_R\| / \|a_L\| | — |
| Measured wave steepness | ka = k\|a_L\| | — |
| ZS system conditioning | D | — |
| 1-σ uncertainties on all above | δR, δk, δ(ka), … | same units |
| Spatial amplitude profiles | — | — |

---

## Method

### Wave field model

In a finite-depth wave tank, the complex free-surface elevation at position x and angular frequency ω is:

```
η(x, t) = Re{ [a_L exp(+ikx) + a_R exp(−ikx)] exp(−iωt) }
```

where `a_L` [m, complex] is the incident amplitude and `a_R` [m, complex] is the reflected amplitude.  Given P gauges at positions x₁, …, x_P with complex DFT amplitudes A₁, …, A_P, this is a 2-unknown, P-equation linear system:

```
M · c = A     M_pj = [exp(+ikx_p), exp(−ikx_p)],   c = [a_L; a_R]
```

ZS solve it by **weighted least squares**:

```
c = (Mᴴ W M)⁻¹ Mᴴ W A
```

The weight `w_p` of gauge p penalises gauge spacings near integer multiples of λ/2 :

```
w_p = Σ_{q≠p} sin²(k Δx_pq) / [1 + (k Δx_pq / π)²]
```

The scalar **denominator D** summarises conditioning:

```
D = 4 · Σ_{p>q} w_p w_q sin²(k(x_p − x_q))
```

| D value | Interpretation |
|---|---|
| D < 0.01 | Near-singular — result **discarded** |
| 0.01 ≤ D < 0.5 | Moderately conditioned — use **with caution** |
| D ≥ 0.5 | Well-conditioned |

Near-singularity occurs when the tank length is close to an integer multiple of λ/2 (resonance.

### Dispersion relation

The wavenumber k [rad/m] is solved from the finite-depth linear dispersion relation by Newton–Raphson iteration:

```
F(k) = g k tanh(kH) − ω² = 0
```

Starting guess: k₀ = ω²/g (deep-water approximation). Convergence tolerance: 10⁻¹⁰ rad/m.

### Steady-state windowing

Only data within the user-configured time window `[t_start_ss, t_end_ss]` are used.  A Hann window is applied (optional) to reduce spectral leakage before the single-bin DFT.  The complex amplitude at each gauge is:

```
A_jp = (2/N_eff) · Σ_n η_w(n) · exp(−2πi k_bin n / N)
```

where `N_eff = sum(hann_window)` is the effective sample count.

---

## Uncertainty Propagation

Three independent sources are propagated in quadrature.

### 1. Frequency uncertainty  δf  [Hz]

Each DFT bin has width Δf = Fs/N, so:
```
δf = Δf / 2 = Fs / (2N)
```

This propagates to wavenumber via:
```
δk = (4πω / F'(k)) · δf
```
where `F'(k) = g[tanh(kH) + kH sech²(kH)]`.

### 2. Amplitude uncertainty  σ_A  [m]  (per gauge)

Two sub-contributions added in quadrature:

**Sideband noise** — RMS of the DFT spectrum in "sideband" bins (bins in `[1, f_max_sb_factor × f_set]` that are more than `n_sb_guard` bins away from the signal peak):
```
σ_A_noise = RMS{ Y_full(k_sb) }
```

**Calibration uncertainty** — from the 1-σ slope (Err_a) and intercept (Err_b) errors of the linear voltage-to-elevation calibration:
```
σ_A_calib = √[ (Err_a · V_rms)² + Err_b² ]
```

Total per-gauge uncertainty:
```
σ_A_total = √( σ_A_noise² + σ_A_calib² )
```

These propagate to a_L and a_R through the WLS gain matrix `C_gain = (MᴴWM)⁻¹ MᴴW`:
```
δ_aL_ampl = σ_A_max · ‖C_gain(1,:)‖
δ_aR_ampl = σ_A_max · ‖C_gain(2,:)‖
```
(conservative: maximum single-gauge σ_A used)

### 3. Sensor position uncertainty  dx_sensor  [m]

Position sensitivity is estimated by finite difference (step `dx_pert`): for each gauge p, the full WLS problem is re-solved with `x_p ± dx_pert`, giving `∂a_L/∂x_p`.  Assuming uncorrelated 1-σ position errors `dx_sensor`:
```
δ_aL_pos² = Σ_p |∂a_L/∂x_p|² · dx_sensor²
```

### Combined uncertainties

```
δ_aL = √( δ_aL_ampl² + δ_aL_pos² )
δ_aR = √( δ_aR_ampl² + δ_aR_pos² )

δR = R · √[ (δ_aR/|a_R|)² + (δ_aL/|a_L|)² ]

δ(ka) = √[ (|a_L| δk)² + (k δ_aL)² ]
```

---

## Input Files

| File | Description |
|---|---|
| `raw_data_dir/*.csv` | Raw acoustic sensor records: two columns — time [s], voltage [V] |
| `acoustic_sensors_calib.csv` | Calibration table: `Mode, Source, Slope_a [m/V], Err_a [m/V], Intercept_b [m], Err_b [m], Uncert_Method` |
| `Metadata_sensors_200526.csv` | Sensor IDs (col 1) and x-positions [m] (col 3) |
| `Metadata_benchmark_200526.csv` | Experimental conditions: `Mode, Acoustic_sensor_filename, Set_f_Hz, Set_volt_V, ka` |

Filenames for raw sensor CSVs must embed the sensor number and position in the form `_SensorN_` and `_xXpYm_` (decimal dot replaced by `p`), e.g. `..._Sensor3_x4p6m_...csv`.

---

## Output

All outputs are written to `output_dir`.

### CSV

`ZS_Reflection_Results_v5.csv` — one row per condition.

| Column | Unit | Description |
|---|---|---|
| `SetAmplitude_V` | V | Commanded wavemaker amplitude |
| `SetFrequency_Hz` | Hz | Commanded frequency |
| `SetSteepness_ka` | — | Commanded wave steepness |
| `MeasFrequency_Hz` | Hz | Measured frequency (DFT bin) |
| `Unc_Frequency_Hz` | Hz | 1-σ frequency uncertainty |
| `Wavenumber_radm` | rad/m | Wavenumber from dispersion relation |
| `Unc_Wavenumber_radm` | rad/m | 1-σ wavenumber uncertainty |
| `Wavelength_m` | m | Wavelength λ = 2π/k |
| `MeasSteepness_ak` | — | Measured steepness k\|a_L\| (reference) |
| `Unc_MeasSteepness_ak` | — | 1-σ uncertainty on measured steepness |
| `IncidentAmp_m` | m | Incident amplitude \|a_L\| |
| `Unc_IncidentAmp_m` | m | 1-σ uncertainty on \|a_L\| |
| `ReflectedAmp_m` | m | Reflected amplitude \|a_R\| |
| `Unc_ReflectedAmp_m` | m | 1-σ uncertainty on \|a_R\| |
| `IncidentPhase_rad` | rad | Phase of a_L |
| `ReflectedPhase_rad` | rad | Phase of a_R |
| `ReflectionCoeff` | — | Reflection coefficient R |
| `Unc_ReflectionCoeff` | — | 1-σ uncertainty on R |
| `NoiseFloor_median_m` | m | Median total amplitude noise floor across gauges |
| `Denominator_D` | — | ZS conditioning denominator |
| `N_gauges` | — | Number of valid gauges used in solve |

### Figures

| Figure name | Content |
|---|---|
| `ZS_R_vs_SetAmplitude` | R vs commanded amplitude, one series per frequency |
| `ZS_aL_aR_vs_SetAmplitude` | \|a_L\| and \|a_R\| vs commanded amplitude, subplots per frequency |
| `ZS_Denominator_D` | ZS conditioning diagnostic D vs measured frequency |
| `ZS_SpatialProfiles_fXXXHz` | Spatial amplitude envelope + sensor data, one figure per frequency |
| `ZS_PhasorDiagram` | Complex phasor plot of a_L and a_R for the lowest frequency |
| `ZS_R_vs_Frequency_fixedSteepness` | R vs commanded frequency, coloured by (ka)_set |
| `ZS_R_vs_Steepness_fixedFreq` | R vs commanded steepness, coloured by frequency |

Each figure is saved as both `.png`  and `.pdf`.

---

## Configuration

All user-editable parameters are in **Section 1** of the script.

| Parameter | Default | Unit | Description |
|---|---|---|---|
| `h_water` | 0.3 | m | Still-water depth H |
| `g` | 9.81 | m/s² | Gravitational acceleration |
| `t_start_ss` | 40 | s | Start of steady-state analysis window |
| `t_end_ss` | 100 | s | End of steady-state analysis window |
| `use_hann_window` | `true` | — | Apply Hann window before DFT |
| `acq_mode` | `'HIGH'` | — | Sensor gain mode (selects calibration rows) |
| `amp_tol_group` | 0.05 | V | Amplitude grouping tolerance |
| `freq_tol_group` | 0.05 | Hz | Frequency grouping tolerance |
| `ka_tol_group` | 0.005 | — | Steepness grouping tolerance |
| `n_sb_guard` | 5 | bins | Guard band around signal peak for noise estimate |
| `f_max_sb_factor` | 3.0 | — | Upper sideband limit as multiple of f_set |
| `n_sb_min` | 10 | bins | Minimum sideband bins; fewer → σ_A_noise = 0 |
| `dx_sensor` | 0.05 | m | 1-σ sensor position uncertainty |
| `dx_pert` | 0.001 | m | Finite-difference step for position sensitivity |
| `NR_maxiter` | 50 | — | Max Newton–Raphson iterations |
| `NR_tol` | 1×10⁻¹⁰ | rad/m | Newton–Raphson convergence tolerance |
| `debug_sensor_plots` | `false` | — | Show per-sensor time series and spectrum |
| `skip_167freq` | `false` | — | Exclude near-singular 1.667 Hz from plots |
| `save_fig` | `true` | — | Export figures |
| `save_results` | `true` | — | Export results CSV |

---

## Known Limitations

- **1.667 Hz singularity**: at this frequency the tank length (14 m) equals exactly 50 × λ/2 = 14.000 m, driving D → 0.  Use `skip_167freq = true` to exclude it from all plots, or interpret results with extreme caution.
- **Conservative amplitude uncertainty**: the worst-case gauge σ_A is used to bound the WLS propagation.  A proper covariance treatment (with individual per-gauge weights) would give tighter bounds.
- **Plane-wave assumption**: the decomposition assumes purely 1D wave propagation and unique reflection .  


---

## Reference

Zelt, J.A. & Skjelbreia, J.E. (1992). *Estimating incident and reflected wave fields using an arbitrary number of wave gauges.* Proc. 23rd Int. Conf. Coastal Engineering, ASCE, 777–789.



---

*Author: Matilde  — June 2026*
