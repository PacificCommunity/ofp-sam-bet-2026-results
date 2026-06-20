#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUTPUT_DIR:-outputs}"
INPUT_DIR="${INPUT_DIR:-inputs}"
ROOT="$(pwd)"

runtime_packages_disabled() {
  case "${KFLOW_RUNTIME_PACKAGES:-}" in
    ""|0|false|FALSE|no|NO|off|OFF|none|NONE|skip|SKIP) return 0 ;;
    *) return 1 ;;
  esac
}

runtime_updates_disabled() {
  case "${KFLOW_RUNTIME_UPDATE:-auto}" in
    ""|0|false|FALSE|no|NO|off|OFF|none|NONE|skip|SKIP|never|NEVER) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_runtime_library() {
  local preferred="${R_LIBS_USER:-${KFLOW_RUNTIME_LIBRARY:-}}"
  local fallback="${ROOT}/.R-library"
  if [[ -z "$preferred" ]]; then
    preferred="$fallback"
  fi
  if mkdir -p "$preferred" 2>/dev/null && [[ -w "$preferred" ]]; then
    export R_LIBS_USER="$preferred"
  else
    export R_LIBS_USER="$fallback"
    mkdir -p "$R_LIBS_USER"
  fi
  export KFLOW_RUNTIME_LIBRARY="$R_LIBS_USER"
  export KFLOW_RUNTIME_STATE_DIR="${KFLOW_RUNTIME_STATE_DIR:-${ROOT}/.kflow-runtime-cache}"
  mkdir -p "$KFLOW_RUNTIME_STATE_DIR" 2>/dev/null || true
}

runtime_private_packages_required() {
  case "${KFLOW_RUNTIME_REQUIRE_PRIVATE_PACKAGES:-false}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

drop_runtime_tokens() {
  unset GIT_PAT GITHUB_PAT GH_TOKEN KFLOW_GITHUB_TOKEN KFLOW_PERSONAL_TOKEN
}

install_missing_runtime_packages() {
  runtime_packages_disabled && return 0
  runtime_updates_disabled && return 0
  ensure_runtime_library
  Rscript - <<'RS'
truthy <- function(value) tolower(value) %in% c("1", "true", "yes", "y", "on", "always")
spec_text <- Sys.getenv("KFLOW_RUNTIME_PACKAGES", "")
parts <- trimws(strsplit(spec_text, ",", fixed = TRUE)[[1]])
parts <- parts[nzchar(parts) & grepl("=", parts, fixed = TRUE)]
if (!length(parts)) quit(save = "no", status = 0)
specs <- lapply(parts, function(part) {
  eq <- regexpr("=", part, fixed = TRUE)[1]
  package <- trimws(substr(part, 1, eq - 1))
  repo_ref <- trimws(substr(part, eq + 1, nchar(part)))
  at <- regexpr("@", repo_ref, fixed = TRUE)[1]
  if (at > 0) {
    repo <- substr(repo_ref, 1, at - 1)
    ref <- substr(repo_ref, at + 1, nchar(repo_ref))
  } else {
    repo <- repo_ref
    ref <- "main"
  }
  list(package = package, repo = repo, ref = ref)
})
lib <- Sys.getenv("R_LIBS_USER", "")
if (!nzchar(lib)) quit(save = "no", status = 43)
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(lib, .libPaths())))
missing <- specs[!vapply(specs, function(spec) requireNamespace(spec$package, quietly = TRUE), logical(1))]
if (!length(missing)) quit(save = "no", status = 0)
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!requireNamespace("remotes", quietly = TRUE)) {
  utils::install.packages("remotes", lib = lib, dependencies = TRUE, repos = getOption("repos"))
}
token <- ""
for (name in c("GITHUB_PAT", "GIT_PAT", "GH_TOKEN", "KFLOW_GITHUB_TOKEN", "KFLOW_PERSONAL_TOKEN")) {
  value <- Sys.getenv(name, "")
  if (nzchar(value)) {
    token <- value
    break
  }
}
for (spec in missing) {
  message("[kflow-runtime-update] Installing missing runtime package ", spec$package, " from ", spec$repo, "@", spec$ref, ".")
  err <- tryCatch({
    remotes::install_github(
      spec$repo,
      ref = spec$ref,
      auth_token = if (nzchar(token)) token else NULL,
      lib = lib,
      upgrade = "never",
      force = TRUE,
      quiet = TRUE
    )
    NULL
  }, error = function(e) e)
  if (inherits(err, "error")) {
    message("[kflow-runtime-update] Runtime package install failed for ", spec$package, ": ", conditionMessage(err))
  }
}
missing_after <- specs[!vapply(specs, function(spec) requireNamespace(spec$package, quietly = TRUE), logical(1))]
if (length(missing_after) && truthy(Sys.getenv("KFLOW_RUNTIME_REQUIRE_PRIVATE_PACKAGES", "false"))) {
  message("[kflow-runtime-update] Required runtime package(s) unavailable: ",
          paste(vapply(missing_after, function(spec) spec$package, character(1)), collapse = ", "))
  quit(save = "no", status = 44)
}
quit(save = "no", status = 0)
RS
}

prepare_runtime_packages() {
  if [[ -n "${TUNA_FLOW_RUNTIME_UPDATE:-}" ]]; then
    export KFLOW_RUNTIME_UPDATE="${TUNA_FLOW_RUNTIME_UPDATE}"
  fi
  runtime_packages_disabled && return 0
  ensure_runtime_library
  if [[ -x /usr/local/bin/30-update-kflow-runtime-packages ]]; then
    if bash /usr/local/bin/30-update-kflow-runtime-packages; then
      :
    else
      update_status=$?
      if runtime_private_packages_required || [[ "$update_status" -eq 42 || "$update_status" -eq 43 ]]; then
        exit "$update_status"
      fi
      echo "[kflow-runtime-update] Runtime package update failed; continuing with bundled packages." >&2
    fi
  else
    echo "[kflow-runtime-update] Runtime updater not found; using bundled packages." >&2
  fi
  install_missing_runtime_packages
  drop_runtime_tokens
}

mkdir -p "${OUT_DIR}" "${INPUT_DIR}"

echo "BET results task"
echo "Input directory: ${INPUT_DIR}"
echo "Output directory: ${OUT_DIR}"

prepare_runtime_packages
Rscript R/build_plots.R
