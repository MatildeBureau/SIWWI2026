# Ice density estimation

Script for estimating the density of ice samples using water-displacement measurements + uncertainty propagation.

---

## Overview

This script computes the density of ice samples from repeated weighing measurements using Archimedes’ principle.

Each ice piece is weighed in three configurations:

1. **Container + water only**
2. **Container + water + floating ice**
3. **Container + water + fully submerged ice**

From these measurements, the script computes:

- Individual ice sample densities
- Mean ice density
- Statistical uncertainty
- Measurement uncertainty
- Total uncertainty

---

# Method

## Measurement Principle

For each sample:

- $m_1$: mass of container + water
- $m_2$: mass of container + water + floating ice
- $m_3$: mass of container + water + submerged ice

The true ice mass is:

$$m_{ice} = m_2 - m_1$$

The displaced water mass is:

$$m_{water} = m_3 - m_1$$

Since:

$$m_{water} = \rho_w V_{ice}$$

the ice density becomes:

$$\rho_{ice} = \rho_w \frac{m_{ice}}{m_{water}}$$

where:

- $\rho_w$ = density of freshwater (assumed 1000 kg/m³)

---

# Workflow

Steps are the following:

1. Imports repeated scale measurements
2. Computes ice mass and displaced water mass
3. Calculates density for each ice sample
4. Computes:
   - Mean density
   - Standard deviation
   - Standard error of the mean (SEM)
5. Propagates measurement uncertainty from scale resolution
6. Combines statistical and instrumental uncertainties
7. Prints final results to console

---

# Uncertainty estimation

## Stat

The statistical uncertainty is estimated using the standard error of the mean:

$$SEM = \frac{\sigma}{\sqrt{N}}$$

where:

- $\sigma$ = sample standard deviation
- $N$ = number of ice samples

The unbiased $N-1$ estimator is used.

---

## Measurement uncertainty

Scale uncertainty is propagated through:

$$\rho = \rho_w \frac{m_{ice}}{m_{water}}$$

using standard relative uncertainty propagation:

$$\frac{u_\rho}{\rho} = \sqrt{\left(\frac{u_m}{m_{ice}}\right)^2 + \left(\frac{u_m}{m_{water}}\right)^2}$$

where:

- $u_m$ is derived from the scale resolution

---

## Total uncertainty

The total uncertainty combines both error sources :

$$u_{tot} = \sqrt{u_{meas}^2 + SEM^2}$$

---

# Output

The script prints:

- Mean ice density
- Statistical uncertainty
- Measurement uncertainty
- Total uncertainty

Example:


Mean density:             917.25 kg/m3
Statistical Uncertainty:  +/- 4.12 kg/m3
Measurement Uncertainty:  +/- 8.45 kg/m3
Total Uncertainty:        +/- 9.40 kg/m3

Author : Matilde
Date : april 2026

