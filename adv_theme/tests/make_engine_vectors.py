import sys,json,argparse
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from dash_cnn.integer.model import dwm_tile
def pack(a,bits):return ''.join(f'{int(x)&((1<<bits)-1):0{(bits+3)//4}x}' for x in np.asarray(a).ravel()[::-1]) if bits%4==0 else f'{sum((int(x)&((1<<bits)-1))<<(bits*i) for i,x in enumerate(np.asarray(a).ravel())):0{(len(np.asarray(a).ravel())*bits+3)//4}x}'
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',default=str(ROOT/'runs/selftest/fixtures'));args=ap.parse_args();out=Path(args.out);out.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(177);lines=[]
    for j in range(256):
        mode=j%2;x=rng.integers(0,256,(6,6));q=rng.integers(-32,32,(5,5));q[:3,:3]=rng.integers(-128,128,(3,3));q[3:,3:]=0
        fa=rng.integers(0,2048,40);fw=rng.integers(-32,32,40)
        if j<8:
            x.fill(255 if j&2 else 0);q[:3,:3]=127 if j&4 else -128
            q[:3,3:]=31 if j&4 else -32;q[3:,:3]=31 if j&4 else -32
            fa.fill(2047 if j&2 else 0);fw.fill(31 if j&4 else -32)
        tile=dwm_tile(x,q);score=fa@fw
        lines.append(f'{j} {mode} {pack(x,8)} {pack(q,8)} {pack(fa,11)} {pack(fw,8)} {pack(tile,32)} {int(score)&0xffffffff:08x}\n')
    (out/'engine_vectors.txt').write_text(''.join(lines))
if __name__=='__main__':main()
