# Wave-Ice Post-Processing Scripts


> Side-camera surface extraction and acoustic + camera post-processing.

---

## Overview

Two main MATLAB scripts form the post-processing layer of the pipeline:

| Script | Purpose |
|--------|---------|
| `tank_process_sidecam_v8.m` | Frame-by-frame surface detection from side-view videos → `eta(t)` CSV files |
| `MAIN_wm_postprocess_all_v10.m` | Loads acoustic CSVs + camera CSVs, calibrates, filters, estimates amplitudes, fits attenuation, produces all plots |

They are designed to be run in sequence. `tank_process_sidecam_v8.m` outputs a folder of CSV files and an index that `MAIN_wm_postprocess_all_v10.m` reads directly.

---

## Dependencies

### MATLAB Toolboxes
- **Signal Processing Toolbox** — `butter`, `filtfilt`, `hilbert`, `findpeaks`, `imgaussfilt`
- **Image Processing Toolbox** — `rgb2gray`, `imshow`, `VideoReader`

### External helper functions (must be on MATLAB path)

`tank_process_sidecam_v8.m`:
```
wm_get_surface_v4           wm_cam_test_section_v4
wm_cam_preprocess           wm_cam_preprocess_defaults
wm_cam_define_roi           wm_cam_calibrate
wm_cam_despike              wm_load_location_metadata
wm_load_calibration         wm_build_pairmeta_from_table
wm_select_files             wm_read_signal
wm_parse_filename           wm_lookup_metadata
wm_find_video               loc_to_key
```

`MAIN_wm_postprocess_all_v11.m`:
```
wm_load_location_metadata   wm_load_calibration
wm_load_pair_metadata_v2    wm_select_files
wm_parse_filename           wm_read_signal
wm_lookup_metadata          wm_apply_calibration
wm_despike_v2               wm_cam_despike
wm_fft_frequency            wm_filter_signal_v2
wm_estimate_amplitude       wm_cam_amplitude
wm_build_refAmp_from_benchmark   wm_get_ref_amp_numeric
wm_validate_benchmark_pairing    wm_compute_attenuation_weighted
wm_plot_debug_v2            wm_plot_fft_debug
wm_style_for_mode           pick_col
```

---

## `tank_process_sidecam_v8.m`

### What it does

Reads side-view videos of the wave tank frame by frame and extracts the raw surface displacement time series `eta(t)` [m] for each video. The detected surface is always the air-contact interface (ice top under normal conditions, water surface if overwash occurs). No amplitude estimation is performed here.

### Inputs (interactive dialogs)
1. **Sensor placement CSV** — columns: `SensorID`, `Channel`, `x_m`, `Camera`
2. **Acoustic calibration CSV** — columns: `Source`, `Mode`, `Slope_a`, `Intercept_b`
3. **Experiment pairing CSV** — links each acoustic filename to its video file, trim times, and set conditions
4. **Acoustic data folder(s)**
5. (Optional) separate video folder

### Key parameters to set in Section 1

| Parameter | Default | Description |
|-----------|---------|-------------|
| `date_str` | `'280426'` | Output folder suffix (DDMMYY) |
| `vid_grad_smooth` | `3` | Gaussian σ [px] for profile smoothing |
| `grad_amp_min` | `1.5` | Minimum gradient amplitude to accept a peak [a.u.] |
| `peak_jump_tol_frac` | `0.1` | Max frame-to-frame displacement as fraction of ROI height |
| `vid_despike_enable` | `false` | Despike `eta(t)` after conversion |
| `calib_per_video` | dialog | `true` = new ROI + calibration each video; `false` = once per camera position |

Videos pre-processing is optional if you want to enhance image quality>
Per-camera preprocessing profiles (`pp_nikon`, `pp_gopro`) are auto-selected from filename keywords. The most important per-camera flag is `pp_gopro.use_strongest_peak = true` (GoPro geometry places reference edges above the water surface, so the strongest rather than uppermost gradient peak is the correct target).

### Detection pipeline (per frame)
1. Convert to greyscale; apply optional preprocessing (CLAHE, denoising, sharpening, gamma)
2. Average strip columns → vertical intensity profile `I(y)`
3. Gaussian smooth + compute discrete gradient `g(y) = |I'(y)|`
4. Find gradient peaks (`findpeaks`, sorted by descending amplitude)
5. `wm_get_surface_v4` selects the best peak, enforcing:
   - Amplitude window `[grad_amp_min_this, grad_amp_max]`
   - Displacement continuity: max jump scaled by wave steepness `ka` from pairing CSV
   - Peak selection mode: uppermost (Nikon) or strongest (GoPro)
6. Store pixel position and HWHM uncertainty [px]
7. After frame loop: rolling-median MAD filter (window ≈ 1 s, threshold = 4 × MAD) to remove residual false detections
8. Convert to metres: `eta_n = -(y_n_px - mean(y_px)) * mm_per_px / 1000`

### Outputs (`results_sidecam_<DATE>_MID/`)
- `CamTS_<VideoBase>_A<V>V_f<Hz>Hz_x<m>m.csv` — three columns: `t_s` [s], `eta_m` [m], `eta_unc_m` [m]
- `CamTimeSeries_INDEX.csv` — one row per exported CSV with full metadata
- All open figures as PNG (300 dpi) and vector PDF

The script includes **checkpoint/resume** logic: if interrupted (Ctrl+C or crash), a `.mat` checkpoint is saved automatically and the user is offered a resume option on the next run.

---

## `MAIN_wm_postprocess_all_v11.m`

### What it does

Loads acoustic sensor CSVs and camera time-series CSVs, runs a full signal-processing chain on both, optionally normalises against an open-water benchmark, plots results, and saves all results and figures.

### Two-pass workflow

**Pass 1 — benchmark (open water):** set `benchmark_mode = true`. Run on open-water data. Output CSV is the benchmark file.

**Pass 2 — ice run:** set `benchmark_mode = false`. Select the Pass-1 CSV when prompted. All amplitudes are normalised as `a/a0` before plotting.

### Inputs (interactive dialogs)
1. **Sensor placement CSV** → `locExpanded`
2. **Acoustic calibration CSV** → `calData`
3. **Experiment pairing CSV** → `pairMeta`
4. **Acoustic data folder(s)**
5. **Camera time-series folder** (`results_sidecam_*_MID/`, optional)
6. (Pass 2 only) **Benchmark Results CSV**

### Acoustic signal chain
| Step | Function | Key parameters |
|------|----------|---------------|
| Calibration | `wm_apply_calibration` | slope + intercept from `calData` |
| Steady-state window | built-in | `t_start_sensors = 40 s` |
| FFT frequency detection | `wm_fft_frequency` | `freqTol = 0.10` (±10 %) |
| Bandpass filter | `wm_filter_signal_v2` | `bp_frac = 1.2`, `bp_order = 4` |
| Hilbert envelope amplitude | `wm_estimate_amplitude` | `env_smooth_periods = 4` |

### Camera signal chain
Time window → NaN removal → optional despiking → FFT → bandpass filter (`vid_bp_frac = 0.9`) → Hilbert envelope amplitude (`A_cam_Env`) + peak-to-trough amplitude (`A_cam_PT`). Both are always stored; `cam_amp_method = 'envelope'` selects which is displayed in plots.


### Plots produced
| Plot | Content |
|------|---------|
| 2 | Amplitude η̄ vs position x, one figure per set voltage |
| 3 | Amplitude calibration: η̄ vs V_set at f = 1 Hz with OLS fit |
| 4 | Frequency check: f_meas vs f_set (should be 1:1) |
| 5 | η̄ vs V_set at fixed frequency, one series per position |
| 6 | η̄(x) per frequency, one subplot per voltage |


### Outputs (`results_postprocess_<DATE>/`)
- `Results_postprocess_<DATE>.csv` — one row per measurement, all computed quantities
- `Calibration_Fits_Per_Location.csv` — OLS slope, intercept, R², RMSE per location (if `skipCalib = false`)
- All figures as PNG + PDF

---

## Filename convention (acoustic CSVs)

```
raw_data_<MODE>_Sensor<N>_x<X>m_<DDMMYY>_a<V>_f<F>.csv
```
Example: `raw_data_HIGH_Sensor2_x3m_280426_a4_f1.csv`

- `MODE`: `HIGH` (Fs = 100 Hz) or `LOW` (Fs = 50 Hz)
- Decimal points encoded as `p`: `f1p25` = 1.25 Hz, `a4p6` = 4.6 V

---

Matilde, May 2026
