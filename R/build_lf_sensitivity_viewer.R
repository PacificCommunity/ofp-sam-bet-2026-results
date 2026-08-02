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
expected_models <- suppressWarnings(as.integer(env(
  "RESULTS_VIEWER_EXPECTED_MODELS",
  env("RESULTS_NATIVE_PAYLOAD_EXPECTED_MODELS", "36")
)))
if (!is.finite(expected_models) || expected_models < 1L) expected_models <- 36L
expected_lf_models <- suppressWarnings(as.integer(env(
  "LF_SENSITIVITY_EXPECTED_MODELS",
  ""
)))
if (!is.finite(expected_lf_models) || expected_lf_models < 1L) {
  expected_lf_models <- NA_integer_
}

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
if (!is.data.frame(summary)) summary <- data.frame()
if (is.finite(expected_lf_models) && nrow(summary) != expected_lf_models) {
  stop(
    "Expected ", expected_lf_models, " LF sensitivity summary rows, found ",
    nrow(summary), ".",
    call. = FALSE
  )
}
has_lf_summary <- nrow(summary) > 0L

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
  tables = as.integer(has_lf_summary),
  table_files = as.integer(has_lf_summary),
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
  file = "../overview/interactive-model-viewer.html",
  purpose = "offline interactive model viewer",
  stringsAsFactors = FALSE
)
if (has_lf_summary) {
  ready_files <- rbind(
    data.frame(
      file = "../overview/lf-conflict-sensitivity-summary.html",
      purpose = "interactive LF sensitivity and Hessian summary",
      stringsAsFactors = FALSE
    ),
    ready_files,
    data.frame(
      file = "../tables/lf-conflict-sensitivity-summary.csv",
      purpose = "LF sensitivity and Hessian summary table",
      stringsAsFactors = FALSE
    )
  )
}
utils::write.csv(
  ready_files,
  file.path(out_dir, "report-ready", "report-ready-files.csv"),
  row.names = FALSE
)

landing_page <- if (has_lf_summary) {
  "overview/lf-conflict-sensitivity-summary.html"
} else {
  "overview/interactive-model-viewer.html"
}
landing_label <- if (has_lf_summary) {
  "Open the LF sensitivity results."
} else {
  "Open the interactive model viewer."
}
writeLines(
  c(
    "<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    paste0("<meta http-equiv='refresh' content='0; url=", landing_page, "'>"),
    paste0("<title>", lf_html_escape(viewer_title), "</title></head><body>"),
    paste0("<p><a href='", landing_page, "'>", landing_label, "</a></p>"),
    "</body></html>"
  ),
  file.path(out_dir, "index.html"),
  useBytes = TRUE
)
readme_lines <- c(
  paste0("# ", viewer_title),
  "",
  paste0("Start with `index.html` or `", landing_page, "`."),
  "The full offline model viewer is `overview/interactive-model-viewer.html`."
)
if (has_lf_summary) {
  readme_lines <- c(
    readme_lines,
    "The Hessian table is `tables/lf-conflict-sensitivity-summary.csv`."
  )
}
writeLines(
  readme_lines,
  file.path(out_dir, "README.md"),
  useBytes = TRUE
)

message(
  "Wrote the interactive Results viewer for ",
  nrow(payload_index),
  " models",
  if (has_lf_summary) " with an LF sensitivity summary." else "."
)
