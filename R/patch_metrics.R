#' Compute patch metrics from a disturbance mask
#'
#' Takes a binary disturbance raster (typically 1 = disturbed, NA or 0 = not disturbed),
#' labels connected disturbed pixels into patches, and computes patch-level metrics
#' such as area (and optionally perimeter/shape metrics). Optionally aggregates
#' severity and/or first occurrence layers per patch.
#'
#' @param disturbance SpatRaster. Disturbance mask (1 for disturbed, NA/0 otherwise).
#'        Usually the `$disturbance` output from `detect_disturbance_z()`.
#' @param severity Optional SpatRaster. Per-pixel severity layer (e.g. `$severity` from `detect_disturbance_z()`).
#' @param first_idx Optional SpatRaster. Per-pixel first detection index (e.g. `$first_idx` from `detect_disturbance_z()`).
#' @param directions Integer. Neighborhood connectivity for patch labelling:
#'        4 (rook) or 8 (queen). Default 8.
#' @param min_patch_cells Integer >= 1. Patches smaller than this number of cells are removed.
#' @param return_polygons Logical. If TRUE, returns dissolved patch polygons.
#' @param stats_severity Character vector. Patch stats for severity. Default c("mean","min","max").
#' @param stats_first_idx Character vector. Patch stats for first_idx. Default c("min").
#'
#' @return A list with:
#' \describe{
#'   \item{patch_id}{SpatRaster with patch IDs (NA outside patches).}
#'   \item{patch_table}{data.frame with patch metrics (one row per patch).}
#'   \item{patch_polygons}{SpatVector polygons (if return_polygons = TRUE), otherwise NULL.}
#' }
#'
#' @export
patch_metrics <- function(disturbance,
                          severity = NULL,
                          first_idx = NULL,
                          directions = 8,
                          min_patch_cells = 1,
                          return_polygons = TRUE,
                          stats_severity = c("mean", "min", "max"),
                          stats_first_idx = c("min")) {

  ## --- Argument checks ------------------------------------------------------

  if (!inherits(disturbance, "SpatRaster")) {
    stop("disturbance must be a terra SpatRaster.")
  }
  if (terra::nlyr(disturbance) != 1) {
    stop("disturbance must be a single-layer SpatRaster.")
  }
  if (!directions %in% c(4, 8)) {
    stop("directions must be 4 or 8.")
  }
  if (!is.numeric(min_patch_cells) || length(min_patch_cells) != 1L ||
      is.na(min_patch_cells) || min_patch_cells < 1) {
    stop("min_patch_cells must be a single number >= 1.")
  }
  min_patch_cells <- as.integer(min_patch_cells)

  # Optional layers checks: must align with disturbance
  if (!is.null(severity)) {
    if (!inherits(severity, "SpatRaster") || terra::nlyr(severity) != 1) {
      stop("severity must be NULL or a single-layer SpatRaster.")
    }
    if (!terra::compareGeom(disturbance, severity, stopOnError = FALSE)) {
      stop("severity must have same geometry as disturbance (extent/resolution/CRS).")
    }
  }

  if (!is.null(first_idx)) {
    if (!inherits(first_idx, "SpatRaster") || terra::nlyr(first_idx) != 1) {
      stop("first_idx must be NULL or a single-layer SpatRaster.")
    }
    if (!terra::compareGeom(disturbance, first_idx, stopOnError = FALSE)) {
      stop("first_idx must have same geometry as disturbance (extent/resolution/CRS).")
    }
  }

  ## --- Ensure binary mask (patch pixels are 1, everything else NA) ----------

  # Accept either 1/NA or 1/0 etc. We standardize to 1/NA for clumping.
  mask <- terra::ifel(!is.na(disturbance) & disturbance != 0, 1L, NA)

  ## --- Label connected components (patch IDs) -------------------------------

  # patch IDs start at 1...n; NA outside patches
  patch_id <- terra::patches(mask, directions = directions)
  names(patch_id) <- "patch_id"

  # If no patches exist, return empty outputs gracefully
  if (all(is.na(terra::values(patch_id)))) {
    return(list(
      patch_id = patch_id,
      patch_table = data.frame(),
      patch_polygons = if (return_polygons) terra::vect() else NULL
    ))
  }

  ## --- Patch size filter (min_patch_cells) ---------------------------------

  # Count cells per patch
  f <- terra::freq(patch_id)
  f <- f[!is.na(f$value), , drop = FALSE]

  keep_ids <- f$value[f$count >= min_patch_cells]

  # Reclass table: values NOT in keep_ids -> NA
  # Build a reclass matrix that maps "keep" ids to themselves
  rcl <- cbind(keep_ids, keep_ids)

  # First set everything to NA, then "burn back" kept IDs
  patch_keep <- terra::classify(patch_id, rcl = rcl, others = NA)

  patch_id <- patch_keep

  # Recompute freq after filtering
  f <- terra::freq(patch_id)
  f <- f[!is.na(f$value), , drop = FALSE]

  ## --- Core metrics: area ---------------------------------------------------

  # area per cell in map units (m^2 if projected in meters)
  cell_area <- terra::cellSize(patch_id, unit = "m")
  # sum cell_area per patch
  area_df <- terra::zonal(cell_area, patch_id, fun = "sum", na.rm = TRUE)
  colnames(area_df) <- c("patch_id", "area_m2")
  area_df$area_ha <- area_df$area_m2 / 10000

  # also store cell count
  count_df <- data.frame(patch_id = f$value, n_cells = f$count)

  ## --- Optional: severity stats per patch ----------------------------------

  sev_df <- NULL
  if (!is.null(severity)) {
    # aggregate severity per patch (mean/min/max by default)
    # terra::zonal supports a single fun; so we compute multiple and merge.
    tmp_list <- lapply(stats_severity, function(fn) {
      z <- terra::zonal(severity, patch_id, fun = fn, na.rm = TRUE)
      colnames(z) <- c("patch_id", paste0("severity_", fn))
      z
    })
    sev_df <- Reduce(function(a, b) merge(a, b, by = "patch_id", all = TRUE), tmp_list)
  }

  ## --- Optional: first_idx stats per patch ---------------------------------

  first_df <- NULL
  if (!is.null(first_idx)) {
    tmp_list <- lapply(stats_first_idx, function(fn) {
      z <- terra::zonal(first_idx, patch_id, fun = fn, na.rm = TRUE)
      colnames(z) <- c("patch_id", paste0("first_idx_", fn))
      z
    })
    first_df <- Reduce(function(a, b) merge(a, b, by = "patch_id", all = TRUE), tmp_list)
  }

  ## --- Optional: polygons + perimeter/shape --------------------------------
  # Note: perimeter is most meaningful in a projected CRS (meters).
  patch_polys <- NULL
  perim_df <- NULL

  if (isTRUE(return_polygons)) {
    patch_polys <- terra::as.polygons(patch_id, dissolve = TRUE, na.rm = TRUE)
    names(patch_polys) <- "patch_id"

    # Try perimeter via terra::perim (SpatVector)
    # If terra::perim is not available in the user's version, we just skip perimeter.
    perim_ok <- "perim" %in% getNamespaceExports("terra")

    if (perim_ok) {
      p_m <- terra::perim(patch_polys) # returns numeric vector
      perim_df <- data.frame(
        patch_id = patch_polys$patch_id,
        perimeter_m = as.numeric(p_m)
      )

      # Simple shape index (one common variant):
      # shape_index = perimeter / (2 * sqrt(pi * area))
      # = 1 for perfect circle, >1 for more complex/elongated shapes
      # (requires perimeter + area)
    }
  }

  ## --- Assemble patch table -------------------------------------------------

  patch_table <- merge(count_df, area_df, by = "patch_id", all = TRUE)

  if (!is.null(sev_df))   patch_table <- merge(patch_table, sev_df,   by = "patch_id", all = TRUE)
  if (!is.null(first_df)) patch_table <- merge(patch_table, first_df, by = "patch_id", all = TRUE)

  if (!is.null(perim_df)) {
    patch_table <- merge(patch_table, perim_df, by = "patch_id", all = TRUE)

    # shape index (guard against missing/zero)
    patch_table$shape_index <- with(patch_table,
                                    perimeter_m / (2 * sqrt(pi * area_m2))
    )
  }

  patch_table <- patch_table[order(patch_table$area_m2, decreasing = TRUE), , drop = FALSE]
  rownames(patch_table) <- NULL

  ## --- Return ---------------------------------------------------------------

  list(
    patch_id = patch_id,
    patch_table = patch_table,
    patch_polygons = patch_polys
  )
}
