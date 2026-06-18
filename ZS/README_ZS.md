# ZS Reflection Analysis 

Estimates incident and reflected wave amplitudes from acoustic surface-elevation records  using the weighted least-squares decomposition of Zelt & Skjelbreia (1992).


---

## What it does

Given a set of time-series files from up to six acoustic sensors distributed along the tank, the script:

1. **Loads** sensor positions, per-sensor calibration coefficients and their uncertainties, and benchmark metadata (set frequency, set voltage, set steepness `ka`) from CSV files.
2. **Groups** raw files into experimental conditions defined by unique `(A_set, f_set)` pairs, with matching tolerances to handle floating-point voltage drift across campaign dates.
3. **Extracts** the complex Fourier coefficient `A_{j,p}` at the target frequency from each sensor time series using a single-bin DFT with optional Hann windowing (replaces `butter`+`filtfilt`, which is numerically catastrophic at the very low normalised cut-off frequencies present here).
4. **Solves** the linear dispersion relation `ω² = gk tanh(kh)` by Newton–Raphson to obtain the wavenumber `k`.
5. **Computes** the Zelt & Skjelbreia goodness-based weights `W_p` and the singularity diagnostic `D`, and skips conditions where `D < 0.01` (near-singular geometry).
6. **Solves** the weighted least-squares system `(M^H W M) [a_L; a_R] = M^H W A_jp` for the complex incident amplitude `a_L` (right-travelling) and reflected amplitude `a_R` (left-travelling).
7. **Propagates uncertainties** from three independent sources through the full processing chain (see below).
8. **Produces seven figures** and saves results to CSV.

---

## Algorithm reference

> Zelt, J.A. & Skjelbreia, J.E. (1992). *Estimating incident and reflected wave fields using an arbitrary number of wave gauges.* Proc. 23rd ICCE, ASCE, pp. 777–789.

| Script operation | Paper equation |
|---|---|
| Complex Fourier coefficient extraction | Eq. 1 |
| Wave field model (incident + reflected) | Eq. 2 |
| Dispersion relation | Eq. 3 |
| Observation equations at each gauge | Eq. 5 |
| Weighted merit function | Eq. 7 |
| Normal equations (weighted least squares) | Eq. 9 |
| Solution for `a_L`, `a_R` | Eq. 11a–b |
| Inter-gauge phase difference `Δφ_{pq}` | Eq. 13 |
| Goodness function `G(Δφ)` | Eq. 21 |
| Per-gauge weight `W_p` | Eq. 22 |
| Singularity diagnostic `D` | Eq. 12c |

---

## Uncertainty budget

Three independent sources are propagated to a final 1σ uncertainty on `R = |a_R|/|a_L|`.

### (1) Frequency — DFT bin discretisation
The measured frequency `f_bin = k_bin × Fs / N` is the nearest DFT bin to `f_set`. The true tone frequency can sit anywhere within ±½ bin:

```
δf = Fs / (2 × N_ss)     [Hz]
```

Propagated to wavenumber by implicit differentiation of the dispersion relation:

```
δk = (4π ω / Fp_k) × δf     [rad/m]
```

where `Fp_k = g (tanh kh + kh sech² kh)` is the analytic derivative.

### (2) Amplitude — calibration + sideband noise
Two contributions combined in quadrature per gauge:

**Calibration** (parsed from `acoustic_sensors_calib.csv`, columns `Err_a` and `Err_b`):
```
σ_A_calib = sqrt( (Err_a × V_rms)² + Err_b² )     [m]
```

**Spectral noise floor** (estimated from DFT sideband bins, excluding the signal peak and harmonics):
```
σ_A_noise = rms( Y[k] for k in sideband )     [m]
```

Total per-gauge amplitude uncertainty:
```
σ_A = sqrt( σ_A_noise² + σ_A_calib² )     [m]
```

The worst-case (maximum) `σ_A` across all gauges in a condition is used for the WLS propagation.

### (3) Sensor position — finite-difference WLS sensitivity
A hardcoded position uncertainty `dx = 0.05 m` (1σ, ruler placement error) is assigned to every sensor. The sensitivity of the WLS solution to a shift in gauge `p` is estimated by centred finite differences:

```
da_L/dx_p ≈ [a_L(x_p + δ) − a_L(x_p − δ)] / (2δ)
```

with `δ = 0.001 m`. The weights `W_p` are recomputed at each perturbed position. Contributions from all gauges are summed in quadrature:

```
δa_L_pos = sqrt( Σ_p |da_L/dx_p|² × dx² )     [m]
```

### Combined and output uncertainties
```
δa_L = sqrt( δa_L_ampl² + δa_L_pos² )
δa_R = sqrt( δa_R_ampl² + δa_R_pos² )

δR   = R × sqrt( (δa_R/|a_R|)² + (δa_L/|a_L|)² )

δ(ak) = sqrt( (|a_L| × δk)² + (k × δa_L)² )
```

---

## Input files

| File | Description |
|---|---|
| `Metadata_sensors_200526.csv` | Sensor numbers and tank positions `x` [m] |
| `acoustic_sensors_calib.csv` | Calibration coefficients `Slope_a`, `Intercept_b` and their 1σ uncertainties `Err_a`, `Err_b`, per sensor and mode |
| `Metadata_benchmark_200526.csv` | One row per raw file: `Set_f_Hz`, `Set_volt_V`, `ka` (set steepness), `Acoustic_sensor_filename`, `Mode` |
| `raw_data_HIGH_Sensor*_*.csv` | Two-column time-series files: `t [s]`, `V [V]` |

The benchmark metadata CSV is the authoritative source of `(f_set, A_set, ka_set)` — no filename parsing is used for physical parameters.

---

## Output files

| File | Description |
|---|---|
| `ZS_Reflection_Results_v5.csv` | One row per condition with all results and uncertainties |
| `ZS_R_vs_SetAmplitude.png/.pdf` | R vs A_set, coloured by frequency |
| `ZS_aL_aR_vs_SetAmplitude.png/.pdf` | |a_L| and |a_R| vs A_set, one panel per frequency |
| `ZS_Denominator_D.png/.pdf` | Conditioning diagnostic D vs measured frequency |
| `ZS_SpatialProfiles.png/.pdf` | Model envelope vs measured sensor amplitudes along tank |
| `ZS_PhasorDiagram.png/.pdf` | Complex phasor diagram at lowest frequency |
| `ZS_R_vs_Frequency_fixedSteepness.png/.pdf` | R vs frequency at fixed set steepness |
| `ZS_R_vs_Steepness_fixedFreq.png/.pdf` | R vs set steepness at fixed frequency |

All figures are saved as both PNG  and  PDF. The flag `skip_167freq = true` in Section 7 re-runs plotting with `f = 1.667 Hz` excluded (which otherwise dominates the y-axis due to near-singular uncertainty bars) and appends `_fskipped` to filenames.

---

## Key parameters

| Parameter | Default | Effect |
|---|---|---|
| `t_start_ss` | 40 s | Discard transient build-up |
| `t_end_ss` | 100 s | End of steady-state window |
| `use_hann_window` | `true` | Reduce spectral leakage in single-bin DFT |
| `amp_tol_group` | 0.05 V | Voltage matching tolerance for condition grouping |
| `freq_tol_group` | 0.05 Hz | Frequency matching tolerance |
| `ka_tol_group` | 0.005 | Steepness grouping tolerance for plots 6 & 7 |
| `n_sb_guard` | 5 bins | Sideband guard width around signal peak |
| `f_max_sb_factor` | 3.0 | Sideband upper limit as multiple of `f_set` (excludes harmonics) |
| `dx_sensor` | 0.05 m | Sensor position 1σ uncertainty |
| `dx_pert` | 0.001 m | Finite-difference step for position sensitivity |
| `skip_167freq` | `false` | Set `true` to exclude f = 1.667 Hz from plots |

--------------

Matilde, June 2026
