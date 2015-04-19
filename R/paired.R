################################################################################
#' Merge paired forward and reverse reads after DADA denoising.
#' 
#' This function takes the output of dada() and the map from read to unique index
#' returned by derepFastq()$map for both the forward and reverse data set. It attempts
#' to merge each pair of reads, rejecting any which do not perfectly overlap.
#' Note: This function assumes that the fastq files for the forward and reverse reads
#' were in the same order.
#' 
#' @param dadaF (Required). Output of dada() function.
#'  The output list returned by the dada() function on the forward reads.
#' 
#' @param mapF (Required). An integer vector map from read index to unique index.
#'  The map returned by derepFastq() for the forward reads.
#'   
#' @param dadaR (Required). Output of dada() function.
#'  The output list returned by the dada() function on the reverse reads.
#' 
#' @param mapR (Required). An integer vector map from read index to unique index.
#'  The map returned by derepFastq() for the reverse reads.
#'
#' @param minOverlap (Optional). A \code{numeric(1)} of the minimum overlap
#'  required for merging the forward and reverse reads. Default is 20.
#'
#' @return Dataframe.
#'  $forward: The index of the forward denoised sequence.
#'  $reverse: The index of the reverse denoised sequence.
#'  $match: TRUE if a perfect match between the forward and reverse denoised sequences of at least MIN_OVERLAP.
#'          FALSE otherwise.
#'  $abundance: Number of reads corresponding to this forward/reverse combination.
#'  $sequence: The merged sequence if match=TRUE. Otherwise an empty sequence, i.e. "";
#'
#' @seealso \code{\link{derepFastq}}, \code{\link{dada}}
#'
#' @export
#' @import Biostrings 
#' 
mergePairs <- function(dadaF, mapF, dadaR, mapR, minOverlap = 20) {
  rF <- dadaF$map[mapF]
  rR <- dadaR$map[mapR]
  if(any(is.na(rF)) || any(is.na(rR))) stop("Non-corresponding maps and dada-outputs.")
  
  pairdf <- data.frame(forward=rF, reverse=rR)
  ups <- unique(pairdf) # The unique forward/reverse pairs of denoised sequences
  Funqseq <- unname(dadaF$clustering$sequence[ups$forward])
  Runqseq <- as(reverseComplement(DNAStringSet(unname(dadaR$clustering$sequence[ups$reverse]))), "character")
  
  Fstart <- mapply(function(x,y) gregexpr(x,y)[[1]], subseq(Runqseq,1,minOverlap), Funqseq, SIMPLIFY=FALSE)
  # Returns a list of integer vectors, which may be -1 (no match), length1 and positive (1 match) or len>1 (multiple matches)
  # Make that a flat vector
  Fstarts <- c(Fstart, recursive=TRUE)
  # Record which pair each match corresponds to
  pairs <- rep(seq(length(Funqseq)), times=sapply(Fstart, length))
  # And get the start/end of the overlap subseqs for each
  Fstarts[Fstarts==-1] <- 1
  Fends <- nchar(Funqseq[pairs])
  Rstarts <- rep(1, length(Fstarts))
  Rends <- Rstarts + Fends - Fstarts
  Rends[Rends > nchar(Runqseq[pairs])] <- nchar(Runqseq[pairs])[Rends > nchar(Runqseq[pairs])]
  
  # Determine what matches
  matches <- mapply(function(x,y) x==y, subseq(Funqseq[pairs], Fstarts, Fends), subseq(Runqseq[pairs], Rstarts, Rends))

  # Take the first match in each pair set (which should be the longest overlap), or the first non-match if no match
  mat <- unname(cbind(pairs, matches, Fstarts, Fends, Rstarts, Rends))
  mat <- mat[!duplicated(mat[,c(1,2)]),] # drop duplicates in pairs/match (ASSUMES earlier matches are first and preferred)
  fmat <- mat[mat[,2]==1,] # Take those that were paired
  fmat <- rbind(fmat, mat[!mat[,1] %in% fmat[,1],]) # Add those that weren't
  fmat <- fmat[order(fmat[,1]),] # And put it in order

  ups$match <- as.logical(fmat[,2])

  # Add abundance and sequence to the output data.frame
  tab <- table(pairdf$forward, pairdf$reverse)
  ups$abundance <- tab[cbind(ups$forward, ups$reverse)]
  ups$sequence <- paste0(Funqseq, subseq(Runqseq,fmat[,6]+1,nchar(Runqseq))) ## WHAT IS SEQ WHEN !MATCH??
  ups$sequence[!ups$match] <- ""
  rownames(ups) <- paste0("s", ups$forward, "_", ups$reverse)
  ups
}



