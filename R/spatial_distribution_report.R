# Suppress CMD CHECK notes for things that look like global vars
if (getRversion() >= "2.15.1")
  utils::globalVariables(c(
    "Cell ID",
    "Cell X Position", "Cell Y Position",
    "To X Position", "To Y Position",
    "x", "y"
    ))

#' Create a spatial distribution report.
#'
#' Creates an HTML report visualizing the location
#' and nearest-neighbor relations for cells of pairs of phenotypes
#' in a single field.
#'
#' A cell seg data file for the field is required. If a tissue segmentation
#' or composite image of the field
#' is available, it will be used as a background.
#'
#' The report is saved to the same directory as the input file.
#'
#' See the tutorial
#' [Selecting cells within a cell segmentation table](https://perkinelmer.github.io/phenoptr/articles/selecting_cells.html)
#'for more on
#' the use of `pairs` and `phenotype_rules`.
#'
#' @param cell_seg_path Path to a cell seg data file.
#' @param pairs A list of pairs of phenotypes. Each entry is a two-element
#'   vector. The report will contain one section for each pair showing the
#'   nearest neighbor relations between the two phenotypes.
#' @param colors A named list of phenotype colors to use when drawing
#'   the output.
#' @param phenotype_rules (Optional) A named list.
#'   Item names are phenotype names and must match entries in `pairs`.
#'   Item values are selectors for [select_rows].
#' @param output_path Optional, path to the output HTML file. If omitted,
#' output will be written to the directory containing `cell_seg_path`.
#' @param pixels_per_micron Conversion factor to microns
#'        (default 2 pixels/micron, the resolution of 20x MSI fields
#'        taken on Vectra Polaris and Vectra 3.).
#'        Set to NA to skip conversion.
#' @export
#' @family distance functions
#' @examples
#' \dontrun{
#' # This example creates a report in the current user's
#' # home or Document directory.
#'
#' cell_seg_path <- sample_cell_seg_path()
#'
#' pairs <- list(
#'   c("CK+", "CD8+"),
#'   c("CK+", "CD68+"))
#' colors <- c('CK+'="cyan", "CD68+"="magenta", "CD8+"="yellow")
#' out_path <- path.expand('~/spatial_distribution_report.html')
#'
#' spatial_distribution_report(cell_seg_path, pairs, colors,
#'   output_path=out_path)
#'
#' # This example extends the previous example to restrict tumor cells to
#' # only PDL1+ cells.
#' # Note that spatial_distribution_report uses read_cell_seg_table
#' # so units are removed from the expression column names.
#'
#' pairs <- list(
#'   c("CK+ PDL1+", "CD8+"),
#'   c("CK+ PDL1+", "CD68+"))
#' colors <- c("CK+ PDL1+"="cyan", "CD68+"="magenta", "CD8+"="yellow")
#' phenotype_rules <- list(
#'   "CK+ PDL1+"=list("CK+", ~`Entire Cell PDL1 (Opal 520) Mean`>3))
#'
#' spatial_distribution_report(cell_seg_path, pairs, colors, phenotype_rules,
#'   output_path=out_path)
#' }
#' @md
spatial_distribution_report <- function(cell_seg_path, pairs, colors,
                      phenotype_rules=NULL, output_path=NULL,
                      pixels_per_micron=getOption('phenoptr.pixels.per.micron')
                      ) {
  stopifnot(endsWith(cell_seg_path, '_cell_seg_data.txt'))
  if (!file.exists(cell_seg_path))
    stop(paste('File not found:', cell_seg_path))

  # Make phenotype_rules for any not already specified
  phenotypes = unique(do.call(c, pairs))
  phenotype_rules = make_phenotype_rules(phenotypes, phenotype_rules)

  stopifnot(length(colors)==length(phenotypes),
            all(phenotypes %in% names(colors)))

  if (is.null(output_path))
    output_path = sub('_cell_seg_data.txt',
                      '_spatial_distribution.html', cell_seg_path)
  rmd_path = system.file("rmd", "SpatialDistributionReport.Rmd",
                         package="phenoptr")

  rmarkdown::render(rmd_path, 'html_document', output_path)
}

## Helpers
## Note these are not exported and the doc comments are not roxygen
### Spatial functions ###

# Get a point pattern for a single phenotype
# @param data Cell seg data
# @param pheno List of (name, color, select)
# @param window spatstat::owin containing the points
# @return List of (data subset, ppp, pheno)
phenotype_as_ppp = function(data, pheno, window)
{
  # Keep just the rows corresponding to the desired expression and phenotypes
  # for our data and columns containing fields of interest
  fixedColumns = c('Cell ID', 'Cell X Position', 'Cell Y Position', 'Phenotype')
  data = data[select_rows(data, pheno$select),fixedColumns]

  data = stats::na.omit(data)

  # Convert to point pattern objects. Guess the dimensions...
  pp = with(data, spatstat::ppp(`Cell X Position`, `Cell Y Position`,
                              window=window,
                              marks=factor(rep(pheno$name, nrow(data)))))
  list(data=data, pp=pp, pheno=pheno)
}

# Compute nearest neighbor distance between positively expressing phenotypes.
# @param pheno_data1 Data for the 'from' phenotype.
# @param pheno_data2 Data for the 'from' phenotype.
# @return A data.frame showing ID and location of from and to points
# with the distance between them.
# @importFrom magrittr "%>%"
find_nearest_neighbor = function(pheno_data1, pheno_data2)
{
  d = spatstat::nncross(pheno_data1$pp, pheno_data2$pp)
  names(d)[1] = 'Distance'
  from_data = pheno_data1$data %>%
    dplyr::select(`Cell ID`, `Cell X Position`, `Cell Y Position`)
  to_data = pheno_data2$data[d$which,] %>%
    dplyr::select('To Cell ID'=`Cell ID`,
                  'To X Position'=`Cell X Position`,
                  'To Y Position'=`Cell Y Position`)
  result = cbind(from_data, d, to_data)
  result$which = NULL
  result
}

### Point plots ###

# Make a plot of all points in pheno_data with lines to nearest neighbors
# as defined by nn_dist
# @param pheno_data result of a call to getPhenotypes
# @param nn_dist result of a call to find_nearest_neighbor
# @param lineColor color for the connecting lines
# @return a ggplot object
nn_plot <- function (pheno_data1, pheno_data2, nn_dist,
                     background, xlim, ylim,
                     line_color='gray40') {
  title = bquote('Nearest neighbor from'
                 ~ italic(.(pheno_data1$pheno$name))
                 ~ 'to'
                 ~ italic(.(pheno_data2$pheno$name)))
  nn_plot_impl(nn_dist, pheno_data1, pheno_data2, title,
               background, xlim, ylim,
               line_color)
}

# Make a plot of mutual nearest neighbors in phenoData -
# points for which each is the NN of the other
nn_plot_mutual = function(pheno_data1, pheno_data2, nn_mutual,
                          background, xlim, ylim,
                          line_color='gray40') {
  title = bquote('Mutual nearest neighbors for'
                 ~ italic(.(pheno_data1$pheno$name))
                 ~ 'and'
                 ~ italic(.(pheno_data2$pheno$name)))
  nn_plot_impl(nn_mutual, pheno_data1, pheno_data2, title,
               background, xlim, ylim, line_color)
}

# Shared implementation for nearest-neighbor plots
nn_plot_impl <- function (nn_dist, pheno_data1, pheno_data2, title,
                          background, xlim, ylim,
                          lineColor) {
  p = nn_plot_base(title, background, xlim, ylim)
  p = add_dist_data(p, nn_dist, lineColor)

  # Draw non-paired cells fainter than paired cells
  alphas = c(0.3, 1)
  from_alpha = alphas[(pheno_data1$data$`Cell ID` %in% nn_dist$`Cell ID`) + 1]
  p = p + geom_point(data=pheno_data1$data,
                     aes(x=`Cell X Position`, y=`Cell Y Position`),
                     color=pheno_data1$pheno$color, alpha=from_alpha)

  to_alpha = alphas[(pheno_data2$data$`Cell ID` %in% nn_dist$`To Cell ID`) + 1]
  p = p + geom_point(data=pheno_data2$data,
                     aes(`Cell X Position`, `Cell Y Position`),
                     color=pheno_data2$pheno$color, alpha=to_alpha)
  p
}

#' @import ggplot2
nn_plot_base = function(title, background, xlim, ylim) {
  # Fake d.f needed to get background to draw...
  p = ggplot(data=data.frame(x=0, y=0), aes(x=x, y=y))
  p = p + labs(x='Cell X Position', y='Cell Y Position', title=title)
  add_scales_and_background(p, background, xlim, ylim)
}

# Add line segments according to nn_dist
#' @import ggplot2
add_dist_data = function(p, nn_dist, lineColor) {
  if (nrow(nn_dist) > 0) {
    p = p + geom_segment(data = nn_dist,
                         aes(x=`Cell X Position`,
                             y=`Cell Y Position`,
                             xend=`To X Position`,
                             yend=`To Y Position`),
                         color=lineColor)
  }
  p
}

# Add scales, scale line and background image to a ggplot object
#' @import ggplot2
add_scales_and_background = function(p, background, xlim, ylim) {
  # Add scales at the image limits. Reverse the y scale to match the image
  p = p + scale_x_continuous(limits=c(0, xlim)) +
    scale_y_reverse(limits=c(ylim, 0))

  # Force square aspect ratio
  p = p + coord_fixed()

  # Add background image if we have one
  if (length(background) > 1)
  {
    p = p + annotation_raster(background, xmin=0, xmax=xlim, ymin=0, ymax=-ylim)
  }

  # Add a 200-micron line segment for scale reference
  p = p + geom_segment(aes(x=xlim-50-200, xend=xlim-50,
                           y=ylim-100, yend=ylim-100),
                       color='black', size=1)
  p = p + geom_text(aes(x=xlim-50-200/2, y=ylim-90, label=paste(200, '~mu*m')),
                    size=3, hjust=0.5, vjust=1, color='black', parse=TRUE)
  p
}
