# BET 2026 Results

<p align="right">
  <a href="kflow.yaml"><img src="kflow-ready.svg" alt="Kflow ready task"></a>
</p>

Kflow task for building report-ready BET 2026 figures, tables, captions, and
QMD section seeds from upstream model payloads.

## Workflow Role

```text
ofp-sam-bet-2026-stepwise -> ofp-sam-bet-2026-results -> ofp-sam-bet-2026-report
```

This task reads one or more upstream artifacts containing `model_payload.rds`,
builds the report figure/table bundle, and passes that bundle to the report
task.

For a parallel sensitivity screen, give this task the completed per-model
merge bundles (one bundle per model), not both the fit and merge archives. The
results job keeps the attached Hessian diagnostic with each model and MFCL
Shiny stages all unique input models together. Set `TRIGGER_NEXT=false` when
the screen is for review rather than an automatic assessment report.

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
placement, captions, and the captured Shiny input state. The report repo still
receives editable QMD section seeds for final manual wording.

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
| `TRIGGER_NEXT` | `true` | Launch the report task after results complete. |
| `FLOW_GROUP` | `bet-2026-base` | Shared label for one stepwise/results/report chain. |
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
| `MFCLSHINY_SELECTION_PUBLISH_CMD` | unset | Optional local-app hook for saving and publishing a selection to the next curated layer. |
| `KFLOW_REPORT_COMMIT_GENERATED` | `false` | Leave generated report inputs in Kflow artifacts rather than committing them back to the report repo. |
| `KFLOW_REPORT_PUSH_GENERATED` | `false` | Do not push generated-input commits from the report task. |
| `KFLOW_REPORT_PUBLISH_REQUIRED` | `false` | Do not fail an otherwise successful report render because generated-input publishing is unavailable. |
