# SIWWI2026
Scripts used for wave/ice data post-processing -- SIWWI facility -- University of Melbourne 2026


Don't hesitate to reach out for any question : matildebureau@gmail.com 

all scripts are Matlab ones.

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


