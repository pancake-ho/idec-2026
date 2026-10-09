"""Strict compare of RTL event CSV against unmodified V18A expected tensors."""
import csv
from pathlib import Path
import numpy as np
from exp_v18a.io.common import json_write

def compare(expected_npz,rtl_csv,out,images=1000):
    with np.load(expected_npz) as f:
        data={k:f[k] for k in f.files}
    if not 1<=images<=len(data['predictions']):
        raise ValueError('invalid image count')
    seen=set();errors=[];counts={};cycles=[]
    mapping={'C1RAW':'conv1_acc_math','C2RAW':'conv2_partial_math','POOL1':'pool1','POOL2':'pool2','LOGIT':'logits'}
    with Path(rtl_csv).open(newline='',encoding='utf-8') as f:
        for row in csv.DictReader(f):
            kind=row['kind'];i=int(row['image']);a,b,c,d=(int(row[k]) for k in ('a','b','c','d'))
            value=int(row['value']) # X/Z or malformed data is a hard failure, never dropped.
            if not 0<=i<images:
                raise ValueError('RTL image index outside requested range')
            valid_index = {
                'C1RAW': 0<=a<3 and 0<=b<24 and 0<=c<24 and d==0,
                'C2RAW': 0<=a<3 and 0<=b<3 and 0<=c<8 and 0<=d<8,
                'POOL1': 0<=a<3 and 0<=b<12 and 0<=c<12 and d==0,
                'POOL2': 0<=a<3 and 0<=b<4 and 0<=c<4 and d==0,
                'LOGIT': 0<=a<10 and b==c==d==0,
                'DECISION': a==b==c==d==0,
                'CYCLES': a==b==c==d==0,
            }
            if not valid_index.get(kind,False):
                raise ValueError('Invalid event coordinate: '+str((kind,i,a,b,c,d)))
            key=(kind,i,a,b,c,d)
            if key in seen:raise ValueError('Duplicate RTL event: '+str(key))
            seen.add(key);counts[kind]=counts.get(kind,0)+1
            if kind=='C1RAW':expected=int(data[mapping[kind]][i,a,b,c])
            elif kind=='C2RAW':expected=int(data[mapping[kind]][i,a,b,c,d])
            elif kind in ('POOL1','POOL2'):expected=int(data[mapping[kind]][i,a,b,c])
            elif kind=='LOGIT':expected=int(data['logits'][i,a])
            elif kind=='DECISION':expected=int(data['predictions'][i])
            elif kind=='CYCLES':
                if value<784:raise ValueError('Impossible latency below the 784-pixel input stream')
                cycles.append(value);continue
            else:raise ValueError('Unknown event kind: '+kind)
            if value!=expected:errors.append(dict(event=list(key),rtl=value,python=expected))
    required={'C1RAW':1728*images,'C2RAW':576*images,'POOL1':432*images,
              'POOL2':48*images,'LOGIT':10*images,'DECISION':images,'CYCLES':images}
    if counts!=required:
        raise ValueError('Incomplete or extra RTL trace: actual='+str(counts)+' expected='+str(required))
    result=dict(images=images,counts=counts,mismatches=len(errors),first_mismatches=errors[:20],
                pass_all=len(errors)==0,cycles_min=min(cycles),cycles_max=max(cycles),
                cycle_definition='inclusive first real pixel capture edge through valid_out edge; excludes reset/dummy',
                gate_simulation=False)
    json_write(out/'rtl_trace_comparison.json',result)
    if errors:raise AssertionError('RTL/Python trace mismatches: '+str(len(errors)))
    return result
