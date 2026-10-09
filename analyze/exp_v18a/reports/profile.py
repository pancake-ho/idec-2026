"""Build descriptive channel/class and transform-lane tables."""
from __future__ import annotations
import numpy as np
from exp_v18a.io.common import csv_write, json_write, trace_arrays
from exp_v18a.metrics.statistics import stats, class_scatter, true_margin
from exp_v18a.models import engine

def profile(model,images,labels,ids,traces,out,split_name):
    arrays=trace_arrays(traces)
    rows=[]
    for name in ("conv1_out","pool1","conv2_out","pool2"):
        a=arrays[name]
        for ch in range(a.shape[1]):
            for label in [-1]+list(range(10)):
                mask=np.ones(len(ids),dtype=bool) if label==-1 else labels[ids]==label
                if mask.any():
                    rows.append(dict(tensor=name,channel=ch,label=label,split=split_name,**stats(a[mask,ch])))
    csv_write(out/"channel_class_stats.csv",rows)
    weights=[]
    for name in ("conv1_w","conv2_w","fc_w"):
        a=getattr(model.p,name)
        for oc in range(len(a)):
            weights.append(dict(tensor=name,output_channel=oc,**stats(a[oc])))
    csv_write(out/"weight_channel_stats.csv",weights)
    scatter=[]
    for name in ("pool1","pool2"):
        a=arrays[name]
        for ch in [-1]+list(range(a.shape[1])):
            scatter.append(dict(tensor=name,channel=ch,split=split_name,
                                **class_scatter(a if ch==-1 else a[:,ch],labels[ids])))
    csv_write(out/"feature_separability.csv",scatter)
    margins=true_margin(arrays["logits"],labels[ids])
    csv_write(out/"baseline_margins.csv",[
        dict(image_index=int(i),label=int(labels[i]),prediction=int(np.argmax(arrays["logits"][k])),
             trueclass_margin=int(margins[k]),**{f"logit_{c}":int(arrays["logits"][k,c]) for c in range(10)})
        for k,i in enumerate(ids)])
    # Keep each operating mode separate. Never use this logical order as SAIF/VCD activity.
    samples={}
    for tr in traces:
        for mode,oc,ic,s in model.engine_requests(tr):
            for stage,a in s.items():
                samples.setdefault((mode,stage),[]).append(a.reshape(-1,a.shape[-1]))
    lane_rows=[]
    for (mode,stage),chunks in sorted(samples.items()):
        a=np.concatenate(chunks,axis=0)
        for j in range(a.shape[1]):
            row=dict(mode=mode,stage=stage,coordinate=j,split=split_name,**stats(a[:,j]))
            if stage in ("P2a","P2b","P3"):
                bits=int({"P2a":engine.AW,"P2b":engine.BW,"P3":engine.PW}[stage][j])
                row["physical_register_bits"]=bits
            else:
                row["physical_register_bits"]=""
            lane_rows.append(row)
    csv_write(out/"transform_stats.csv",lane_rows)
    wrap=[]
    for name,original,limited in (
        ("conv1_acc20",np.stack([t.conv1_acc_math for t in traces]),np.stack([t.conv1_acc20 for t in traces])),
        ("conv2_partial20",np.stack([t.conv2_partial_math for t in traces]),np.stack([t.conv2_partial20 for t in traces])),
        ("conv2_acc20",np.stack([t.conv2_full_math for t in traces]),np.stack([t.conv2_acc20 for t in traces])),
        ("conv1_output12",np.stack([(t.conv1_acc20>>8)+model.p.conv1_b[:,None,None] for t in traces]),arrays["conv1_out"]),
        ("conv2_output12",np.stack([(t.conv2_internal14>>1)+model.p.conv2_b[:,None,None] for t in traces]),arrays["conv2_out"]),
        ("fc_acc20",np.stack([t.fc_acc_math for t in traces]),np.stack([t.fc_acc20 for t in traces])),
    ):
        d=original!=limited
        wrap.append(dict(location=name,split=split_name,elements=int(d.size),
                         changed_elements=int(d.sum()),affected_unique_images=int(d.reshape(len(ids),-1).any(axis=1).sum())))
    csv_write(out/"wrap_stats.csv",wrap)
    json_write(out/"profile_metadata.json",dict(split=split_name,unique_images=len(ids),
        observed_widths_are_not_proofs=True,transform_order_is_not_cycle_activity=True,
        feature_metric_is_exact_ddamq=False,full_ddamq_training_implemented=False))
    return dict(profile_unique_images=len(ids),profile_split=split_name,
                pool1_channel_zero_ratios=[float(np.mean(arrays["pool1"][:,c]==0)) for c in range(3)])
