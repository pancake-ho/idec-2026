# Frozen V18A reference / ASAP7 / 750 ps
V20_PACKAGE_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
REPO_ROOT := $(abspath $(V20_PACKAGE_ROOT)/..)

export PLATFORM               = asap7
export DESIGN_NAME            = chip
export DESIGN_NICKNAME        = chip_v18a_v20_ab
export SYNTH_HDL_FRONTEND      = slang
export SYNTH_MEMORY_MAX_BITS   = 4096

export VERILOG_FILES = \
    $(REPO_ROOT)/far_pfdw_v19/reference_v18a/pfdw_pipe49_booth_engine_v18a.sv \
    $(REPO_ROOT)/far_pfdw_v19/reference_v18a/chip_pfdw_fc_v18a.sv \
    $(REPO_ROOT)/far_pfdw_v19/reference_v18a/chip_v18a_top.v

export SDC_FILE               = $(V20_PACKAGE_ROOT)/orfs/chip_v18a/constraint.sdc
export ABC_AREA               = 1
export ABC_CLOCK_PERIOD_IN_PS = 750
export CORE_UTILIZATION       = 40
export CORE_ASPECT_RATIO      = 1
export CORE_MARGIN            = 2
export PLACE_DENSITY          = 0.65
export TNS_END_PERCENT        = 100
export EQUIVALENCE_CHECK     ?= 1
export REMOVE_CELLS_FOR_EQY   = TAPCELL*
