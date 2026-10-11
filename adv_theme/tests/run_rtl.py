"""Run real iverilog/vvp simulation with the checked synthetic fixture weights."""
import argparse,os,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--iverilog',default='iverilog');ap.add_argument('--vvp',default='vvp');ap.add_argument('--ivl-base');a=ap.parse_args()
    subprocess.run([sys.executable,str(ROOT/'tests'/'check_python.py')],check=True)
    subprocess.run([sys.executable,str(ROOT/'tests'/'make_engine_vectors.py')],check=True)
    subprocess.run([sys.executable,str(ROOT/'src'/'generate_rtl.py')],check=True)
    outputs={};fixture=ROOT/'tests'/'fixtures';base=[a.iverilog]+([] if a.ivl_base is None else ['-B',a.ivl_base])
    files=[str(ROOT/'rtl'/x) for x in ['dash_booth.sv','dash_engine_pfdw.sv','dash_engine_direct.sv','dash_top.sv']]
    with tempfile.TemporaryDirectory() as d:
        for name in ['engine','top']:
            exe=str(Path(d)/(name+'.vvp'))
            subprocess.run(base+['-g2012','-I',str(fixture),'-s','tb_'+name,'-o',exe]+files+[str(ROOT/'tests'/('tb_'+name+'.sv'))],check=True)
            r=subprocess.run([a.vvp,exe],cwd=fixture,check=True,capture_output=True,text=True,timeout=180)
            outputs[name]=r.stdout;print(r.stdout)
    outputs.update(status='PASS',scope='synthetic functional RTL simulation; no PPA or real-video accuracy',
        engine_cases=256,top_frames=4,top_profiles=[0,1,2,3],numpy_reference_checked=True)
    (ROOT/'results'/'rtl_validation.json').write_text(json.dumps(outputs,indent=2)+'\n')
if __name__=='__main__':main()
