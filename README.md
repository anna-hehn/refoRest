# refoRest

refoRest provides tools to detect, analyze and map disturbance patterns in remote sensing index time series.
The package implements a reproducible workflow for disturbance detection using z-scores, spatial patch delination and automated generation of maps and summary outputs.

---

## Key Features

Designed for raster time series data (e.g. NDVI), the package provides functions to:

- Detect disturbance events using z-score based methods 
- Apply robust statistics (median / MAD) to reduce sensitivity to outliers
- Identify spatially connected disturbance patches
- Compute patch-level metrics (area, severity, timing)
- Generate disturbance maps using `ggplot2`
- Produce automated outputs including maps, tables and reports


## Usage

Users can detect and analyze disturbance dynamics in forest time series, making it ideal for applications in sustainable forest management and forest monitoring.


## Requirements

This package requires the following R packages:

- `sf`
- `terra`
- `ggplot2`
- `scales`
- `utils`


## Limitations
?

---

## Installation
From GitHub

```
# List of required packages
packages < - c("sf", "terra", "ggplot2", "scales", "utils")

# Check which packages are missing
missing_packages <- packages[!(packages %in% installed.packages()[,"Package"])]

# Install only missing packages
if (length(missing_packages) > 0) {
  install.packages(missing_packages)
} else {
  message("All packages are already installed!")
}

remotes::install_github("anna-hehn/refoRest")
```

## EXAMPLE: Detecting Forest Disturbances within a time series

```
library(refoRest)

# Load example data
ex <- get_example_data()

# Read and clip the local NDVI time series
x <- get_index_local(
  aoi   = ex$aoi,
  files = ex$files,
  dates = ex$dates
)

# Run the full workflow
# This creates  a disturbance detection result, patch metrics, four disturbance maps, 
a CSV table with patch statistics and a text report
res <- create_map_and_report(
  x = x,
  aoi = ex$aoi,
  baseline = 1:5,
  z_thresh = -2,
  direction = "drop",
  min_duration = 1,
  robust = TRUE,
  min_spread = 0,
  output_dir = "disturbance_output"
)
```

---

## Detailed Explanation

### `get_example_data()`
```
library(refoRest)

# Load example dataset
ex <- get_example_data()

# Inspect structure
str(ex)
```
This function loads the synthetic example dataset included in the package.
### Output
- `aoi`: an `sf`polygon defining the Area of Interest
- `files`: charcter vector of NDVI raster file paths
- `dates`: `Date`vector corresponding to the raster layers

### `get_index_local()`
```
x <- get_index_local(
  aoi   = ex$aoi,
  files = ex$files,
  dates = ex$dates
)
```
This function reads a time series of raster files and clips them to a given AOI.
### Arguments
- `aoi`: `sf`polygon (Area of Interest)
- `files`: charcter vector of raster file paths
- `dates`: `Date`vector matching the raster files
### Processing steps
- Reads raster files into a multi-layer `SpatRaster`
- Converts the AOI to a `terra`vector
- Crops and masks the raster to the AOI
- Assigns layer names based on the provided dates
### Output
- A `terra::SpatRaster`with one layer per date

### `detect_disturbance_(z)
```
dz <- detect_disturbance_z(
  x = x,
  baseline = 1:5,
  z_thresh = -2,
  direction = "drop",
  min_duration = 1,
  robust = TRUE,
  min_spread = 0
)
```
This function detects disturbance from a raster time series using z-scores relative to a baseline period, which describes the core step of the workflow.

### Key Concepts
- Baseline statistics are computed per pixel
- Disturbance is defined as deviation from baseline
- Supports both decreases ("drop") and increases

### Arguments
- `x`: raster time series (`SpatRaster`)
- `baseline`: indiced defining the reference period
- `z_thresh`: z-score threshold
- `direction`: `"drop"`or `"rise"`
- `min_duration`: minimum number of consecutive disturbed observations
- `robust`: use median/MAD instead of mean/sd
- `min_spread`: lower bound for variability

### Outputs
- `disturbance`: binary disturbance mask
- `first_idx`: first detection index per pixel
- `severity`: most extreme z-score in the post-baseline period
- `summary`: method and result overview
