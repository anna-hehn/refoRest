get_example_data <- function() {

  # Paths
  aoi_path <- system.file("extdata", "aoi.gpkg", package = "refoRest")
  ext_dir  <- system.file("extdata", package = "refoRest")

  # NDVI files
  files <- list.files(
    ext_dir,
    pattern = "^ndvi_\\d+\\.tif$",
    full.names = TRUE
  )
  files <- files[order(files)]

  # Dates (synthetic daily sequence starting 2023-01-01)
  dates <- as.Date("2023-01-01") + (seq_along(files) - 1)

  # Return
  list(
    aoi   = sf::st_read(aoi_path, quiet = TRUE),
    files = files,
    dates = dates
  )
}
