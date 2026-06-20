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

The `_review/` folder intentionally duplicates the main HTML/QMD review files
so the report preview is easy to find even when the figure bundle is large.

The outputs bundle is designed to be consumed by
`ofp-sam-bet-2026-curation`, which selects and orders report figures and tables
before the report is rendered.
