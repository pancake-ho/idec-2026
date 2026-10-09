"""Export deterministic full-width legal engine requests for the RTL scoreboard."""
import numpy as np
from exp_v18a.models import engine
from exp_v18a.io.common import json_write

def export_vectors(out,seed=2026,cases=512):
    if not 4<=cases<=60000:
        raise ValueError('engine vector cases must be 4..60000')
    rng=np.random.default_rng(seed)
    path=out/'engine_cases.txt'
    with path.open('w',encoding='ascii') as f:
        f.write(str(cases)+'\n')
        for i in range(cases):
            mode=i%2
            a=rng.integers(0,2048,size=48,dtype=np.int64)
            b=rng.integers(-128,128,size=48,dtype=np.int64)
            if i in (0,1):a[:]=0;b[:]=-128
            if i in (2,3):a[:]=2047;b[:]=-128
            if mode:
                conv=np.zeros(4,dtype=np.int64);fc=int(engine.fc(a,b))
                assert fc==int(np.sum(a*b))
            else:
                tile=a[:36].reshape(6,6);w=b[:25].reshape(5,5)
                conv=engine.conv(tile,w);fc=0
                np.testing.assert_array_equal(conv,engine.direct_conv(tile,w))
            values=[i,mode]+a.tolist()+b.tolist()+conv.tolist()+[fc]
            f.write(' '.join(map(str,values))+'\n')
    json_write(out/'engine_vectors_metadata.json',dict(seed=seed,cases=cases,
               legal_activation_range=[0,2047],legal_weight_range=[-128,127],
               response_edge_offset=6,registered_stages=7,
               scoreboard_checks='mode, tag, all outputs, fixed valid latency; inserted bubbles',
               rtl_simulation_run=False))
    return path
