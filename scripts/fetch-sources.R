# Downloads the exact source of every pinned component, before anything is
# built: a CRAN package from CRAN (its current file or its archive), a webR
# fork from GitHub at its pinned commit. The build compiles these files and
# nothing else, and the release publishes them unchanged, so the source a
# binary was built from is the source beside it.
#
#   Rscript scripts/fetch-sources.R
#
# Writes sources/<file> and build/sources.dcf (asset, URL, SHA-256, MD5).

options(timeout = 600)
cran <- "https://cloud.r-project.org"
pinned <- as.data.frame(read.dcf("packages.dcf"), stringsAsFactors = FALSE)
dir.create("sources", showWarnings = FALSE)
dir.create("build", showWarnings = FALSE)

sha256 <- function(path) {
  tool <- if (nzchar(Sys.which("sha256sum"))) c("sha256sum") else c("shasum", "-a", "256")
  out <- system2(tool[1], c(tool[-1], shQuote(path)), stdout = TRUE)
  sub("[[:space:]].*$", "", out[1])
}

current <- available.packages(repos = cran, fields = "MD5sum")
rows <- vector("list", nrow(pinned))
for (i in seq_len(nrow(pinned))) {
  p <- pinned$Package[i]
  v <- pinned$Version[i]
  source <- pinned$Source[i]
  if (identical(source, "cran")) {
    file <- sprintf("%s_%s.tar.gz", p, v)
    is_current <- p %in% rownames(current) && identical(unname(current[p, "Version"]), v)
    url <- if (is_current) {
      sprintf("%s/src/contrib/%s", cran, file)
    } else {
      sprintf("%s/src/contrib/Archive/%s/%s", cran, p, file)
    }
    expected_md5 <- if (is_current) unname(current[p, "MD5sum"]) else NA_character_
  } else {
    parts <- regmatches(source, regexec("^github::([^/]+)/([^@]+)@([0-9a-f]{40})$", source))[[1]]
    if (length(parts) != 4) stop("A fork must be pinned to a full commit: ", source)
    file <- sprintf("%s_%s_%s.tar.gz", p, v, substr(parts[4], 1, 12))
    url <- sprintf("https://codeload.github.com/%s/%s/tar.gz/%s", parts[2], parts[3], parts[4])
    expected_md5 <- NA_character_
  }
  path <- file.path("sources", file)
  if (!file.exists(path)) download.file(url, path, mode = "wb", quiet = TRUE)
  md5 <- unname(tools::md5sum(path))
  if (!is.na(expected_md5) && !identical(md5, expected_md5))
    stop(sprintf("%s: MD5 %s, CRAN says %s", file, md5, expected_md5))
  rows[[i]] <- c(Package = p, Version = v, Asset = file, URL = url, SHA256 = sha256(path), MD5 = md5)
  message(sprintf("%-12s %-12s %s", p, v, url))
}
write.dcf(do.call(rbind, rows), file.path("build", "sources.dcf"))
message(sprintf("%d sources fetched", length(rows)))
