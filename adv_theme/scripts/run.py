#!/usr/bin/env python3
"""One explicit CLI over independently importable modules. All work paths are explicit."""
import argparse
import importlib.util
import json
import platform
from pathlib import Path
import shutil
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.common import config, write_json

def main():
    ap = argparse.ArgumentParser(description='BBB/ED AVC 2s four-grade local quality prototype')
    ap.add_argument('command', choices=['doctor', 'plan', 'download', 'prepare', 'audit', 'controls', 'train', 'evaluate', 'verify', 'verify-rtl', 'verify-export', 'smoke', 'flow'])
    ap.add_argument('--config', default=str(ROOT / 'configs/avc4.json')); ap.add_argument('--work', default=str(ROOT / 'runs/avc4'))
    ap.add_argument('--media-work', help='Reuse a downloaded media_manifest and frame caches from this directory')
    ap.add_argument('--references', action='store_true'); ap.add_argument('--device', default='cpu'); ap.add_argument('--variant', choices=['dense8', 'mask8', 'mixed11', 'final'])
    ap.add_argument('--base-epochs', type=int); ap.add_argument('--qat-epochs', type=int)
    ap.add_argument('--iverilog', default='iverilog'); ap.add_argument('--vvp', default='vvp'); ap.add_argument('--ivl-base')
    ap.add_argument('--engine', choices=['direct', 'pfdw']); ap.add_argument('--clock-period', type=float, default=1000)
    ap.add_argument('--allow-synthetic', action='store_true'); a = ap.parse_args(); work = Path(a.work).resolve()
    if a.command == 'doctor':
        report = dict(hostname=platform.node(), python=sys.version.split()[0], ffmpeg=shutil.which('ffmpeg'), ffprobe=shutil.which('ffprobe'),
                      iverilog=shutil.which(a.iverilog), vvp=shutil.which(a.vvp), torch_installed=bool(importlib.util.find_spec('torch')))
        try:
            from dash_cnn.data.media import ffmpeg_info
            info = ffmpeg_info()
            report.update(ffmpeg_version=info['version'], frame_sync_args=info['frame_sync_args'])
        except (ImportError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            report['ffmpeg_error'] = str(error)
        if report['ffprobe']:
            try:
                result = subprocess.run([report['ffprobe'], '-version'], capture_output=True, text=True, check=True, timeout=30)
                report['ffprobe_version'] = result.stdout.splitlines()[0]
            except (OSError, subprocess.SubprocessError) as error:
                report['ffprobe_error'] = str(error)
        if report['torch_installed']:
            import torch
            report.update(torch=torch.__version__, cuda_available=torch.cuda.is_available(), cuda_devices=torch.cuda.device_count())
        print(json.dumps(report, indent=2)); return
    if a.command == 'verify':
        subprocess.run([sys.executable, str(ROOT / 'tests/check_python.py'), '--out', str(work)], check=True)
        subprocess.run([sys.executable, str(ROOT / 'tests/test_data.py')], check=True); return
    if a.command == 'verify-rtl':
        args = [sys.executable, str(ROOT / 'tests/run_rtl.py'), '--out', str(work), '--iverilog', a.iverilog, '--vvp', a.vvp]
        if a.ivl_base: args += ['--ivl-base', a.ivl_base]
        subprocess.run(args, check=True); return
    if a.command == 'verify-export':
        args = [sys.executable, str(ROOT / 'tests/check_export_rtl.py'), '--weights', str(work / 'models/final/integer'),
                '--data', str(work / 'data/validation.npz'), '--out', str(work / 'reports/export_rtl.json'), '--iverilog', a.iverilog, '--vvp', a.vvp]
        if a.ivl_base: args += ['--ivl-base', a.ivl_base]
        subprocess.run(args, check=True); return
    if a.command == 'smoke':
        subprocess.run([sys.executable, str(ROOT / 'tests/make_smoke_data.py'), '--out', str(work)], check=True); return
    if a.command == 'flow':
        if not a.engine: ap.error('--engine is required for flow')
        args = [sys.executable, str(ROOT / 'scripts/prepare_flow.py'), '--weights', str(work / 'models/final/integer'),
                '--out', str(work / 'build' / a.engine), '--engine', a.engine, '--clock-period', str(a.clock_period)]
        if a.allow_synthetic: args.append('--allow-synthetic')
        subprocess.run(args, check=True); return
    c = config(a.config)
    if a.command in ('plan', 'download'):
        from dash_cnn.data.download import acquire
        acquire(c, work, references=a.references, plan=a.command == 'plan')
    elif a.command == 'prepare':
        from dash_cnn.data.prepare import prepare
        prepare(c, work, a.media_work)
    elif a.command == 'audit':
        from dash_cnn.data.audit import load, validate_splits, coverage
        ds = [load(work / 'data' / (s + '.npz')) for s in ('train', 'validation', 'test')]
        r = dict(split_audit=validate_splits(*ds), splits={s: coverage(d) for s, d in zip(('train', 'validation', 'test'), ds)})
        write_json(work / 'reports/audit_recheck.json', r); print(json.dumps(r, indent=2))
    elif a.command == 'controls':
        from dash_cnn.evaluation.baselines import baselines
        baselines(work)
    elif a.command == 'train':
        from dash_cnn.training.trainer import train
        train(c, work, a.device, a.base_epochs, a.qat_epochs, a.variant)
    elif a.command == 'evaluate':
        from dash_cnn.evaluation.evaluate import evaluate
        evaluate(work, a.variant or c['training']['variant'])

if __name__ == '__main__': main()
