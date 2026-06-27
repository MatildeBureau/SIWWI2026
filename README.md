# SIWWI2026
Scripts (Matlab) used for wave/ice data post-processing -- SIWWI facility -- University of Melbourne 2026

Don't hesitate to reach out for any question : matildebureau@gmail.com 

NB: and yes i've been lazy at the end of my project;  i've fed Claude with my scripts to get clearly commented files + Readme. I've checked everything
before uploading but it's still AI-written style, I have made zero effort to change the writing...

Folders general description:

## 3pt_bending_tests :
scripts and test files + metadata for ice sample mechanical characterization (Young modulus through bending tests). 

##  DT_boards: 
DT Boards installation for Matlab Data Translation. Used to send wave outputs to the wave maker + collect acoustic sensors data.  for heavy .exe files : see Releases --> .exe files for Data Translation set up - SIWWI2026

## ice_density:
basic script to compute ice density from water displacement measurements. 

## acoustic_sensors:
raw calibration data and script for 6 acoustic sensors.

## tank_deflexion :
script to test if I could monitor tank deflexion due to temperature changes or water filling. We suspected those were the main causes for the floor to the deform and then create leaks.

## run_wave_maker :
scripts to : tune wave parameters for target inputs, generate wave inputs for main scripts, test if the wave maker runs (its name is Wolfgang - Wolfy btw) correctly, run it and simultaneously acquire and save data from acoustic sensors through the DTbox. + example .csv output containing wave parameters used as inputs on 13/05/26.

## wave_maker_calib :
sample raw datas from 6 acoustic sensors + two side-cameras obtained during open-water tests in the tank. The goal of those test was to obtain the input voltag > actual wave amplitudes conversion for the padle, amd compare cameras and sensors measurements. metadata files for all tests run on this date + example output figures are attached.

## papers:
Some useful references + documentation and specs.

## post_processing_wave_ice_tests:
Main scripts to process SIWWI wave/ice tests: extract ice (or water) surface elevation vs time from acoustic sensors and side cameras, image + raw sensors' signals preprocessing, and then various results can be extracted, saved, and plotted (temporal mean amplitude, attenuation...). 

## wave_classifier:
Scripts to scatter all SIWWI tests in the Le Méhauté's diagram + return statistics for all relevant dimensional and dimensionless wave/ice parameters for all wave-ice tests + plot fracture threshold vs tested steepnesses and periods.


## ZS: 
script to try and split incident wave sfrom reflected ones in the tank, based on  Zelt & Skjelbreia (1992). Still too naive atm; need to better tune temporal windowing or completely change method and use wave packets inputs to be able to clearly
separate reflections.





