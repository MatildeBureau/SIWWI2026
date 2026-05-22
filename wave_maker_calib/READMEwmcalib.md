# Wave maker calibration — 28/04/26

This folder contains example raw data, metadata, processed results, and diagnostic figures from  **open-water wavemaker calibration tests** run on 28/04/26 (no ice in the tank).  The purpose of those tests was to establish the linear relationship between the wavemaker input voltage $V_{set}$ [V] and the resulting wave amplitude $\bar{\eta}$ [m] at each sensor location. Desired output was the **wavemaker calibration** which I then used for `Wave_param_tuning.m` to plan all subsequent experimental runs.

Those test were also used to compare side-camera amplitude measurements against acoustic sensors outputs. 
Water height was h = 30cm in the tank, and all sensors were placed 30cm above water.

---

## Contents

- [Session Overview](#session-overview)
- [Experimental Setup](#experimental-setup)
- [File Index](#file-index)
  - [Metadata](#metadata)
  - [Raw Acoustic Sensor Data](#raw-acoustic-sensor-data)
  - [Wave Parameter Planning Table](#wave-parameter-planning-table)
  - [Post-Processing Outputs](#post-processing-outputs)
  - [Camera Time Series](#camera-time-series)
  - [Diagnostic Figures](#diagnostic-figures)
- [Processing Pipeline](#processing-pipeline)
- [Key Results](#key-results)

---

## Session Overview

| Parameter | Value |
|-----------|-------|
| Date | 28 April 2026 |
| Tank configuration | Open water (no ice) |
| Mode | HIGH (100 Hz DAQ acquisition rate) |
| Wave type | Monochromatic |
| Fixed frequency for amplitude sweep | $f = 1.0$ Hz |
| Amplitude sweep | $A_{set} \in \{1, 2, 3, 3.5, 4, 5, 5.5, 6, 7, 8\}$ V |
| Frequency sweep (fixed $A_{set} = 4$ V) | $f \in \{0.75, 1.0, 1.25, 1.5\}$ Hz |
| Number of acoustic sensors | 6 |
| Number of camera locations | 2 ($x = 3.0$ m and $x = 9.4$ m) |
| Signal duration per run | 180 s (acoustic) |
| Steady-state analysis window | $t \in [40, 180]$ s |

---

## Experimental Setup

**Sensor layout** (from `Metadata_sensorsplacement_wmtests_280426.csv`):

| Sensor ID | DAQ Channel | $x$ [m] |
|-----------|-------------|---------|
| 1 | 3 | 1.0 |
| 2 | 2 | 3.0 |
| 3 | 5 | 4.6 |
| 4 | 6 | 6.2 |
| 5 | 1 | 7.8 |
| 6 | 4 | 9.4 |

$x = 0$ is defined at the wavemaker paddle face. Channels are assigned to the DT9836 DAQ.

**Camera setup**: A Nikon DSLR (lens: 60mm) was used as a side camera at two locations ($x = 3.0$ m and $x = 9.4$ m) to record wave surface displacement time series for cross-validation against the acoustic sensors. Frame rate: ~59.94 fps.

---

## File Index

### Metadata

#### `Metadata_sensorsplacement_wmtests_280426.csv`
Sensor placement table required by `RunWavemaker_CollectData_v3.m` at runtime. Maps each sensor ID to its DAQ channel and physical position in the tank.

**Columns:** `Sensor`, `Channel`, `x_m`

#### `Metadata_wm_calib_280426.csv`
Acoustic-to-video pairing table required by the post-processing pipeline (`MAIN_wm_postprocess_all_v8.m`). Each row links one acoustic sensor CSV to its corresponding side-camera video file, with video trim times to isolate the steady-state window.

**Columns:**

| Column | Description |
|--------|-------------|
| `Acoustic_sensor_filename` | Acoustic CSV filename (no path) |
| `Video_filename` | Raw video filename (`.MOV`) |
| `Set_volt_V` | Wavemaker set voltage [V] |
| `Set_f_Hz` | Set frequency [Hz] |
| `Mode` | Acquisition mode (`HIGH`) |
| `Camera_loc_m` | Camera position in tank [m] |
| `vid_t_start_s` | Video trim start [s] |
| `vid_t_end_s` | Video trim end [s] |
| `wave_time_series_sidecam` | Output camera TS CSV filename |

Note: `wave_time_series_sidecam` column was dropped for tests performed after this date, and sensor/cam matching was done using `CamTimeSeries_INDEX.csv` then.

---

### Raw Acoustic Sensor Data

Files named: `raw_data_HIGH_SensorN_xLOCm_280426_aAMP_fFREQ.csv`

Example: `raw_data_HIGH_Sensor3_x4p6m_280426_a7_f1.csv`

**Format:** Two-column headerless ASCII CSV — `[time (s), voltage (V)]`. Written directly by `RunWavemaker_CollectData_v3.m` at 100 Hz (HIGH mode). One file per sensor per run.

| Field | Encoding |
|-------|----------|
| Mode | `HIGH` — 100 Hz acquisition |
| Sensor N | Sensor ID (1–6) |
| xLOC | Position in tank with `p` for decimal point |
| aAMP | Set voltage in V |
| fFREQ | Set frequency in Hz |

**Example files included** (all for the $A_{set} = 7$ V, $f = 1$ Hz condition):
- `raw_data_HIGH_Sensor1_x1m_280426_a7_f1.csv` — Sensor 1, $x = 1.0$ m
- `raw_data_HIGH_Sensor2_x3m_280426_a7_f1.csv` — Sensor 2, $x = 3.0$ m
- `raw_data_HIGH_Sensor3_x4p6m_280426_a7_f1.csv` — Sensor 3, $x = 4.6$ m
- `raw_data_HIGH_Sensor4_x6p2m_280426_a7_f1.csv` — Sensor 4, $x = 6.2$ m
- `raw_data_HIGH_Sensor5_x7p8m_280426_a7_f1.csv` — Sensor 5, $x = 7.8$ m
- `raw_data_HIGH_Sensor6_x9p4m_280426_a7_f1.csv` — Sensor 6, $x = 9.4$ m

The raw voltage is converted to metres [m] by the post-processing script using the acoustic sensor calibration.

---

### Wave Parameter Planning Table

#### `Waves_param_HIGH_280426.csv`

Output of `Wave_param_tuning.m`, saved before the session to plan the voltage and frequency combinations to run. Contains the full grid of wave parameters for the HIGH mode calibration sweep.

**Columns:** `T_s`, `f_Hz`, `omega_rad_s`, `k_rad_m`, `lambda_m`, `kh`, `ka`, `a_m`, `H_m`, `V_set_V`, `Flags`

Used to select the $A_{set}$ values that span the full measurable range of the wavemaker (1–8 V) while staying within the sensor resolution limit ($a > 1$ mm) and the 10 V hardware ceiling.

---

### Post-Processing Outputs

#### `Results_postprocess_all.csv`

Main results table produced by `MAIN_wm_postprocess_all_v8.m`. One row per (sensor, run) combination for acoustic sensors, plus one row per (camera location, run) combination for camera measurements. 

**Columns:**

| Column | Unit | Description |
|--------|------|-------------|
| `Measurement` | — | `Acoustic_Sensor` or `Side_Camera` |
| `Filename` | — | Source CSV or camera TS filename |
| `Mode` | — | `HIGH` |
| `Date_DDMMYY` | — | Session date |
| `SensorID` | — | Sensor number (acoustic only) |
| `Channel` | — | DAQ channel (acoustic only) |
| `SensorLocation_m` | m | Sensor or camera $x$-position |
| `SetAmplitude_V` | V | Wavemaker set voltage |
| `SetFrequency_Hz` | Hz | Set frequency |
| `MeasuredFrequency_FFT_Hz` | Hz | Peak frequency from FFT |
| `MeasuredAmplitude_m` | m | Wave amplitude (Hilbert envelope) |
| `UncertaintyAmplitude_m` | m | Amplitude uncertainty |
| `UncertaintyFrequency_Hz` | Hz | Frequency uncertainty ($\Delta f = F_s / N$) |
| `Cam_Amplitude_PT_m` | m | Camera amplitude — peak-to-trough half-range |
| `Cam_Uncertainty_PT_m` | m | Camera PT uncertainty |
| `Cam_Amplitude_Envelope_m` | m | Camera amplitude — Hilbert envelope |
| `Cam_Uncertainty_Envelope_m` | m | Camera envelope uncertainty |
| `Final_amp_error_m` | m | Mean \|cam − acoustic\| amplitude error across all conditions |
| `Final_freq_error_Hz` | Hz | Mean \|cam − acoustic\| frequency error |


#### `Calibration_Fits_Per_Location.csv`

Linear fit of measured wave amplitude vs. set voltage at each sensor location, derived from the amplitude sweep at $f = 1$ Hz. This is the **key output of the calibration session** — it is the file loaded by `Wave_param_tuning.m` to convert target wave parameters into wavemaker voltages for future experiments.

**Columns:**

| Column | Unit | Description |
|--------|------|-------------|
| `Sensor_Location_m` | m | Sensor $x$-position |
| `Sensor_Number` | — | Sensor ID |
| `Slope_m_per_V` | m/V | Calibration fit slope |
| `Slope_SE_m_per_V` | m/V | Standard error on slope |
| `Intercept_m` | m | Fit intercept |
| `Intercept_SE_m` | m | Standard error on intercept |
| `R2` | — | Coefficient of determination |
| `RMSE_m` | m | Root-mean-square fit residual |
| `Mode` | — | `HIGH` |
| `N_points_used` | — | Number of voltage steps in fit |

Summary of fits (all $R^2 > 0.993$, 10 amplitude points per location):

| $x$ [m] | Sensor | Slope [m/V] | Intercept [m] | $R^2$ |
|---------|--------|-------------|---------------|-------|
| 1.0 | 1 | 0.003026 | 0.001419 | 0.9976 |
| 3.0 | 2 | 0.001566 | −0.000235 | 0.9997 |
| 4.6 | 3 | 0.001988 | −0.000931 | 0.9934 |
| 6.2 | 4 | 0.003043 | 0.001227 | 0.9984 |
| 7.8 | 5 | 0.001645 | −0.000167 | 0.9997 |
| 9.4 | 6 | 0.002891 | 0.001742 | 0.9978 |

> **Note on spatial variation**: The slope (wave amplitude per volt) varies significantly with $x$ — sensors at $x = 1.0$ m, $x = 6.2$ m and $x = 9.4$ m measure roughly twice the amplitude of sensors at $x = 3.0$ m, $x = 4.6$ m, and $x = 7.8$ m for the same input voltage. This might reflect a standing wave pattern that develops in the finite-length tank due to partial reflection from the beach end. The calibration fit at the reference location ($x = 1$ m by default in `Wave_param_tuning.m`) is used to compute $V_{set}$; all other locations are informational. See the `Amp_Calib_envelope.png` figure for the full picture.

---

### Camera Time Series

#### `CamTimeSeries_INDEX.csv`

Index table linking each camera video to its processed surface displacement CSV, its paired acoustic file, and its acquisition parameters. Generated by `tank_process_sidecam_v7.m`.

**Columns:** `VideoFile`, `AcousticFile`, `SetAmplitude_V`, `SetFrequency_Hz`, `CameraLocation_m`, `FrameRate_fps`, `CamTS_CSV_filename`

28 entries: 10 amplitude steps × 2 camera locations ($x = 3.0$ m and $x = 9.4$ m) + 6 frequency sweep steps × 2 locations. Frame rate: 59.94 fps for all videos.

#### `CamTS__DSC7753_A7.00V_f1.000Hz_x9.40m.csv`

Example camera surface displacement time series for the $A_{set} = 7$ V, $f = 1$ Hz, $x = 9.4$ m condition. Extracted from video `_DSC7753.MOV` by `tank_process_sidecam_v7.m`.

**Columns:**

| Column | Unit | Description |
|--------|------|-------------|
| `t_s` | s | Time from video start |
| `eta_m` | m | Zero-mean surface displacement (air-contact surface) |

Time step: $1/59.94 \approx 0.01668$ s. The analysis window used in post-processing is $t \in [80, 200]$ s (specified in `Metadata_wm_calib_280426.csv`).

---

## Diagnostic Figures

All figures are outputs of `MAIN_wm_postprocess_all.m` unless noted otherwise.

---

### Signal-Level Diagnostics (single run example)

#### `_raw_data_HIGH_Sensor3_x4p6m_280426_a7_f1_csv_.png` — Debug time series

Two-panel debug figure for Sensor 3 ($x = 4.6$ m), $A_{set} = 7$ V, $f = 1$ Hz.

- **Top panel**: Full raw and bandpass-filtered time series over 0–180 s. Green dashed lines mark the steady-state window ($t = 40$ s to $t = 180$ s).
- **Bottom panel**: Filtered signal within the steady-state window, with the Hilbert envelope (black) and the mean amplitude estimate (red dashed line). 

#### `FFT_Spectrum_DEBUG__raw_data_HIGH_Sensor3_x4p6m_280426_a7_f1_csv.png` — FFT spectrum

Amplitude spectrum of the steady-state window for the same file.

- Dominant peak at $f_{meas} = 1.0000$ Hz, coinciding with the set frequency.
- Grey band: ±10% FFT search window around $f_{set}$.
- Pink dashed lines: bandpass filter cutoffs (±80% of $f_{meas}$, i.e. approximately 0.8–1.8 Hz for this run).
- Red triangles mark detected harmonics: **2f = 6.7%**, 3f = 1.0%, 4f = 0.4% of the fundamental. The 2nd harmonic is non-negligible at this amplitude, consistent with weakly nonlinear wave generation at $A_{set} = 7$ V.

---

### Amplitude vs. Sensor Location

One figure per set voltage, showing measured amplitude $\bar{\eta}$ [m] at all 6 sensor positions for that voltage condition. All runs are at $f = 1$ Hz.

| Figure | $A_{set}$ [V] | Amplitude range |
|--------|--------------|-----------------|
| `Amp_vs_Loc_A1_00_envelope.png` | 1.00 | ~1.3–4.1 mm |
| `Amp_vs_Loc_A2_00_envelope.png` | 2.00 | ~2.8–7.5 mm |
| `Amp_vs_Loc_A3_00_envelope.png` | 3.00 | ~4.4–10.6 mm |
| `Amp_vs_Loc_A3_50_envelope.png` | 3.50 | ~5.2–12.2 mm |
| `Amp_vs_Loc_A4_00_envelope.png` | 4.00 | ~6.1–13.9 mm |
| `Amp_vs_Loc_A5_00_envelope.png` | 5.00 | ~7.6–16.9 mm |
| `Amp_vs_Loc_A5_50_envelope.png` | 5.50 | ~8.4–18.3 mm |
| `Amp_vs_Loc_A6_00_envelope.png` | 6.00 | ~9.2–19.7 mm |
| `Amp_vs_Loc_A7_00_envelope.png` | 7.00 | ~10.7–22.5 mm |
| `Amp_vs_Loc_A8_00_envelope.png` | 8.00 | ~12.1–25.1 mm |


---

### Amplitude Calibration

#### `Amp_Calib_envelope.png`

Calibration figure. Measured amplitude $\bar{\eta}$ [m] vs. set voltage $V_{set}$ [V] for all 6 sensor locations simultaneously, at $f = 1$ Hz.

- Each colour represents one sensor location ($x = 1.0, 3.0, 4.6, 6.2, 7.8, 9.4$ m).
- Linear fits are shown for each location (lines through the data points).
- The dashed horizontal line marks the sensor resolution limit at 1 mm.
- All sensors show excellent linearity ($R^2 > 0.993$) across the full 1–8 V range.
- The two distinct response clusters (higher slope at $x = 1, 6.2, 9.4$ m vs. lower slope at $x = 3, 4.6, 7.8$ m) again reflect the standing wave pattern described above.
- The fits from this figure are saved in `Calibration_Fits_Per_Location.csv`.

---

### Amplitude vs. Set Voltage (Acoustic + Camera)

#### `Amplitude_vs_SetVoltage.png`

Measured amplitude vs. $V_{set}$ at $f = 1$ Hz for all acoustic sensor locations, with camera measurements overlaid at $x = 3.0$ m and $x = 9.4$ m. Both amplitude methods (Hilbert envelope, shown) and peak-to-trough are computed; the envelope is plotted here.


---

### Frequency Check

#### `Freq_Check.png`

Measured frequency $f_{meas}$ vs. set frequency $f_{set}$ for all acoustic (blue) and camera (orange) measurements across all runs. All points fall exactly on the 1:1 dashed reference line, confirming that the wavemaker generates the correct frequency across the full tested range ($f \in \{0.75, 1.0, 1.25, 1.5\}$ Hz) with no measurable frequency error in either sensor type.

---

### Camera Time Series Diagnostics

#### `Raw_Wave____DSC7753_MOV.png` — Raw camera surface displacement

Raw camera surface displacement $\eta(t)$ extracted by `tank_process_sidecam_v7.m` from video `_DSC7753.MOV` ($A_{set} = 7$ V, $f = 1$ Hz, $x = 9.4$ m). The detected air-contact surface oscillates cleanly between approximately ±22 mm throughout the ~120 s recording.  This is the direct output of the video processing pipeline before any filtering is applied in post-processing.

#### `Cam_Wave_--_CamTS__DSC7753_A7_00V_f1_000Hz_x9_40m_csv___x_9_40m.png` — Processed camera wave

Post-processed camera time series for the same condition, output by `MAIN_wm_postprocess_all_v8.m`. Shows:
- **Grey**: raw $\eta(t)$ from the camera CSV (after MAD cleaning).
- **Green**: bandpass-filtered signal.
- **Red dashed**: Hilbert envelope smoothed over 4 wave periods.
- **Horizontal lines**: $A_{PT} = A_{Env} = 0.0228$ m ± 0.0001 m — peak-to-trough and envelope estimates agree to within 0.01 mm, confirming excellent signal quality for this condition.

The analysis window $t \in [80, 200]$ s is applied before this figure is generated (consistent with `Metadata_wm_calib_280426.csv`). 

---

## Processing Pipeline

The full pipeline to reproduce all results from the raw data is:

```

raw_data_HIGH_*.csv                          video files (_DSC77xx.MOV)
(from RunWavemaker_CollectData_v3.m)                  │
         │                                            ▼
         │                               tank_process_sidecam_v7.m
         │                               (using Metadata_wm_calib_280426.csv)
         │                                            │
         │                                            ▼
         │                               CamTS_*.csv + CamTimeSeries_INDEX.csv
         │                                            │
         │                                            |
         │                                            │                              
         └──────────────────────┐                     │                              
                                ▼                     ▼                              
                              MAIN_wm_postprocess_all_v8.m                           
                                (benchmark_mode = true,                              
                                 uses Metadata_sensorsplacement_wmtests_280426.csv)  
                                              │                                      
                                              ▼                                      
                              Results_postprocess_all.csv                            
                              Calibration_Fits_Per_Location.csv  
                                              │
                                              ▼
                              Wave_param_tuning.m  (next experimental session)


```

---

## Key Results

| Metric | Value |
|--------|-------|
| Calibration linearity ($R^2$, all sensors) | > 0.993 |
| Voltage range covered | 1–8 V |
| Amplitude range covered | ~1.3 mm to ~25 mm |
| Frequency accuracy (all sensors + camera) | < 0.001 Hz error |
| Mean camera–acoustic amplitude difference | ~5.1 mm (all conditions) |
| Camera frequency error vs. acoustic | < 0.001 Hz |
| Standing wave amplitude ratio (max/min location) | ~2× at all voltages |

The `Calibration_Fits_Per_Location.csv` produced in this session is the input used by `Wave_param_tuning.m` for subsequent wave/ice experiments. The reference location used for voltage inversion is $x = 1$ m (Sensor 1).

---

**Author:** Matilde Bureau  
**Date:** April 2026
