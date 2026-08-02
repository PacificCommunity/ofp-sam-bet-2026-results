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
  payload_file <- file.path(model_dir, "model_payload.rds")
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
        "built"
      },
      error = function(error) {
        detail <<- conditionMessage(error)
        "failed"
      }
    )
  }
  data.frame(
    model = basename(model_dir),
    model_dir = normalizePath(model_dir, winslash = "/", mustWork = FALSE),
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
