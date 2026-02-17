#' Read NDVI/NBR time series from local files and clip to AOI
#'
#' @param aoi sf polygon (Area of Interest)
#' @param files character vector of raster file paths (one per date)
#' @param dates Date vector (same length as files)
#'
#' @return A terra SpatRaster with one layer per date (names = dates)
#' @export
get_index_local <- function(aoi, files, dates) {

  if(!inherits(aoi, "sf")) stop("aoi must be an sf object.")
  if(length(files) == 0) stop("No files provided.")
  if(length(files)!= length(dates)) stop("files and dates must have same length.")
  if(any(!file.exists(files))) stop("Some file do not exist.")

  #read rasters (multi-layer SpatRaster)
  x <- terra::rast(files)

  #convert AOI to terra vector
  aoi_v <- terra::vect(aoi)

  #clip (crop = faster, mask = exact)
  x <- terra::crop(x, aoi_v)
  x <- terra::mask(x, aoi_v)

  #layer names = dates
  names(x) <- as.character(dates)

  x
}
