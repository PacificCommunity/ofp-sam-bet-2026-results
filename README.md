# BET 2026 Plot

Kflow task repository for BET 2026 report-ready plots.

This task reads one or more upstream stepwise jobs, finds `model_payload.rds`
files, and writes:

- `outputs/plot-report.html`
- `outputs/_review/plot-report.html`
- `outputs/figures/*.png`
- `outputs/tables/*.csv`
- `outputs/figure-index.csv`
- `outputs/table-index.csv`

The `_review/` folder intentionally duplicates the main HTML/QMD review files
so the report preview is easy to find even when the figure bundle is large.

The plot bundle is designed to be consumed by the BET report task.
