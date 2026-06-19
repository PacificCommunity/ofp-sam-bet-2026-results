`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

env <- function(name, default = "") {
  value <- Sys.getenv(name, unset = NA_character_)
  if (is.na(value) || !nzchar(value)) default else value
}

truthy_env <- function(name, default = TRUE) {
  value <- env(name, if (isTRUE(default)) "true" else "false")
  tolower(value) %in% c("1", "true", "yes", "y", "on", "always")
}

first_text <- function(x, default = "") {
  value <- tryCatch(as.character(x), error = function(e) character())
  if (!length(value) || is.na(value[[1L]]) || !nzchar(value[[1L]])) default else value[[1L]]
}

bind_rows_fill <- function(rows) {
  rows <- rows[vapply(rows, function(x) is.data.frame(x) && nrow(x), logical(1))]
  if (!length(rows)) return(data.frame(stringsAsFactors = FALSE))
  cols <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(x) {
    missing <- setdiff(cols, names(x))
    for (name in missing) x[[name]] <- NA
    x[, cols, drop = FALSE]
  })
  do.call(rbind, rows)
}

call_with_supported_args <- function(fun, args) {
  supported <- names(formals(fun))
  if (!"..." %in% supported) {
    args <- args[names(args) %in% supported]
  }
  do.call(fun, args)
}

payload_label <- function(payload, fallback) {
  reg <- tryCatch(payload$data$info$registry, error = function(e) NULL)
  info <- tryCatch(payload$data$info, error = function(e) NULL)
  for (name in c("plot_label", "model_label", "model_token", "job_key")) {
    value <- first_text(tryCatch(reg[[name]], error = function(e) NULL))
    if (nzchar(value)) return(value)
  }
  for (name in c("plot_label", "model_label", "model_token", "job_key")) {
    value <- first_text(tryCatch(info[[name]], error = function(e) NULL))
    if (nzchar(value)) return(value)
  }
  fallback
}

payloads <- function(input_dir) {
  files <- list.files(input_dir, pattern = "^model_payload[.]rds$", recursive = TRUE, full.names = TRUE)
  rows <- lapply(files, function(file) {
    payload <- tryCatch(readRDS(file), error = function(e) NULL)
    if (is.null(payload)) return(NULL)
    folder <- dirname(file)
    data.frame(
      model_label = payload_label(payload, basename(folder)),
      model_folder = normalizePath(folder, winslash = "/", mustWork = FALSE),
      payload_file = normalizePath(file, winslash = "/", mustWork = FALSE),
      stringsAsFactors = FALSE
    )
  })
  bind_rows_fill(rows)
}

write_payload_index <- function(payload_index, output_dir) {
  table_dir <- file.path(output_dir, "tables")
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(payload_index, file.path(table_dir, "payload-index.csv"), row.names = FALSE)
  utils::write.csv(payload_index, file.path(output_dir, "payload-index.csv"), row.names = FALSE)
  invisible(payload_index)
}

write_plot_summary <- function(result, payload_index, output_dir) {
  figure_index <- result$figures %||% data.frame()
  table_index <- result$tables %||% data.frame()
  summary <- data.frame(
    payloads = nrow(payload_index),
    figures = if (nrow(figure_index)) length(unique(figure_index$figure)) else 0L,
    figure_files = nrow(figure_index),
    tables = if (nrow(table_index)) length(unique(table_index$table)) else 0L,
    table_files = nrow(table_index),
    build_errors = if (is.data.frame(result$log)) sum(result$log$status == "error", na.rm = TRUE) else NA_integer_,
    html = file.exists(file.path(output_dir, "plot-report.html")),
    source = "mfclshiny_shiny_registry",
    stringsAsFactors = FALSE
  )
  utils::write.csv(summary, file.path(output_dir, "plot-summary.csv"), row.names = FALSE)
  invisible(summary)
}

organize_review_outputs <- function(output_dir,
                                    html_file = "plot-report.html",
                                    qmd_file = "plot-report.qmd") {
  review_dir <- file.path(output_dir, "_review")
  dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)
  copied <- character()
  for (file in c(html_file, qmd_file, "mfclshiny-report-files.csv", "plot-summary.csv", "figure-optimization.csv")) {
    source <- file.path(output_dir, file)
    if (!file.exists(source)) next
    target <- file.path(review_dir, basename(file))
    file.copy(source, target, overwrite = TRUE)
    copied <- c(copied, target)
  }
  readme <- file.path(review_dir, "README.txt")
  writeLines(
    c(
      "BET plot review outputs",
      "",
      "Open plot-report.html first when reviewing this Kflow plot job.",
      "The full figure bundle remains under ../figures and table outputs under ../tables.",
      "",
      paste("Files copied:", length(copied))
    ),
    readme
  )
  invisible(data.frame(
    file = basename(c(copied, readme)),
    path = normalizePath(c(copied, readme), winslash = "/", mustWork = FALSE),
    stringsAsFactors = FALSE
  ))
}

short_error <- function(x) {
  x <- as.character(x %||% "")
  x <- trimws(paste(x, collapse = " "))
  if (!nzchar(x)) "unknown error" else substr(x, 1L, 240L)
}

empty_optimization_log <- function() {
  data.frame(
    file = character(),
    original_bytes = numeric(),
    optimized_bytes = numeric(),
    candidate_bytes = numeric(),
    saved_bytes = numeric(),
    optimized = logical(),
    method = character(),
    webp_file = character(),
    webp_bytes = numeric(),
    webp_saved_bytes = numeric(),
    webp_created = logical(),
    pdf_file = character(),
    pdf_bytes = numeric(),
    pdf_saved_bytes = numeric(),
    pdf_created = logical(),
    reason = character(),
    stringsAsFactors = FALSE
  )
}

pngquant_quality <- function(value = env("PLOT_PNGQUANT_QUALITY", "60-85")) {
  value <- trimws(as.character(value %||% "60-85"))
  if (!grepl("^[0-9]{1,3}-[0-9]{1,3}$", value)) {
    return("60-85")
  }
  parts <- suppressWarnings(as.integer(strsplit(value, "-", fixed = TRUE)[[1]]))
  if (length(parts) != 2L || any(!is.finite(parts)) || any(parts < 0L) || any(parts > 100L) || parts[[1]] > parts[[2]]) {
    return("60-85")
  }
  value
}

webp_quality <- function(value = env("PLOT_WEBP_QUALITY", "72")) {
  value <- suppressWarnings(as.numeric(value))
  if (!is.finite(value) || value < 1 || value > 100) 72 else value
}

jpeg_quality <- function(value = env("PLOT_JPEG_QUALITY", "82")) {
  value <- suppressWarnings(as.numeric(value))
  if (!is.finite(value) || value < 1 || value > 100) 82 else value
}

jpeg_sampling_factor <- function(value = env("PLOT_JPEG_SAMPLING_FACTOR", "4:2:0")) {
  value <- trimws(as.character(value %||% "4:2:0"))
  if (value %in% c("4:4:4", "4:2:2", "4:2:0")) value else "4:2:0"
}

pngquant_speed <- function(value = env("PLOT_PNGQUANT_SPEED", "1")) {
  value <- suppressWarnings(as.integer(value))
  if (!is.finite(value) || value < 1L || value > 11L) 1L else value
}

optimizer_mode <- function(value = env("PLOT_OPTIMIZE_MODE", "lossy")) {
  value <- tolower(trimws(as.character(value %||% "lossy")))
  value <- gsub("[^a-z0-9]+", "-", value)
  aliases <- c(
    lossy = "lossy",
    pngquant = "lossy",
    small = "lossy",
    max = "lossy",
    lossless = "lossless",
    imagemagick = "lossless",
    convert = "lossless",
    off = "none",
    none = "none",
    false = "none",
    "0" = "none"
  )
  if (value %in% names(aliases)) aliases[[value]] else "lossy"
}

replace_if_smaller <- function(file, tmp, before, row, method, reason) {
  candidate_bytes <- suppressWarnings(file.info(tmp)$size)
  if (!is.finite(candidate_bytes) || candidate_bytes <= 0) {
    return(row(FALSE, method, candidate_bytes, "optimizer produced an empty file"))
  }
  if (candidate_bytes >= before) {
    return(row(FALSE, method, candidate_bytes, "already optimal or candidate larger"))
  }
  ok <- file.copy(tmp, file, overwrite = TRUE)
  if (!isTRUE(ok)) {
    return(row(FALSE, method, candidate_bytes, "could not replace original file"))
  }
  row(TRUE, method, candidate_bytes, reason)
}

optimize_png_file <- function(file,
                              output_dir,
                              mode = optimizer_mode(),
                              quality = pngquant_quality(),
                              pngquant_bin = Sys.which("pngquant"),
                              convert_bin = Sys.which("convert")) {
  root <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  full_file <- normalizePath(file, winslash = "/", mustWork = FALSE)
  rel_file <- if (startsWith(full_file, paste0(root, "/"))) {
    substr(full_file, nchar(root) + 2L, nchar(full_file))
  } else {
    basename(full_file)
  }
  before <- suppressWarnings(file.info(file)$size)
  row <- function(optimized, method, candidate_bytes, reason) {
    after <- if (isTRUE(optimized)) candidate_bytes else before
    data.frame(
      file = rel_file,
      original_bytes = before,
      optimized_bytes = after,
      candidate_bytes = candidate_bytes,
      saved_bytes = if (isTRUE(optimized)) before - after else 0,
      optimized = isTRUE(optimized),
      method = method,
      reason = reason,
      stringsAsFactors = FALSE
    )
  }
  if (!is.finite(before) || before <= 0) {
    return(row(FALSE, "none", NA_real_, "missing or empty file"))
  }

  mode <- optimizer_mode(mode)
  if (identical(mode, "none")) {
    return(row(FALSE, "none", NA_real_, "optimization disabled"))
  }

  tmp <- tempfile(pattern = paste0(tools::file_path_sans_ext(basename(file)), "-"), fileext = ".png")
  on.exit(unlink(tmp), add = TRUE)

  if (identical(mode, "lossy") && nzchar(pngquant_bin)) {
    args <- c(
      "--force",
      "--strip",
      "--speed", as.character(pngquant_speed()),
      "--quality", quality,
      "--output", tmp,
      normalizePath(file, winslash = "/", mustWork = TRUE)
    )
    output <- tryCatch(
      system2(pngquant_bin, args, stdout = TRUE, stderr = TRUE),
      error = function(e) structure(conditionMessage(e), status = 1L)
    )
    status <- attr(output, "status") %||% 0L
    if (identical(as.integer(status), 0L) && file.exists(tmp)) {
      return(replace_if_smaller(file, tmp, before, row, "pngquant", paste0("lossy PNG quality ", quality)))
    }
    pngquant_message <- short_error(output)
  } else {
    pngquant_message <- "pngquant unavailable"
  }

  if (nzchar(convert_bin)) {
    unlink(tmp)
    input <- normalizePath(file, winslash = "/", mustWork = TRUE)
    args <- if (identical(mode, "lossy")) {
      c(input, "-strip", "-colors", "256", paste0("PNG8:", tmp))
    } else {
      c(
        input,
        "-strip",
        "-define", "png:compression-level=9",
        "-define", "png:compression-filter=5",
        "-define", "png:compression-strategy=1",
        tmp
      )
    }
    output <- tryCatch(
      system2(convert_bin, args, stdout = TRUE, stderr = TRUE),
      error = function(e) structure(conditionMessage(e), status = 1L)
    )
    status <- attr(output, "status") %||% 0L
    if (!identical(as.integer(status), 0L) || !file.exists(tmp)) {
      return(row(FALSE, "imagemagick", NA_real_, short_error(output)))
    }
    method <- if (identical(mode, "lossy")) "imagemagick-png8" else "imagemagick"
    reason <- if (identical(mode, "lossy")) "lossy PNG8 palette fallback" else "lossless PNG strip/recompress"
    return(replace_if_smaller(file, tmp, before, row, method, reason))
  }

  row(FALSE, "none", NA_real_, paste("pngquant/ImageMagick unavailable:", pngquant_message))
}

create_webp_file <- function(file,
                             output_dir,
                             quality = webp_quality(),
                             cwebp_bin = Sys.which("cwebp")) {
  root <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  full_file <- normalizePath(file, winslash = "/", mustWork = FALSE)
  rel_file <- if (startsWith(full_file, paste0(root, "/"))) {
    substr(full_file, nchar(root) + 2L, nchar(full_file))
  } else {
    basename(full_file)
  }
  target <- sub("[.][Pp][Nn][Gg]$", ".webp", file)
  rel_target <- sub("[.][Pp][Nn][Gg]$", ".webp", rel_file)
  before <- suppressWarnings(file.info(file)$size)
  row <- function(created, bytes, reason) {
    data.frame(
      file = rel_file,
      webp_file = rel_target,
      webp_bytes = bytes,
      webp_saved_bytes = if (isTRUE(created) && is.finite(before)) before - bytes else 0,
      webp_created = isTRUE(created),
      webp_reason = reason,
      stringsAsFactors = FALSE
    )
  }
  if (!is.finite(before) || before <= 0) {
    return(row(FALSE, NA_real_, "missing or empty PNG source"))
  }
  if (!nzchar(cwebp_bin)) {
    return(row(FALSE, NA_real_, "cwebp unavailable"))
  }
  tmp <- tempfile(pattern = paste0(tools::file_path_sans_ext(basename(file)), "-"), fileext = ".webp")
  on.exit(unlink(tmp), add = TRUE)
  args <- c(
    "-quiet",
    "-preset", "drawing",
    "-q", as.character(quality),
    "-m", "6",
    "-mt",
    "-sharp_yuv",
    normalizePath(file, winslash = "/", mustWork = TRUE),
    "-o", tmp
  )
  output <- tryCatch(
    system2(cwebp_bin, args, stdout = TRUE, stderr = TRUE),
    error = function(e) structure(conditionMessage(e), status = 1L)
  )
  status <- attr(output, "status") %||% 0L
  if (!identical(as.integer(status), 0L) || !file.exists(tmp)) {
    return(row(FALSE, NA_real_, short_error(output)))
  }
  candidate_bytes <- suppressWarnings(file.info(tmp)$size)
  if (!is.finite(candidate_bytes) || candidate_bytes <= 0) {
    return(row(FALSE, candidate_bytes, "cwebp produced an empty file"))
  }
  if (candidate_bytes >= before) {
    unlink(target)
    return(row(FALSE, candidate_bytes, "WebP candidate larger than PNG"))
  }
  ok <- file.copy(tmp, target, overwrite = TRUE)
  if (!isTRUE(ok)) {
    return(row(FALSE, candidate_bytes, "could not write WebP file"))
  }
  row(TRUE, candidate_bytes, paste0("WebP quality ", quality))
}

create_pdf_jpeg_file <- function(file,
                                 output_dir,
                                 quality = jpeg_quality(),
                                 sampling_factor = jpeg_sampling_factor(),
                                 convert_bin = Sys.which("convert")) {
  root <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  full_file <- normalizePath(file, winslash = "/", mustWork = FALSE)
  rel_file <- if (startsWith(full_file, paste0(root, "/"))) {
    substr(full_file, nchar(root) + 2L, nchar(full_file))
  } else {
    basename(full_file)
  }
  target <- sub("[.][Pp][Nn][Gg]$", ".jpg", file)
  rel_target <- sub("[.][Pp][Nn][Gg]$", ".jpg", rel_file)
  before <- suppressWarnings(file.info(file)$size)
  row <- function(created, bytes, reason) {
    data.frame(
      file = rel_file,
      pdf_file = rel_target,
      pdf_bytes = bytes,
      pdf_saved_bytes = if (isTRUE(created) && is.finite(before)) before - bytes else 0,
      pdf_created = isTRUE(created),
      pdf_reason = reason,
      stringsAsFactors = FALSE
    )
  }
  if (!is.finite(before) || before <= 0) {
    return(row(FALSE, NA_real_, "missing or empty PNG source"))
  }
  if (!nzchar(convert_bin)) {
    return(row(FALSE, NA_real_, "ImageMagick convert unavailable"))
  }
  tmp <- tempfile(pattern = paste0(tools::file_path_sans_ext(basename(file)), "-"), fileext = ".jpg")
  on.exit(unlink(tmp), add = TRUE)
  args <- c(
    normalizePath(file, winslash = "/", mustWork = TRUE),
    "-background", "white",
    "-alpha", "remove",
    "-alpha", "off",
    "-strip",
    "-interlace", "Plane",
    "-sampling-factor", sampling_factor,
    "-quality", as.character(quality),
    tmp
  )
  output <- tryCatch(
    system2(convert_bin, args, stdout = TRUE, stderr = TRUE),
    error = function(e) structure(conditionMessage(e), status = 1L)
  )
  status <- attr(output, "status") %||% 0L
  if (!identical(as.integer(status), 0L) || !file.exists(tmp)) {
    return(row(FALSE, NA_real_, short_error(output)))
  }
  candidate_bytes <- suppressWarnings(file.info(tmp)$size)
  if (!is.finite(candidate_bytes) || candidate_bytes <= 0) {
    return(row(FALSE, candidate_bytes, "JPEG conversion produced an empty file"))
  }
  if (candidate_bytes >= before) {
    unlink(target)
    return(row(FALSE, candidate_bytes, "JPEG candidate larger than PNG"))
  }
  ok <- file.copy(tmp, target, overwrite = TRUE)
  if (!isTRUE(ok)) {
    return(row(FALSE, candidate_bytes, "could not write JPEG file"))
  }
  row(TRUE, candidate_bytes, paste0("JPEG quality ", quality, ", sampling ", sampling_factor))
}

optimize_plot_figures <- function(output_dir, enabled = TRUE) {
  log_file <- file.path(output_dir, "figure-optimization.csv")
  if (!isTRUE(enabled)) {
    result <- empty_optimization_log()
    utils::write.csv(result, log_file, row.names = FALSE)
    message("Figure optimization disabled; wrote empty figure-optimization.csv.")
    return(result)
  }

  figure_dir <- file.path(output_dir, "figures")
  files <- if (dir.exists(figure_dir)) {
    list.files(figure_dir, pattern = "[.]png$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  } else {
    character()
  }
  if (!length(files)) {
    result <- empty_optimization_log()
    utils::write.csv(result, log_file, row.names = FALSE)
    message("No PNG report figures found for optimization.")
    return(result)
  }

  mode <- optimizer_mode()
  quality <- pngquant_quality()
  webp_enabled <- truthy_env("PLOT_WEBP_FIGURES", TRUE)
  pdf_jpeg_enabled <- truthy_env("PLOT_PDF_JPEG_FIGURES", TRUE)
  webp_q <- webp_quality()
  jpeg_q <- jpeg_quality()
  jpeg_sampling <- jpeg_sampling_factor()
  pngquant_bin <- Sys.which("pngquant")
  convert_bin <- Sys.which("convert")
  png_rows <- lapply(
    files,
    optimize_png_file,
    output_dir = output_dir,
    mode = mode,
    quality = quality,
    pngquant_bin = pngquant_bin,
    convert_bin = convert_bin
  )
  png_result <- bind_rows_fill(png_rows)
  if (isTRUE(webp_enabled)) {
    webp_rows <- lapply(files, create_webp_file, output_dir = output_dir, quality = webp_q, cwebp_bin = Sys.which("cwebp"))
    webp_result <- bind_rows_fill(webp_rows)
    result <- merge(png_result, webp_result, by = "file", all = TRUE, sort = FALSE)
  } else {
    webp_result <- empty_optimization_log()
    result <- png_result
    result$webp_file <- ""
    result$webp_bytes <- NA_real_
    result$webp_saved_bytes <- 0
    result$webp_created <- FALSE
    result$webp_reason <- "WebP disabled"
  }
  if (isTRUE(pdf_jpeg_enabled)) {
    jpeg_rows <- lapply(
      files,
      create_pdf_jpeg_file,
      output_dir = output_dir,
      quality = jpeg_q,
      sampling_factor = jpeg_sampling,
      convert_bin = convert_bin
    )
    jpeg_result <- bind_rows_fill(jpeg_rows)
    result <- merge(result, jpeg_result, by = "file", all = TRUE, sort = FALSE)
  } else {
    result$pdf_file <- ""
    result$pdf_bytes <- NA_real_
    result$pdf_saved_bytes <- 0
    result$pdf_created <- FALSE
    result$pdf_reason <- "PDF JPEG disabled"
  }
  utils::write.csv(result, log_file, row.names = FALSE)
  saved <- sum(result$saved_bytes, na.rm = TRUE)
  optimized <- sum(result$optimized, na.rm = TRUE)
  webp_saved <- sum(result$webp_saved_bytes, na.rm = TRUE)
  webp_created <- sum(result$webp_created, na.rm = TRUE)
  pdf_saved <- sum(result$pdf_saved_bytes, na.rm = TRUE)
  pdf_created <- sum(result$pdf_created, na.rm = TRUE)
  message(
    "Optimized ", optimized, " PNG figure(s); saved ",
    format(round(saved / 1024 / 1024, 2), nsmall = 2), " MB using ",
    mode, " mode. Created ", webp_created, " WebP sidecar(s); HTML can save ",
    format(round(webp_saved / 1024 / 1024, 2), nsmall = 2), " MB. Created ",
    pdf_created, " PDF JPEG sidecar(s); PDF can save ",
    format(round(pdf_saved / 1024 / 1024, 2), nsmall = 2), " MB."
  )
  invisible(result)
}

input_dir <- env("INPUT_DIR", "inputs")
out_dir <- env("OUTPUT_DIR", "outputs")
title <- env("PLOT_TITLE", "BET 2026 report-ready figures")
species_code <- env("FLOW_SPECIES", "BET")
species_label <- env("FLOW_SPECIES_LABEL", "bigeye tuna")
assessment_year <- env("FLOW_ASSESSMENT_YEAR", "2026")
optimize_figures <- truthy_env("PLOT_OPTIMIZE_FIGURES", TRUE)
max_fisheries <- suppressWarnings(as.integer(env("PLOT_MAX_FISHERIES", "18")))
if (!is.finite(max_fisheries) || max_fisheries < 1L) max_fisheries <- 18L

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

payload_index <- payloads(input_dir)
if (!nrow(payload_index)) {
  stop("No model_payload.rds files found in upstream inputs.", call. = FALSE)
}
write_payload_index(payload_index, out_dir)

if (!requireNamespace("mfclshiny", quietly = TRUE) ||
    !"build_app_report_figures" %in% getNamespaceExports("mfclshiny")) {
  stop("mfclshiny::build_app_report_figures is required for BET plot export.", call. = FALSE)
}

message("Building BET plots with mfclshiny Shiny report registry.")
message("Payloads: ", nrow(payload_index))
message("Output: ", normalizePath(out_dir, winslash = "/", mustWork = FALSE))

result <- call_with_supported_args(
  mfclshiny::build_app_report_figures,
  list(
    model_dir = input_dir,
    folders = payload_index$model_folder,
    output_dir = out_dir,
    title = title,
    formats = "png",
    build_payloads = FALSE,
    overwrite = TRUE,
    render_html = TRUE,
    qmd_file = "plot-report.qmd",
    html_file = "plot-report.html",
    figure_dir = "figures",
    table_dir = "tables",
    copy_legacy_root = FALSE,
    species_code = species_code,
    species_label = species_label,
    assessment_year = assessment_year,
    max_fisheries = max_fisheries
  )
)

if (is.null(result) || !is.data.frame(result$figures) || !nrow(result$figures)) {
  stop("mfclshiny Shiny registry export produced no report-ready figures.", call. = FALSE)
}

write_plot_summary(result, payload_index, out_dir)
optimize_plot_figures(out_dir, enabled = optimize_figures)
organize_review_outputs(out_dir)

message("Wrote ", length(unique(result$figures$figure)), " report-ready mfclshiny figure(s).")
if (is.data.frame(result$log) && any(result$log$status == "error", na.rm = TRUE)) {
  message("Some registered plots failed; see mfclshiny-figure-build-log.csv.")
}
