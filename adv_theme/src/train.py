"""FP training, QAT, codec adaptation, integer export; never reads test data."""
import argparse,copy,json,random
from pathlib import Path
import numpy as np
import torch
from torch.nn import functional as F
from model import DASHAdaptCNN
from data import load,validate_splits,metrics,sha256
from integer import infer,export

def forward(model,x,p,adapt):
    if not adapt:return model(x,0)
    result=x.new_zeros((len(x),3))
    for k in (1,2):
        ids=torch.nonzero(p==k,as_tuple=True)[0]
        if len(ids):result[ids]=model(x[ids],k)
    return result

@torch.no_grad()
def evaluate(model,d,adapt):
    model.eval();pred=[]
    for i in range(0,len(d['x']),128):
        x=torch.from_numpy(d['x'][i:i+128])[:,None].to(next(model.parameters()).device).to(next(model.parameters()).dtype)/256
        p=torch.from_numpy(d['profile'][i:i+128]).to(x.device)
        pred.extend(forward(model,x,p,adapt).argmax(1).cpu().numpy())
    return metrics(d['y'],np.asarray(pred),d['profile'])

def evaluate_integer(model,d,adapt):
    """Adapter acceptance is based on the exact deployed arithmetic."""
    p=model.export_integer()
    pred=np.asarray([infer(x,p,int(k) if adapt else 0,'direct',model.variant)['decision']
                     for x,k in zip(d['x'],d['profile'])])
    return metrics(d['y'],pred,d['profile'])

def fit(model,train,val,epochs,lr,adapt,seed):
    opt=torch.optim.AdamW([p for p in model.parameters() if p.requires_grad],lr=lr,weight_decay=1e-4)
    rng=np.random.default_rng(seed);best=-1.;state=copy.deepcopy(model.state_dict());history=[]
    pair=train['profile']*3+train['y'];counts=np.bincount(pair,minlength=9)
    if np.any(counts[3:9]==0):raise ValueError('Training needs all three label classes in each codec; inspect dataset_audit')
    probs=1/counts[pair];probs=probs/probs.sum()
    dev=next(model.parameters()).device;dtype=next(model.parameters()).dtype
    for epoch in range(epochs):
        ix=rng.choice(len(pair),len(pair),replace=True,p=probs);model.train();losses=[]
        for i in range(0,len(ix),64):
            ids=ix[i:i+64];x=torch.from_numpy(train['x'][ids])[:,None].to(dev,dtype)/256
            y=torch.from_numpy(train['y'][ids]).to(dev).long();p=torch.from_numpy(train['profile'][ids]).to(dev)
            opt.zero_grad();z=forward(model,x,p,adapt);loss=F.cross_entropy(z,y);loss.backward();opt.step();losses.append(float(loss))
        m=evaluate(model,val,adapt);score=m['overall']['macro_f1']
        history.append(dict(epoch=epoch+1,loss=float(np.mean(losses)),metrics=m))
        print('adapt' if adapt else 'base',epoch+1,round(score,4),flush=True)
        if score>best:best=score;state=copy.deepcopy(model.state_dict())
    model.load_state_dict(state);return history

def audit_export(model,d,p):
    model=model.cpu().double().eval();q=model.quant;count=0
    for i in np.linspace(0,len(d['x'])-1,min(6,len(d['x'])),dtype=int):
        for k in (0,1,2):
            ref=infer(d['x'][i],p,k,'direct',model.variant);win=infer(d['x'][i],p,k,'dwm',model.variant)
            for key in ['pool1','pool2','scores']:
                if not np.array_equal(ref[key],win[key]):raise AssertionError('DWM != direct: '+key)
            with torch.no_grad():z,a,b=model(torch.tensor(d['x'][i],dtype=torch.float64)[None,None]/256,k,True)
            for key,t,e in [('pool1',a,q['ea1']),('pool2',b,q['ea2']),('scores',z,q['ea2']+q['ewfc'])]:
                if not np.array_equal(np.rint(t[0].numpy()/2.**e).astype(np.int64),ref[key]):raise AssertionError('QAT/export mismatch '+key)
            count+=1
    return count

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--train',required=True);ap.add_argument('--validation',required=True);ap.add_argument('--out',required=True)
    ap.add_argument('--variant',choices=['dense8','mask8','mixed11','final'],default='final');ap.add_argument('--seed',type=int,default=2026)
    ap.add_argument('--base-epochs',type=int,default=40);ap.add_argument('--qat-epochs',type=int,default=15);ap.add_argument('--adapt-epochs',type=int,default=15)
    ap.add_argument('--device',default='cpu');ap.add_argument('--synthetic-smoke',action='store_true');a=ap.parse_args()
    random.seed(a.seed);np.random.seed(a.seed);torch.manual_seed(a.seed);torch.set_num_threads(2)
    td=load(a.train);vd=load(a.validation);audit=validate_splits(td,vd)
    model=DASHAdaptCNN(a.variant).to(a.device);model.train_base();stages={}
    stages['fp32']=fit(model,td,vd,a.base_epochs,1e-3,False,a.seed)
    ix=np.random.default_rng(a.seed).choice(len(td['x']),min(1024,len(td['x'])),replace=False)
    model.calibrate(torch.from_numpy(td['x'][ix])[:,None].to(a.device).float()/256)
    stages['qat']=fit(model,td,vd,a.qat_epochs,2e-4,False,a.seed+1)
    out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    pre=evaluate_integer(model,vd,False);export(model.export_integer(),out/'shared',a.variant)
    # Before adaptation, retain a checkpoint for exact shared-only comparison.
    torch.save(dict(state=model.cpu().state_dict(),quant=model.quant,variant=a.variant),out/'shared'/'model.pt')
    model=model.to(a.device);model.train_adapters()
    stages['adapters']=fit(model,td,vd,a.adapt_epochs,5e-4,True,a.seed+2)
    post=evaluate_integer(model,vd,True);accepted={}
    for k in (1,2):
        old=pre['profiles'][str(k)];new=post['profiles'][str(k)]
        # Keep only validation-beneficial adapters without worsening severe->low error.
        keep=new['macro_f1']>old['macro_f1'] and new['severe_missed_as_low']<=old['severe_missed_as_low']
        accepted[str(k)]=keep
        if not keep:
            with torch.no_grad():model.lb[k-1].zero_();model.db[k-1].zero_()
    params=model.export_integer();n=audit_export(model,vd,params)
    pred=np.asarray([infer(x,params,int(k),'direct',a.variant)['decision'] for x,k in zip(vd['x'],vd['profile'])])
    export(params,out/'adapted',a.variant)
    for sub in ['shared','adapted']:
        mp=out/sub/'manifest.json';m=json.loads(mp.read_text())
        m.update(provenance='SYNTHETIC_SMOKE_ONLY' if a.synthetic_smoke else 'TRAINED_CANDIDATE',
                 train_sha256=sha256(a.train),validation_sha256=sha256(a.validation),seed=a.seed)
        mp.write_text(json.dumps(m,indent=2)+'\n')
    torch.save(dict(state=model.state_dict(),quant=model.quant,variant=a.variant),out/'adapted'/'model.pt')
    report=dict(status='SYNTHETIC_SMOKE_ONLY' if a.synthetic_smoke else 'TRAINED_CANDIDATE_TEST_AND_PPA_PENDING',
        variant=a.variant,seed=a.seed,torch_version=torch.__version__,split_audit=audit,
        train_sha256=sha256(a.train),validation_sha256=sha256(a.validation),stages=stages,
        shared_validation=pre,adapted_validation_before_selection=post,accepted_adapters=accepted,
        integer_validation=metrics(vd['y'],pred,vd['profile']),integer_crosschecks=n,quant=model.quant,
        ppa='NOT_MEASURED',test='NOT_READ')
    (out/'training_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report['status'],flush=True)
if __name__=='__main__':main()
