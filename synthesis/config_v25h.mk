# KNU IDEC CCDC - V25-H / ASAP7
# Fixed-model multiplierless PFDW:
# W566 + A88 + Conv PoT1 + temporal FC SP2 + M67 channel pruning.
export PLATFORM               = asap7
export DESIGN_NAME            = chip
export DESIGN_NICKNAME        = chip_v25h

export SYNTH_HDL_FRONTEND      = slang
export SYNTH_MEMORY_MAX_BITS   = 4096

export VERILOG_FILES = \
    $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/pfdw_pipe49_shift_engine_v25h.sv \
    $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/chip_pfdw_fc_v25h.sv \
    $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/chip_v25h_top.v

export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

export ABC_AREA                 = 1
export CORE_UTILIZATION         = 40
export CORE_ASPECT_RATIO        = 1
export CORE_MARGIN              = 2
export PLACE_DENSITY            = 0.65
export TNS_END_PERCENT          = 100
export EQUIVALENCE_CHECK       ?= 1
export REMOVE_CELLS_FOR_EQY     = TAPCELL*
