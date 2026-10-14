"""Run both actual RTL engines and full four-class tops against NumPy outputs."""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.common import write_json

def simulate(fixture, out, *, iverilog='iverilog', vvp='vvp', ivl_base=None, engine=True):
    fixture = Path(fixture).resolve(); out = Path(out)
    base = [iverilog] + ([] if ivl_base is None else ['-B', ivl_base])
    files = [str(ROOT / 'rtl' / x) for x in ('dash_booth.sv', 'dash_engine_pfdw.sv', 'dash_engine_direct.sv', 'dash_top.sv')]
    outputs = {}
    with tempfile.TemporaryDirectory() as temp:
        for name in (('engine', 'top') if engine else ('top',)):
            exe = str(Path(temp) / (name + '.vvp'))
            p = subprocess.run(base + ['-g2012', '-I', str(fixture), '-s', 'tb_' + name, '-o', exe] + files + [str(ROOT / 'tests' / ('tb_' + name + '.sv'))],
                               capture_output=True, text=True)
            if p.returncode:
                raise RuntimeError(p.stderr[-12000:])
            run = subprocess.run([vvp, exe], cwd=fixture, capture_output=True, text=True, timeout=240)
            if run.returncode or 'PASS' not in run.stdout:
                raise RuntimeError(run.stdout + run.stderr)
            outputs[name] = run.stdout; print(run.stdout)
    outputs.update(status='PASS', classes=4, top_runs=5, engine_cases=256 if engine else 0,
                   scope='functional simulation only; no real-video accuracy/PPA claim')
    write_json(out, outputs); return outputs

def main():
    a = argparse.ArgumentParser(); a.add_argument('--out', default=str(ROOT / 'runs/selftest'))
    a.add_argument('--iverilog', default='iverilog'); a.add_argument('--vvp', default='vvp'); a.add_argument('--ivl-base'); args = a.parse_args()
    out = Path(args.out).resolve()
    subprocess.run([sys.executable, str(ROOT / 'tests/check_python.py'), '--out', str(out)], check=True)
    subprocess.run([sys.executable, str(ROOT / 'tests/make_engine_vectors.py'), '--out', str(out / 'fixtures')], check=True)
    simulate(out / 'fixtures', out / 'rtl_validation.json', iverilog=args.iverilog, vvp=args.vvp, ivl_base=args.ivl_base)

if __name__ == '__main__': main()
