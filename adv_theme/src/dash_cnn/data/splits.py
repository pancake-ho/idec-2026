"""Blocked temporal prototype split. All representations of a scene interval stay together."""
import numpy as np

def assignments(video_id, duration, cfg):
    block = float(cfg['block_seconds']); guard = float(cfg['guard_seconds'])
    if block <= 2 * guard or guard < 0:
        raise ValueError('block_seconds must exceed two guard margins')
    n = int(np.ceil(duration / block))
    if n < 7:
        raise ValueError('at least seven temporal blocks per movie required')
    # Stable movie-specific seed, never Python hash().
    import hashlib
    seed = int(cfg['seed']) + int(hashlib.sha256(video_id.encode()).hexdigest()[:8], 16)
    order = np.random.default_rng(seed).permutation(n)
    nv = max(1, round(n * float(cfg['validation_fraction'])))
    nt = max(1, round(n * float(cfg['test_fraction'])))
    if nv + nt >= n:
        raise ValueError('no training blocks')
    table = {int(i): 'train' for i in order}
    table.update({int(i): 'validation' for i in order[:nv]})
    table.update({int(i): 'test' for i in order[nv:nv + nt]})
    return table

def segment_split(segment, duration, table, cfg):
    block = float(cfg['block_seconds']); guard = float(cfg['guard_seconds'])
    start, end = segment['start'], segment['start'] + segment['duration']
    k = int(start // block)
    if k not in table or start < k * block + guard or end > min((k + 1) * block - guard, duration):
        return None
    return table[k]
