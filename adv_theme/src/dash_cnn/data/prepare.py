"""Actual DASH representations -> source-aligned local patches -> grouped NPZ splits."""
import json
from pathlib import Path
import numpy as np
from PIL import Image
from ..common import write_json, sha256
from .mpd import Representation, local_segments
from .media import probe, reference_cache, decoded_cache, read_y, reference_at, ffmpeg_info
from .splits import assignments, segment_split
from .labels import ssim_local, grade
from .patches import coordinates, controls
from .audit import validate_splits, coverage

def _alignment(reference_dir, decoded_dir, ref_indices, decoded_indices, width, height, cfg):
    correlations, errors, used = [], [], []
    for ri, di in zip(ref_indices, decoded_indices):
        a = reference_at(reference_dir / f'{ri:08d}.png', width, height).astype(float)
        b = read_y(decoded_dir / f'{di:08d}.png').astype(float)
        # Flat frames cannot establish geometric/temporal alignment.
        if a.std() < 5 or b.std() < 5:
            continue
        ca = np.asarray(Image.fromarray(a.astype(np.uint8)).resize((128, 72), Image.Resampling.BILINEAR)).ravel()
        cb = np.asarray(Image.fromarray(b.astype(np.uint8)).resize((128, 72), Image.Resampling.BILINEAR)).ravel()
        correlations.append(float(np.corrcoef(ca, cb)[0, 1])); errors.append(float(np.abs(a - b).mean())); used.append(di)
    result = dict(informative_probe_frames=used, median_correlation=None if not correlations else float(np.median(correlations)),
                  median_mae=None if not errors else float(np.median(errors)),
                  note='Train-only heuristic alignment gate, not a proof of exact encoder preprocessing')
    result['passed'] = len(used) >= 3 and result['median_correlation'] >= cfg['minimum_median_correlation'] and result['median_mae'] <= cfg['maximum_median_mae']
    return result

def prepare(cfg, work, media_work=None):
    # Detect incompatible FFmpeg before the expensive streamed reference extraction.
    info = ffmpeg_info()
    print('FFmpeg:', info['version'], '| frame sync:', ' '.join(info['frame_sync_args']), flush=True)
    work = Path(work); media_root = Path(media_work) if media_work is not None else work
    media = json.loads((media_root / 'media_manifest.json').read_text())
    if media['status'] != 'DOWNLOADED':
        raise ValueError('download media, not just a plan, first')
    out = work / 'data'; out.mkdir(parents=True, exist_ok=True)
    if any((out / (s + '.npz')).exists() for s in ('train', 'validation', 'test')):
        raise ValueError('Prepared data already exists; use a new work directory to preserve split identity')
    records = {s: [] for s in ('train', 'validation', 'test')}; audits = []
    stride = int(cfg['segment_stride']); offset = int(cfg['alignment']['reference_frame_offset'])
    if stride < 1:
        raise ValueError('positive segment_stride')
    for v in media['videos']:
        reference = Path(v['reference_path'])
        if not reference.exists():
            raise ValueError('download references with --references first: ' + str(reference))
        reps = [Representation(**{k: r[k] for k in Representation.__dataclass_fields__}) for r in v['representations']]
        paths = {r['index']: Path(r['path']) for r in v['representations']}
        highest = max(reps, key=lambda r: r.bandwidth)
        canonical = local_segments(paths[highest.index], highest)
        duration = canonical[-1]['start'] + canonical[-1]['duration']
        table = assignments(v['id'], duration, cfg['split'])
        selected = []
        for s in canonical:
            split = segment_split(s, duration, table, cfg['split'])
            if split and s['segment_index'] % stride == 0:
                for dt in cfg['frame_offsets_seconds']:
                    if not 0 <= dt < 2:
                        raise ValueError('frame offsets must be within a 2-second segment')
                    if dt < s['duration']:
                        selected.append((s['segment_index'], split, s['start'] + float(dt)))
        if not selected or set(s[1] for s in selected) != set(records):
            raise ValueError('empty temporal split; use more segments/shorter stride')
        # Select informative alignment probes only from training segments.
        train_times = sorted(set(t for _, split, t in selected if split == 'train'))
        probe_times = [train_times[i] for i in np.linspace(0, len(train_times) - 1, min(cfg['alignment']['probe_frame_count'], len(train_times)), dtype=int)]
        ref_indices = [int(round(t * highest.fps)) + offset for _, _, t in selected]
        ref_dir = media_root / 'cache' / v['id'] / 'reference'
        ref_info = reference_cache(reference, ref_indices, ref_dir)
        if abs(ref_info['fps'] - highest.fps) > 1e-6:
            raise ValueError('reference and DASH frame rates differ; explicit temporal alignment is required')
        hi_dir = media_root / 'cache' / v['id'] / f'rep_{highest.index:02d}'
        hi_indices = [int(round(t * highest.fps)) for _, _, t in selected]
        hi_probe = probe(paths[highest.index])
        decoded_cache(paths[highest.index], hi_indices, hi_dir)
        aligned = _alignment(ref_dir, hi_dir, [int(round(t * highest.fps)) + offset for t in probe_times],
                             [int(round(t * highest.fps)) for t in probe_times], highest.width, highest.height, cfg['alignment'])
        aligned.update(video_id=v['id'], reference_frame_offset=offset, reference_header=ref_info['header'], highest_rep=highest.index)
        write_json(work / 'reports' / (v['id'] + '_alignment.json'), aligned)
        if not aligned['passed']:
            raise ValueError(f'{v["id"]}: source alignment failed. Read reports/{v["id"]}_alignment.json; do not train on guessed labels')
        for r in reps:
            meta = probe(paths[r.index])
            if (meta['width'], meta['height']) != (r.width, r.height) or abs(meta['fps'] - r.fps) > 1e-6 or abs(r.fps - ref_info['fps']) > 1e-6:
                raise ValueError('decoded stream disagrees with MPD/reference')
            segments = local_segments(paths[r.index], r)
            if len(segments) != len(canonical) or any(abs(a['start'] - b['start']) > 1e-6 or abs(a['duration'] - b['duration']) > 1e-6 for a, b in zip(segments, canonical)):
                raise ValueError('representations have different segment timelines')
            dec_dir = media_root / 'cache' / v['id'] / f'rep_{r.index:02d}'
            decoded_cache(paths[r.index], hi_indices, dec_dir)
            for segid, split, t in selected:
                fi = int(round(t * r.fps)); ri = fi + offset
                q = read_y(dec_dir / f'{fi:08d}.png'); original = reference_at(ref_dir / f'{ri:08d}.png', r.width, r.height)
                seg = segments[segid]; bitrate = seg['size_bytes'] * 8 / seg['duration']
                for pi, (y, x) in enumerate(coordinates(r.height, r.width, cfg['patch_grid'])):
                    patch = q[y:y + 28, x:x + 28].copy(); target = original[y:y + 28, x:x + 28]
                    score = ssim_local(target, patch); md, hc = controls(patch, bitrate, r.width, r.height, r.fps)
                    records[split].append(dict(x=patch, y=grade(score), ssim=score, video_id=v['id'],
                        group_id=f'{v["id"]}/segment/{segid}', sample_id=f'{v["id"]}/{segid}/{r.index}/{fi}/{pi}',
                        segment_start=seg['start'], segment_duration=seg['duration'], guard_seconds=float(cfg['split']['guard_seconds']),
                        source_sha256=ref_info['source_sha256'], representation_index=r.index, frame_index=fi,
                        reference_frame_index=ri, patch_y=y, patch_x=x, width=r.width, height=r.height,
                        bitrate_bps=bitrate, metadata=md, handcrafted=hc))
            print(v['id'], 'representation', r.index, 'patches complete', flush=True)
            audits.append(dict(video_id=v['id'], representation=r.index, stream=meta, segment_count=len(segments),
                               last_segment_seconds=segments[-1]['duration'], media_sha256=sha256(paths[r.index])))
    datasets = {}
    for split, rs in records.items():
        if not rs:
            raise ValueError('empty split')
        datasets[split] = {k: np.asarray([r[k] for r in rs]) for k in rs[0]}
    check = validate_splits(*datasets.values())
    # All outputs are published only after validation; a failure leaves no misleading NPZ files.
    for split, d in datasets.items():
        np.savez_compressed(out / (split + '.npz'), **d)
    report = dict(status='PREPARED_CLASS_COVERAGE_REQUIRES_REVIEW', split_audit=check,
                  splits={s: coverage(d) for s, d in datasets.items()}, media=audits,
                  label='local Gaussian SSIM, fixed AWS-inspired four bins', resampling='Pillow bicubic on source Y only',
                  input='decoded Y bytes, never original or SSIM', real_accuracy='NOT_MEASURED')
    write_json(work / 'reports' / 'dataset_audit.json', report); write_json(work / 'config_snapshot.json', cfg)
    print(json.dumps(report['splits'], indent=2)); return report
