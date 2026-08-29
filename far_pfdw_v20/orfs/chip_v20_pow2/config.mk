# PFDW V20 W5 power-of-two / ASAP7 / 750 ps
V20_PACKAGE_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

export PLATFORM               = asap7
export DESIGN_NAME            = chip
export DESIGN_NICKNAME        = chip_v20_pow2
export SYNTH_HDL_FRONTEND      = slang
export SYNTH_MEMORY_MAX_BITS   = 4096

export VERILOG_FILES = \
    $(V20_PACKAGE_ROOT)/rtl/pfdw_pipe49_booth_engine_v20_w5.sv \
    $(V20_PACKAGE_ROOT)/rtl/chip_pfdw_fc_v20_pow2.sv \
    $(V20_PACKAGE_ROOT)/rtl/chip_v20_pow2_top.v

export SDC_FILE               = $(V20_PACKAGE_ROOT)/orfs/chip_v20_pow2/constraint.sdc
export ABC_AREA               = 1
export ABC_CLOCK_PERIOD_IN_PS = 750
export CORE_UTILIZATION       = 40
export CORE_ASPECT_RATIO      = 1
export CORE_MARGIN            = 2
export PLACE_DENSITY          = 0.65
export TNS_END_PERCENT        = 100
export EQUIVALENCE_CHECK     ?= 0
export REMOVE_CELLS_FOR_EQY   = TAPCELL*
