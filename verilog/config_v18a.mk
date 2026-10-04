# KNU IDEC CCDC - PFDW V18A / ASAP7
export PLATFORM               = asap7
export DESIGN_NAME            = chip
export DESIGN_NICKNAME        = chip_v18a

export SYNTH_HDL_FRONTEND      = slang
export SYNTH_MEMORY_MAX_BITS   = 4096

export VERILOG_FILES = \
    $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/pfdw_pipe49_booth_engine_v18a.sv \
    $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/chip_pfdw_fc_v18a.sv \
    $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/chip_v18a_top.v

export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

export ABC_AREA                 = 1
export CORE_UTILIZATION         = 40
export CORE_ASPECT_RATIO        = 1
export CORE_MARGIN              = 2
export PLACE_DENSITY            = 0.65
export TNS_END_PERCENT          = 100
export EQUIVALENCE_CHECK       ?= 1
export REMOVE_CELLS_FOR_EQY     = TAPCELL*
