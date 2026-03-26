#' Detect disturbance from an index time series using (robust) z-scores
#'
#' @param x terra SpatRaster time series (layers named as dates, or any names)
#' @param baseline integer vector of layer indices used as reference period
#' @param z_thresh numeric threshold (e.g. -2 for drops). More extreme = stricter.
#' @param direction "drop" (default) or "rise"
#' @param min_duration integer, how many consecutive layers must meet the threshold
#' @param robust logical, if TRUE uses median/MAD instead of mean/sd (more robust to outliers)
#' @param min_spread numeric >= 0. Optional lower bound for baseline spread (MAD/SD).
#'   Use >0 to avoid extremely large absolute z-scores when baseline variability is tiny.
#'
#' @return list(disturbance, first_idx, severity, summary)
#' @export
detect_disturbance_z <- function(x,
                                 baseline     = 1:5,
                                 z_thresh     = -2,
                                 direction    = c("drop", "rise"),
                                 min_duration = 1,
                                 robust       = TRUE,
                                 min_spread   = 0) {

##Argument checks

  direction <- match.arg(direction)

  if (!inherits(x, "SpatRaster")) {
    stop("x must be a terra SpatRaster.")
  }

  # numeric check: terra stores raster value type per layer, factors are categorical
  if (any(terra::is.factor(x))) {
    stop("x must be numeric (no categorical/factor layers).")
  }

  if (terra::nlyr(x) < 2) {
    stop("x must have at least 2 layers.")
  }

  if (length(baseline) < 2) {
    stop("baseline should contain at least 2 layers.")
  }

  if (any(baseline < 1L) || any(baseline > terra::nlyr(x))) {
    stop("baseline indices out of range.")
  }

  if (!is.numeric(z_thresh) || length(z_thresh) != 1L || is.na(z_thresh)) {
    stop("z_thresh must be a single non-NA numeric value.")
  }

  if (!is.numeric(min_duration) || length(min_duration) != 1L ||
      is.na(min_duration) || min_duration < 1L) {
    stop("min_duration must be a single number >= 1.")
  }

  if (!is.logical(robust) || length(robust) != 1L || is.na(robust)) {
    stop("robust must be TRUE/FALSE (single value).")
  }

  if (!is.numeric(min_spread) || length(min_spread) != 1L ||
      is.na(min_spread) || min_spread < 0) {
    stop("min_spread must be a single non-NA numeric value >= 0.")
  }

  min_duration <- as.integer(min_duration)

##Baseline-Statistic per Pixel

  x_base <- x[[baseline]]

  if (robust) {
    center <- terra::app(x_base, fun = function(v) stats::median(v, na.rm = TRUE))
    mad_fn <- function(v) stats::mad(v, constant = 1, na.rm = TRUE)
    spread <- terra::app(x_base, fun = mad_fn)
  } else {
    center <- terra::app(x_base, fun = function(v) mean(v, na.rm = TRUE))
    spread <- terra::app(x_base, fun = function(v) stats::sd(v, na.rm = TRUE))
  }

## Spread == 0 -> NA setzen, damit nicht durch 0 geteilt wird
  spread <- terra::ifel(spread == 0, NA, spread)

  # optional floor to avoid extremely large z-scores when baseline variability is tiny
  if (min_spread > 0) {
    spread <- terra::ifel(spread < min_spread, min_spread, spread)
  }

##Z-Scores

  z <- (x - center) / spread

##Select and evaluate only post-baseline Layers (exclude baseline period)
  post_idx <- setdiff(seq_len(terra::nlyr(x)), baseline)
  if (length(post_idx) == 0L) {
    stop("No post-baseline layers to evaluate (baseline covers all layers).")
  }
  z_post <- z[[post_idx]]

##Threshold condition (binary raster: 0/1)

  if (direction == "drop") {
    cond <- terra::ifel(z_post < z_thresh, 1L, 0L)
  } else {
    cond <- terra::ifel(z_post > z_thresh, 1L, 0L)
  }
  names(cond) <- names(z_post)

##Disturbance detection (at least min_duration consecutive events)

  if (min_duration == 1L) {
    disturbed <- terra::app(
      cond,
      fun = function(v) {
        v[is.na(v)] <- 0L
        as.integer(any(v == 1L))
      }
    )
  } else {
    disturbed <- terra::app(
      cond,
      fun = function(v) {
        v[is.na(v)] <- 0L
        r <- rle(v == 1L)
        as.integer(any(r$values & r$lengths >= min_duration))
      }
    )
  }

  disturbed <- terra::ifel(disturbed == 1L, 1L, NA)
  names(disturbed) <- "disturbance"

##First occurrence of Disturbance

  first_idx <- terra::app(
    cond,
    fun = function(v) {
      v[is.na(v)] <- 0L
      w <- which(v == 1L)
      if (length(w) == 0L) return(NA_integer_)
      as.integer(w[1L])
    }
  )
  first_idx <- terra::mask(first_idx, disturbed)
  names(first_idx) <- "first_idx"

##Disturbance Severity (most extreme z-value during post-baseline period)

  if (direction == "drop") {
    severity <- terra::app(
      z_post,
      fun = function(v) {
        if (all(is.na(v))) return(NA_real_)
        suppressWarnings(min(v, na.rm = TRUE))
      }
    )
  } else {
    severity <- terra::app(
      z_post,
      fun = function(v) {
        if (all(is.na(v))) return(NA_real_)
        suppressWarnings(max(v, na.rm = TRUE))
      }
    )
  }
  severity <- terra::mask(severity, disturbed)
  names(severity) <- "severity_z"

##Summary Statistics

  n_pix_total <- terra::ncell(disturbed)
  n_pix_dist  <- as.integer(terra::global(!is.na(disturbed), "sum", na.rm = TRUE)[1, 1])
  pct_dist    <- 100 * n_pix_dist / n_pix_total

  layer_names <- names(x)
  post_names  <- layer_names[post_idx]

  list(
    disturbance = disturbed,
    first_idx   = first_idx,
    severity    = severity,
    summary = list(
      method             = if (robust) "median/MAD z-score" else "mean/sd z-score",
      direction          = direction,
      z_thresh           = z_thresh,
      baseline           = baseline,
      post_idx           = post_idx,
      post_names         = post_names,
      disturbed_pixels   = n_pix_dist,
      total_pixels       = n_pix_total,
      disturbed_percent  = pct_dist
    )
  )
}
