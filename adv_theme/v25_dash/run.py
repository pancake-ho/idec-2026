#!/usr/bin/env python3
"""Additive CLI. Run from adv_theme; no mutation of existing runs/avc4."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
ROOT=Path(__file__).resolve().parent
ADV=ROOT.parent
sys.path.insert(0,str(ADV/'src'))
sys.path.insert(0,str(ROOT))

def shared(p):
    p.add_argument('--data-work',required=True,help='existing runs/avc4 containing data/*.npz')
    p.add_argument('--out',required=True,help='new experiment output, e.g. runs/v25_avc4')

def main():
    p=argparse.ArgumentParser(description='V25-H DASH: 1->2->3, FC48->4, TD PoT1 + FC SP2')
    sub=p.add_subparsers(dest='command',required=True)
    d=sub.add_parser('doctor')
    s=sub.add_parser('smoke');s.add_argument('--data-work',required=True)
    t=sub.add_parser('train');shared(t)
    t.add_argument('--stage',choices=('fp32','int8','v25h','all'),default='all')
    t.add_argument('--base-epochs',type=int,default=40);t.add_argument('--qat-epochs',type=int,default=15)
    t.add_argument('--coded-epochs',type=int,default=15);t.add_argument('--batch-size',type=int,default=64)
    t.add_argument('--lr',type=float,default=.001);t.add_argument('--qat-lr',type=float,default=.0002)
    t.add_argument('--calibration-samples',type=int,default=1024);t.add_argument('--seed',type=int,default=2026)
    t.add_argument('--device',default='cpu');t.add_argument('--threads',type=int,default=2)
    v=sub.add_parser('verify-export');shared(v)
    v.add_argument('--stage',choices=('int8','v25h','all'),default='all')
    v.add_argument('--iverilog',default='iverilog');v.add_argument('--vvp',default='vvp');v.add_argument('--ivl-base')
    e=sub.add_parser('evaluate');shared(e);e.add_argument('--stage',choices=('int8','v25h','all'),default='all');e.add_argument('--batch-size',type=int,default=128)
    f=sub.add_parser('flow');f.add_argument('--out',required=True);f.add_argument('--period-ns',type=float,default=10.)
    c=sub.add_parser('selftest')
    a=p.parse_args()
    if a.command=='doctor':
        import torch
        from v25.model import V25DASH
        print(json.dumps(dict(python=sys.version.split()[0],torch=torch.__version__,cuda=torch.cuda.is_available(),
              iverilog=shutil.which('iverilog'),vvp=shutil.which('vvp'),parameters=sum(x.numel() for x in V25DASH().parameters()),
              channels=[1,2,3],fc=[48,4],existing_data_reused=True),indent=2));return
    if a.command=='smoke':
        script=ADV/'tests/make_smoke_data.py'
        if not script.exists():raise FileNotFoundError('existing adv_theme/tests/make_smoke_data.py required')
        subprocess.run([sys.executable,str(script),'--out',a.data_work],check=True);return
    if a.command=='train':
        from v25.train import train
        train(a);return
    if a.command=='evaluate':
        from v25.train import evaluate
        evaluate(a);return
    if a.command=='verify-export':
        from dash_cnn.data.audit import load
        from v25.train import representatives,dataset_identity,checkpoint
        from v25.integer import load as load_integer
        from v25.verify import verify
        from v25.util import sha256
        import numpy as np
        va=load(Path(a.data_work)/'data/validation.npz');x,_=representatives(va)
        for stage in (('int8','v25h') if a.stage=='all' else (a.stage,)):
            folder=Path(a.out)/'models'/stage
            report=json.loads((folder/'training_report.json').read_text())
            if report['dataset_identity']!=dataset_identity(a.data_work) or report['checkpoint_sha256']!=sha256(folder/'weights.pt'):raise ValueError('checkpoint/data changed')
            params=load_integer(folder/'integer/weights_int.npz');m,_=checkpoint(folder/'weights.pt')
            for key,value in m.export_integer().items():
                if not np.array_equal(value,params[key]):raise ValueError('export changed: '+key)
            verify(params,x,Path(a.out)/'verification'/stage,a.iverilog,a.vvp,a.ivl_base)
        return
    if a.command=='flow':
        from v25.flow import prepare
        prepare(a);return
    if a.command=='selftest':
        import unittest
        suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'),pattern='test_*.py')
        if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():raise SystemExit(1)

if __name__=='__main__':main()
