# BET 2026 Results

<p align="right">
  <a href="kflow.yaml"><img src="kflow-ready.svg" alt="Kflow ready task"></a>
</p>

Kflow task for building standalone BET 2026 figures, tables, captions, and
interactive review outputs from upstream model payloads.

## Workflow Role

```text
ofp-sam-bet-2026-stepwise -> ofp-sam-bet-2026-results
```

This task reads one or more upstream artifacts containing `model_payload.rds`
and builds its own figure/table review bundle. It does not trigger, update,
commit to, or push to the report repository.

For a parallel sensitivity screen, give this task the completed per-model
merge bundles (one bundle per model), not both the fit and merge archives. The
results job keeps the attached Hessian diagnostic with each model and MFCL
Shiny stages all unique input models together.

The MFCL Shiny local app can now act as a curation layer. Open the app from a
results job, adjust model selections, overlays, facets, uncertainty controls,
and figure/table inclusion, then save `report-selection.json`. A follow-up
results run can read that small selection file with `PLOT_REPORT_SELECTION` or
`MFCLSHINY_REPORT_SELECTION_FILE` and rebuild the report-ready outputs from the
same Shiny state.

The app runs in local Docker on your computer. Kflow reads the needed model
payloads from the submitter over SSH instead of starting Shiny on the submitter.

## Main Outputs

```text
outputs/figures/
outputs/tables/
outputs/indices/figure-index.csv
outputs/indices/table-index.csv
outputs/indices/payload-index.csv
outputs/indices/plot-summary.csv
outputs/overview/report-ready-figures.html
outputs/overview/interactive-model-viewer.html
outputs/overview/report-map.html
outputs/report-ready/figures.qmd
outputs/report-ready/tables.qmd
outputs/review/plot-report.qmd
outputs/logs/
outputs/README.txt
```

Open `outputs/overview/report-ready-figures.html` to review all generated
figures in a compact one-page gallery. Open
`outputs/overview/interactive-model-viewer.html` to share an offline,
double-clickable interactive model viewer with no R or Shiny server required.
Open `outputs/overview/report-map.html` to browse generated figures, tables,
and QMD markers. The selection file controls inclusion, main/appendix
placement, captions, and the captured Shiny input state. These outputs remain
inside the Results job for review only.

`analysis-manifest.json` is deliberately small: it records available analysis
layers such as model runs, likelihood profiles, Hessian checks, jitter, and
self-tests without copying large seed-level objects. Heavy artifacts stay in
their upstream outputs and are loaded only when a plot needs them.

The large self-contained `plot-report.html` review is off by default. Enable it
only for a one-off review run with `PLOT_RENDER_REVIEW_HTML=true`.

## Figure Size

Normal Kflow runs optimize generated images for smaller artifacts and reports.
PNGs remain the print-quality fallback and smaller WebP companions serve HTML.
JPEG conversion is off by default because the optimized BET PNGs were smaller
in the full 106-figure benchmark.

## Run

Kflow runs:

```bash
bash run.sh
```

For local testing, put upstream model payload artifacts under `inputs/`, then
run the same command.

## Common Kflow Config

| Field | Typical value | Purpose |
| --- | --- | --- |
| `FLOW_GROUP` | `bet-2026-base` | Shared label for one stepwise/results review chain. |
| `PLOT_MAX_FISHERIES` | `18` | Limit fishery-level diagnostic plots per plot family. |
| `PLOT_REPORT_SELECTION` | `report-selection.json` | Optional Shiny curation manifest to replay before rendering. |
| `MFCLSHINY_INTERACTIVE_VIEWER_TITLE` | `BET 2026 Interactive Assessment Viewer` | Title passed to `mfclshiny::write_interactive_model_viewer()`. |
| `PLOT_RENDER_REVIEW_HTML` | `false` | Render the large review HTML. Keep false for normal runs. |
| `PLOT_OPTIMIZE_FIGURES` | `true` | Optimize generated plot files. |
| `PLOT_PNGQUANT_QUALITY` | `50-78` | Lossy PNG quality range when `pngquant` is available. Lower values keep large multi-model result bundles lighter. |
| `PLOT_WEBP_QUALITY` | `66` | WebP sidecar quality for HTML. |
| `PLOT_PDF_JPEG_FIGURES` | `false` | Skip JPEG conversion; the measured BET bundle retained none. |
| `MFCLSHINY_INTERACTIVE_INCLUDE_FITS` | `true` | Include length, weight, and CPUE fit panels in the offline interactive viewer. |
| `MFCLSHINY_INTERACTIVE_FIT_MODEL_LIMIT` | `Inf` | Maximum number of models with fit panels; `Inf` keeps all models. |
| `MFCLSHINY_INTERACTIVE_JSON_DIGITS` | `5` | Significant digits embedded in the portable viewer payload. |
| `KFLOW_REPO_RUNTIME_PACKAGES` | exact mfclkit and mfclshiny SHAs | Install only when the cached package does not match the tested release. |
| `MFCLKIT_GITHUB_REF` / `MFCLSHINY_GITHUB_REF` | reviewed commit SHAs | Keep the local MFCL Shiny app on the same diagnostic reader versions as the results job. |
## LF conflict sensitivity results

When the inputs are the completed per-model Hessian merge bundles from the
BET 2026 LF conflict sensitivity experiment, the Results job also writes:

- `outputs/overview/lf-conflict-sensitivity-summary.html`: a lightweight,
  filterable and sortable review of all sensitivity settings and Hessian
  diagnostics.
- `outputs/tables/lf-conflict-sensitivity-summary.csv`: the same review as a
  reusable table, including Hessian completion and negative eigenvalue counts.
- `outputs/overview/interactive-model-viewer.html`: the full offline model
  viewer, linked directly to the sensitivity summary.

Supply one completed Hessian merge bundle per model. Do not supply both a fit
job and its Hessian merge job, because the merge bundle already contains the
fit payload.

The reproducible Kflow submission is:

```bash
python3 scripts/submit_lf_conflict_results.py --dry-run
python3 scripts/submit_lf_conflict_results.py
```

The script validates the complete 36-model grid and submits the Results job to
Suva. It stops before submission if a model is missing a completed Hessian
merge bundle.
