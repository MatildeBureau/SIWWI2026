# Running SIWWI's wave maker through Data Translation + Matlab

This repository contains MATLAB scripts developed for the SIWWI 2026 experiments. Purpose: tuning of wave parameters, generation of wave signals inputs, hardware verification, synchronized multi-channel data acquisition using Data Translation (DT) hardware.

##  Contents
* [System Requirements](#system-requirements)
* [Workflow Overview](#workflow-overview)
* [Script Documentation](#script-documentation)
    * [Wave_param_tuning.m](#1-wave_param_tuningm)
    * [Generate_Monochromatic.m](#2-generate_monochromaticm)
    * [RunWavemaker_test.m](#3-runwavemaker_testm)
    * [RunWavemaker_CollectData_v3.m](#4-runwavemaker_collectdata_v3m)
* [File Naming Conventions](#file-naming-conventions)
* [Calibration & Metadata](#calibration--metadata)

##  Requirements
* **Software**: MATLAB (Works with R2023b, later versions can sometime struggle with DT communication ).
* **Toolboxes**: Data Acquisition Toolbox.
* **Hardware**: Data Translation DAQ (e.g., DT9836).
* **Drivers**: Data Translation OmniCD drivers.

## Steps
To run a wave experiments, I followed those steps:
1. **Tune**: Use `Wave_param_tuning.m` to determine the required input voltage/frequency to match target wave parameters.
2. **Generate**: Use `Generate_Monochromatic.m` to create the `.dat` input file using the voltage found in step 1.
3. **Check**: - Option - Run `RunWavemaker_test.m` to ensure DAQ is transmitting the signal correctly.
4. **Acquire**: Run `RunWavemaker_CollectData_v3.m` to drive the wave maker and record data from the sensors.

##  Script Documentation

### 1. Wave_param_tuning.m
**Purpose**:  
Computes the complete set of physical wave characteristics and determines the required wavemaker set-voltage ($V_{set}$) based on target experimental parameters (Steepness $ka$ or Amplitude $a$).

**Methods**:  
* **Linear Dispersion Relation**: Solves $\omega^2 = g k \tanh(kh)$ iteratively using the Newton-Raphson method.
* **Disperion relation check**: I have included a section to check the validity of the pure gravity dispersion relation. Obviously, surface tension is neglligible for water at this scale, so I added this section out of curiosity to put numbers on it, but it is useless. 
* **Voltage mapping**: Inverts a linear calibration fit ($a = Slope \cdot V + Intercept$) to find the required voltage (from wave maker calibration).
* 

**Inputs**:  
* `Calibration_Fits_Per_Location.csv`: Contains slope/intercept for the wavemaker paddle (NOT acoustic sensors).
* **User inputs**: Water depth ($h$), Wavemaker mode (LOW/HIGH), Frequency axis ($T$ or $f$), and Amplitude axis ($ka$, $a$, or $V$).

**Outputs**:  
* A table containing: $T$, $f$, $\omega$, $k$, $\lambda$, $kh$, $ka$, $a$, $H$, and $V_{set}$.
* **Diagnostic flags**: `BELOW_RESOLUTION` (amplitude < 1mm), `NEGATIVE_VOLTAGE`, or `V > 10V`.

### 2. Generate_Monochromatic.m
**Purpose**:  
Generates a monochromatic  wave profile and saves it as a `.dat` input file for the hardware controller.

**Tunable Parameters**:  
* `sf`: Sampling frequency (Hz).
* `ff`: Wave frequency (Hz).
* `aa`: Amplitude (Volts).
* `duration`: Signal length (seconds).

**Outputs**:  
* A two-column `.dat` file containing `[time, voltage]`.
* A plot of the waveform for visual verification.
* Automated filename generation (see [Naming Conventions](#-file-naming-conventions)).

### 3. RunWavemaker_test.m
**Purpose**:  
A diagnostic tool to confirm that the analog voltage signal is correctly transmitted by the DAQ hardware.

**Functionality**:  
* Loads a `.dat` waveform, sends it through **Analog Output Channel 0**, and simultaneously records it via **Analog Input Channel 0**.
* Compares "Sent" vs. "Measured" signals to detect sampling rate mismatches, phase shifts, or hardware distortions.

**Key Checks**:  
* Verifies time-vector uniformity (error if deviation > $10^{-6}$s).
* Prints detected sampling rate based on the file's time-step.

### 4. RunWavemaker_CollectData_v3.m
**Purpose**:  
The primary experimental script. Simultaneously drives the wavemaker and records time-series data from multiple sensors distributed along the tank.

**Dependencies**:  
* A sensor metadata `.csv` (specifying Sensor #, DAQ Channel, and Position $x$ [m]).
* A pre-generated `.dat` wave file.

**Key Features**:  
* **Hardware Reset**: Executes `daqreset` to clear previous sessions.
* **Synchronized I/O**: Uses the `readwrite` function for zero-latency start between output and input.
* **Single-Ended Configuration**: Sets channels to `SingleEnded` with a $\pm 10$V range.

**Outputs**:  
* A MATLAB timetable of the full acquisition.
* A multi-panel figure showing the input wave and all sensor time-series.
* Individual `.csv` files for each sensor saved in a dedicated session folder.

##  File naming conventions
The scripts automatically format filenames to encode experimental metadata:
* **Input Waves**: `mono_wave_DATE_AMPlitudeV_FREQhz_SFsf_DURs.dat`
    * *Example*: `mono_wave_230426_12p5v_0p83hz_1000sf_180s.dat`
* **Output Data**: `raw_data_MODE_SensorID_xLOCATIONm_DATE_aAMPlitude_fFREQ.csv`
    * *Example*: `raw_data_HIGH_Sensor1_x1p0m_280426_a8_f1.csv`

##  Calibration & Metadata

### Sensor Metadata (.csv)
Required for `RunWavemaker_CollectData_v3.m`. Columns must include:
* **Sensor**: Unique ID number.
* **Channel**: The physical DAQ channel index.
* **x_m**: Longitudinal position in the tank (meters).

### Wavemaker Calibration (.csv)
Required for `Wave_param_tuning.m`.
> **Note**: This file maps Input Voltage (V) to Paddle Amplitude (m). It is NOT the conversion for the acoustic sensors.

**Required Columns**: `Sensor_Location_m`, `Mode`, `Slope_m_per_V`, `Intercept_m`, `R2`.

---
**Author**: Matilde  Bureau
**Date**: April 2026  
