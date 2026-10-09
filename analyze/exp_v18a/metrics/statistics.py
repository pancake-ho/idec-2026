"""Descriptive metrics; no statistical score is treated as a precision proof."""
from __future__ import annotations
import numpy as np
from exp_v18a.io.common import required_signed_bits

def stats(x):
    x = np.asarray(x,dtype=np.int64).reshape(-1)
    if not len(x):
        raise ValueError("empty statistics")
    lo,hi = int(x.min()),int(x.max())
    return dict(count=len(x),min=lo,max=hi,mean=float(x.mean()),std=float(x.std()),
                p01=float(np.percentile(x,1)),p50=float(np.percentile(x,50)),p99=float(np.percentile(x,99)),
                zero_ratio=float(np.mean(x==0)),negative_ratio=float(np.mean(x<0)),
                observed_required_signed_bits=required_signed_bits(lo,hi))

def error_metrics(reference,candidate):
    a,b = np.asarray(reference,dtype=np.float64),np.asarray(candidate,dtype=np.float64)
    if a.shape != b.shape:
        raise ValueError("error metric shapes differ")
    d=b-a
    mse=float(np.mean(d*d))
    signal=float(np.mean(a*a))
    sqnr = float(10*np.log10(signal/mse)) if mse>0 and signal>0 else None
    return dict(mse=mse,max_abs_error=float(np.max(np.abs(d))),sqnr_db=sqnr,
                exact=int(np.array_equal(a,b)),changed_elements=int(np.count_nonzero(d)))

def true_margin(logits,labels):
    logits=np.asarray(logits,dtype=np.int64)
    labels=np.asarray(labels,dtype=np.int64)
    other=logits.copy()
    other[np.arange(len(labels)),labels]=-1000000
    return logits[np.arange(len(labels)),labels]-other.max(axis=1)

def class_scatter(features,labels):
    """Class-balanced centroid scatter. A proxy, NOT DDAMQ eq.(6)-(9).

    Uses the full flattened feature map, preserving spatial coordinates.
    Reports conventional between/within and its reciprocal with explicit names.
    """
    x=np.asarray(features,dtype=np.float64).reshape(len(labels),-1)
    labels=np.asarray(labels)
    classes=np.unique(labels)
    means=np.stack([x[labels==c].mean(axis=0) for c in classes])
    center=means.mean(axis=0)
    within=float(np.mean([np.mean((x[labels==c]-means[i])**2) for i,c in enumerate(classes)]))
    between=float(np.mean((means-center)**2))
    eps=1e-12
    return dict(classes=len(classes),features=x.shape[1],within_mse=within,between_mse=between,
                between_over_within=between/(within+eps),within_over_between=within/(between+eps),
                metric_definition="class-balanced full-vector centroid scatter; not exact DDAMQ reproduction")

def compare_predictions(base_pred,new_pred,base_logits,new_logits,labels):
    base_pred,new_pred,labels=map(np.asarray,(base_pred,new_pred,labels))
    bm,nm=true_margin(base_logits,labels),true_margin(new_logits,labels)
    base_ok,new_ok=base_pred==labels,new_pred==labels
    return dict(images=len(labels),baseline_correct=int(base_ok.sum()),candidate_correct=int(new_ok.sum()),
                decision_changes=int(np.sum(base_pred!=new_pred)),fixed=int(np.sum(~base_ok&new_ok)),
                broken=int(np.sum(base_ok&~new_ok)),wrong_to_other_wrong=int(np.sum(~base_ok&~new_ok&(base_pred!=new_pred))),
                baseline_margin_median=float(np.median(bm)),candidate_margin_median=float(np.median(nm)),
                margin_delta_mean=float(np.mean(nm-bm)),nonpositive_margin=int(np.sum(nm<=0)),
                **{"logit_"+k:v for k,v in error_metrics(base_logits,new_logits).items()})
