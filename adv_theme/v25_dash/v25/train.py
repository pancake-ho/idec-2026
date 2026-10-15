"""Train/validation only. Three frozen stages: FP32 -> dense INT8 -> V25-H coded QAT."""
import copy
import csv
import json
from pathlib import Path
import random
import time
import numpy as np
import torch
from torch.nn import functional as F
from torch.utils.data import DataLoader,TensorDataset,WeightedRandomSampler
from dash_cnn.data.audit import load,validate_splits,coverage
from dash_cnn.evaluation.metrics import metrics
from .model import V25DASH
from .integer import infer,infer_spatial,export
from .spec import SOURCE_COMMIT
from .util import write_json,sha256

def seed_all(seed,threads):
    if threads<1:raise ValueError('threads >= 1 required')
    random.seed(seed);np.random.seed(seed);torch.manual_seed(seed);torch.set_num_threads(threads)
    torch.use_deterministic_algorithms(True)
    if torch.cuda.is_available():torch.cuda.manual_seed_all(seed)

def dataset_identity(data_work,splits=('train','validation')):
    return {s:sha256(Path(data_work)/'data'/(s+'.npz')) for s in splits}

def checkpoint(path,device='cpu'):
    c=torch.load(path,map_location='cpu',weights_only=True)
    m=V25DASH(c['mode']);m.load_state_dict(c['state_dict']);m.quant=c['quant'];m.to(device);m.eval()
    return m,c

def save_checkpoint(path,model,epoch,identity):
    torch.save(dict(mode=model.mode,quant=copy.deepcopy(model.quant),epoch=int(epoch),
                    state_dict={k:v.detach().cpu() for k,v in model.state_dict().items()},dataset_identity=identity),path)

def predict_integer(x,p,batch_size=128):
    values=[]
    for start in range(0,len(x),batch_size):
        values.append(infer(x[start:start+batch_size],p,check=False)['decision'])
    return np.concatenate(values)

@torch.no_grad()
def validation(model,d,batch_size,device):
    if model.mode!='fp32':pred=predict_integer(d['x'],model.export_integer(),batch_size)
    else:
        pred=[]
        for start in range(0,len(d['x']),batch_size):
            x=torch.from_numpy(d['x'][start:start+batch_size].copy()).to(device=device,dtype=torch.float32)[:,None]/256
            pred.append(model(x).argmax(1).cpu().numpy())
        pred=np.concatenate(pred)
    return metrics(d['y'],pred,d['video_id'])

@torch.no_grad()
def crosscheck(model,x,device):
    p=model.export_integer();a=infer(x,p)
    s,p1,p2=model(torch.from_numpy(x.copy()).to(device=device,dtype=torch.float32)[:,None]/256,maps=True)
    q=model.quant
    torch_values=dict(pool1=(p1/2.**q['ea1']).cpu().numpy(),pool2=(p2/2.**q['ea2']).cpu().numpy(),
                      scores=(s/2.**(q['ea2']+q['ewfc'])).cpu().numpy(),decision=s.argmax(1).cpu().numpy())
    b=infer(x,p,'shift') if model.mode=='v25h' else infer_spatial(x,p)
    for k in a:
        if not np.array_equal(a[k],torch_values[k]) or not np.array_equal(a[k],b[k]):
            raise AssertionError('QAT/export/backend mismatch: '+k)
    return dict(status='PASS_QAT_INTEGER_BACKENDS',n=len(x),maps=['pool1','pool2','four_scores','decision'])

def representatives(d,count=4):
    ids=[int(np.flatnonzero(d['y']==c)[0]) for c in range(4) if np.any(d['y']==c)]
    ids+= [i for i in range(len(d['y'])) if i not in ids][:max(0,count-len(ids))]
    return d['x'][ids[:count]],d['sample_id'][ids[:count]].astype(str).tolist()

def train(args):
    seed_all(args.seed,args.threads)
    device=torch.device(args.device)
    if device.type=='cuda' and not torch.cuda.is_available():raise ValueError('CUDA unavailable; use --device cpu')
    if args.batch_size<1 or min(args.base_epochs,args.qat_epochs,args.coded_epochs)<1 or args.calibration_samples<1:
        raise ValueError('positive epochs, batch and calibration count required')
    work=Path(args.data_work);out=Path(args.out);identity=dataset_identity(work)
    # Test NPZ is deliberately never opened by training or model selection.
    tr=load(work/'data/train.npz');va=load(work/'data/validation.npz')
    audit=validate_splits(tr,va)
    if not coverage(tr)['all_classes_present'] or not coverage(va)['all_classes_present']:
        raise ValueError('all four train/validation labels required')
    smoke=bool(np.asarray(tr.get('synthetic_smoke',False)).item())
    if smoke!=bool(np.asarray(va.get('synthetic_smoke',False)).item()):raise ValueError('mixed synthetic/real splits')
    stages=('fp32','int8','v25h') if args.stage=='all' else (args.stage,)
    config=dict(seed=args.seed,batch_size=args.batch_size,threads=args.threads,device=str(device),
                base_epochs=args.base_epochs,qat_epochs=args.qat_epochs,coded_epochs=args.coded_epochs,
                lr=args.lr,qat_lr=args.qat_lr,calibration_samples=args.calibration_samples,
                sampling='inverse-frequency WeightedRandomSampler, replacement; unweighted cross entropy')
    for stage in stages:
        dest=out/'models'/stage
        report_path=dest/'training_report.json'
        if report_path.exists():
            old=json.loads(report_path.read_text())
            if old['dataset_identity']!=identity or old['config']!=config:raise ValueError('completed stage configuration differs: use a new --out')
            if sha256(dest/'weights.pt')!=old['checkpoint_sha256']:raise ValueError('completed checkpoint changed')
            print('REUSE_COMPLETED',stage,flush=True);continue
        if dest.exists() and any(dest.iterdir()):raise ValueError('incomplete stage already exists: '+str(dest)+'; inspect it, then use a new --out')
        dest.mkdir(parents=True,exist_ok=True)
        seed_all(args.seed,args.threads)
        parent=None
        if stage=='fp32':model=V25DASH(stage).to(device)
        else:
            previous='fp32' if stage=='int8' else 'int8';parent=out/'models'/previous/'weights.pt'
            previous_report=parent.with_name('training_report.json')
            if not previous_report.exists():raise ValueError('complete '+previous+' first')
            parent_model,parent_info=checkpoint(parent)
            if parent_info['dataset_identity']!=identity:raise ValueError('parent uses a different dataset')
            if sha256(parent)!=json.loads(previous_report.read_text())['checkpoint_sha256']:raise ValueError('parent checkpoint changed')
            model=V25DASH(stage);model.load_state_dict(parent_model.state_dict());model.to(device)
        rng=np.random.default_rng(args.seed)
        calib_ids=np.sort(rng.choice(len(tr['x']),min(args.calibration_samples,len(tr['x'])),replace=False))
        if stage!='fp32':
            cx=torch.from_numpy(tr['x'][calib_ids].copy()).to(device=device,dtype=torch.float32)[:,None]/256
            model.calibrate(cx);del cx
        x=torch.from_numpy(tr['x'].copy())[:,None].float()/256;y=torch.from_numpy(tr['y'].copy()).long()
        counts=np.bincount(tr['y'],minlength=4)
        sampler=WeightedRandomSampler(torch.from_numpy(1./counts[tr['y']]),len(y),replacement=True,
                                      generator=torch.Generator().manual_seed(args.seed))
        loader=DataLoader(TensorDataset(x,y),batch_size=args.batch_size,sampler=sampler,num_workers=0)
        optimizer=torch.optim.Adam(model.parameters(),lr=args.lr if stage=='fp32' else args.qat_lr)
        epochs={'fp32':args.base_epochs,'int8':args.qat_epochs,'v25h':args.coded_epochs}[stage]
        model.eval();best=validation(model,va,args.batch_size,device);best_epoch=0
        # Include calibrated epoch zero; coding QAT is permitted to improve or retain it.
        save_checkpoint(dest/'weights.pt',model,0,identity)
        hist=[dict(epoch=0,loss='',val_macro_f1=best['macro_f1'],val_accuracy=best['accuracy'],seconds=0)]
        print(stage,0,'calibrated_val_F1',round(best['macro_f1'],6),flush=True)
        for epoch in range(1,epochs+1):
            start=time.perf_counter();model.train();loss_sum=0.
            for bx,by in loader:
                bx=bx.to(device);by=by.to(device);optimizer.zero_grad(set_to_none=True)
                loss=F.cross_entropy(model(bx),by)
                if not torch.isfinite(loss):raise FloatingPointError('nonfinite training loss')
                loss.backward();optimizer.step();loss_sum+=float(loss.detach())*len(by)
            model.eval();val=validation(model,va,args.batch_size,device)
            hist.append(dict(epoch=epoch,loss=loss_sum/len(y),val_macro_f1=val['macro_f1'],
                             val_accuracy=val['accuracy'],seconds=time.perf_counter()-start))
            print(stage,epoch,'loss',round(loss_sum/len(y),5),'val_F1',round(val['macro_f1'],6),flush=True)
            if val['macro_f1']>best['macro_f1']:
                best=val;best_epoch=epoch;save_checkpoint(dest/'weights.pt',model,epoch,identity)
        model,_=checkpoint(dest/'weights.pt',device)
        write_json(dest/'validation.json',best)
        with (dest/'history.csv').open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=list(hist[0]));writer.writeheader();writer.writerows(hist)
        provenance=dict(dataset_identity=identity,checkpoint_sha256=sha256(dest/'weights.pt'),seed=args.seed,
                        selected_epoch=best_epoch,synthetic_smoke=smoke)
        check=None
        if stage!='fp32':
            vx,_=representatives(va,6);check=crosscheck(model,vx,device)
            export(model.export_integer(),dest/'integer',provenance)
        report=dict(status='SYNTHETIC_SMOKE_ONLY' if smoke else 'TRAINED_TEST_AND_PPA_PENDING',
                    mode=stage,source_commit=SOURCE_COMMIT,parameters=sum(p.numel() for p in model.parameters()),
                    dataset_identity=identity,config=config,split_audit=audit,train=coverage(tr),validation=coverage(va),
                    best_epoch=best_epoch,best_validation=best,selection='maximum validation macro-F1, earliest tie; includes epoch zero',
                    calibration='train only; frozen activation/weight exponents throughout QAT',
                    calibration_sample_ids=tr['sample_id'][calib_ids].astype(str).tolist() if stage!='fp32' else [],
                    quant=model.quant,parent_checkpoint_sha256=sha256(parent) if parent else None,
                    checkpoint_sha256=sha256(dest/'weights.pt'),integer_crosscheck=check,
                    ppa_status='NOT_MEASURED')
        write_json(report_path,report)
        print('COMPLETE',stage,report['status'],flush=True)
    return out

def evaluate(args):
    from .integer import load as load_integer
    from .integer import validate
    out=Path(args.out);work=Path(args.data_work)
    stages=('int8','v25h') if args.stage=='all' else (args.stage,)
    ds=[load(work/'data'/(s+'.npz')) for s in ('train','validation','test')]
    audit=validate_splits(*ds);test=ds[2];identity=dataset_identity(work)
    result={}
    for stage in stages:
        folder=out/'models'/stage;report=json.loads((folder/'training_report.json').read_text())
        if report['dataset_identity']!=identity or report['checkpoint_sha256']!=sha256(folder/'weights.pt'):
            raise ValueError('frozen checkpoint/dataset identity changed')
        p=load_integer(folder/'integer/weights_int.npz')
        if validate(p)!=stage:raise ValueError('integer mode mismatch')
        # Verify export against the frozen model so a changed NPZ cannot be evaluated silently.
        model,_=checkpoint(folder/'weights.pt');expected=model.export_integer()
        for key in expected:
            if not np.array_equal(expected[key],p[key]):raise ValueError('export changed: '+key)
        pred=predict_integer(test['x'],p,args.batch_size)
        r=metrics(test['y'],pred,test['video_id'])
        r.update(mode=stage,split_audit=audit,checkpoint_sha256=report['checkpoint_sha256'],
                 integer_sha256=sha256(folder/'integer/weights_int.npz'),test_sha256=sha256(work/'data/test.npz'),
                 status='SYNTHETIC_SMOKE_ONLY' if bool(test.get('synthetic_smoke',False)) else 'FROZEN_TEST_RESULT_PPA_PENDING')
        write_json(out/'reports'/('test_'+stage+'.json'),r)
        np.savez_compressed(out/'reports'/('test_predictions_'+stage+'.npz'),y=test['y'],prediction=pred,sample_id=test['sample_id'],video_id=test['video_id'])
        print(stage,json.dumps(r,ensure_ascii=False),flush=True);result[stage]=r
    if len(result)==2:
        write_json(out/'reports/test_comparison.json',dict(baseline='int8',candidate='v25h',
                   macro_f1_delta=result['v25h']['macro_f1']-result['int8']['macro_f1'],
                   model_selection='validation only; this is a frozen test comparison',ppa_status='NOT_MEASURED'))
