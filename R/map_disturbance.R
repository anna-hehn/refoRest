#' Create a nice disturbance map (ggplot2)
#'
#' @param patch_id SpatRaster. Patch ID raster from patch_metrics().
#' @param severity Optional SpatRaster. Severity raster (e.g., z-scores). If given, map shows severity.
#' @param aoi Optional sf or SpatVector. AOI boundary overlay.
#' @param top_n Optional integer. If set, keep only the largest N patches (by cell count).
#' @param show What to show if severity is NULL: "presence" (default) or "patch_id".
#' @param title,subtitle,caption Character. Plot labels.
#' @param presence_color Single color for presence map (e.g. "#d73027").
#' @param na_color Color for NA background.
#' @param severity_palette Character vector of colors for severity scale (low -> high).
#' @param severity_limits Optional numeric length-2. If given, limits for color scale (does not change data).
#' @param severity_oob How to handle values outside limits: "squish" (default) or "censor".
#' @param aoi_color,aoi_size AOI outline styling.
#' @param raster_alpha Numeric 0..1.
#' @param theme_base_size Numeric. ggplot base font size.
#' @param save_path Optional file path (png/pdf). If provided, saves via ggsave.
#' @param width,height,dpi Save size.
#'
#' @return A ggplot object.
#' @export
map_disturbance <- function(patch_id,
                            severity = NULL,
                            aoi = NULL,
                            top_n = NULL,
                            show = c("presence", "patch_id"),
                            title = NULL,
                            subtitle = NULL,
                            caption = NULL,
                            presence_color = "#d73027",
                            na_color = "white",
                            severity_palette = c("firebrick4", "khaki", "forestgreen"),
                            severity_limits = NULL,
                            severity_oob = c("squish", "censor"),
                            aoi_color = "darkgray",
                            aoi_size = 0.6,
                            raster_alpha = 1,
                            theme_base_size = 12,
                            save_path = NULL,
                            width = 7,
                            height = 6,
                            dpi = 300) {

  show <- match.arg(show)
  severity_oob <- match.arg(severity_oob)

  if (!inherits(patch_id, "SpatRaster")) stop("patch_id must be a terra SpatRaster.")
  if (terra::nlyr(patch_id) != 1) stop("patch_id must be single-layer.")

  if (!is.null(severity)) {
    if (!inherits(severity, "SpatRaster")) stop("severity must be a terra SpatRaster.")
    if (terra::nlyr(severity) != 1) stop("severity must be single-layer.")
    if (!terra::compareGeom(patch_id, severity, stopOnError = FALSE)) {
      stop("severity must match patch_id geometry.")
    }
  }

  # AOI to sf if provided
  aoi_sf <- NULL
  if (!is.null(aoi)) {
    if (inherits(aoi, "SpatVector")) aoi_sf <- sf::st_as_sf(aoi)
    if (inherits(aoi, "sf")) aoi_sf <- aoi
    if (is.null(aoi_sf)) stop("aoi must be sf or SpatVector.")
  }

  # Optionally keep only top N patches (by cell count)
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

  # What raster to plot
  plot_r <- NULL
  value_name <- NULL

  if (!is.null(severity)) {
    # show severity only where there is a patch
    plot_r <- terra::mask(severity, pid)
    value_name <- "severity"
  } else {
    if (show == "presence") {
      plot_r <- terra::ifel(!is.na(pid), 1L, NA)
      value_name <- "presence"
    } else {
      plot_r <- pid
      value_name <- "patch_id"
    }
  }

  # Convert raster to data frame for ggplot
  # (xy=TRUE => columns x,y + layer values)
  df <- terra::as.data.frame(plot_r, xy = TRUE, na.rm = FALSE)
  names(df)[3] <- value_name

  # Build ggplot
  p <- ggplot2::ggplot(df, ggplot2::aes(x = x, y = y)) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = title, subtitle = subtitle, caption = caption, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = theme_base_size) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold"),
      legend.title = ggplot2::element_text(face = "bold")
    )

  # Raster layer styling
  if (value_name == "presence") {
    p <- p +
      ggplot2::geom_raster(ggplot2::aes(fill = factor(presence)), alpha = raster_alpha) +
      ggplot2::scale_fill_manual(
        values = c("1" = presence_color),
        na.value = na_color,
        name = "Disturbance"
      )
  } else if (value_name == "patch_id") {
    # Discrete palette for IDs (visually nicer than 0..400 continuous scale)
    # For many patches, this becomes busy; users can prefer show="presence".
    p <- p +
      ggplot2::geom_raster(ggplot2::aes(fill = factor(patch_id)), alpha = raster_alpha) +
      ggplot2::guides(fill = ggplot2::guide_legend(override.aes = list(alpha = 1))) +
      ggplot2::scale_fill_viridis_d(na.value = na_color, name = "Patch ID")
  } else {
    # severity continuous
    oob_fun <- if (severity_oob == "squish") scales::squish else scales::censor

    p <- p +
      ggplot2::geom_raster(ggplot2::aes(fill = severity), alpha = raster_alpha) +
      ggplot2::scale_fill_gradientn(
        colors = severity_palette,
        limits = severity_limits,
        oob = oob_fun,
        na.value = na_color,
        name = "Severity (z)"
      )
  }

  # AOI overlay
  if (!is.null(aoi_sf)) {
    p <- p +
      ggplot2::geom_sf(
        data = aoi_sf,
        fill = NA,
        color = aoi_color,
        linewidth = aoi_size,
        inherit.aes = FALSE
      )
  }

  # Save if requested
  if (!is.null(save_path)) {
    ggplot2::ggsave(filename = save_path, plot = p, width = width, height = height, dpi = dpi)
  }

  p
}
