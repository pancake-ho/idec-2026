"""Single-factor sensitivity and optional small layer-wise weight grid.

Calibration ranks candidates; validation selects ONE. Holdout is evaluated only
after selection. The final supplied-file accuracy includes previously seen data.
"""
from __future__ import annotations
from itertools import product
import numpy as np
from exp_v18a.io.common import RTLReferenceCNN, run_records, trace_arrays, csv_write, json_write
from exp_v18a.models.cnn import V18ACNN
from exp_v18a.experiments.quantization import quant_parameters
from exp_v18a.metrics.statistics import compare_predictions, error_metrics, true_margin
from exp_v18a.metrics.hardware_cost import shared_cost

class FastCandidateCNN(V18ACNN):
    # Direct-convolution fast path. Exact arithmetic equivalence is checked for
    # the unmodified model and the selected candidate using the V18A engine.
    _conv1=RTLReferenceCNN._conv1
    _conv2=RTLReferenceCNN._conv2
    _fully_connected=RTLReferenceCNN._fully_connected

def candidate_specs(grid=False,roundings=("floor","even")):
    specs=[dict(name="baseline",wbits=(8,8,8),abits=(11,11),rounding="floor",kind="baseline")]
    for mode in roundings:
        if grid:
            combinations=list(product((8,7,6,5),repeat=3))
        else:
            combinations=[]
            for layer in range(3):
                for bits in (7,6,5):
                    wb=[8,8,8];wb[layer]=bits;combinations.append(tuple(wb))
        for wb in combinations:
            if wb!=(8,8,8):
                specs.append(dict(name=f"W{wb[0]}_{wb[1]}_{wb[2]}_{mode}",wbits=wb,
                                  abits=(11,11),rounding=mode,kind="weight_grid" if grid else "weight_single"))
        for layer in range(2):
            for bits in (10,9,8):
                ab=[11,11];ab[layer]=bits
                specs.append(dict(name=f"A{ab[0]}_{ab[1]}_{mode}",wbits=(8,8,8),
                                  abits=tuple(ab),rounding=mode,kind="activation_single"))
    return specs

def evaluate(model,images,labels,ids,bp,bt):
    pred,traces=run_records(model,images,ids)
    a,b=trace_arrays(bt),trace_arrays(traces)
    result=compare_predictions(bp,pred,a["logits"],b["logits"],labels[ids])
    for name in ("conv1_out","pool1","conv2_out","pool2"):
        result.update({name+"_"+k:v for k,v in error_metrics(a[name],b[name]).items()})
    return result,pred,traces

def run_sweep(params,images,labels,unique_ids,splits,out,grid=False,roundings=("floor","even")):
    ids=np.concatenate((splits["calibration"],splits["validation"]))
    ncal=len(splits["calibration"])
    base=FastCandidateCNN(params)
    bp,bt=run_records(base,images,ids)
    barrays=trace_arrays(bt)
    rows=[]
    baseline_proxy=shared_cost()[1]
    specs=candidate_specs(grid,roundings)
    cache={}
    for index,spec in enumerate(specs):
        qp=quant_parameters(params,spec["wbits"],spec["rounding"])
        model=FastCandidateCNN(qp,spec["abits"],spec["rounding"])
        # Reuse numerically identical candidates, including unchanged W8.
        key=(qp.conv1_w.tobytes(),qp.conv2_w.tobytes(),qp.fc_w.tobytes(),spec["abits"],spec["rounding"])
        if key not in cache:
            cache[key]=run_records(model,images,ids)
        pred,tr=cache[key]
        arrays=trace_arrays(tr)
        _,cost=shared_cost(spec["wbits"],spec["abits"])
        row=dict(candidate=spec["name"],kind=spec["kind"],w1=spec["wbits"][0],w2=spec["wbits"][1],
                 wfc=spec["wbits"][2],a_pool1=spec["abits"][0],a_pool2=spec["abits"][1],rounding=spec["rounding"])
        for split,sl in (("calibration",slice(0,ncal)),("validation",slice(ncal,None))):
            metric=compare_predictions(bp[sl],pred[sl],barrays["logits"][sl],arrays["logits"][sl],labels[ids[sl]])
            row.update({split+"_"+k:v for k,v in metric.items()})
        for name in ("conv1_out","pool1","conv2_out","pool2"):
            row.update({"calibration_"+name+"_"+k:v for k,v in error_metrics(barrays[name][:ncal],arrays[name][:ncal]).items()})
        for name in ("conv1_w","conv2_w","fc_w"):
            row.update({name+"_"+k:v for k,v in error_metrics(getattr(params,name),getattr(qp,name)).items()})
        row.update({"proxy_"+k:v for k,v in cost.items()})
        row["proxy_bitproduct_reduction_pct"]=100*(1-cost["multiplier_bitproduct"]/baseline_proxy["multiplier_bitproduct"])
        row["calibration_accuracy_retained"]=int(row["calibration_candidate_correct"]>=row["calibration_baseline_correct"])
        row["validation_accuracy_retained"]=int(row["validation_candidate_correct"]>=row["validation_baseline_correct"])
        # Retain accuracy on BOTH internal selection splits, then minimize structural cost.
        # Margin and decision changes are diagnostics/tie-breakers, not invented official requirements.
        row["internal_eligible"]=int(row["calibration_accuracy_retained"] and row["validation_accuracy_retained"])
        rows.append(row)
        print(f"[{index+1}/{len(specs)}] {spec['name']}: cal={row['calibration_candidate_correct']}/{ncal}, "
              f"val={row['validation_candidate_correct']}/{len(ids)-ncal}, proxy={cost['multiplier_bitproduct']}",flush=True)
    eligible=[r for r in rows if r["internal_eligible"]]
    chosen=min(eligible,key=lambda r:(r["proxy_multiplier_bitproduct"],-r["validation_candidate_correct"],
                -r["calibration_candidate_correct"],r["validation_decision_changes"],r["candidate"]))
    selected=next(s for s in specs if s["name"]==chosen["candidate"])
    csv_write(out/"sensitivity.csv",rows)
    rows_cost,cost=shared_cost(selected["wbits"],selected["abits"])
    csv_write(out/"selected_shared_lane_cost.csv",rows_cost)
    qp=quant_parameters(params,selected["wbits"],selected["rounding"])
    chosen_model=V18ACNN(qp,selected["abits"],selected["rounding"])
    # Check selected direct model vs transform model on ALL unique images, field by field.
    fast=FastCandidateCNN(qp,selected["abits"],selected["rounding"])
    cp,ct=run_records(chosen_model,images,unique_ids)
    fp,ft=run_records(fast,images,unique_ids)
    for x,y in zip(ct,ft):
        for name in x.__dataclass_fields__:
            if not np.array_equal(getattr(x,name),getattr(y,name)):
                raise AssertionError("Selected candidate arithmetic mismatch: "+name)
    if not np.array_equal(cp,fp):
        raise AssertionError("Selected candidate prediction mismatch")
    fullbp,fullbt=run_records(V18ACNN(params),images,unique_ids)
    pos={int(i):k for k,i in enumerate(unique_ids)}
    hi=np.array([pos[int(i)] for i in splits["holdout"]])
    hold=compare_predictions(fullbp[hi],cp[hi],np.stack([fullbt[k].logits for k in hi]),
                             np.stack([ct[k].logits for k in hi]),labels[splits["holdout"]])
    # Map representative predictions to all original supplied-file entries, without 10x recomputation.
    by_pixels={images[int(i)].tobytes():k for k,i in enumerate(unique_ids)}
    full_map=np.array([by_pixels[x.tobytes()] for x in images])
    supplied=compare_predictions(fullbp[full_map],cp[full_map],
              np.stack([t.logits for t in fullbt])[full_map],np.stack([t.logits for t in ct])[full_map],labels)
    decisions=[]
    baseline_margins=true_margin(np.stack([t.logits for t in fullbt]),labels[unique_ids])
    selected_margins=true_margin(np.stack([t.logits for t in ct]),labels[unique_ids])
    for k,i in enumerate(unique_ids):
        decisions.append(dict(image_index=int(i),label=int(labels[i]),baseline_pred=int(fullbp[k]),
                 selected_pred=int(cp[k]),baseline_correct=int(fullbp[k]==labels[i]),
                 selected_correct=int(cp[k]==labels[i]),
                 baseline_trueclass_margin=int(baseline_margins[k]),
                 selected_trueclass_margin=int(selected_margins[k]),
                 margin_delta=int(selected_margins[k]-baseline_margins[k]),
                 split=next(n for n,a in splits.items() if int(i) in set(map(int,a)))))
    csv_write(out/"selected_image_decisions.csv",decisions)
    json_write(out/"selected_candidate.json",dict(configuration=selected,
        selection_rule="calibration and validation correct>=baseline, minimize shared multiplier bit-product proxy; "
                       "accuracy and decision-change tie-breakers. Holdout unused until selection.",
        holdout=hold,supplied_file_descriptive=supplied,shared_cost_proxy=cost,
        selected_engine_vs_direct_all_unique=True,rtl_implemented=False,ppa_verified=False,
        scope="Uniform per-layer power-of-two STEP PTQ. No per-channel scale, clipping-threshold search, "
              "QAT or exact DDAMQ bit-allocation algorithm. Proxy assumes a future q-domain datapath "
              "with static layer shifts restored after dot products; current V18A retains its physical widths."))
    return dict(selected_candidate=selected["name"],holdout_correct=hold["candidate_correct"],
                holdout_images=hold["images"],supplied_correct=supplied["candidate_correct"],
                candidate_count=len(rows),ppa_verified=False)
