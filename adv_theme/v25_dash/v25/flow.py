"""Prepare comparable ORFS/ASAP7 and Vivado inputs, without inventing PPA measurements."""
import json
from pathlib import Path
from .integer import load
from .hardware import generate
from .util import sha256,write_json

def prepare(args):
    out=Path(args.out).resolve();period=float(args.period_ns)
    if period<=0 or period!=period or period==float('inf'):raise ValueError('positive finite period required')
    if any(c.isspace() for c in str(out)):raise ValueError('flow path must not contain whitespace')
    for stage,backend,label in (('int8','mul','before_int8_mul'),('v25h','shift','after_v25h_shift'),('v25h','mul','ablation_v25h_mul')):
        folder=out/'models'/stage;meta=json.loads((folder/'training_report.json').read_text())
        proof=json.loads((out/'verification'/stage/'verification.json').read_text())
        params=load(folder/'integer/weights_int.npz')
        if meta['checkpoint_sha256']!=sha256(folder/'weights.pt'):raise ValueError('checkpoint changed')
        dst=generate(params,out/'flow'/label,backend)
        # Independent coefficient-export integrity is checked in verify-export before PPA preparation.
        actual={f.name:sha256(f) for f in dst.glob('v25_*.sv')}
        if actual!=proof['logs'][backend]['rtl_sha256']:raise ValueError('RTL changed since verified export; rerun verify-export')
        period_ps=period*1000
        sdc=f'''# ASAP7: default period in ps. Confirm with report_units in the installed flow.
create_clock -name core_clk -period {period_ps:g} [get_ports clk]
set_input_delay {period_ps*.2:g} -clock core_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay {period_ps*.2:g} -clock core_clk [all_outputs]
set_clock_uncertainty {period_ps*.05:g} [get_clocks core_clk]
'''
        (dst/'constraint.sdc').write_text(sdc)
        files=' '.join(str(dst/f) for f in ('v25_dash_engine.sv','v25_dash_top.sv'))
        (dst/'config.mk').write_text(f'''export PLATFORM = asap7
export DESIGN_NAME = v25_dash_top
export DESIGN_NICKNAME = {label}
export SYNTH_HDL_FRONTEND = slang
export SYNTH_MEMORY_MAX_BITS = 65536
export VERILOG_FILES = {files}
export SDC_FILE = {dst/'constraint.sdc'}
export ABC_AREA = 1
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.65
export TNS_END_PERCENT = 100
''')
        (dst/'vivado.tcl').write_text(f'''# Vivado batch template. Run inside this directory, with the same PART for every design.
if {{$argc != 1}} {{error "Pass exact FPGA PART as -tclargs PART"}}
set part [lindex $argv 0]
read_verilog -sv [list v25_dash_engine.sv v25_dash_top.sv]
synth_design -top v25_dash_top -part $part
create_clock -name core_clk -period {period:g} [get_ports clk]
set_input_delay {period*.2:g} -clock core_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay {period*.2:g} -clock core_clk [all_outputs]
set_clock_uncertainty {period*.05:g} [get_clocks core_clk]
opt_design
place_design
route_design
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
report_power -file power_vectorless.rpt
write_checkpoint -force routed.dcp
''')
        write_json(dst/'flow_manifest.json',dict(status='VERIFIED_RTL_FLOW_INPUTS_ONLY',mode=stage,backend=backend,
            integer_sha256=sha256(folder/'integer/weights_int.npz'),rtl_sha256=actual,period_ns=period,
            asap7_default_sdc_unit='ps; confirm installed Liberty units',synthetic_weights=meta['status']=='SYNTHETIC_SMOKE_ONLY',
            ppa_status='NOT_MEASURED',power='vectorless estimate unless matching activity is supplied',
            comparison='before/after includes quantization and coding; candidate MUL vs SHIFT isolates backend with identical weights'))
        print(dst/'config.mk',flush=True)
