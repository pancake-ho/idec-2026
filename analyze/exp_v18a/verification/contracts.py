"""Meaningful arithmetic contracts and full intermediate-field equivalence."""
from __future__ import annotations
import numpy as np
from exp_v18a.models import engine
from exp_v18a.models.cnn import V18ACNN
from exp_v18a.io.common import RTLReferenceCNN, run_records, trace_arrays, json_write, csv_write
from exp_v18a.metrics.hardware_cost import shared_cost
from exp_v18a.experiments.quantization import weight_quant, activation_quant, round_shift

def arithmetic_contracts(seed=2026,cases=4096):
    rng=np.random.default_rng(seed)
    x=rng.integers(0,2048,size=(cases,6,6),dtype=np.int64)
    w=rng.integers(-128,128,size=(cases,5,5),dtype=np.int64)
    for i,(a,b) in enumerate(((0,0),(2047,-128),(2047,127),(0,-128))):
        if i<cases:x[i]=a;w[i]=b
    got=engine.conv(x,w);expected=engine.direct_conv(x,w)
    np.testing.assert_array_equal(got,expected)
    _,stages=engine.conv(x,w,True)
    # Verify that independently applied inverse integer scales are exactly divisible.
    np.testing.assert_array_equal(stages['P5'][...,:4] % 4,0)
    np.testing.assert_array_equal(stages['P5'][...,4:12] % 2,0)
    a=rng.integers(0,2048,size=(cases,48),dtype=np.int64)
    b=rng.integers(-128,128,size=(cases,48),dtype=np.int64)
    for i,(av,bv) in enumerate(((0,0),(2047,-128),(2047,127))):
        if i<cases:a[i]=av;b[i]=bv
    np.testing.assert_array_equal(engine.fc(a,b),(a*b).sum(axis=-1))
    # Restored-domain vs q-domain scaling identity supports the structural proxy.
    for bits in (7,6,5):
        restored,q,shift=weight_quant(w,bits,'even')
        np.testing.assert_array_equal(engine.conv(x,restored),engine.conv(x,q)*(1<<shift))
    np.testing.assert_array_equal(round_shift(np.array([-5,-4,-3,3,4,5]),2,'floor'),[-2,-1,-1,0,1,1])
    np.testing.assert_array_equal(round_shift(np.array([-6,-2,2,6]),2,'even'),[-2,0,0,2])
    allw=np.arange(-128,128)
    for bits in (8,7,6,5):
        for mode in ('floor','trunc','even'):
            restored,q,shift=weight_quant(allw,bits,mode)
            assert np.all((q>=-(1<<(bits-1)))&(q<=(1<<(bits-1))-1))
            assert np.all((restored>=-128)&(restored<=127))
            np.testing.assert_array_equal(restored,q*(1<<shift))
    for bits in (11,10,9,8):
        for mode in ('floor','trunc','even'):
            aq=activation_quant(np.arange(2048),bits,mode)
            assert np.all((aq>=0)&(aq<=2047))
    rows,cost=shared_cost()
    assert all(r['baseline_aw']==r['proposed_aw'] and r['baseline_bw']==r['proposed_bw']
               and r['baseline_pw']==r['proposed_pw'] for r in rows)
    assert cost['p2_register_bits']==1117 and cost['p3_register_bits']==1068 and cost['multiplier_bitproduct']==6274
    return dict(seed=seed,random_conv_cases=cases,random_fc_cases=cases,
                transform_vs_direct=True,inverse_shift_divisibility=True,
                weight_restoration_identity=True,quantizer_signed_corner_cases=True,
                baseline_lane_widths_reproduced=True,rtl_simulation_run=False)

def validate(params,images,labels,unique_ids,membership,out,seed=2026):
    contracts=arithmetic_contracts(seed)
    ref,v18a=RTLReferenceCNN(params),V18ACNN(params)
    rp,rt=run_records(ref,images,unique_ids)
    vp,vt=run_records(v18a,images,unique_ids)
    for i,x,y in zip(unique_ids,rt,vt):
        for name in x.__dataclass_fields__:
            if not np.array_equal(getattr(x,name),getattr(y,name)):
                raise AssertionError(f"image={i}, field={name}: Reference/V18A mismatch")
    np.testing.assert_array_equal(rp,vp)
    pos={int(i):k for k,i in enumerate(unique_ids)}
    mapping=np.array([pos[r['representative']] for r in membership])
    arrays=trace_arrays(vt)
    # Full original index order is essential for deterministic RTL trace comparison.
    np.savez_compressed(out/'expected_trace.npz',predictions=vp[mapping],labels=labels,
                        **{name:a[mapping] for name,a in arrays.items()})
    csv_write(out/'baseline_predictions.csv',[
        dict(image_index=i,expected=int(labels[i]),predicted=int(vp[mapping[i]]),
             correct=int(vp[mapping[i]]==labels[i]),representative=membership[i]['representative'])
        for i in range(len(images))])
    report=dict(**contracts,reference_v18a_all_fields_equal=True,unique_images=len(unique_ids),
                unique_correct=int(np.sum(vp==labels[unique_ids])),supplied_images=len(images),
                supplied_correct=int(np.sum(vp[mapping]==labels)),functional_model_not_cycle_model=True,
                rtl_trace_validation_pending=True,gate_simulation_pending=True,ppa_pending=True)
    json_write(out/'model_validation.json',report)
    csv_write(out/'baseline_shared_lane_cost.csv',shared_cost()[0])
    return report,vt
