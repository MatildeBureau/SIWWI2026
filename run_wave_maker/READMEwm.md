# Running SIWWI's wave maker through Data Translation + MATLAB

This repository contains matlab scripts for tuning of wave parameters, generation of wave signal inputs, hardware verification, and synchronised data acquisition using Data Translation (DT) hardware.

---

## Contents

- [System Requirements](#system-requirements)
- [Workflow Overview](#workflow-overview)
- [Script Documentation](#script-documentation)
  - [Wave_param_tuning.m](#1-wave_param_tuningm)
  - [Generate_Monochromatic.m](#2-generate_monochromaticm)
  - [Generate_PM.m](#3-generate_pmm)
  - [RunWavemaker_test.m](#4-runwavemaker_testm)
  - [RunWavemaker_CollectData_v3.m](#5-runwavemaker_collectdata_v3m)
- [Data Files](#data-files)
  - [Waves_param_HIGH_130526.csv](#waves_param_high_130526csv)
- [File Naming Conventions](#file-naming-conventions)
- [Calibration & Metadata](#calibration--metadata)

---

## System Requirements

- **Software**: MATLAB (tested on R2023b — later versions can sometimes struggle with DT communication).
- **Toolboxes**: Data Acquisition Toolbox.
- **Hardware**: Data Translation DAQ (e.g., DT9836).
- **Drivers**: Data Translation OmniCD drivers.

---

## Workflow Overview

To run a wave experiment, follow these steps in order:

1. **Tune** — Use `Wave_param_tuning.m` to determine the required input voltage and frequency to match target wave parameters (steepness, amplitude, or frequency).
2. **Generate** — Use `Generate_Monochromatic.m` (regular waves) or `Generate_PM.m` (irregular waves) to create the `.dat` input file using the voltage found in step 1.
3. **Check** *(optional)* — Run `RunWavemaker_test.m` to confirm the DAQ is transmitting the signal correctly before starting a full acquisition.
4. **Acquire** — Run `RunWavemaker_CollectData_v3.m` to drive the wavemaker and simultaneously record data from all sensors.

---

## Script Documentation

### 1. `Wave_param_tuning.m`

**Purpose:**
Computes the complete set of physical wave characteristics for all combinations of a user-defined frequency and amplitude grid, and determines the required wavemaker set-voltage ($V_{set}$) for each combination. All inputs are entered interactively at runtime via GUI dialogs — no hardcoded parameters need to be changed between sessions.

**Method:**

- **Linear dispersion relation**: Solves $\omega^2 = g k \tanh(kh)$ iteratively using Newton-Raphson, starting from the deep-water approximation $k_0 = \omega^2/g$. Note that this is the open-water dispersion relation, measured wavelengths value will be different in ice. This is just to tune T/f/ak as inputs.
- **Voltage mapping**: Inverts the linear calibration fit at the chosen reference sensor location:

$$a_{\text{meas}} \, [\text{m}] = \text{Slope} \, [\text{m/V}] \times V_{\text{set}} \, [\text{V}] + \text{Intercept} \, [\text{m}]$$

$$\Rightarrow \quad V_{\text{set}} \, [\text{V}] = \frac{a_{\text{target}} \, [\text{m}] - \text{Intercept}}{\text{Slope}}$$

- The reference location defaults to $x = 1$ m (sensor closest to the wavemaker) but is tunable in the script.

**Interactive inputs (GUI dialogs at runtime):**

| Prompt | Options | Default |
|--------|---------|---------|
| Calibration CSV | file browser | — |
| Water depth $h$ [m] | free text | `0.5` |
| Wavemaker mode | `LOW (50 Hz)` / `HIGH (100 Hz)` | `HIGH` |
| Frequency axis type | `Periods T [s]` / `Frequencies f [Hz]` | `Periods` |
| Frequency values | space-separated list | `1 1.5 2` |
| Amplitude axis type | `ka [-]` / `a [m]` / `V [V]` | `ka` |
| Amplitude values | space-separated list | `0.03 0.05 0.07` |
| Save results as CSV? | `Yes` / `No` | `No` |

All combinations of the frequency and amplitude vectors are computed: $N_f \times N_a$ rows in the output table.

**Output table columns:**

| Column | Symbol | Unit | Description |
|--------|--------|------|-------------|
| `T_s` | $T$ | s | Wave period |
| `f_Hz` | $f$ | Hz | Wave frequency |
| `omega_rad_s` | $\omega$ | rad/s | Angular frequency |
| `k_rad_m` | $k$ | rad/m | Wavenumber (from dispersion relation) |
| `lambda_m` | $\lambda$ | m | Wavelength |
| `kh` | $kh$ | — | Relative depth parameter |
| `ka` | $ka$ | — | Wave steepness |
| `a_m` | $a$ | m | Wave amplitude (mean-to-crest) |
| `H_m` | $H = 2a$ | m | Wave height (peak-to-trough) |
| `V_set_V` | $V_{set}$ | V | Required wavemaker input voltage |
| `Flags` | — | — | Warning flags (empty = OK) |

**Diagnostic flags:**

| Flag | Meaning |
|------|---------|
| `BELOW_RESOLUTION` | $a < 1$ mm — amplitude below sensor accuracy threshold |
| `NEGATIVE_VOLTAGE` | Calibration inversion gives $V < 0$ — check calibration or target $ka$ |
| `NEGATIVE_AMP` | Voltage input converts to $a \leq 0$ m — below calibration range |
| `V>10V` | Required voltage exceeds 10 V — verify wavemaker operating range |

**Required input file:**
- `Calibration_Fits_Per_Location.csv` — output of the main post-processing script. Must contain columns: `Sensor_Location_m`, `Sensor_Number`, `Mode`, `Slope_m_per_V`, `Intercept_m`, `R2`, `RMSE_m`.

**Dependencies:** No MATLAB toolboxes required.

---

### 2. `Generate_Monochromatic.m`

**Purpose:**
Generates a monochromatic (single-frequency) sine wave signal and saves it as a `.dat` input file for the wavemaker hardware controller.

**Tunable parameters** (hardcoded at the top of the script):

| Parameter | Variable | Unit | Description |
|-----------|----------|------|-------------|
| Sampling frequency | `sf` | Hz | DAQ output sample rate (typically 1000 Hz) |
| Wave frequency | `ff` | Hz | Target wave frequency |
| Amplitude | `aa` | V | Signal amplitude in volts |
| Duration | `duration` | s | Total signal length |
| Save path | `filepath` | — | Output folder (absolute path) |
| Date string | `date_str` | DDMMYY | Encoded in output filename |

**Signal generation:**
$$y(t) = a \cdot \sin(2\pi f \cdot t)$$

The script also includes a `cv` conversion factor (default = 1) for cases where the amplitude is specified in metres and needs converting to volts before saving.

**Output:**
- A two-column ASCII `.dat` file: `[time (s), voltage (V)]`.
- A figure showing the generated waveform for visual verification.
- Filename formatted as described in [File Naming Conventions](#file-naming-conventions).

**Dependencies:** No MATLAB toolboxes required.

---

### 3. `Generate_PM.m`

**Purpose:**
Generates an irregular wave signal based on the **Pierson-Moskowitz (PM) spectrum** and saves it as a `.dat` input file for the wavemaker. Intended for irregular sea-state experiments.

The implementation follows the spectral definition used by Passerotti et al. (2022).

**Tunable parameters** (hardcoded at the top of the script):

| Parameter | Variable | Unit | Description |
|-----------|----------|------|-------------|
| Sampling frequency | `sf` | Hz | DAQ output sample rate (typically 1000 Hz) |
| Peak frequency | `fp` | Hz | Frequency at spectral peak |
| Significant wave height | `Hs` | m | Target $H_s$ |
| Duration | `duration` | s | Total signal length (typically 1200 s for irregular waves) |
| Save path | `filepath` | — | Output folder (absolute path) |
| Date string | `date_str` | DDMMYY | Encoded in output filename |

**Spectral method:**

The one-sided PM spectrum shape is:

$$S(f) = \alpha_f \cdot \frac{g^2}{f^5} \exp\!\left[-1.25 \left(\frac{f}{f_p}\right)^{-4}\right]$$

where the scaling factor $\alpha_f$ is chosen so that $4\sqrt{m_0} = H_s$. The time series is then synthesised by summing sinusoids at each discrete frequency with random phases and Rayleigh-distributed amplitudes:

$$y(t) = \sum_i A_i \cos(2\pi f_i t + \phi_i), \quad A_i = \sigma_i \sqrt{-2 \ln U_i}, \quad \phi_i \sim \mathcal{U}[0, 2\pi)$$

**Console output (printed after generation):**

| Quantity | Symbol | Unit |
|----------|--------|------|
| Realised significant wave height | $H_{s,0}$ | m |
| Scaling factor | $\alpha_f$ | — |
| Wave steepness | $k_p H_{s,0}/2$ | — |
| Peak wavelength (deep water) | $\lambda_p$ | m |
| Peak period | $T_p$ | s |
| Spectral variance (zeroth moment) | $m_0$ | m² |

**Output:**
- A two-column ASCII `.dat` file: `[time (s), voltage (V)]`.
- A two-panel figure: PM spectrum and the generated time series.
- Filename formatted as: `pm_wave_DATE_HsHs_FREQhz_SFsf_DURs.dat`.

**Note on random realisations:** Because phases and amplitudes are randomly drawn, each call to `Generate_PM.m` produces a different time series with the same statistical properties. Re-seed `rand` or save the `.dat` file to ensure reproducibility.

**Dependencies:** No MATLAB toolboxes required.

---

### 4. `RunWavemaker_test.m`

**Purpose:**
A diagnostic tool to confirm that the DAQ hardware is correctly transmitting the analog voltage signal to the wavemaker before starting a full acquisition run.

**Functionality:**
- Prompts for a `.dat` waveform file path (entered as text).
- Sends the signal through **Analog Output Channel 0** of the DT9836.
- Simultaneously records the actual output through **Analog Input Channel 0** (loopback).
- Plots the "Sent" vs "Measured" signals on the same axes for visual comparison.

**Key checks performed:**
- Time vector uniformity: raises an error if any step deviates from the mean by more than $10^{-6}$ s (required for uniform DAQ rate).
- Sample rate: detected automatically from the file time step and printed to the console.

**DAQ configuration:**
- Input channel: `SingleEnded`, range ±10 V.
- Output channel: Analog Output 0.
- Rate: inherited from the `.dat` file time step.

**Usage notes:**
- This script uses a single input/output channel pair and does not load a sensor metadata file. It is intended purely for hardware verification, not data collection.
- If "Measured" differs from "Sent" in amplitude or phase, check DAQ driver version, cable connections, and MATLAB version compatibility.

**Dependencies:** Data Acquisition Toolbox, Data Translation OmniCD drivers.

---

### 5. `RunWavemaker_CollectData_v3.m`

**Purpose:**
The primary experimental acquisition script. Simultaneously drives the wavemaker and records time-series data from multiple acoustic sensors distributed along the tank. This is the script run during every actual experimental condition.

**Workflow:**

1. **Hardware reset** — calls `daqreset` to clear any previous DAQ sessions and avoid channel conflicts.
2. **User parameters** — hardcoded at the top of Section 2: sent voltage (`a_sent`), sent frequency (`f_sent`), acquisition mode (`mode`), date string (`date_str`), and save flag (`save_results`).
3. **Load wave file** — prompts for the `.dat` file path; detects sample rate from the time step and checks time vector uniformity.
4. **Hardware pre-check** — calls `daqlist('dt')` to verify that the DT9836 is connected and detected before any channel setup.
5. **Sensor metadata** — loads a CSV file (selected via file browser) specifying which sensors are active, their DAQ channel indices, and their positions in the tank.
6. **DAQ channel setup** — adds Analog Output 0 (wavemaker drive) and all input channels listed in the metadata, sorted by channel index. All input channels are configured as `SingleEnded`, ±10 V.
7. **Acquisition** — calls `readwrite(dq, y_out)` for zero-latency synchronised start between output and input. The full time series is returned as a MATLAB timetable.
8. **Plotting** — generates a multi-panel figure: wavemaker drive signal on top, followed by one panel per sensor.
9. **Saving** — writes one CSV per sensor with format `[time (s), voltage (V)]` if `save_results = true`.

**Hardcoded parameters to update before each run (Section 2):**

| Variable | Description |
|----------|-------------|
| `a_sent` | Sent voltage [V] — for filename encoding only |
| `f_sent` | Sent frequency [Hz] — for filename encoding only |
| `mode` | `'LOW'` or `'HIGH'` — DAQ acquisition mode |
| `date_str` | Session date string `'DDMMYY'` |
| `save_results` | `true` to save CSV files, `false` to skip |

**Required input files:**
- A `.dat` waveform file (output of `Generate_Monochromatic.m` or `Generate_PM.m`).
- A sensor metadata CSV (see [Calibration & Metadata](#calibration--metadata)).

**Output files** (one per sensor, written to `wm_test_results_DDMMYY/`):
```
raw_data_MODE_SensorN_xLOCm_DATE_aAMP_fFREQ.csv
```

**Dependencies:** Data Acquisition Toolbox, Data Translation OmniCD drivers.

---

## Data Files

### `Waves_param_HIGH_130526.csv`

An example output of `Wave_param_tuning.m`, saved for the HIGH-mode acquisition session on 13/05/26. Contains the full parameter grid used to plan that session.

**Columns:** `T_s`, `f_Hz`, `omega_rad_s`, `k_rad_m`, `lambda_m`, `kh`, `ka`, `a_m`, `H_m`, `V_set_V`, `Flags`

**Grid covered:**
- Frequencies: $f \in \{1.67, 1.25, 1.00, 0.83, 0.71\}$ Hz (periods $T \in \{0.6, 0.8, 1.0, 1.2, 1.4\}$ s)
- Steepnesses: $ka \in \{0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.10\}$
- Mode: HIGH (100 Hz)
- Water depth: $h = 0.3$ m

The `V>10V` flag appears for the $(f = 0.71 \text{ Hz},\ ka = 0.10)$ combination, indicating that the required voltage exceeds the wavemaker's 10 V operating limit for that condition.

---

## File Naming Conventions

Scripts automatically format filenames to encode experimental metadata. Decimal points are replaced with `p` to avoid filesystem issues.

**Wavemaker input signals:**

| Type | Format | Example |
|------|--------|---------|
| Monochromatic | `mono_wave_DATE_AMPv_FREQhz_SFsf_DURs.dat` | `mono_wave_060526_10v_1p6667hz_1000sf_180s.dat` |
| Pierson-Moskowitz | `pm_wave_DATE_HsHs_FREQhz_SFsf_DURs.dat` | `pm_wave_060526_0p06Hs_0p625hz_1000sf_1200s.dat` |

**Acquired sensor data:**

Format: `raw_data_MODE_SensorN_xLOCm_DATE_aAMP_fFREQ.csv`

Example: `raw_data_HIGH_Sensor3_x4p6m_200526_a10p86_f0p71.csv`

**Wave parameter tables:**

Format: `Waves_param_MODE_DATE.csv`

Example: `Waves_param_HIGH_130526.csv`

---

## Calibration & Metadata

### Sensor Metadata CSV

Required by `RunWavemaker_CollectData_v3.m`. Selected via file browser at runtime.

**Required columns:**

| Column | Type | Description |
|--------|------|-------------|
| `Sensor` | integer | Unique sensor ID number |
| `Channel` | integer | Physical DAQ channel index on the DT9836 |
| `x_m` | float | Longitudinal position in the tank [m], with $x = 0$ at the wavemaker |

Channels are sorted numerically by the script before setup, so row order in the CSV does not matter.

### Wavemaker Calibration CSV (`Calibration_Fits_Per_Location.csv`)

Required by `Wave_param_tuning.m`. Selected via file browser at runtime.

> **Important**: This file maps **wavemaker input voltage [V] to measured wave amplitude [m]** at each sensor location. It is the output of the post-processing script (`MAIN_wm_postprocess_all.m`) and is **not** the same as the acoustic sensor voltage-to-displacement calibration.

**Required columns:**

| Column | Description |
|--------|-------------|
| `Sensor_Location_m` | Sensor $x$-position [m] |
| `Sensor_Number` | Sensor ID |
| `Mode` | `LOW` or `HIGH` |
| `Slope_m_per_V` | Linear fit slope [m/V] |
| `Intercept_m` | Linear fit intercept [m] |
| `R2` | Coefficient of determination of the fit |
| `RMSE_m` | Root-mean-square fit error [m] |

The calibration model assumed throughout is:
$$a_{\text{meas}} \, [\text{m}] = \text{Slope} \times V_{\text{set}} \, [\text{V}] + \text{Intercept}$$

---

**Author:** Matilde Bureau  
**Date:** April–May 2026
