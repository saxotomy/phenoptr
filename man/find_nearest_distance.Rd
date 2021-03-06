% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/distance_funcs.R
\name{find_nearest_distance}
\alias{find_nearest_distance}
\title{Nearest neighbor distances for each cell and phenotype.}
\usage{
find_nearest_distance(csd, phenotypes = NULL)
}
\arguments{
\item{csd}{A data frame with \code{Cell X Position},
\code{Cell Y Position} and \code{Phenotype} columns,
such as the result of calling
\link{read_cell_seg_data}.}

\item{phenotypes}{Optional list of phenotypes to include. If omitted,
\code{unique(csd$Phenotype)} will be used.}
}
\value{
A \code{data_frame} containing a \code{Distance to <phenotype>} column
for each phenotype. Will contain \code{NA} values where there is no other cell
of the phenotype.
}
\description{
For each cell in a single sample,
find the distances from
the cell to the nearest neighbor cells in each of the provided phenotypes.
}
\examples{
# Compute distance columns
csd <- sample_cell_seg_data
nearest <- find_nearest_distance(csd)
dplyr::glimpse(nearest)

# Make a combined data frame including original data and distance columns
csd <- cbind(csd, find_nearest_distance(csd))

\dontrun{
# If `merged` is a data frame containing cell seg data from multiple fields,
# this code will create a new `data_frame` with distance columns computed
# for each `Sample Name` in the data.
merged_with_distance <- merged \%>\%
  dplyr::group_by(`Sample Name`) \%>\%
  dplyr::do(dplyr::bind_cols(., find_nearest_distance(.)))
}
}
\seealso{
\link{compute_all_nearest_distance} which applies this function to a
(possibly merged) data file.

Other distance functions: \code{\link{compute_all_nearest_distance}},
  \code{\link{count_touching_cells}},
  \code{\link{count_within_batch}},
  \code{\link{count_within}},
  \code{\link{distance_matrix}},
  \code{\link{spatial_distribution_report}},
  \code{\link{subset_distance_matrix}}
}
\concept{distance functions}
