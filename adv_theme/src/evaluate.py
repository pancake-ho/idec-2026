"""Independent test evaluation after model/threshold/precision selection is frozen."""
import argparse,json
from pathlib import Path
import numpy as np
from data import load,validate_splits,metrics,sha256
from integer import load as weights,infer
def main():
    p=argparse.ArgumentParser();p.add_argument('--model',required=True);p.add_argument('--train',required=True)
    p.add_argument('--validation',required=True);p.add_argument('--test',required=True);p.add_argument('--out',required=True)
    p.add_argument('--variant',default='final');a=p.parse_args()
    td,vd,d=[load(x) for x in [a.train,a.validation,a.test]];audit=validate_splits(td,vd,d);w=weights(a.model)
    pred=np.array([infer(x,w,int(k),variant=a.variant)['decision'] for x,k in zip(d['x'],d['profile'])])
    base=np.array([infer(x,w,0,variant=a.variant)['decision'] for x in d['x']])
    Path(a.out).write_text(json.dumps(dict(test=metrics(d['y'],pred,d['profile']),fallback=metrics(d['y'],base,d['profile']),
        split_audit=audit,weights_sha256=sha256(a.model),test_sha256=sha256(a.test)),indent=2)+'\n')
if __name__=='__main__':main()
