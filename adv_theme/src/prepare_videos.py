"""Controlled AVC/HEVC encoding of local licensed sources; reference never enters CNN.

CSV columns: source_id,split,path. Split original contents BEFORE running this.
Output uses decoded luma code values; common fps, dimensions and frame indices.
"""
import argparse,csv,json,subprocess
from pathlib import Path
import numpy as np
from data import ssim_local,grade,features,sha256,validate_splits

def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def decode(path,w,h):
    raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-vf','extractplanes=y','-f','rawvideo','-pix_fmt','gray','-'])
    return np.frombuffer(raw,np.uint8).reshape(-1,h,w)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--sources',required=True);ap.add_argument('--out',required=True)
    ap.add_argument('--seconds',type=int,default=8);ap.add_argument('--width',type=int,default=640);ap.add_argument('--height',type=int,default=360)
    ap.add_argument('--fps',type=int,default=12);ap.add_argument('--crf',type=int,nargs='+',default=[18,30,42])
    a=ap.parse_args();out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    if min(a.width,a.height)<28 or a.width%2 or a.height%2:raise ValueError('even dimensions >=28')
    if a.seconds<=0 or a.fps<=0 or any(c<0 or c>51 for c in a.crf):raise ValueError('positive seconds/fps and CRF 0..51 required')
    rows=list(csv.DictReader(Path(a.sources).open()));identity={};seen=set();records={s:[] for s in ['train','validation','test']}
    for row in rows:
        sid=row['source_id'];split=row['split'];src=Path(row['path']).expanduser().resolve();digest=sha256(src)
        if split not in records or sid in seen:raise ValueError('invalid split or duplicate source_id')
        if digest in identity:raise ValueError('duplicate source file; assign all versions to one source')
        identity[digest]=split;seen.add(sid)
        # Path-independent safe directory; user identifiers remain in metadata.
        d=out/'encoded'/digest[:16];d.mkdir(parents=True,exist_ok=True);ref=d/'reference.mkv'
        vf=f'scale={a.width}:{a.height}:flags=bicubic:in_range=auto:out_range=tv,fps={a.fps},format=yuv420p,setsar=1'
        run(['ffmpeg','-v','error','-y','-i',str(src),'-t',str(a.seconds),'-vf',vf,'-an','-c:v','ffv1','-color_range','tv',str(ref)])
        original=decode(ref,a.width,a.height)
        for profile,enc in [(1,'libx264'),(2,'libx265')]:
            for crf in a.crf:
                dst=d/f'p{profile}_crf{crf}.mkv'
                cmd=['ffmpeg','-v','error','-y','-i',str(ref),'-an','-c:v',enc,'-preset','medium','-crf',str(crf),'-threads','2','-pix_fmt','yuv420p','-color_range','tv']
                if profile==2:cmd+=['-x265-params','pools=1:frame-threads=1:log-level=error']
                run(cmd+[str(dst)]);decoded=decode(dst,a.width,a.height)
                if decoded.shape!=original.shape:raise ValueError('frame count/shape mismatch')
                # Container size is only an observable metadata approximation, NOT a label.
                bitrate=dst.stat().st_size*8/(len(decoded)/a.fps)
                coords=[(int((a.height-28)*yy),int((a.width-28)*xx)) for yy,xx in [(0.2,0.2),(0.2,0.8),(0.5,0.5),(0.8,0.2),(0.8,0.8)]]
                for fi in range(0,len(decoded),a.fps):
                    for pi,(y,x) in enumerate(coords):
                        r=original[fi,y:y+28,x:x+28];q=decoded[fi,y:y+28,x:x+28].copy()
                        score=ssim_local(r,q);meta,feat=features(q,bitrate,a.width,a.height,a.fps,profile)
                        records[split].append(dict(x=q,y=grade(score),profile=profile,source_id=sid,source_sha256=digest,
                            sample_id=f'{sid}/{profile}/{crf}/{fi}/{pi}',ssim=score,bitrate_bps=bitrate,
                            metadata=meta,handcrafted=feat,frame_index=fi,patch_y=y,patch_x=x))
        print(sid,split,'complete',flush=True)
    ds={}
    for split,rs in records.items():
        if not rs:raise ValueError('all three source-disjoint splits are required')
        ds[split]={k:np.asarray([r[k] for r in rs]) for k in rs[0]}
        np.savez_compressed(out/(split+'.npz'),**ds[split])
    audit=validate_splits(ds['train'],ds['validation'],ds['test'])
    audit['class_counts']={s:np.bincount(d['y'],minlength=3).tolist() for s,d in ds.items()}
    audit['codec_class_counts']={s:{str(p):np.bincount(d['y'][d['profile']==p],minlength=3).tolist()
                                  for p in (1,2)} for s,d in ds.items()}
    audit['contract']='local Gaussian SSIM: 11x11 sigma1.5 valid windows, data_range255; low>=.97, high<.90'
    audit['ffmpeg_version']=subprocess.check_output(['ffmpeg','-version']).decode().splitlines()[0]
    (out/'dataset_audit.json').write_text(json.dumps(audit,indent=2)+'\n')
if __name__=='__main__':main()
