#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUTPUT_DIR:-outputs}"
INPUT_DIR="${INPUT_DIR:-inputs}"

mkdir -p "${OUT_DIR}" "${INPUT_DIR}"

echo "BET plot task"
echo "Input directory: ${INPUT_DIR}"
echo "Output directory: ${OUT_DIR}"

Rscript R/build_plots.R

