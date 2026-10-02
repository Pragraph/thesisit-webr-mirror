# Builds every pinned component for webR from the sources fetched by
# fetch-sources.R, inside the webR toolchain's own container, then packs one
# Emscripten filesystem image per group: the group's packages and their
# runtime dependencies, nothing else.
#
#   Rscript scripts/build.R
#
# Reads packages.dcf, groups.dcf and build/sources.dcf. Writes repo/ (a
# CRAN-like repository of WebAssembly binaries) and dist/<group>.data.gz
# with dist/<group>.js.metadata.

pinned <- as.data.frame(read.dcf("packages.dcf"), stringsAsFactors = FALSE)
groups <- as.data.frame(read.dcf("groups.dcf"), stringsAsFactors = FALSE)
sources <- as.data.frame(read.dcf(file.path("build", "sources.dcf")), stringsAsFactors = FALSE)
base_packages <- c("R", rownames(installed.packages(priority = "base")))

# Every component is built from the exact file the release publishes. A CRAN
# package is a source tarball already; a fork's GitHub snapshot is unpacked
# and built as a local package directory.
refs <- vapply(seq_len(nrow(pinned)), function(i) {
  p <- pinned$Package[i]
  asset <- sources$Asset[sources$Package == p]
  path <- normalizePath(file.path("sources", asset))
  if (identical(pinned$Source[i], "cran")) return(paste0("local::", path))
  into <- file.path("build", "forks", p)
  unlink(into, recursive = TRUE)
  dir.create(into, recursive = TRUE)
  utils::untar(path, exdir = into)
  paste0("local::", normalizePath(list.dirs(into, recursive = FALSE)[1]))
}, character(1))

# remotes = NULL: no substitution. The two webR forks are pinned above by
# commit, so rwasm must not swap in its own moving branches.
rwasm::add_pkg(refs, repo_dir = "repo", remotes = NULL, dependencies = FALSE, compress = TRUE)

index <- Sys.glob("repo/bin/emscripten/contrib/*/PACKAGES")
if (length(index) != 1) stop("expected one binary repository, found ", length(index))
contrib <- dirname(index)
built <- read.dcf(index)
rownames(built) <- built[, "Package"]
missing <- setdiff(pinned$Package, rownames(built))
if (length(missing)) stop("not built: ", paste(missing, collapse = ", "))
wrong <- pinned$Package[built[pinned$Package, "Version"] != pinned$Version]
if (length(wrong)) stop("built at another version: ", paste(wrong, collapse = ", "))

closure <- function(roots) {
  deps <- tools::package_dependencies(roots, db = built, which = c("Depends", "Imports"), recursive = TRUE)
  sort(setdiff(unique(c(roots, unlist(deps))), base_packages))
}

strip <- c("demo", "doc", "examples", "help", "html", "include", "tests", "vignette", "vignettes")
dir.create("dist", showWarnings = FALSE)
membership <- list()
for (i in seq_len(nrow(groups))) {
  g <- groups$Group[i]
  roots <- trimws(strsplit(groups$Roots[i], ",")[[1]])
  members <- closure(roots)
  absent <- setdiff(members, rownames(built))
  if (length(absent)) stop(g, " needs packages the mirror does not pin: ", paste(absent, collapse = ", "))
  repo <- file.path("build", "groups", g)
  bin <- file.path(repo, "bin", "emscripten", "contrib", basename(contrib))
  unlink(repo, recursive = TRUE)
  dir.create(bin, recursive = TRUE)
  tgz <- file.path(contrib, sprintf("%s_%s.tgz", members, built[members, "Version"]))
  stopifnot(all(file.exists(tgz)))
  file.copy(tgz, bin)
  tools::write_PACKAGES(bin, type = "mac.binary", addFiles = FALSE)
  rwasm::make_vfs_library(out_dir = "dist", out_name = paste0(g, ".data"), repo_dir = repo, compress = TRUE, strip = strip)
  unlink(file.path("dist", paste0(g, ".data")))
  membership[[g]] <- members
  message(sprintf("%-7s %2d packages: %s", g, length(members), paste(members, collapse = " ")))
}
saveRDS(membership, file.path("build", "membership.rds"))
