isHit100 <- function(clust, fn) {
  bb <- read.table(fn, comment.char="#", col.names=c("seqid", "subject", "identity", "coverage", "mismatches", "gaps", "seq_start", "seq_end", "sub_start", "sub_end", "e", "score"))
  bbHit100 <- bb[bb$identity == 100 & bb$coverage == nchar(clust[match(bb$seqid,clust$id),"sequence"]),]
  return(clust$id %in% bbHit100$seqid)
}

isOneOff <- function(clust, fn) {
  hit <- isHit100(clust, fn)
  bball <- read.table(fn, comment.char="#", col.names=c("seqid", "subject", "identity", "coverage", "mismatches", "gaps", "seq_start", "seq_end", "sub_start", "sub_end", "e", "score"))
  bb <- bball[bball$coverage == nchar(clust[match(bball$seqid,clust$id),"sequence"]),] # Only full length hits
  tab <- tapply(bb$identity, bb$seqid, max)
  tab <- tab[match(clust$id, names(tab))]
  seqlens <- nchar(clust$sequence)
  oneOff <- tab<100 & (abs(tab - 100.0*(seqlens-1)/seqlens) < 0.01)
  oneOff[is.na(oneOff)] <- FALSE # happens if no hits were full coverage
  names(oneOff) <- clust$id # Also drop the name to NA so fix here
  # Also get coverage-1 matches
  # But still wont catch mismatches within the first or last couple of nts that cutoff more than 1 nt...
  bb <- bball[bball$coverage == nchar(clust[match(bball$seqid,clust$id),"sequence"])-1,] # Full length-1 hits
  bb <- bb[bb$identity==100,]
  oneOff <- oneOff | clust$id %in% bb$seqid
  # Make sure not a hit
  oneOff[hit] <- FALSE
  return(oneOff)
}

checkConvergence <- function(dadaO) {
  sapply(dadaO$err_in, function(x) sum(abs(dadaO$err_out-x)))
}

#' @export
nwalign <- function(s1, s2, score=getDadaOpt("SCORE_MATRIX"), gap=getDadaOpt("GAP_PENALTY"), band=getDadaOpt("BAND_SIZE")) {
  if(!is.character(s1) || !is.character(s2)) stop("Can only align character sequences.")
  if(nchar(s1) >= 1000 || nchar(s2) >= 1000) stop("Can only align strings up to 999 nts in length.")
  if(nchar(s1) != nchar(s2)) {
    if(band != -1) message("Sequences of unequal length must use unbanded alignment.")
    band = -1
  }
  C_nwalign(s1, s2, score, gap, band)
}

#' @export 
nwhamming <- Vectorize(function(s1, s2, ...) {
  al <- nwalign(s1, s2, ...)
  out <- dada2:::C_eval_pair(al[1], al[2])
  return(out["mismatch"]+out["indel"])
})

nweval <- Vectorize(function(s1, s2, ...) {
  al <- nwalign(s1, s2, ...)
  C_eval_pair(al[1], al[2])
})

strdiff <- function(s1, s2) {
  xx = unlist(strsplit(s1,""))
  yy = unlist(strsplit(s2,""))
  dd <- which(xx != yy)
  data.frame(pos=dd,nt0=xx[dd],nt1=yy[dd])
}

#' @export
rc <- Vectorize(function(x) as(reverseComplement(DNAString(x)), "character"))

#' @export
hamming <- Vectorize(function(x, y) nrow(strdiff(x, y)))

#' @export
#' @import ggplot2
#' @importFrom gridExtra grid.arrange
showSubPos <- function(subpos, ...) {
  subpos$pos <- seq(nrow(subpos))
  subpos <- subpos[1:match(0,subpos$nts)-1,]
  p <- ggplot(data=subpos, aes(x=pos))
  pA <- p + geom_line(aes(y=A2C/(1+A)), color="red") + geom_line(aes(y=A2G/(1+A)), color="orange") + geom_line(aes(y=A2T/(1+A)), color="blue") + ylab("Subs at As")
  pC <- p + geom_line(aes(y=C2A/(1+C)), color="grey") + geom_line(aes(y=C2G/(1+C)), color="orange") + geom_line(aes(y=C2T/(1+C)), color="blue") + ylab("Subs at Cs")
  pG <- p + geom_line(aes(y=G2A/(1+G)), color="grey") + geom_line(aes(y=G2C/(1+G)), color="red") + geom_line(aes(y=G2T/(1+G)), color="blue") + ylab("Subs at Gs")
  pT <- p + geom_line(aes(y=T2A/(1+T)), color="grey") + geom_line(aes(y=T2C/(1+T)), color="red") + geom_line(aes(y=T2G/(1+T)), color="orange") + ylab("Subs at Ts")
  pAll <- p + geom_line(aes(y=subs/nts)) + ylab("Sub rate (all nts)")
  grid.arrange(pAll, pAll, pA, pC, pG, pT, nrow=3, ...)
}

subseqUniques <- function(unqs, start, end) {
  subnms <- subseq(names(unqs), start, end)
  newNames <- unique(subnms)
  newUniques <- as.integer(rep(0,length(newNames)))
  names(newUniques) <- newNames
  for(i in seq(length(unqs))) {
    newnm <- subnms[[i]]
    newUniques[[newnm]] <- newUniques[[newnm]] + unqs[[i]]
  }
  newUniques[sapply(names(newUniques), function(nm) nchar(nm) == (end-start+1))]
}

mergeUniques <- function(unqsList, ...) {
  if(!is.list(unqsList) && length(list(...))>=1) {
    unqsList = list(unqsList, unlist(unname(list(...))))
  }
  concat <- c(unlist(unqsList))
  unqs <- unique(names(concat))
  mrg <- as.integer(rep(0, length(unqs)))
  names(mrg) <- unqs
  # Probably a better way to do this than for loop...
  for(i in seq(length(concat))) {
    unq <- names(concat)[[i]]
    mrg[[unq]] <- mrg[[unq]] + concat[[i]]
  }
  mrg
}

#' @export
as.uniques <- function(foo) {
  if(is.integer(foo) && length(names(foo)) != 0 && !any(is.na(names(foo)))) { # Named integer vector already
    return(foo)
  } else if(class(foo) == "dada") {  # dada return 
    return(foo$genotypes)
  } else if(class(foo) == "derep") {
    return(foo$uniques)
  } else if(is.data.frame(foo) && all(c("sequence", "abundance") %in% colnames(foo))) {
    unqs <- as.integer(foo$abundance)
    names(unqs) <- foo$sequence
    return(unqs)
  } else {
    stop("Unrecognized format: Requires named integer vector, dada, derep, or a data.frame with $sequence and $abundance columns.")
  }
}