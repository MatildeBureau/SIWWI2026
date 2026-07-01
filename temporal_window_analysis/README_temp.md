# `window_sensitivity_analysis.m`

Sensitivity analysis of wave amplitude estimates (from acoustic sensors) to the choice of temporal analysis window.

The script automatically loops over all `(ka_set, T_set)` conditions found in the pairing metadata and tests influence of temporal windod location/length on
measured amplitudes. This test was run on the benchmark dataset (open-water -- 20/05).

---

## What it does

Two analysis modes are available (set by `user_test_mode`):

| Mode | `user_test_mode` | What is swept | What is fixed |
|---|---|---|---|
| **A — Window location** | `'location'` | Window start time `t_start` (`n_windows_location` linearly spaced values) | Window length (`win_fixed_length_s`) |
| **B — Window length** | `'length'` | Window length (`win_length_min_s` → `win_length_max_s`, step `win_length_step_s`) | Window start time (`tstart_fixed_s`) |

---

## Processing pipeline (per sensor, per file)

1. Parse the acoustic filename for mode, channel, date, set voltage, set frequency.
2. Snap the parsed frequency to the nearest standard test frequency.
3. Match the file to every `(ka_set, T_set, V_set)` condition in the pairing metadata within tolerance — a single file can match more than one condition.
4. Read the raw signal and look up sensor placement metadata.
5. Calibrate volts → metres; optionally despike (MAD-based).
6. Detect the measured frequency `f_meas` via FFT on a representative sub-window (used to centre the bandpass filter consistently across the whole window sweep).
7. **Window sweep:** for each `(t_start, window length)` pair —
   - extract and zero-mean the segment,
   - bandpass filter around `f_meas`,
   - compute the Hilbert envelope, smooth over `env_smooth_periods` wave periods,
   - record the mean envelope amplitude and its standard error.
8. Sensor 5 (≈ 7.80 m, near a reflection node) can optionally be excluded.

---

## Outputs

All outputs are written to `externalDrivePath`.

- **CSV** — `WindowSensitivity_<MODE>_<DATE>.csv`
  One row per (sensor, window case, condition), with columns: source file, sensor ID & location, `ka_set`, `T_set`, window index/start/length, amplitude, and amplitude uncertainty.

- **Plot 1** — `Plot1_byLength_ak<X>_<DATE>.png/.pdf` (Mode B)
  One figure per `ka_set`; one subplot per `T_set` (longest period left); amplitude vs. sensor position `x`, colour-coded by window length.

- **Plot 2** — `Plot2_byTstart_ak<X>_<DATE>.png/.pdf` (Mode A)
  Same layout, colour-coded by window start time `t_start`.

- **Console statistics table**: for every `(ka_set, T_set, sensor)` combination, the mean amplitude, standard deviation, and coefficient of variation (CV %) across the window sweep — a low CV indicates the amplitude estimate is robust to window choice.

---

## Required input files


| # | Prompt | Content |
|---|---|---|
| 1 | Sensor placement CSV | Acoustic sensor ID ↔ tank position `x` (m) lookup table |
| 2 | Acoustic sensor calibration CSV | Voltage → metres calibration coefficients per sensor/mode |
| 3 | Experiment pairing CSV | Maps each test run to its set conditions: `ka` (steepness), `Set_f_Hz`/`f_Hz` (frequency), `Set_volt_V`/`volt_V` (wavemaker voltage) |
| 4 | Acoustic data folder(s) | Raw acoustic sensor `.csv` recordings (one folder per session, e.g. `06/05`, `13/05`, `14/05`) |

> Column names in the pairing CSV are resolved flexibly (`ka`/`ka_set`/`steepness`, `Set_f_Hz`/`f_Hz`/`freq_Hz`, `Set_volt_V`/`volt_V`/`voltage_V`), so minor naming differences between metadata versions are tolerated.

---

## Required external helper functions

 (shared with `MAIN_wm_postprocess_all.m`):

```
wm_load_location_metadata   wm_load_calibration
wm_load_pair_metadata_v2    wm_select_files
wm_parse_filename           wm_read_signal
wm_lookup_metadata          wm_apply_calibration
wm_despike_v2                wm_fft_frequency
wm_filter_signal_v2         pick_col
```

---

## Key configuration (Section 1 of the script)

| Parameter | Meaning |
|---|---|
| `user_test_mode` | `'location'` or `'length'` — selects which sweep mode runs |
| `win_fixed_length_s`, `tstart_min_s`, `tstart_max_s`, `n_windows_location` | Mode A sweep settings |
| `tstart_fixed_s`, `win_length_min_s`, `win_length_max_s`, `win_length_step_s` | Mode B sweep settings |
| `freq_match_tol`, `volt_match_tol` | Tolerances for matching parsed frequency/voltage to pairing metadata |
| `despike_enable`, `despike_mode`, `despike_win_s`, `despike_thresh` | Optional MAD-based despiking |
| `filterEnable`, `filterMode`, `bp_frac`, `bp_order`, `freqTol` | Bandpass filtering around the measured frequency |
| `env_smooth_periods` | Hilbert envelope smoothing window, in wave periods |
| `skip_sensor5`, `sensor5_loc_m`, `sensor5_tol_m` | Optional exclusion of the reflection-node sensor |
| `date_str`, `externalDrivePath`, `save_csv`, `save_fig` | Output naming/location/format |


Matilde -- July 2026
