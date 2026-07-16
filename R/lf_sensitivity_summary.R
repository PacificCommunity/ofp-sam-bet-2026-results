lf_html_escape <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

lf_first_value <- function(row, candidates, default = NA_character_) {
  for (candidate in candidates) {
    if (!candidate %in% names(row)) next
    value <- row[[candidate]]
    if (is.list(value)) value <- value[[1L]]
    if (length(value) && !all(is.na(value))) return(as.character(value[[1L]]))
  }
  default
}

lf_number <- function(x) {
  value <- suppressWarnings(as.numeric(x[[1L]] %||% NA_character_))
  if (!length(value) || !is.finite(value)) NA_real_ else value
}

lf_flag <- function(x) {
  tolower(trimws(as.character(x[[1L]] %||% ""))) %in% c("true", "t", "yes", "y", "1")
}

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || all(is.na(x))) y else x
}

lf_scenario_from_text <- function(x) {
  text <- paste(as.character(x), collapse = " ")
  match <- regexpr(
    "S[0-9]{3}-TC[0-9]+-(?:NOCUT|CUT[0-9]+)-DW[0-9]+",
    text,
    perl = TRUE
  )
  if (match[[1L]] < 0L) return(NA_character_)
  regmatches(text, match)[[1L]]
}

lf_model_folder <- function(row) {
  candidates <- c(
    "folder", "model_folder", "model_dir", "directory", "path",
    "payload_file", "payload_path", "payload"
  )
  for (candidate in candidates) {
    if (!candidate %in% names(row)) next
    value <- row[[candidate]]
    if (is.list(value)) value <- value[[1L]]
    value <- as.character(value[[1L]] %||% "")
    if (!nzchar(value)) next
    if (file.exists(value) && !dir.exists(value)) value <- dirname(value)
    if (dir.exists(value)) return(normalizePath(value, mustWork = FALSE))
  }
  NA_character_
}

lf_hessian_check_file <- function(folder) {
  if (is.na(folder) || !dir.exists(folder)) return(NA_character_)
  direct <- file.path(folder, "hessian", "check-summary.csv")
  if (file.exists(direct)) return(direct)
  candidates <- list.files(
    folder,
    pattern = "check-summary\\.csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  candidates <- candidates[
    grepl("[/\\\\]hessian[/\\\\]check-summary\\.csv$", candidates) &
      !grepl("[/\\\\]part_[^/\\\\]+[/\\\\]", candidates)
  ]
  if (!length(candidates)) NA_character_ else candidates[[1L]]
}

lf_read_hessian_check <- function(file) {
  if (is.na(file) || !file.exists(file)) return(NULL)
  data <- tryCatch(
    utils::read.csv(file, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(...) NULL
  )
  if (is.null(data) || !nrow(data)) return(NULL)
  if ("check_type" %in% names(data)) {
    selected <- which(tolower(data$check_type) == "hessian")
    if (length(selected)) data <- data[selected[[1L]], , drop = FALSE]
  }
  data[1L, , drop = FALSE]
}

lf_hessian_value <- function(check, field, default = NA_character_) {
  if (is.null(check) || !field %in% names(check)) return(default)
  value <- check[[field]][[1L]]
  if (is.null(value) || !length(value) || is.na(value)) default else as.character(value)
}

lf_sensitivity_row <- function(row) {
  folder <- lf_model_folder(row)
  scenario <- lf_scenario_from_text(c(unlist(row, recursive = TRUE), folder))
  if (is.na(scenario)) return(NULL)

  tokens <- regexec(
    "^S([0-9]{3})-TC([0-9]+)-(NOCUT|CUT([0-9]+))-DW([0-9]+)$",
    scenario,
    perl = TRUE
  )
  values <- regmatches(scenario, tokens)[[1L]]
  if (length(values) != 6L) return(NULL)

  check_file <- lf_hessian_check_file(folder)
  check <- lf_read_hessian_check(check_file)
  n_units <- lf_number(lf_hessian_value(check, "n_units"))
  n_success <- lf_number(lf_hessian_value(check, "n_success"))
  merge_status <- lf_hessian_value(check, "merge_status")
  all_required <- lf_flag(lf_hessian_value(check, "all_required_units_successful"))
  total_eigen <- lf_number(lf_hessian_value(check, "n_total_eigenvalues"))
  count_failure <- lf_hessian_value(check, "eigenvalue_counts_failure_reason", "")
  units_ok <- all_required || (
    is.finite(n_units) && n_units > 0 && is.finite(n_success) && n_success == n_units
  )
  merge_ok <- tolower(merge_status) %in% c("complete", "completed")
  counts_ok <- is.finite(total_eigen) && total_eigen > 0 && !nzchar(trimws(count_failure))
  hessian_complete <- !is.null(check) && units_ok && merge_ok && counts_ok

  negative <- lf_number(lf_hessian_value(check, "n_strictly_negative_eigenvalues"))
  if (!is.finite(negative)) {
    negative <- lf_number(lf_hessian_value(check, "n_negative_eigenvalues"))
  }

  data.frame(
    scenario = scenario,
    scenario_number = as.integer(values[[2L]]),
    tail_compression_percent = as.integer(values[[3L]]),
    cutoff_cm = if (values[[4L]] == "NOCUT") NA_integer_ else as.integer(values[[5L]]),
    lf_downweight_divisor = as.integer(values[[6L]]),
    hessian = if (hessian_complete) "Yes" else "No",
    hessian_status = lf_hessian_value(check, "hessian_status", "Not available"),
    hessian_reliability = lf_hessian_value(check, "hessian_reliability", "Not available"),
    negative_eigenvalues = negative,
    nonpositive_eigenvalues = lf_number(
      lf_hessian_value(check, "n_nonpositive_eigenvalues")
    ),
    total_eigenvalues = total_eigen,
    hessian_units_successful = n_success,
    hessian_units_total = n_units,
    hessian_merge_status = ifelse(nzchar(merge_status), merge_status, "Not available"),
    stringsAsFactors = FALSE
  )
}

lf_build_sensitivity_summary <- function(payload_index) {
  if (!is.data.frame(payload_index) || !nrow(payload_index)) return(data.frame())
  rows <- lapply(seq_len(nrow(payload_index)), function(index) {
    lf_sensitivity_row(payload_index[index, , drop = FALSE])
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())
  result <- do.call(rbind, rows)
  result <- result[order(result$scenario_number), , drop = FALSE]
  rownames(result) <- NULL
  result
}

lf_display_integer <- function(x) {
  ifelse(is.na(x), "--", format(as.integer(x), big.mark = ",", scientific = FALSE))
}

lf_summary_html <- function(summary) {
  complete <- sum(summary$hessian == "Yes", na.rm = TRUE)
  with_negative <- sum(summary$negative_eigenvalues > 0, na.rm = TRUE)
  total_negative <- sum(summary$negative_eigenvalues, na.rm = TRUE)
  row_html <- vapply(seq_len(nrow(summary)), function(index) {
    row <- summary[index, , drop = FALSE]
    cutoff <- if (is.na(row$cutoff_cm)) "None" else paste0(row$cutoff_cm, " cm")
    hessian_class <- if (row$hessian == "Yes") "ok" else "missing"
    negative_class <- if (!is.na(row$negative_eigenvalues) && row$negative_eigenvalues > 0) {
      "warn"
    } else {
      "ok"
    }
    paste0(
      "<tr data-tc='", row$tail_compression_percent,
      "' data-cut='", ifelse(is.na(row$cutoff_cm), "none", row$cutoff_cm),
      "' data-dw='", row$lf_downweight_divisor,
      "' data-hessian='", tolower(row$hessian), "'>",
      "<td data-sort='", row$scenario_number, "'><strong>",
      lf_html_escape(row$scenario), "</strong></td>",
      "<td data-sort='", row$tail_compression_percent, "'>",
      row$tail_compression_percent, "%</td>",
      "<td data-sort='", ifelse(is.na(row$cutoff_cm), -1, row$cutoff_cm), "'>",
      cutoff, "</td>",
      "<td data-sort='", row$lf_downweight_divisor, "'>",
      row$lf_downweight_divisor, "x</td>",
      "<td><span class='badge ", hessian_class, "'>", row$hessian, "</span></td>",
      "<td>", lf_html_escape(row$hessian_status), "</td>",
      "<td>", lf_html_escape(row$hessian_reliability), "</td>",
      "<td class='numeric' data-sort='", row$negative_eigenvalues %||% -1,
      "'><span class='badge ", negative_class, "'>",
      lf_display_integer(row$negative_eigenvalues), "</span></td>",
      "<td class='numeric' data-sort='", row$nonpositive_eigenvalues %||% -1, "'>",
      lf_display_integer(row$nonpositive_eigenvalues), "</td>",
      "<td class='numeric' data-sort='", row$total_eigenvalues %||% -1, "'>",
      lf_display_integer(row$total_eigenvalues), "</td>",
      "</tr>"
    )
  }, character(1L))

  c(
    "<!doctype html>",
    "<html lang='en'><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>BET 2026 LF conflict sensitivity results</title>",
    "<style>",
    ":root{--ink:#172026;--muted:#607078;--paper:#f4f1e8;--panel:#fffdf7;--line:#d7d2c4;--teal:#0c7468;--amber:#b66b16;--red:#a33b2b}",
    "*{box-sizing:border-box}body{margin:0;background:linear-gradient(145deg,#e8efe9 0,#f4f1e8 42%,#eee5d6 100%);color:var(--ink);font:15px/1.45 'Aptos','Segoe UI',sans-serif}",
    ".shell{max-width:1500px;margin:auto;padding:34px 28px 60px}.eyebrow{text-transform:uppercase;letter-spacing:.16em;color:var(--teal);font-weight:800;font-size:12px}",
    "h1{font:700 clamp(30px,4vw,54px)/1.03 Georgia,serif;margin:8px 0 10px;max-width:900px}.lede{color:var(--muted);max-width:850px;font-size:17px}",
    ".actions{display:flex;gap:10px;flex-wrap:wrap;margin:20px 0}.button{display:inline-block;padding:10px 14px;border-radius:8px;background:var(--ink);color:white;text-decoration:none;font-weight:700}.button.alt{background:var(--teal)}",
    ".cards{display:grid;grid-template-columns:repeat(4,minmax(140px,1fr));gap:12px;margin:22px 0}.card{background:rgba(255,253,247,.88);border:1px solid var(--line);border-radius:12px;padding:16px}.card b{display:block;font:700 28px/1 Georgia,serif;margin-bottom:5px}.card span{color:var(--muted)}",
    ".panel{background:var(--panel);border:1px solid var(--line);border-radius:14px;box-shadow:0 18px 48px rgba(36,47,43,.10);overflow:hidden}.filters{display:grid;grid-template-columns:2fr repeat(4,1fr);gap:10px;padding:14px;border-bottom:1px solid var(--line)}",
    "label{font-size:12px;font-weight:800;color:var(--muted);text-transform:uppercase;letter-spacing:.05em}input,select{display:block;width:100%;margin-top:5px;padding:9px 10px;border:1px solid var(--line);border-radius:7px;background:white;color:var(--ink)}",
    ".table-wrap{overflow:auto;max-height:70vh}table{border-collapse:collapse;width:100%;min-width:1050px}th{position:sticky;top:0;background:#243138;color:white;text-align:left;padding:11px 10px;cursor:pointer;white-space:nowrap}td{padding:10px;border-bottom:1px solid #ebe6da;white-space:nowrap}tbody tr:hover{background:#f1f7f4}.numeric{text-align:right}",
    ".badge{display:inline-block;min-width:42px;text-align:center;border-radius:999px;padding:3px 8px;font-weight:800}.badge.ok{background:#dcefe8;color:#176253}.badge.warn{background:#fff0d7;color:#8a500f}.badge.missing{background:#f4ded9;color:#8c3024}",
    ".foot{display:flex;justify-content:space-between;gap:15px;color:var(--muted);font-size:13px;padding:12px 15px}.hidden{display:none}@media(max-width:850px){.shell{padding:22px 12px}.cards{grid-template-columns:repeat(2,1fr)}.filters{grid-template-columns:1fr 1fr}.filters .search{grid-column:1/-1}}",
    "</style></head><body><main class='shell'>",
    "<div class='eyebrow'>MULTIFAN-CL sensitivity review</div>",
    "<h1>BET 2026 LF conflict sensitivities</h1>",
    "<p class='lede'>A compact review of the 36 length-frequency sensitivity models and their merged Hessian diagnostics. Hessian completion and curvature quality are shown separately: a completed Hessian can still contain negative eigenvalues.</p>",
    "<div class='actions'><a class='button alt' href='interactive-model-viewer.html'>Open model viewer</a><a class='button' href='../tables/lf-conflict-sensitivity-summary.csv'>Download table</a></div>",
    "<section class='cards'>",
    paste0("<div class='card'><b>", nrow(summary), "</b><span>models</span></div>"),
    paste0("<div class='card'><b>", complete, "</b><span>Hessians complete</span></div>"),
    paste0("<div class='card'><b>", with_negative, "</b><span>models with negative eigenvalues</span></div>"),
    paste0("<div class='card'><b>", total_negative, "</b><span>negative eigenvalues in total</span></div>"),
    "</section><section class='panel'><div class='filters'>",
    "<label class='search'>Search<input id='search' type='search' placeholder='Scenario, Hessian status, reliability'></label>",
    "<label>Tail compression<select id='tc'><option value=''>All</option><option value='0'>0%</option><option value='1'>1%</option><option value='3'>3%</option><option value='5'>5%</option></select></label>",
    "<label>Cutoff<select id='cut'><option value=''>All</option><option value='none'>None</option><option value='70'>70 cm</option><option value='100'>100 cm</option></select></label>",
    "<label>Downweight<select id='dw'><option value=''>All</option><option value='1'>1x</option><option value='10'>10x</option><option value='100'>100x</option></select></label>",
    "<label>Hessian<select id='hessian'><option value=''>All</option><option value='yes'>Yes</option><option value='no'>No</option></select></label>",
    "</div><div class='table-wrap'><table id='results'><thead><tr>",
    "<th>Scenario</th><th>TC</th><th>Cutoff</th><th>LF divisor</th><th>Hessian</th><th>Status</th><th>Reliability</th><th>Negative eigenvalues</th><th>Nonpositive</th><th>Total eigenvalues</th>",
    "</tr></thead><tbody>", row_html, "</tbody></table></div>",
    "<div class='foot'><span id='visible'></span><span>Click a column heading to sort.</span></div></section></main>",
    "<script>",
    "const rows=[...document.querySelectorAll('#results tbody tr')];const controls=['search','tc','cut','dw','hessian'].map(id=>document.getElementById(id));",
    "function filter(){const q=controls[0].value.trim().toLowerCase();let n=0;rows.forEach(r=>{const show=(!q||r.textContent.toLowerCase().includes(q))&&(!controls[1].value||r.dataset.tc===controls[1].value)&&(!controls[2].value||r.dataset.cut===controls[2].value)&&(!controls[3].value||r.dataset.dw===controls[3].value)&&(!controls[4].value||r.dataset.hessian===controls[4].value);r.classList.toggle('hidden',!show);if(show)n++});document.getElementById('visible').textContent=n+' of '+rows.length+' models shown'}",
    "controls.forEach(c=>c.addEventListener('input',filter));let direction=1;document.querySelectorAll('th').forEach((th,i)=>th.addEventListener('click',()=>{direction*=-1;rows.sort((a,b)=>{const av=a.children[i].dataset.sort??a.children[i].textContent.trim();const bv=b.children[i].dataset.sort??b.children[i].textContent.trim();const an=Number(av),bn=Number(bv);return direction*((Number.isFinite(an)&&Number.isFinite(bn))?an-bn:String(av).localeCompare(String(bv)))}).forEach(r=>r.parentNode.appendChild(r));filter()}));filter();",
    "</script></body></html>"
  )
}

write_lf_sensitivity_summary <- function(payload_index, output_dir) {
  summary <- lf_build_sensitivity_summary(payload_index)
  if (!nrow(summary)) return(invisible(summary))
  table_dir <- file.path(output_dir, "tables")
  index_dir <- file.path(output_dir, "indices")
  overview_dir <- file.path(output_dir, "overview")
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(index_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(overview_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    summary,
    file.path(table_dir, "lf-conflict-sensitivity-summary.csv"),
    row.names = FALSE,
    na = ""
  )
  utils::write.csv(
    summary,
    file.path(index_dir, "lf-conflict-sensitivity-summary.csv"),
    row.names = FALSE,
    na = ""
  )
  writeLines(
    lf_summary_html(summary),
    file.path(overview_dir, "lf-conflict-sensitivity-summary.html"),
    useBytes = TRUE
  )
  invisible(summary)
}

lf_inject_summary_link <- function(viewer_path) {
  if (!length(viewer_path) || !file.exists(viewer_path)) return(invisible(FALSE))
  html <- paste(readLines(viewer_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (grepl("lf-conflict-summary-link", html, fixed = TRUE)) return(invisible(TRUE))
  banner <- paste0(
    "<a id='lf-conflict-summary-link' href='lf-conflict-sensitivity-summary.html' ",
    "style='position:fixed;right:18px;top:14px;z-index:99999;padding:10px 14px;", 
    "border-radius:8px;background:#0c7468;color:white;text-decoration:none;", 
    "font:700 14px sans-serif;box-shadow:0 5px 18px rgba(0,0,0,.22)'>", 
    "LF sensitivity Hessian summary</a>"
  )
  updated <- sub("(<body[^>]*>)", paste0("\\1", banner), html, perl = TRUE)
  if (identical(updated, html)) return(invisible(FALSE))
  writeLines(updated, viewer_path, useBytes = TRUE)
  invisible(TRUE)
}

if (exists("write_interactive_model_viewer_output", mode = "function")) {
  .lf_original_write_interactive_model_viewer_output <-
    get("write_interactive_model_viewer_output", mode = "function")
  write_interactive_model_viewer_output <- function(...) {
    result <- .lf_original_write_interactive_model_viewer_output(...)
    candidates <- character()
    if (is.character(result)) candidates <- c(candidates, result)
    if (exists("out_dir", envir = .GlobalEnv, inherits = FALSE)) {
      result_dir <- get("out_dir", envir = .GlobalEnv, inherits = FALSE)
      candidates <- c(
        candidates,
        file.path(result_dir, "overview", "interactive-model-viewer.html")
      )
    }
    candidates <- unique(candidates[file.exists(candidates)])
    if (length(candidates)) lf_inject_summary_link(candidates[[1L]])
    result
  }
}
