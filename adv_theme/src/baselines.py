"""Fit metadata-only and metadata+simple-spatial-feature linear controls.

No test data are read here. These controls establish whether visual CNN features
add value beyond profile and bitrate; they are not state-of-the-art IQA metrics.
"""
import argparse,json
from pathlib import Path
import numpy as np
import torch
from data import load,validate_splits,metrics
def main():
    p=argparse.ArgumentParser();p.add_argument('--train',required=True);p.add_argument('--validation',required=True);p.add_argument('--out',required=True)
    p.add_argument('--epochs',type=int,default=300);a=p.parse_args();td=load(a.train);vd=load(a.validation);validate_splits(td,vd)
    torch.manual_seed(2026);torch.set_num_threads(2);report={};out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    for key in ['metadata','handcrafted']:
        mu=td[key].mean(0);sd=td[key].std(0);sd=np.where(sd>1e-9,sd,1.)
        x=torch.tensor((td[key]-mu)/sd,dtype=torch.float32);vx=torch.tensor((vd[key]-mu)/sd,dtype=torch.float32)
        y=torch.tensor(td['y']).long();m=torch.nn.Linear(x.shape[1],3);opt=torch.optim.Adam(m.parameters(),lr=.03)
        counts=np.bincount(td['y'],minlength=3);cw=torch.tensor(1/np.maximum(counts,1),dtype=torch.float32);cw=cw/cw.mean()
        best=-1;state=None
        for _ in range(a.epochs):
            opt.zero_grad();loss=torch.nn.functional.cross_entropy(m(x),y,weight=cw);loss.backward();opt.step()
            with torch.no_grad():pred=m(vx).argmax(1).numpy()
            score=metrics(vd['y'],pred,vd['profile'])['overall']['macro_f1']
            if score>best:best=score;state={k:v.detach().clone() for k,v in m.state_dict().items()}
        m.load_state_dict(state)
        with torch.no_grad():pred=m(vx).argmax(1).numpy()
        report[key]=metrics(vd['y'],pred,vd['profile'])
        np.savez_compressed(out/(key+'.npz'),mu=mu,sd=sd,w=m.weight.detach().numpy(),b=m.bias.detach().numpy())
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
