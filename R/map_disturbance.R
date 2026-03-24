#' Create a disturbance map with ggplot2
#'
#' Plots disturbance patches as:
#' - presence / absence map,
#' - patch IDs,
#' - or severity values within patches.
#'
#' Typically used with outputs from patch_metrics() and detect_disturbance_z().
#'
#' @param patch_id SpatRaster. Patch ID raster from patch_metrics().
#' @param severity Optional SpatRaster. Severity raster (e.g. output$severity from detect_disturbance_z()).
#' @param aoi Optional sf or SpatVector. AOI boundary overlay.
#' @param top_n Optional integer. Keep only the largest N patches by cell count.
#' @param show Character. If severity is NULL:
#'   "presence" = show disturbance presence only,
#'   "patch_id" = show patch IDs.
#' @param title,subtitle,caption Character. Plot labels.
#' @param presence_color Character. Fill color for disturbance presence map.
#' @param na_color Character. Fill color for NA / background.
#' @param severity_palette Character vector. Colors for severity gradient (low -> high).
#' @param severity_limits Optional numeric vector of length 2. Limits for severity color scale.
#' @param severity_oob Character. How to handle values outside limits:
#'   "squish" or "censor".
#' @param aoi_color Character. AOI outline color.
#' @param aoi_size Numeric. AOI outline width.
#' @param panel_border_color Character. Color of rectangular plot frame.
#' @param panel_border_size Numeric. Width of rectangular plot frame.
#' @param raster_alpha Numeric in [0,1]. Raster transparency.
#' @param theme_base_size Numeric. Base font size.
#' @param save_path Optional file path. If provided, plot is saved via ggsave().
#' @param width,height,dpi Save parameters passed to ggsave().
#'
#' @return A ggplot object.
#' @export
map_disturbance <- function(
    patch_id,
    severity = NULL,
    aoi = NULL,
    top_n = NULL,
    show = c("presence", "patch_id"),
    title = NULL,
    subtitle = NULL,
    caption = NULL,
    presence_color = "firebrick4",
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
    save_path = NULL,
    width = 7,
    height = 6,
    dpi = 300
) {

  ## --- Argument checks ------------------------------------------------------

  show <- match.arg(show)
  severity_oob <- match.arg(severity_oob)

  if (!inherits(patch_id, "SpatRaster")) {
    stop("patch_id must be a terra SpatRaster.")
  }
  if (terra::nlyr(patch_id) != 1) {
    stop("patch_id must be single-layer.")
  }

  if (!is.null(severity)) {
    if (!inherits(severity, "SpatRaster")) {
      stop("severity must be a terra SpatRaster.")
    }
    if (terra::nlyr(severity) != 1) {
      stop("severity must be single-layer.")
    }
    if (!terra::compareGeom(patch_id, severity, stopOnError = FALSE)) {
      stop("severity must match patch_id geometry.")
    }
  }

  ## --- AOI handling ---------------------------------------------------------

  aoi_sf <- NULL
  if (!is.null(aoi)) {
    if (inherits(aoi, "SpatVector")) aoi_sf <- sf::st_as_sf(aoi)
    if (inherits(aoi, "sf")) aoi_sf <- aoi
    if (is.null(aoi_sf)) stop("aoi must be sf or SpatVector.")
  }

  ## --- Keep only top N patches if requested --------------------------------

  pid <- patch_id

  if (!is.null(top_n)) {
    if (!is.numeric(top_n) || length(top_n) != 1L || is.na(top_n) || top_n < 1) {
      stop("top_n must be a single number >= 1.")
    }

    top_n <- as.integer(top_n)

    f <- terra::freq(pid)
    f <- f[!is.na(f$value), , drop = FALSE]
    f <- f[order(f$count, decreasing = TRUE), , drop = FALSE]

    keep_ids <- head(f$value, top_n)
    rcl <- cbind(keep_ids, keep_ids)
    pid <- terra::classify(pid, rcl = rcl, others = NA)
  }

  ## --- Decide what to plot --------------------------------------------------

  plot_r <- NULL
  value_name <- NULL

  if (!is.null(severity)) {
    # show severity only where patches exist
    plot_r <- terra::mask(severity, pid)
    value_name <- "severity"
  } else if (show == "presence") {
    # 1 = disturbed, 0 = undisturbed
    plot_r <- terra::ifel(!is.na(pid), 1L, 0L)
    value_name <- "presence"
  } else {
    # show patch IDs directly
    plot_r <- pid
    value_name <- "patch_id"
  }

  ## --- Raster to data.frame for ggplot -------------------------------------

  df <- terra::as.data.frame(plot_r, xy = TRUE, na.rm = FALSE)
  names(df)[3] <- value_name

  ## --- Base plot ------------------------------------------------------------

  p <- ggplot2::ggplot(df, ggplot2::aes(x = x, y = y)) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      caption = caption,
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_minimal(base_size = theme_base_size) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold"),
      legend.title = ggplot2::element_text(face = "bold"),
      panel.border = ggplot2::element_rect(
        fill = NA,
        color = panel_border_color,
        linewidth = panel_border_size
      )
    )

  ## --- Add raster layer -----------------------------------------------------

  if (value_name == "presence") {

    df$presence_label <- ifelse(
      is.na(df$presence) | df$presence == 0,
      "No Disturbance",
      "Disturbed area"
    )

    p <- p +
      ggplot2::geom_raster(
        ggplot2::aes(fill = presence_label),
        alpha = raster_alpha
      ) +
      ggplot2::scale_fill_manual(
        values = c(
          "No Disturbance" = na_color,
          "Disturbed area" = presence_color
        ),
        breaks = c("Disturbed area", "No Disturbance"),
        name = "Disturbance"
      )

  } else if (value_name == "patch_id") {

    p <- p +
      ggplot2::geom_raster(
        ggplot2::aes(fill = factor(patch_id)),
        alpha = raster_alpha
      ) +
      ggplot2::guides(
        fill = ggplot2::guide_legend(
          override.aes = list(alpha = 1)
        )
      ) +
      ggplot2::scale_fill_viridis_d(
        na.value = na_color,
        name = "Patch ID"
      )

  } else {

    oob_fun <- if (severity_oob == "squish") scales::squish else scales::censor

    p <- p +
      ggplot2::geom_raster(
        ggplot2::aes(fill = severity),
        alpha = raster_alpha
      ) +
      ggplot2::scale_fill_gradientn(
        colors = severity_palette,
        limits = severity_limits,
        oob = oob_fun,
        na.value = na_color,
        name = "Severity (z)"
      )
  }

  ## --- Add AOI outline ------------------------------------------------------

  if (!is.null(aoi_sf)) {
    p <- p +
      ggplot2::geom_sf(
        data = aoi_sf,
        fill = NA,
        color = aoi_color,
        linewidth = aoi_size,
        inherit.aes = FALSE
      ) +
      ggplot2::coord_sf(expand = FALSE)
  } else {
    p <- p + ggplot2::coord_equal()
  }

  ## --- Save -----------------------------------------------------------------

  if (!is.null(save_path)) {
    ggplot2::ggsave(
      filename = save_path,
      plot = p,
      width = width,
      height = height,
      dpi = dpi
    )
  }

  p
}

#' @export
devtools::document()
devtools::load_all()
