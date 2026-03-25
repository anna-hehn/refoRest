#' Create disturbance maps and a simple report
#'
#' Runs the disturbance mapping/reporting workflow on an index time series.
#' This function combines:
#' \itemize{
#'   \item disturbance detection via \code{detect_disturbance_z()}
#'   \item patch delineation via \code{patch_metrics()}
#'   \item map creation via \code{map_disturbance()}
#'   \item saving outputs (maps, patch table, text report)
#' }
#'
#' @param x SpatRaster time series. Typically output from \code{get_index_local()}.
#' @param aoi Optional sf or SpatVector. AOI boundary for map overlay.
#'
#' @param baseline Integer vector. Baseline layer indices for \code{detect_disturbance_z()}.
#' @param z_thresh Numeric. Z-score threshold for disturbance detection.
#' @param direction Character. Either \code{"drop"} (default) or \code{"rise"}.
#' @param min_duration Integer >= 1. Minimum number of consecutive layers exceeding threshold.
#' @param robust Logical. If TRUE, use median/MAD instead of mean/sd.
#' @param min_spread Numeric >= 0. Lower bound for baseline spread.
#'
#' @param directions Integer. Patch connectivity for \code{patch_metrics()}: 4 or 8.
#' @param min_patch_cells Integer >= 1. Remove patches smaller than this many cells.
#' @param return_polygons Logical. If TRUE, patch polygons are returned by \code{patch_metrics()}.
#' @param stats_severity Character vector. Severity stats per patch.
#' @param stats_first_idx Character vector. First-detection stats per patch.
#'
#' @param top_n Integer >= 1. Number of largest patches shown in the top-patches map.
#'
#' @param presence_title Character. Title for presence map.
#' @param patches_title Character. Title for patch-ID map.
#' @param severity_title Character. Title for severity map.
#' @param top_title Character. Title for top-patches map.
#'
#' @param presence_color Character. Fill color for disturbance presence map.
#' @param na_color Character. Fill color for NA/background.
#' @param severity_palette Character vector. Colors for severity gradient.
#' @param severity_limits Optional numeric vector of length 2 for severity scale limits.
#' @param severity_oob Character. How to handle values outside severity_limits:
#'   \code{"squish"} or \code{"censor"}.
#'
#' @param aoi_color Character. AOI outline color.
#' @param aoi_size Numeric. AOI outline width.
#' @param panel_border_color Character. Color of rectangular plot frame.
#' @param panel_border_size Numeric. Width of rectangular plot frame.
#' @param raster_alpha Numeric in [0,1]. Raster transparency.
#' @param theme_base_size Numeric. Base font size for maps.
#'
#' @param output_dir Character. Directory where outputs should be written.
#' @param save_maps Logical. If TRUE, save maps as PNG files.
#' @param save_patch_table Logical. If TRUE, save patch table as CSV.
#' @param save_report Logical. If TRUE, save text report.
#' @param width,height,dpi Numeric. Output size and resolution for saved maps.
#'
#' @return A list with:
#' \describe{
#'   \item{detection}{Output from \code{detect_disturbance_z()}}
#'   \item{patches}{Output from \code{patch_metrics()}}
#'   \item{maps}{Named list of ggplot objects}
#'   \item{files}{Named list of written file paths}
#' }
#'
#' @export
create_map_and_report <- function(
    x,
    aoi = NULL,

    baseline = 1:5,
    z_thresh = -2,
    direction = c("drop", "rise"),
    min_duration = 1,
    robust = TRUE,
    min_spread = 0,

    directions = 8,
    min_patch_cells = 1,
    return_polygons = TRUE,
    stats_severity = c("mean", "min", "max"),
    stats_first_idx = c("min"),

    top_n = 5,

    presence_title = "Detected disturbance",
    patches_title = "Disturbance patches",
    severity_title = "Disturbance severity",
    top_title = "Top disturbance patches",

    presence_color = "#d73027",
    na_color = "white",
    severity_palette = c("firebrick4", "khaki", "forestgreen"),
    severity_limits = NULL,
    severity_oob = c("squish", "censor"),

    aoi_color = "darkgray",
    aoi_size = 0.6,
    panel_border_color = "gray70",
    panel_border_size = 0.6,
    raster_alpha = 1,
    theme_base_size = 12,

    output_dir = "disturbance_output",
    save_maps = TRUE,
    save_patch_table = TRUE,
    save_report = TRUE,
    width = 7,
    height = 6,
    dpi = 300
) {

  ## --- Argument checks ------------------------------------------------------

  direction <- match.arg(direction)
  severity_oob <- match.arg(severity_oob)

  if (!inherits(x, "SpatRaster")) {
    stop("x must be a terra SpatRaster.")
  }

  if (!is.null(aoi)) {
    aoi_ok <- inherits(aoi, "sf") || inherits(aoi, "SpatVector")
    if (!aoi_ok) stop("aoi must be NULL, sf, or SpatVector.")
  }

  if (!is.numeric(top_n) || length(top_n) != 1L || is.na(top_n) || top_n < 1) {
    stop("top_n must be a single number >= 1.")
  }
  top_n <- as.integer(top_n)

  if (!is.character(output_dir) || length(output_dir) != 1L || is.na(output_dir)) {
    stop("output_dir must be a single character string.")
  }

  if (!is.logical(save_maps) || length(save_maps) != 1L || is.na(save_maps)) {
    stop("save_maps must be TRUE/FALSE.")
  }
  if (!is.logical(save_patch_table) || length(save_patch_table) != 1L || is.na(save_patch_table)) {
    stop("save_patch_table must be TRUE/FALSE.")
  }
  if (!is.logical(save_report) || length(save_report) != 1L || is.na(save_report)) {
    stop("save_report must be TRUE/FALSE.")
  }

  ## --- Create output directory ---------------------------------------------

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  ## --- 1) Detect disturbance -----------------------------------------------

  dz <- detect_disturbance_z(
    x = x,
    baseline = baseline,
    z_thresh = z_thresh,
    direction = direction,
    min_duration = min_duration,
    robust = robust,
    min_spread = min_spread
  )

  ## --- 2) Compute patches --------------------------------------------------

  pm <- patch_metrics(
    disturbance = dz$disturbance,
    severity = dz$severity,
    first_idx = dz$first_idx,
    directions = directions,
    min_patch_cells = min_patch_cells,
    return_polygons = return_polygons,
    stats_severity = stats_severity,
    stats_first_idx = stats_first_idx
  )

  ## --- 3) Create maps ------------------------------------------------------

  p_presence <- map_disturbance(
    patch_id = pm$patch_id,
    aoi = aoi,
    show = "presence",
    title = presence_title,
    subtitle = NULL,
    caption = NULL,
    presence_color = presence_color,
    na_color = na_color,
    aoi_color = aoi_color,
    aoi_size = aoi_size,
    panel_border_color = panel_border_color,
    panel_border_size = panel_border_size,
    raster_alpha = raster_alpha,
    theme_base_size = theme_base_size
  )

  p_patches <- map_disturbance(
    patch_id = pm$patch_id,
    aoi = aoi,
    show = "patch_id",
    title = patches_title,
    subtitle = NULL,
    caption = NULL,
    na_color = na_color,
    aoi_color = aoi_color,
    aoi_size = aoi_size,
    panel_border_color = panel_border_color,
    panel_border_size = panel_border_size,
    raster_alpha = raster_alpha,
    theme_base_size = theme_base_size
  )

  p_severity <- map_disturbance(
    patch_id = pm$patch_id,
    severity = dz$severity,
    aoi = aoi,
    title = severity_title,
    subtitle = NULL,
    caption = NULL,
    na_color = na_color,
    severity_palette = severity_palette,
    severity_limits = severity_limits,
    severity_oob = severity_oob,
    aoi_color = aoi_color,
    aoi_size = aoi_size,
    panel_border_color = panel_border_color,
    panel_border_size = panel_border_size,
    raster_alpha = raster_alpha,
    theme_base_size = theme_base_size
  )

  p_top <- map_disturbance(
    patch_id = pm$patch_id,
    severity = dz$severity,
    aoi = aoi,
    top_n = top_n,
    title = paste(top_title, "(", top_n, "largest)", sep = ""),
    subtitle = NULL,
    caption = NULL,
    na_color = na_color,
    severity_palette = severity_palette,
    severity_limits = severity_limits,
    severity_oob = severity_oob,
    aoi_color = aoi_color,
    aoi_size = aoi_size,
    panel_border_color = panel_border_color,
    panel_border_size = panel_border_size,
    raster_alpha = raster_alpha,
    theme_base_size = theme_base_size
  )

  maps <- list(
    presence = p_presence,
    patches = p_patches,
    severity = p_severity,
    top_patches = p_top
  )

  ## --- 4) Save outputs -----------------------------------------------------

  files_out <- list(
    presence_map = NULL,
    patch_map = NULL,
    severity_map = NULL,
    top_map = NULL,
    patch_table = NULL,
    report = NULL
  )

  if (save_maps) {
    files_out$presence_map <- file.path(output_dir, "detected_disturbance.png")
    files_out$patch_map    <- file.path(output_dir, "disturbance_patches.png")
    files_out$severity_map <- file.path(output_dir, "disturbance_severity.png")
    files_out$top_map      <- file.path(output_dir, "disturbance_top_patches.png")

    ggplot2::ggsave(files_out$presence_map, plot = p_presence, width = width, height = height, dpi = dpi)
    ggplot2::ggsave(files_out$patch_map,    plot = p_patches,  width = width, height = height, dpi = dpi)
    ggplot2::ggsave(files_out$severity_map, plot = p_severity, width = width, height = height, dpi = dpi)
    ggplot2::ggsave(files_out$top_map,      plot = p_top,      width = width, height = height, dpi = dpi)
  }

  if (save_patch_table) {
    files_out$patch_table <- file.path(output_dir, "patch_metrics.csv")
    utils::write.csv(pm$patch_table, files_out$patch_table, row.names = FALSE)
  }

  if (save_report) {
    files_out$report <- file.path(output_dir, "disturbance_report.txt")

    n_patches <- if (nrow(pm$patch_table) == 0) 0L else nrow(pm$patch_table)
    largest_patch_ha <- if (n_patches == 0) NA_real_ else max(pm$patch_table$area_ha, na.rm = TRUE)

    report_lines <- c(
      "Disturbance Analysis Report",
      "===========================",
      "",
      paste("Created:", as.character(Sys.time())),
      "",
      "Detection settings",
      "------------------",
      paste("Method:", dz$summary$method),
      paste("Direction:", dz$summary$direction),
      paste("Z-threshold:", dz$summary$z_thresh),
      paste("Baseline layers:", paste(dz$summary$baseline, collapse = ", ")),
      paste("Post-baseline layers:", paste(dz$summary$post_idx, collapse = ", ")),
      paste("Post-baseline names:", paste(dz$summary$post_names, collapse = ", ")),
      paste("Minimum duration:", min_duration),
      paste("Minimum spread:", min_spread),
      "",
      "Patch settings",
      "--------------",
      paste("Directions:", directions),
      paste("Minimum patch cells:", min_patch_cells),
      "",
      "Results summary",
      "---------------",
      paste("Total cells:", dz$summary$total_pixels),
      paste("Disturbed cells:", dz$summary$disturbed_pixels),
      paste("Disturbed percent:", round(dz$summary$disturbed_percent, 2)),
      paste("Number of patches:", n_patches),
      paste("Largest patch (ha):", ifelse(is.na(largest_patch_ha), "NA", round(largest_patch_ha, 4))),
      ""
    )

    utils::write.table(
      report_lines,
      file = files_out$report,
      quote = FALSE,
      row.names = FALSE,
      col.names = FALSE
    )
  }

  ## --- Return --------------------------------------------------------------

  list(
    detection = dz,
    patches = pm,
    maps = maps,
    files = files_out
  )
}
