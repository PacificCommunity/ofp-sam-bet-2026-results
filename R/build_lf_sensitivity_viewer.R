Sys.setenv(BUILD_PLOTS_DEFINITIONS_ONLY = "true")
source("R/build_plots.R", local = FALSE)
Sys.unsetenv("BUILD_PLOTS_DEFINITIONS_ONLY")
source("R/lf_sensitivity_summary.R", local = FALSE)

input_dir <- env("INPUT_DIR", "inputs")
out_dir <- env("OUTPUT_DIR", "outputs")
title <- env("PLOT_TITLE", "BET 2026 LF conflict sensitivity results")
viewer_title <- env(
  "MFCLSHINY_INTERACTIVE_VIEWER_TITLE",
  "BET 2026 LF conflict sensitivity viewer"
)
expected_models <- suppressWarnings(as.integer(env("LF_SENSITIVITY_EXPECTED_MODELS", "36")))
if (!is.finite(expected_models) || expected_models < 1L) expected_models <- 36L

for (folder in c("overview", "tables", "indices", "logs", "report-ready")) {
  dir.create(file.path(out_dir, folder), recursive = TRUE, showWarnings = FALSE)
}

payload_index <- payloads(input_dir)
if (nrow(payload_index) != expected_models) {
  stop(
    "Expected ", expected_models, " unique model payloads, found ",
    nrow(payload_index), ".",
    call. = FALSE
  )
}
write_payload_index(payload_index, out_dir)

summary <- write_lf_sensitivity_summary(payload_index, out_dir)
if (!is.data.frame(summary) || nrow(summary) != expected_models) {
  stop(
    "Expected ", expected_models, " LF sensitivity summary rows, found ",
    if (is.data.frame(summary)) nrow(summary) else 0L, ".",
    call. = FALSE
  )
}

interactive_viewer <- write_interactive_model_viewer_output(
  input_dir,
  payload_index,
  out_dir,
  title,
  viewer_title = viewer_title
)
if (!is.data.frame(interactive_viewer) || !nrow(interactive_viewer)) {
  stop("The offline interactive model viewer was not created.", call. = FALSE)
}
viewer_html <- paste(
  readLines(interactive_viewer$path[[1L]], warn = FALSE, encoding = "UTF-8"),
  collapse = "\n"
)
if (!grepl('"key"\\s*:\\s*"key_quantities"', viewer_html, perl = TRUE)) {
  stop(
    "The offline interactive model viewer does not contain key quantities.",
    call. = FALSE
  )
}

plot_summary <- data.frame(
  payloads = nrow(payload_index),
  figures = 0L,
  figure_files = 0L,
  tables = 1L,
  table_files = 1L,
  build_errors = 0L,
  html = TRUE,
  source = "lf_sensitivity_viewer_only",
  stringsAsFactors = FALSE
)
utils::write.csv(
  plot_summary,
  file.path(out_dir, "indices", "plot-summary.csv"),
  row.names = FALSE
)

ready_files <- data.frame(
  file = c(
    "../overview/lf-conflict-sensitivity-summary.html",
    "../overview/interactive-model-viewer.html",
    "../tables/lf-conflict-sensitivity-summary.csv"
  ),
  purpose = c(
    "interactive LF sensitivity and Hessian summary",
    "offline interactive model viewer",
    "LF sensitivity and Hessian summary table"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  ready_files,
  file.path(out_dir, "report-ready", "report-ready-files.csv"),
  row.names = FALSE
)

writeLines(
  c(
    "<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    "<meta http-equiv='refresh' content='0; url=overview/lf-conflict-sensitivity-summary.html'>",
    "<title>BET 2026 LF conflict sensitivity results</title></head><body>",
    "<p><a href='overview/lf-conflict-sensitivity-summary.html'>Open the LF sensitivity results.</a></p>",
    "</body></html>"
  ),
  file.path(out_dir, "index.html"),
  useBytes = TRUE
)
writeLines(
  c(
    "# BET 2026 LF conflict sensitivity results",
    "",
    "Start with `index.html` or `overview/lf-conflict-sensitivity-summary.html`.",
    "The Hessian table is `tables/lf-conflict-sensitivity-summary.csv`.",
    "The full offline model viewer is `overview/interactive-model-viewer.html`."
  ),
  file.path(out_dir, "README.md"),
  useBytes = TRUE
)

message(
  "Wrote the lightweight LF sensitivity Results viewer for ",
  nrow(payload_index),
  " models."
)
