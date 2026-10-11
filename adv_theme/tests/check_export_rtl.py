"""Check a newly exported FINAL model against both full RTL tops on four patches."""
import argparse,json,subprocess,sys,tempfile
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from integer import load,infer,export
from data import sha256

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--weights',required=True);ap.add_argument('--data',required=True)
    ap.add_argument('--out',required=True);ap.add_argument('--iverilog',default='iverilog')
    ap.add_argument('--vvp',default='vvp');ap.add_argument('--ivl-base');a=ap.parse_args()
    w=Path(a.weights);m=json.loads((w/'manifest.json').read_text())
    if m['variant']!='final':raise ValueError('final RTL only')
    p=load(w/'weights_int.npz');d=load(a.data)
    if len(d['x'])<4:raise ValueError('at least four input patches required')
    ids=np.linspace(0,len(d['x'])-1,4,dtype=int)
    with tempfile.TemporaryDirectory() as td:
        t=Path(td);export(p,t)
        for i,j in enumerate(ids):
            x=d['x'][j];z=infer(x,p,i if i<3 else 0)
            (t/f'input_{i}.mem').write_text(''.join(f'{int(v):02x}\n' for v in x.ravel()))
            (t/f'expected_{i}.mem').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in z['scores']))
        base=[a.iverilog]+([] if a.ivl_base is None else ['-B',a.ivl_base])
        files=[str(ROOT/'rtl'/f) for f in ['dash_booth.sv','dash_engine_direct.sv','dash_engine_pfdw.sv','dash_top.sv']]
        exe=str(t/'top.vvp')
        subprocess.run(base+['-g2012','-I',td,'-s','tb_top','-o',exe]+files+[str(ROOT/'tests/tb_top.sv')],check=True)
        r=subprocess.run([a.vvp,exe],cwd=td,check=True,capture_output=True,text=True,timeout=180)
    report=dict(status='PASS',scope='Four exported-model functional RTL checks; not accuracy/PPA',
                weights_sha256=sha256(w/'weights_int.npz'),data_sha256=sha256(a.data),
                sample_indices=ids.tolist(),profiles=[0,1,2,3],stdout=r.stdout)
    out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n')
    print(r.stdout)
if __name__=='__main__':main()
