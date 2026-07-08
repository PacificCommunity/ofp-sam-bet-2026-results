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

Normal Kflow runs optimize generated images for smaller artifacts and smaller
reports. PNGs remain the fallback; WebP/JPEG sidecars are used where they help
HTML or PDF output.

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
| `PLOT_PNGQUANT_QUALITY` | `60-85` | Lossy PNG quality range when `pngquant` is available. |
| `PLOT_WEBP_QUALITY` | `72` | WebP sidecar quality for HTML. |
| `PLOT_JPEG_QUALITY` | `82` | JPEG sidecar quality for PDF rendering. |
| `KFLOW_RUNTIME_PACKAGES` | `mfclkit=PacificCommunity/ofp-sam-mfclkit@main,mfclshiny=PacificCommunity/mfclshiny@9ba0e02faf662ae3b0ac91646c2809e12a493e8c` | Runtime packages checked and installed when the job starts. |
| `MFCLSHINY_SELECTION_PUBLISH_CMD` | unset | Optional local-app hook for saving and publishing a selection to the next curated layer. |
| `KFLOW_REPORT_COMMIT_GENERATED` | `false` | Leave generated report inputs in Kflow artifacts rather than committing them back to the report repo. |
| `KFLOW_REPORT_PUSH_GENERATED` | `false` | Do not push generated-input commits from the report task. |
| `KFLOW_REPORT_PUBLISH_REQUIRED` | `false` | Do not fail an otherwise successful report render because generated-input publishing is unavailable. |
