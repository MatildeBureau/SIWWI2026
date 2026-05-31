# Le Méhauté Wave Theory Classifier

This MATLAB script classifies data into valid wave theories based on the Le Méhauté (1976) diagram, 
updated with specific boundaries from Zhao et al. (2024). It takes nominal wave parameters and post-processed results, calculates the necessary dimensionless variables, classifies each wave condition, and plots them on a Le Méhauté diagram.


## Features

* **Frequency Matching:** Uses a fuzzy-matching algorithm (with a configurable tolerance, default 12%) to map the actual programmed wavemaker frequency (`SetFrequency_Hz`) to the nominal frequency (`f_Hz`) to accurately retrieve the theoretical wavelength.
* **Ice Tagging:** Prompts the user via the console to specify whether ice was present for each experimental dataset, allowing for distinct visual markers on the final plot.
* **Classification:** Calculates dimensionless depth ($h/gT^2$) and dimensionless steepness ($H/gT^2$), along with $h/L$, $H/L$, and the Ursell number ($Ur$).
* **Zone Identification:** Automatically categorizes waves by depth regime (Deep, Intermediate, Shallow) and valid theory (Linear, Stokes 2nd-5th, Cnoidal, or Breaking).
* **Plotting:** Generates a log-log Le Méhauté diagram with breaking limits, Ursell number iso-lines, and Stokes order thresholds.
* **Export:** Exports the classification results to a summary `.csv` and saves the generated plot in both high-resolution PDF and PNG formats.


## Inputs

The script relies on pairs of `.csv` files for each experiment. Ensure your input tables contain the following headers:

**1. Wave Parameters CSV :**
* `f_Hz`: The nominal wavemaker frequency.
* `lambda_m`: The theoretical wavelength.

**2. Results Post-Process CSV :**
* `SetFrequency_Hz`: The programmed frequency logged by the controller.
* `MeasuredFrequency_FFT_Hz`: The actual frequency measured via FFT.
* `MeasuredAmplitude_m`: The measured wave amplitude (script multiplies by 2 for wave height $H$).

## References

* Le Méhauté, B. (1976). *An Introduction to Hydrodynamics and Water Waves*. Springer, Berlin, Heidelberg.
* Zhao, X., Wang, Y., & Liu, Y. (2024). *Coastal Engineering*, 188, 104432.

Matilde, May 2026
