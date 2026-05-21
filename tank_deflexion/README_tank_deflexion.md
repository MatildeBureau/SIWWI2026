# Tracking tank deformation

## Experiment
I have placed a camera outside of the tank, pointing at a ruler taped on a tank's wall (x=2.5m) and tested if I could monitor any movement due to temperature changes or water load changes.
My steps were:
* 1/ Empty tank, T changes -- from DSC__01 to DSC__0024. (camera files ID)
* 2/ Tank is progressively filled, T is (set to be) constant -- from DSC__0023 to DSC__0038.
* 3/ Water height is then kept costant and T changes (set to -12°C) -- from DSC__0036 to DSC__00.

### Camera spec
* **Software:** DigiCamControl.
* **Cam:** Nikon DSLR D810.
* **Lens:** Telephoto macro lens, Tamron SPDI 180mm AF, max aperture f/3.5, min aperture f/32. Macro 1:1.

### Temperature
* **07/04/26:** set to -12°C after 2 first pictures are taken (~9:10am).
* **Between 07/04 and 08/04:** T set at 15°C over night after last pictures have been taken (~18:00).
* **08/04:** T still set at 15°C when filling the tank.

### Metadata
* Experimental metadata is stored in `METADATA_tank_deflexion.csv` (date, time, lights on or off in the lab, picture filename, temperature, water height)

---

## Script Documentation: `tank_deformation_trackking_v8.m`
This script requires a folder with raw `.tif` images and a `.csv` metadata file to be run. It allows the user to select required images for tracking, set calibration, and select the tracking feature.

### Purpose
The script performs 2D image-based deformation tracking on a series of grayscale `.TIF` photographs.

### Methods
* **Normalised Cross-Correlation (NCC):** A small reference "template" patch is selected from the first image, and the script searches for the best matching location of that patch in every subsequent image.
* **Sub-pixel refinement:** The correlation peak can be refined beyond integer-pixel resolution using either a Parabolic fit or a Gaussian fit.
* **Lighting :** Displacements are tracked separately for images taken with laboratory lights ON vs OFF to account for baseline position shifts caused by image brightness differences.
* **Displacement :** The shift in position between frames is computed relative to the first image of each lighting group and is converted from pixels to millimetres using manual calibration.

### Inputs
* A folder of `.TIF` or `.tif` images named `DSC_XXXX.tif`.
* **Metadata File:** The `METADATA_tank_deflexion.csv` file. This file must have variable names on Line 1, physical units on Line 2, and one row per image starting from Line 3 (with fields including Name, Temperature, WaterHeight, LabLights, etc.).

### Outputs
Results folders are created with names including the date and the cross-correlation fitting method used (e.g., `results_DDMMYY_method`). Inside this timestamped subfolder, you will find:
* `session_metadata.txt`: Automatically generated metadata detailing parameters like tracking method, assumed resolution error, calibration pixel scale, image source, and images selected.
* `displacement_plot.png` / `.pdf`: Displacement vs. image number plots (dX and dY) separating Lights ON and Lights OFF conditions.
* `tracking_process.png` / `.pdf`: Visual representations of the tracking process.
* `Tank_deflexion_results.csv`: A table containing the computed X and Y displacements in mm appended with all experimental metadata per image.

### Dependencies
* **MATLAB Image Processing Toolbox:** Required for functions such as `normxcorr2`, `imshow`, `imcrop`, and `rgb2gray`. No additional toolboxes are strictly required.

### User-tunable parameters
1. **Save Flags:** Internal script flags (`save_fig` and `save_results`) can be set to true/false to control whether figures and CSV results are saved.
2. **File Selection:** Interactive GUI dialogs prompt the user to select the image folder and the `METADATA_tank_deflexion.csv` file.
3. **Image Filtering:** Users can choose to process all images automatically or enter a comma-separated list of specific image indices. The automatic mode deduplicates consecutive images where Temperature, WaterHeight, and LabLights remain identical.
4. **Calibration:** The user interactively zooms and clicks two points of a known distance on the first image, then inputs the real-world distance (in cm) to establish the pixel-to-cm scale factor.
5. **Template Selection:** The user draws an interactive rectangle around the physical feature or marker to track in the reference frame.
6. **Sub-pixel Enhancement Options:** The user selects from a dialog menu to use 'None (Integer Only)', 'Parabolic Fit', or 'Gaussian Fit' to process the correlation map peaks.

7. ---
**Author**: Matilde  Bureau
**Date**: March 2026
