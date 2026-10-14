#!/usr/bin/env bash
set -euo pipefail

# Run from ~/OpenROAD-flow-scripts/flow after copying/unzipping this package there.
SRC_DIR="./V25_H_PFDW_Multiplierless/v25h"
RTL_DST="./designs/src/chip_v25h"
CFG_DST="./designs/asap7/chip_v25h"

mkdir -p "$RTL_DST" "$CFG_DST"

cp "$SRC_DIR/rtl/pfdw_pipe49_shift_engine_v25h.sv" "$RTL_DST/"
cp "$SRC_DIR/rtl/chip_pfdw_fc_v25h.sv" "$RTL_DST/"
cp "$SRC_DIR/rtl/chip_v25h_top.v" "$RTL_DST/"
cp "$SRC_DIR/synthesis/config_v25h.mk" "$CFG_DST/config.mk"
cp "$SRC_DIR/synthesis/post_synth_report.tcl" "$CFG_DST/post_synth_report.tcl"

# Fair PPA comparison: reuse the exact V24 clock/IO constraint.
cp ./designs/asap7/chip_v24/constraint.sdc "$CFG_DST/constraint.sdc"

echo "[V25-H] installed:"
ls -lh "$RTL_DST"
ls -lh "$CFG_DST"
