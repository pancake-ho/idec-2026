"""Synthetic data exercises software plumbing only; no real codec accuracy claim."""
import sys,argparse,json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from data import ssim_local,grade,features,validate_splits
def main():
    p=argparse.ArgumentParser();p.add_argument('--out',required=True);a=p.parse_args();out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(822);ds={}
    for split in ['train','validation','test']:
        rows=[]
        for sid in range(2):
            for frame in range(4):
                ref=rng.integers(30,226,(28,28),dtype=np.uint8)
                noise=rng.normal(0,1,(28,28))
                for profile in [1,2]:
                    for target in range(3):
                        for sigma in np.linspace(.5,70,100):
                            x=np.clip(np.rint(ref.astype(float)+sigma*noise),0,255).astype(np.uint8);s=ssim_local(ref,x)
                            if grade(s)==target:break
                        assert grade(s)==target
                        meta,h=features(x,1e6,640,360,12,profile)
                        rows.append(dict(x=x,y=target,profile=profile,source_id=f'{split}_{sid}',source_sha256=f'SYNTHETIC_{split}_{sid}',
                            sample_id=f'{split}_{sid}_{frame}_{profile}_{target}',ssim=s,bitrate_bps=1e6,metadata=meta,handcrafted=h))
        ds[split]={k:np.asarray([r[k] for r in rows]) for k in rows[0]};np.savez_compressed(out/(split+'.npz'),**ds[split])
    (out/'NOTICE.txt').write_text('SYNTHETIC FUNCTIONAL FIXTURES. These are not AVC/HEVC video samples.\n')
    print(validate_splits(ds['train'],ds['validation'],ds['test']))
if __name__=='__main__':main()
