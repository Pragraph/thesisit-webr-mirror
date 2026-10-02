# thesisit-webr-mirror

Pinned WebAssembly builds of the R packages behind Thesis-It's on-device analyses, for **webR 0.6.0 (R 4.6.0)**, with the exact sources they were built from.

Thesis-It runs statistics in the student's browser, inside a sandbox that never reaches the network. Each package that sandbox loads has to be a fixed, verifiable file served by Thesis-It itself. [repo.r-wasm.org](https://repo.r-wasm.org) is a rolling repository, so this mirror freezes the builds Thesis-It uses, one release at a time.

## What a release holds

| File | What it is |
| --- | --- |
| `<group>.data.gz`, `<group>.js.metadata` | An Emscripten filesystem image of one group's packages and their runtime dependencies, mountable by webR. |
| `<package>_<version>.tgz` | Each package's WebAssembly binary, as a CRAN-like repository would serve it, and `PACKAGES`, its index. |
| `<package>_<version>.tar.gz` | Each package's exact source, unchanged: from CRAN, or from a webR fork at a pinned commit. |
| `licenses.tar.gz` | The licence files each source carries, with R's standard licence texts. |
| `manifest.json` | Every package's version, licence, source and binary with SHA-256 checksums, every group's members and image, and how the release was built. |
| `SHA256SUMS` | The checksum of every file in the release. |
| `build-log.txt` | The build's full log. |

## Groups

| Group | For | Roots |
| --- | --- | --- |
| `psych` | Exploratory factor analysis and omega reliability | psych, GPArotation |
| `lavaan` | Confirmatory factor analysis, mediation and moderation | lavaan |
| `plspm` | Partial least squares structural equation modelling | plspm |
| `haven` | Reading SPSS `.sav` files | haven |

`packages.dcf` pins all 42 packages and `groups.dcf` names the groups. Each image holds the closure of its roots' `Depends` and `Imports`, without R's base packages, which webR provides.

## How a release is built

`.github/workflows/build.yml`, run by hand with a tag such as `r4.6.0-webr0.6.0-1`:

1. **Sources.** `scripts/fetch-sources.R` downloads every source first, checking each CRAN file against CRAN's MD5:
   - each CRAN package at its pinned version;
   - two webR forks at pinned commits, which webR's maintainers patched for WebAssembly:
     - **`r-wasm/mnormt`:** Fortran COMMON blocks rewritten as a module for LLVM flang;
     - **`r-wasm/vroom`:** `std::async` deferred, as webR has no threads.
2. **Build.** `scripts/build.R` compiles exactly those files with `rwasm::add_pkg()`, inside `ghcr.io/r-wasm/webr:v0.6.0` pinned by digest. It does no substitution, so nothing drifts to a moving branch. It refuses a binary at any version but the pinned one, then packs each group's image with `rwasm::make_vfs_library()`, stripping documentation and tests.
3. **Records.** `scripts/manifest.R` writes the manifest, collects the licences and writes the release notes.
4. **Draft.** A second job, the only one with write access, checks every file against `SHA256SUMS` and creates a **draft** release. The build itself never holds a token.

A maintainer then downloads the draft and verifies each checksum, loads each image in webR 0.6.0 with a representative analysis, and publishes. This repository has release immutability on, so a published release's files and tag can never change. Releases are never deleted; a rebuild gets a new tag.

## Verifying a release yourself

```sh
TAG=r4.6.0-webr0.6.0-1
gh release download "$TAG" --repo Pragraph/thesisit-webr-mirror --dir "$TAG"
cd "$TAG" && sha256sum --check SHA256SUMS
```

Anyone can download the files without signing in, from `https://github.com/Pragraph/thesisit-webr-mirror/releases/download/<tag>/<file>`.

## Licences

Each package keeps its own licence. Its unchanged source is attached to the same release, and `licenses.tar.gz` carries its licence files. The licences are listed per package in `manifest.json` and in each release's notes. They are GPL-2 or GPL-3 in their R forms, MIT and Apache-2.0.

This repository's own files are MIT-licensed (`LICENSE`): the scripts, the workflow and this documentation.

## How Thesis-It uses it

Thesis-It's bundle lock names each image by its release URL and SHA-256. Its build fetches and checks the files, and its sandbox serves them only from that checked copy. The analysis sandbox mounts an image only when a method needs it, and R's own installers stay disabled there. No student data ever reaches this repository.
