# Writes the release's records after build.R: each package's version,
# licence, exact source (with its SHA-256) and WebAssembly binary, each
# group's image and members, how and where it was built, the component
# licences, and release notes. Copies every publishable file into dist/.
#
#   Rscript scripts/manifest.R <release tag>
#
# The workflow passes the image digest, commit and run address through the
# environment: MIRROR_IMAGE, GITHUB_SHA, GITHUB_SERVER_URL,
# GITHUB_REPOSITORY and GITHUB_RUN_ID.

tag <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(tag) || !nzchar(tag)) stop("usage: Rscript scripts/manifest.R <release tag>")

pinned <- as.data.frame(read.dcf("packages.dcf"), stringsAsFactors = FALSE)
groups <- as.data.frame(read.dcf("groups.dcf"), stringsAsFactors = FALSE)
sources <- as.data.frame(read.dcf(file.path("build", "sources.dcf")), stringsAsFactors = FALSE)
membership <- readRDS(file.path("build", "membership.rds"))
index <- Sys.glob("repo/bin/emscripten/contrib/*/PACKAGES")
contrib <- dirname(index)
built <- read.dcf(index)
rownames(built) <- built[, "Package"]

sha256 <- function(path) sub("[[:space:]].*$", "", system2("sha256sum", shQuote(path), stdout = TRUE)[1])
asset <- function(path) list(name = basename(path), bytes = file.size(path), sha256 = sha256(path))
env <- function(name) { value <- Sys.getenv(name); if (nzchar(value)) value else NULL }
release_url <- function(name) {
  repo <- Sys.getenv("GITHUB_REPOSITORY", "Pragraph/thesisit-webr-mirror")
  sprintf("https://github.com/%s/releases/download/%s/%s", repo, tag, utils::URLencode(name, reserved = TRUE))
}

# Sources and binaries go out unchanged, beside the images.
file.copy(file.path("sources", sources$Asset), "dist", overwrite = TRUE)
binaries <- file.path(contrib, sprintf("%s_%s.tgz", pinned$Package, built[pinned$Package, "Version"]))
file.copy(binaries, "dist", overwrite = TRUE)
file.copy(index, file.path("dist", "PACKAGES"), overwrite = TRUE)

# The component licences: R's standard texts, and every licence file each
# package's own source carries.
licences <- file.path("build", "licenses")
unlink(licences, recursive = TRUE)
dir.create(file.path(licences, "R-share-licenses"), recursive = TRUE)
file.copy(list.files(file.path(R.home("share"), "licenses"), full.names = TRUE), file.path(licences, "R-share-licenses"))
for (i in seq_len(nrow(sources))) {
  p <- sources$Package[i]
  members <- utils::untar(file.path("sources", sources$Asset[i]), list = TRUE)
  wanted <- members[grepl("^[^/]+/(DESCRIPTION|LICEN[CS]E[^/]*|COPYING[^/]*|inst/(COPYRIGHTS|AUTHORS|LICEN[CS]E[^/]*))$", members)]
  into <- file.path(licences, "packages", p)
  dir.create(into, recursive = TRUE, showWarnings = FALSE)
  scratch <- tempfile()
  utils::untar(file.path("sources", sources$Asset[i]), files = wanted, exdir = scratch)
  for (member in wanted) file.copy(file.path(scratch, member), file.path(into, gsub("/", "__", sub("^[^/]+/", "", member))))
  unlink(scratch, recursive = TRUE)
}
old <- setwd("build")
utils::tar(file.path("..", "dist", "licenses.tar.gz"), files = "licenses", compression = "gzip", tar = "internal")
setwd(old)

emcc <- tryCatch(system2("emcc", "--version", stdout = TRUE)[1], error = function(e) NA_character_)
build <- list(
  image = env("MIRROR_IMAGE"),
  host_r = R.version.string,
  rwasm = as.character(packageVersion("rwasm")),
  emscripten = emcc,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  commit = env("GITHUB_SHA"),
  run = if (!is.null(env("GITHUB_RUN_ID"))) sprintf("%s/%s/actions/runs/%s", Sys.getenv("GITHUB_SERVER_URL"), Sys.getenv("GITHUB_REPOSITORY"), Sys.getenv("GITHUB_RUN_ID")) else NULL,
  host_build_dependencies = "rwasm installs each package's build-time dependencies into the container's native R from CRAN, as R CMD INSTALL needs them; they are not part of any WebAssembly output.",
  adjustments = list(
    "quadprog: rwasm's Makevars override replaced by PKG_LIBS = $(BLAS_LIBS), because its $(SAFE_FFLAGS) expands to host x86 flags that flang refuses (scripts/build.R).",
    "System requirements are not installed (PKG_SYSREQS=false): they serve the host's native R, never a WebAssembly binary."
  )
)

packages <- lapply(seq_len(nrow(pinned)), function(i) {
  p <- pinned$Package[i]
  s <- sources[sources$Package == p, ]
  bin <- file.path("dist", sprintf("%s_%s.tgz", p, built[p, "Version"]))
  list(
    package = p,
    version = pinned$Version[i],
    license = pinned$License[i],
    source = list(
      from = if (identical(pinned$Source[i], "cran")) "cran" else pinned$Source[i],
      upstream_url = s$URL,
      asset = s$Asset,
      url = release_url(s$Asset),
      sha256 = s$SHA256,
      md5 = s$MD5
    ),
    note = if (!is.null(pinned$Note) && !is.na(pinned$Note[i])) pinned$Note[i] else NULL,
    binary = c(asset(bin), list(url = release_url(basename(bin)), built = unname(built[p, "Built"]))),
    groups = names(Filter(function(m) p %in% m, membership))
  )
})

images <- lapply(seq_len(nrow(groups)), function(i) {
  g <- groups$Group[i]
  data <- file.path("dist", paste0(g, ".data.gz"))
  meta <- file.path("dist", paste0(g, ".js.metadata"))
  list(
    group = g,
    purpose = groups$Purpose[i],
    roots = trimws(strsplit(groups$Roots[i], ",")[[1]]),
    packages = membership[[g]],
    data = c(asset(data), list(url = release_url(basename(data)))),
    metadata = c(asset(meta), list(url = release_url(basename(meta))))
  )
})

manifest <- list(
  mirror = "thesisit-webr-mirror",
  release = tag,
  runtime = list(webr = "0.6.0", r = "4.6.0"),
  build = build,
  groups = images,
  packages = packages
)
jsonlite::write_json(manifest, file.path("dist", "manifest.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)

lines <- c(
  sprintf("# %s", tag),
  "",
  "WebAssembly builds of R packages for webR 0.6.0 (R 4.6.0), for Thesis-It's on-device analyses.",
  "",
  "Built in `ghcr.io/r-wasm/webr` pinned by digest, from the exact sources attached to this release. `manifest.json` lists every file with its SHA-256; `SHA256SUMS` repeats them.",
  "",
  "## Images",
  "",
  "| Group | Purpose | Packages | Data |",
  "| --- | --- | --- | --- |",
  vapply(images, function(x) sprintf("| %s | %s | %d | `%s` (%s bytes) |", x$group, x$purpose, length(x$packages), x$data$name, format(x$data$bytes, big.mark = ",")), ""),
  "",
  "## Packages",
  "",
  "| Package | Version | Licence | Source |",
  "| --- | --- | --- | --- |",
  vapply(packages, function(x) sprintf("| %s | %s | %s | %s |", x$package, x$version, x$license, if (identical(x$source$from, "cran")) "CRAN" else x$source$from), ""),
  "",
  "Each package keeps its own licence. Its source, unchanged, is attached as named above, and `licenses.tar.gz` holds the licence files every source carries with R's standard licence texts."
)
writeLines(lines, file.path("dist", "RELEASE_NOTES.md"))
message("manifest written for ", tag)
