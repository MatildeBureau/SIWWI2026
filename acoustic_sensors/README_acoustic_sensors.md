# Acoustic sensors calibration

##  Folder contents and raw data
* Raw calibration files (`.csv`) include the sensor number (taped on probes) and its acquisition mode (LOW = 50Hz sampling rate, HIGH = 100Hz).
* Acquisition modes include "low" (50Hz sampling frequency) and "high" (100Hz). eg, `sensor2_low.csv` corresponds to sensor number 2 in low mode.
* The data columns within the raw files represent: tension (U), tension uncertainty (dU), distance from water surface to sensor (l), and distance uncertainty (dl). meters are used as distances units, and Volts for voltage.
* .pdf : calibration output plot.
* .csv : calibration table output results.

##  Experimental setup
Measurements were taken by recording the distance between the water surface and the upper part of the transparent piece holding the probe, as it was easier to measure.

To allow for potential distance offset correction, the distance (`L`) between the upper measuring point and the lower part of the probe was recorded for each unit (+/- 0.1cm possible reading error):
* Sensor 1 - L = 6.3cm
* Sensor 2 - L = 6.6cm
* Sensor 3 - L = 6.4cm
* Sensor 4 - L = 5.9cm
* Sensor 5 - L = 5.3cm
* Sensor 6 - L = 6.0cm


**Measuring range:** Data collection for a sensor was stopped when measurements appeared to exit the valid range. This was identified by observing highly fluctuating values on the multimeter, doubtful non-monotonic behavior, or a 0 signal.

---

##  Script documentation: `Acoustics-sensors-calib.m`

### Purpose
The script processes calibration data for 6 acoustic sensors across two modes (Low = 50 Hz, High = 100 Hz). It performs individual linear fits for each sensor, calculates statistics over the whole set of sensors as an ensemble for each mode, saves fitting parameters, and plots the results.

### Methods
1. **Monte Carlo Simulation:** The script propagates uncertainties from raw data to fitting parameters. It runs the linear fit `num_trials` times (default 5000) by perturbing the data with random Gaussian noise proportional to the measured errors. The final sensor slope/intercept is the mean of these trials, and the uncertainty is the standard deviation.
2. **Ensemble Statistics:** The script treats the collection of valid sensors as a statistical series to determine variability over the whole set. It computes an average slope and intercept for the valid ensemble. The total uncertainty for the ensemble is calculated as the maximum of either the average precision of individual sensors (propagated error) or the variation between sensors (standard deviation of the ensemble).

### Inputs
* The raw calibration data files found in the defined directory, named using the pattern `sensorX_MODE.csv` (e.g., `sensor1_high.csv`).
* The script reads axis labels and units from the first two header lines, and numeric data matrices from line 3 onwards.

### Outputs
* **Calibration Plot (`acoustic_sensors_calib.png` and `acoustic_sensors_calib.pdf`):** A visual plot combining the scatter data points, error bars, individual sensor coloring, and an ensemble line with a shaded variance ribbon.
* **Results Table (`acoustic_sensors_calib.csv`):** A saved CSV table of the calculated fitting parameters. In these outputs, voltages are in V, distances are in meters (converted from raw cm via `1e-2` scaling), slopes are in m/V, and intercepts are in m. 

### Dependencies
* Standard MATLAB base functions (e.g., `readmatrix`, `polyfit`, `randn`, `errorbar`, `fill`). No specific specialized toolboxes are explicitly referenced.

### User-Tunable Parameters
Variables at the top of the script can be modified by the user:
* `folder_path`: Directory path containing the raw `.csv` files.
* `save_fig`: Boolean flag (`true`/`false`) to toggle saving the generated plots.
* `save_results`: Boolean flag to toggle exporting the final parameters table.
* `results_filename`: String defining the output filename.
* `num_sensors`: The total number of sensors to loop through (set to 6).
* `modes` and `mode_markers`: Arrays defining the acquisition modes (`'low'`, `'high'`) and their corresponding scatter plot markers.
* `num_trials`: The number of iterations for the Monte Carlo error propagation loop (set to 5000).

---
**Author**: Matilde  Bureau
**Date**: March 2026  
