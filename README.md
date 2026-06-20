# BET 2026 Outputs

Kflow task repository for BET 2026 report-ready figure and table outputs.

This task reads one or more upstream model-output jobs, finds
`model_payload.rds` files, and writes:

- `outputs/plot-report.html`
- `outputs/_review/plot-report.html`
- `outputs/figures/*.png`
- `outputs/tables/*.csv`
- `outputs/figure-index.csv`
- `outputs/table-index.csv`
- `outputs/report-ready/figures.qmd`
- `outputs/report-ready/tables.qmd`
- `outputs/report-ready/report-map.html`

The `_review/` folder intentionally duplicates the main HTML/QMD review files
and the report-ready map so the useful review files are easy to find even when
the figure bundle is large.

The outputs bundle is designed to be consumed directly by
`ofp-sam-bet-2026-report`. The report job copies the generated assets under
`generated/outputs/` and seeds `sections/Figures.qmd` and `sections/Tables.qmd`
only when those files are missing, so manual report edits are preserved.

Open `outputs/report-ready/report-map.html` to browse generated figures and
tables. To change report content, edit the seeded QMD files in the report
repository: remove blocks, reorder blocks, move appendix material, or rewrite
captions there.
