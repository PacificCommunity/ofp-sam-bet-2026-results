# BET 2026 Results

Kflow task repository for BET 2026 report-ready figures, tables, and report
section seeds.

This task reads one or more upstream model payload jobs, finds
`model_payload.rds` files, and writes the result bundle:

- `outputs/figures/*.png`
- `outputs/tables/*.csv`
- `outputs/figure-index.csv`
- `outputs/table-index.csv`
- `outputs/report-ready/figures.qmd`
- `outputs/report-ready/tables.qmd`
- `outputs/report-ready/report-map.html`
- `outputs/plot-report.html` and `outputs/_review/plot-report.html` for
  artifact-only review

The `_review/` folder intentionally duplicates the HTML/QMD review files and
the report-ready map so useful review files are easy to find in Kflow artifacts
even when the figure bundle is large.

The results bundle is designed to be consumed directly by
`ofp-sam-bet-2026-report`. The report job copies the generated assets under
`generated/outputs/` and seeds `sections/Figures.qmd` and `sections/Tables.qmd`
only when those files are missing, so manual report edits are preserved. The
report repository commits only the report-ready QMD, referenced figure/table
files, and provenance metadata; review HTML stays in Kflow artifacts.

Open `outputs/report-ready/report-map.html` to browse generated figures and
tables. To change report content, edit the seeded QMD files in the report
repository: remove blocks, reorder blocks, move appendix material, or rewrite
captions there.
