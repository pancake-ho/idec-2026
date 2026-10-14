"""Four-class metrics with explicit support, adjacent errors and severe->excellent misses."""
import numpy as np
from ..spec import NUM_CLASSES, CLASSES

def metrics(y, pred, video_id=None):
    y, p = np.asarray(y), np.asarray(pred)
    if y.shape != p.shape or y.ndim != 1 or not len(y):
        raise ValueError('nonempty matched 1D labels')
    if min(y.min(), p.min()) < 0 or max(y.max(), p.max()) >= NUM_CLASSES:
        raise ValueError('class range')
    cm = np.zeros((NUM_CLASSES, NUM_CLASSES), np.int64); np.add.at(cm, (y, p), 1)
    support = cm.sum(1); den = support + cm.sum(0)
    f1 = np.divide(2 * np.diag(cm), den, out=np.zeros(NUM_CLASSES), where=den > 0)
    recall = np.divide(np.diag(cm), support, out=np.zeros(NUM_CLASSES), where=support > 0)
    r = dict(n=len(y), accuracy=float(np.trace(cm) / len(y)), macro_f1=float(f1.mean()),
             class_names=list(CLASSES), class_support=support.tolist(), class_f1=f1.tolist(),
             class_recall=recall.tolist(), confusion=cm.tolist(),
             severe_missed_as_excellent=None if not support[3] else float(cm[3, 0] / support[3]),
             mean_absolute_grade_error=float(np.abs(y - p).mean()),
             all_classes_present=bool(np.all(support > 0)))
    if video_id is not None:
        ids = np.asarray(video_id).astype(str)
        r['videos'] = {k: metrics(y[ids == k], p[ids == k]) for k in sorted(set(ids))}
    return r
