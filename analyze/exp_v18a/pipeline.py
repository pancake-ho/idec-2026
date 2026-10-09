"""Orchestrate independently callable analysis stages."""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
from exp_v18a.io.common import COMMIT,REPO,source_manifest,load_parameters,dataset_audit,json_write,csv_write
from exp_v18a.models.cnn import V18ACNN
from exp_v18a.verification.contracts import validate
from exp_v18a.verification.vectors import export_vectors
from exp_v18a.verification.rtl_compare import compare
from exp_v18a.reports.profile import profile
from exp_v18a.reports.summary import write_summary
from exp_v18a.experiments.sweep import run_sweep

def parse_args(argv=None):
    p=argparse.ArgumentParser(description='Read-only V18A analysis; writes results only to --out.')
    p.add_argument('stage',choices=('audit','validate','profile','sweep','all','plots','compare-rtl','engine-vectors'))
    p.add_argument('--repo-root',type=Path,default=REPO)
    p.add_argument('--dataset',type=Path)
    p.add_argument('--labels',type=Path,help='Optional decimal label per image; required for unknown datasets')
    p.add_argument('--out',type=Path)
    p.add_argument('--seed',type=int,default=2026)
    p.add_argument('--profile-split',choices=('calibration','all-unique'),default='calibration')
    p.add_argument('--grid',action='store_true',help='Explore 4^3 weight combinations per rounding instead of single-factor weights')
    p.add_argument('--roundings',nargs='+',choices=('floor','even','trunc'),default=['floor','even'])
    p.add_argument('--vectors',type=int,default=512)
    p.add_argument('--rtl-csv',type=Path)
    p.add_argument('--images',type=int,default=1000)
    p.add_argument('--no-plots',action='store_true',help='Skip automatic figure generation after profile/sweep/all')
    p.add_argument('--plot-formats',nargs='+',choices=('png','pdf','svg'),default=['png','pdf'])
    p.add_argument('--plot-dpi',type=int,default=180)
    return p.parse_args(argv)

def main(argv=None):
    args=parse_args(argv)
    repo=args.repo_root.resolve()
    out=(args.out or repo/'analyze/exp_v18a/outputs').resolve()
    out.mkdir(parents=True,exist_ok=True)
    if args.stage=='plots':
        from exp_v18a.plots.render import render_all
        render_all(out,args.plot_formats,args.plot_dpi)
        return 0
    if args.stage=='compare-rtl':
        if args.rtl_csv is None:raise ValueError('--rtl-csv is required')
        r=compare(out/'expected_trace.npz',args.rtl_csv,out,args.images)
        print(r);return 0
    if args.stage=='engine-vectors':
        print(export_vectors(out,args.seed,args.vectors));return 0
    manifest=source_manifest(repo)
    params=load_parameters(repo/'data')
    images,labels,unique,splits,audit,membership=dataset_audit(args.dataset or repo/'data/input_1000.txt',args.labels,args.seed)
    audit['reference_commit']=COMMIT
    audit['source_manifest']=manifest
    audit['parameter_files']=[dict(path=str(f.relative_to(repo)),sha256=hashlib.sha256(f.read_bytes()).hexdigest())
                              for f in sorted((repo/'data').glob('*.txt')) if 'weight' in f.name or 'bias' in f.name]
    json_write(out/'dataset_audit.json',audit)
    csv_write(out/'dataset_membership.csv',membership)
    print(f"DATA: {len(images)} entries / {len(unique)} unique; splits={audit['split_sizes']}",flush=True)
    if args.stage=='audit':return 0
    validation,traces=validate(params,images,labels,unique,membership,out,args.seed)
    print(f"MODEL: all fields PASS, correct={validation['supplied_correct']}/{len(images)}",flush=True)
    if args.stage=='validate':return 0
    prof=None;sw=None
    if args.stage in ('profile','all'):
        ids=unique if args.profile_split=='all-unique' else splits['calibration']
        lookup={int(i):t for i,t in zip(unique,traces)}
        prof=profile(V18ACNN(params),images,labels,ids,[lookup[int(i)] for i in ids],out,args.profile_split)
        print('PROFILE:',prof,flush=True)
    if args.stage in ('sweep','all'):
        sw=run_sweep(params,images,labels,unique,splits,out,args.grid,args.roundings)
        print('SWEEP:',sw,flush=True)
    if args.stage=='all':
        export_vectors(out,args.seed,args.vectors)
        write_summary(out,audit,validation,prof,sw)
    if args.stage in ('profile','sweep','all') and not args.no_plots:
        from exp_v18a.plots.render import render_all
        render_all(out,args.plot_formats,args.plot_dpi)
    return 0
