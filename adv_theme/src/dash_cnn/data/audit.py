"""Dataset identity, grouped leakage, temporal gap and label coverage checks."""
import numpy as np
from ..spec import NUM_CLASSES
from .labels import grade

def load(path):
    with np.load(path, allow_pickle=False) as f:
        return {k: f[k] for k in f.files}

def validate_splits(*datasets):
    groups = []; samples = []; spans = []
    required = ('y', 'video_id', 'group_id', 'sample_id', 'ssim', 'segment_start', 'segment_duration',
                'guard_seconds', 'source_sha256', 'frame_index', 'metadata', 'handcrafted')
    for d in datasets:
        n = len(d['x'])
        if not n or d['x'].dtype != np.uint8 or d['x'].shape != (n, 28, 28):
            raise ValueError('nonempty uint8 N,28,28 patches required')
        for k in required:
            if k not in d or len(d[k]) != n:
                raise ValueError(k + ' missing/length mismatch')
        if not np.issubdtype(d['y'].dtype, np.integer) or d['y'].min() < 0 or d['y'].max() >= NUM_CLASSES:
            raise ValueError('four-class integer labels required')
        if not np.array_equal(d['y'], np.array([grade(v) for v in d['ssim']])):
            raise ValueError('SSIM/label boundary mismatch')
        for k in ('metadata', 'handcrafted', 'segment_start', 'segment_duration', 'guard_seconds'):
            if not np.isfinite(d[k]).all():
                raise ValueError(k + ' not finite')
        if np.any(d['segment_duration'] <= 0) or np.any(d['guard_seconds'] < 0):
            raise ValueError('invalid temporal span')
        for k in ('video_id', 'group_id', 'sample_id', 'source_sha256'):
            if '' in set(d[k].astype(str)):
                raise ValueError('empty ' + k)
        ss = set(d['sample_id'].astype(str))
        if len(ss) != n:
            raise ValueError('duplicate sample ID')
        groups.append(set(d['group_id'].astype(str))); samples.append(ss)
        spans.append(set(zip(d['video_id'].astype(str), d['source_sha256'].astype(str),
                             d['segment_start'].astype(float), d['segment_duration'].astype(float), d['guard_seconds'].astype(float))))
    for i in range(len(datasets)):
        for j in range(i):
            if groups[i] & groups[j] or samples[i] & samples[j]:
                raise ValueError('segment or sample crosses splits')
            for vi, hi, si, di, gi in spans[i]:
                for vj, hj, sj, dj, gj in spans[j]:
                    if vi != vj and hi != hj:
                        continue
                    distance = max(si, sj) - min(si + di, sj + dj)
                    if distance < max(gi, gj) - 1e-6:
                        raise ValueError('overlapping/too-close temporal groups across splits')
    return dict(policy='blocked_temporal_with_guard', segment_groups_disjoint=True, temporal_gap_checked=True,
                content_disjoint=False, source_counts=[len(set(d['video_id'])) for d in datasets],
                class_counts=[np.bincount(d['y'], minlength=NUM_CLASSES).tolist() for d in datasets],
                note='Prototype within-content split; not an unseen-content generalization claim')

def coverage(d):
    result = dict(n=len(d['x']), classes=np.bincount(d['y'], minlength=NUM_CLASSES).tolist())
    result['videos'] = {str(v): np.bincount(d['y'][d['video_id'] == v], minlength=NUM_CLASSES).tolist()
                        for v in sorted(set(d['video_id']))}
    result['all_classes_present'] = all(result['classes'])
    return result
