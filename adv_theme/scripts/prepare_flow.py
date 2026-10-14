"""Generate self-contained source/ROM/constraint files for the same-model PPA pair.

ORFS/ASAP7 and Vivado are user-installed tools. This script never creates PPA results.
"""
import argparse,json,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from dash_cnn.integer.model import load,validate
from dash_cnn.common import sha256
def main():
    p=argparse.ArgumentParser();p.add_argument('--weights',required=True);p.add_argument('--out',required=True)
    p.add_argument('--engine',choices=['direct','pfdw'],required=True);p.add_argument('--clock-period',type=float,default=1000)
    p.add_argument('--allow-synthetic',action='store_true');a=p.parse_args();w=Path(a.weights).resolve();out=Path(a.out).resolve()
    if any(c.isspace() for c in str(out)):raise ValueError('flow output path must not contain whitespace')
    if a.clock_period<=0:raise ValueError('clock period must be positive')
    m=json.loads((w/'manifest.json').read_text())
    if m['variant']!='final' or m.get('classes')!=4 or m.get('codec_banks')!=1:raise ValueError('RTL implements final variant only')
    synthetic=(w/'NOTICE.txt').exists() or m.get('provenance')=='SYNTHETIC_SMOKE_ONLY' or m.get('provenance')=='UNSPECIFIED_NOT_A_TRAINED_CLAIM'
    if synthetic and not a.allow_synthetic:raise ValueError('Synthetic weights are not a trained model; --allow-synthetic only for flow checks')
    validate(load(w/'weights_int.npz'));out.mkdir(parents=True,exist_ok=True)
    for f in ROOT.joinpath('rtl').glob('*.sv'):shutil.copy2(f,out/f.name)
    for f in list(w.glob('*.mem'))+[w/'params.svh']:shutil.copy2(f,out/f.name)
    top=(out/'dash_top.sv').read_text().replace('parameter DIRECT=0',f'parameter DIRECT={int(a.engine=="direct")}')
    top=top.replace('"params.svh"',json.dumps(str(out/'params.svh')))
    for name in ['q1','q2','qfc','b1','b2','bfc']:top=top.replace('"'+name+'.mem"',json.dumps(str(out/(name+'.mem'))))
    (out/'dash_top.sv').write_text(top)
    sdc=f'''# Time values use the loaded Liberty units. Default 1000 is intended for ASAP7 ps units.
# Confirm units in the tool log; do not compare this with Vivado ns without conversion.
create_clock -name core_clk -period {a.clock_period:g} [get_ports clk]
set_input_delay {a.clock_period*.2:g} -clock core_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay {a.clock_period*.2:g} -clock core_clk [all_outputs]
set_clock_uncertainty {a.clock_period*.05:g} [get_clocks core_clk]
'''
    (out/'constraint.sdc').write_text(sdc)
    files=' '.join(str(out/x) for x in ['dash_booth.sv','dash_engine_direct.sv','dash_engine_pfdw.sv','dash_top.sv'])
    (out/'config.mk').write_text(f'''export PLATFORM = asap7
export DESIGN_NAME = dash_top
export DESIGN_NICKNAME = dash_{a.engine}
export SYNTH_HDL_FRONTEND = slang
export SYNTH_MEMORY_MAX_BITS = 65536
export VERILOG_FILES = {files}
export SDC_FILE = {out/'constraint.sdc'}
export ABC_AREA = 1
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.65
export TNS_END_PERCENT = 100
''')
    (out/'vivado.tcl').write_text('''# Vivado 2024.1 batch template. Usage: vivado -mode batch -source vivado.tcl -tclargs PART
if {$argc != 1} {error "Pass the exact FPGA PART for BOTH designs"}
set part [lindex $argv 0]
read_verilog -sv [glob *.sv]
synth_design -top dash_top -part $part
create_clock -name core_clk -period 10.0 [get_ports clk]
set_input_delay 2.0 -clock core_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 2.0 -clock core_clk [all_outputs]
opt_design
place_design
route_design
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
report_power -file power_vectorless.rpt
write_checkpoint -force routed.dcp
''')
    (out/'run_manifest.json').write_text(json.dumps(dict(engine=a.engine,weights_sha256=sha256(w/'weights_int.npz'),
        clock_period=a.clock_period,clock_unit='confirm loaded ASAP7 Liberty unit',status='FLOW_INPUTS_ONLY',
        synthetic_weights=synthetic,
        note='Same model, ROM mapping, activity, PVT, I/O, flow stage, tool commits required. Vectorless power is an estimate.'),indent=2)+'\n')
    print(out/'config.mk')
if __name__=='__main__':main()
