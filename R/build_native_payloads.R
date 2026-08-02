input_dir <- Sys.getenv("INPUT_DIR", "inputs")
output_dir <- Sys.getenv("OUTPUT_DIR", "outputs")
expected_models <- suppressWarnings(as.integer(Sys.getenv(
  "RESULTS_NATIVE_PAYLOAD_EXPECTED_MODELS",
  "0"
)))

if (!dir.exists(input_dir)) {
  stop("Native payload input directory does not exist: ", input_dir, call. = FALSE)
}
if (!requireNamespace("mfclshiny", quietly = TRUE)) {
  stop("mfclshiny is required to build native input payloads.", call. = FALSE)
}

final_pars <- sort(unique(list.files(
  input_dir,
  pattern = "^final[.]par$",
  recursive = TRUE,
  full.names = TRUE
)))
model_dirs <- sort(unique(dirname(final_pars)))
payload_root <- file.path(input_dir, "native-payloads")

safe_slug <- function(value, fallback) {
  value <- tolower(trimws(as.character(value)))
  value <- gsub("[^a-z0-9.]+", "-", value)
  value <- gsub("^-+|-+$", "", value)
  if (!nzchar(value)) fallback else value
}

model_metadata <- function(model_dir) {
  candidates <- c("sensitivity-metadata.csv", "ensemble-metadata.csv")
  for (filename in candidates) {
    path <- file.path(model_dir, filename)
    if (!file.exists(path)) next
    out <- tryCatch(
      utils::read.csv(path, stringsAsFactors = FALSE),
      error = function(error) NULL
    )
    if (!is.data.frame(out) || !nrow(out)) next
    return(list(
      values = as.list(out[1L, , drop = FALSE]),
      source = filename
    ))
  }
  list(values = list(), source = "")
}

first_text <- function(value, fallback = "") {
  value <- as.character(value)
  if (!length(value) || is.na(value[[1L]]) || !nzchar(trimws(value[[1L]]))) fallback else trimws(value[[1L]])
}

first_metadata_text <- function(metadata, fields, fallback = "") {
  for (field in fields) {
    value <- metadata[[field]]
    text <- first_text(value, "")
    if (nzchar(text)) return(text)
  }
  fallback
}

label_payload <- function(payload_file, payload_dir, label, key) {
  payload <- readRDS(payload_file)
  if (!is.list(payload$data)) payload$data <- list()
  if (!is.list(payload$data$info)) payload$data$info <- list()
  registry <- payload$data$info$registry
  if (!is.list(registry)) registry <- list()
  registry$model_label <- label
  registry$plot_label <- label
  registry$model_token <- key
  registry$job_key <- key
  payload$data$info$registry <- registry
  payload$folder <- payload_dir
  saveRDS(payload, payload_file, compress = "xz")
  mfclshiny::write_model_payload_manifest(
    payload = payload,
    folder = payload_dir,
    payload_file = payload_file
  )
  invisible(payload_file)
}

if (!length(model_dirs)) {
  stop("No native MFCL model folders containing final.par were found.", call. = FALSE)
}
if (is.finite(expected_models) && expected_models > 0L && length(model_dirs) != expected_models) {
  stop(
    "Expected ", expected_models, " native MFCL model folders, found ",
    length(model_dirs), ".",
    call. = FALSE
  )
}

rows <- lapply(model_dirs, function(model_dir) {
  metadata_record <- model_metadata(model_dir)
  metadata <- metadata_record$values
  key <- first_metadata_text(
    metadata,
    c("key", "ensemble_id", "job_key", "model"),
    basename(model_dir)
  )
  label <- first_metadata_text(
    metadata,
    c("label", "model_label", "plot_label"),
    basename(model_dir)
  )
  # Completed sensitivity archives produced before the Lorenzen terminology
  # correction retain the legacy key/label. Normalize presentation metadata
  # only; fitted inputs and outputs are never changed here.
  key <- sub("^m-scaler-", "lorenzen-m-scalar-", key)
  label <- sub("^M scaler ", "Lorenzen M scalar ", label)
  payload_dir <- file.path(payload_root, safe_slug(label, basename(model_dir)))
  dir.create(payload_dir, recursive = TRUE, showWarnings = FALSE)
  payload_file <- file.path(payload_dir, "model_payload.rds")
  status <- "existing"
  detail <- ""
  if (!file.exists(payload_file)) {
    status <- tryCatch(
      {
        mfclshiny::build_model_payload(
          model_dir,
          output_file = payload_file,
          overwrite = TRUE,
          recursive = FALSE,
          object_cache = Sys.getenv("MFCLSHINY_PAYLOAD_OBJECT_CACHE", "all"),
          artifacts = Sys.getenv("MFCLSHINY_PAYLOAD_ARTIFACTS", "core")
        )
        if (!file.exists(payload_file)) {
          stop("model_payload.rds was not created", call. = FALSE)
        }
        label_payload(payload_file, payload_dir, label, key)
        "built"
      },
      error = function(error) {
        detail <<- conditionMessage(error)
        "failed"
      }
    )
  }
  data.frame(
    model = key,
    model_label = label,
    metadata_source = metadata_record$source,
    model_dir = normalizePath(model_dir, winslash = "/", mustWork = FALSE),
    payload_dir = normalizePath(payload_dir, winslash = "/", mustWork = FALSE),
    payload_file = normalizePath(payload_file, winslash = "/", mustWork = FALSE),
    status = status,
    detail = detail,
    stringsAsFactors = FALSE
  )
})

index <- do.call(rbind, rows)
dir.create(file.path(output_dir, "indices"), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  index,
  file.path(output_dir, "indices", "native-payload-index.csv"),
  row.names = FALSE
)

failed <- index$status == "failed" | !file.exists(index$payload_file)
if (any(failed)) {
  stop(
    "Native payload generation failed for: ",
    paste(index$model[failed], collapse = ", "),
    call. = FALSE
  )
}

message(
  "Prepared ", nrow(index), " native MFCL payload(s): ",
  sum(index$status == "built"), " built, ",
  sum(index$status == "existing"), " existing."
)
