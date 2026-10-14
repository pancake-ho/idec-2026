"""Resumable HTTP downloads; receipts prevent silently trusting partial media."""
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from ..common import sha256, write_json
from .mpd import parse_mpd

def head(url):
    with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=45) as r:
        return dict(url=r.url, size_bytes=int(r.headers['Content-Length']) if r.headers.get('Content-Length') else None,
                    etag=r.headers.get('ETag'), last_modified=r.headers.get('Last-Modified'))

def download(url, destination):
    dst = Path(destination); dst.parent.mkdir(parents=True, exist_ok=True)
    remote = head(url); receipt = dst.with_suffix(dst.suffix + '.receipt.json')
    if dst.exists():
        if not receipt.exists():
            raise ValueError(f'Existing file has no download receipt: {dst}; register local media separately or move it aside')
        saved = json.loads(receipt.read_text())
        if saved['url'] != url or dst.stat().st_size != saved['size_bytes'] or sha256(dst) != saved['sha256']:
            raise ValueError(f'Existing download identity/hash mismatch: {dst}')
        print('verified existing', dst, flush=True); return saved
    part = dst.with_suffix(dst.suffix + '.part'); meta = part.with_suffix(part.suffix + '.json')
    if part.exists():
        if not meta.exists() or json.loads(meta.read_text()) != remote:
            raise ValueError(f'Partial download source changed: {part}; move it aside before retrying')
    else:
        write_json(meta, remote)
    for attempt in range(3):
        start = part.stat().st_size if part.exists() else 0
        total = remote['size_bytes']
        if total is not None and start > total:
            raise ValueError('partial download exceeds remote length')
        if total is not None and start == total:
            break
        headers = {'User-Agent': 'DASH-AVC4-research/1.0', 'Accept-Encoding': 'identity'}
        if start:
            headers['Range'] = f'bytes={start}-'
            if remote['etag']:
                headers['If-Range'] = remote['etag']
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
                if start and (response.status != 206 or not response.headers.get('Content-Range', '').startswith(f'bytes {start}-')):
                    raise ValueError('server did not honor resumable range; partial file kept')
                with part.open('ab' if start else 'wb') as f:
                    printed = start
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        f.write(chunk); start += len(chunk)
                        if start - printed >= 128 * 1024 * 1024:
                            print(dst.name, f'{start / 1e9:.2f} GB', flush=True); printed = start
            if total is not None and start != total:
                raise OSError(f'incomplete transfer: {start}/{total}')
            break
        except (OSError, urllib.error.URLError):
            if attempt == 2:
                raise
            time.sleep(1)
    os.replace(part, dst); meta.unlink(missing_ok=True)
    saved = dict(url=url, size_bytes=dst.stat().st_size, sha256=sha256(dst), remote=remote)
    write_json(receipt, saved); print('downloaded', dst, flush=True)
    return saved

def acquire(cfg, work, references=False, plan=False):
    work = Path(work); videos = []
    for v in cfg['videos']:
        root = work / 'media' / v['id']; mpd = root / 'manifest.mpd'
        download(v['mpd_url'], mpd)
        reps = parse_mpd(mpd, v['mpd_url'])
        selected = cfg.get('representation_indices', 'all')
        if selected != 'all':
            if not selected or len(set(selected)) != len(selected) or any(i < 0 or i >= len(reps) for i in selected):
                raise ValueError('invalid representation selection')
            reps = [r for r in reps if r.index in selected]
        info = dict(id=v['id'], mpd=str(mpd.resolve()), mpd_url=v['mpd_url'], reference_url=v['reference_url'],
                    reference_path=str((root / 'reference.y4m.xz').resolve()), representations=[])
        for r in reps:
            path = root / f'rep_{r.index:02d}.mp4'
            record = dict(r.__dict__, path=str(path.resolve()))
            record['remote'] = head(r.url) if plan else download(r.url, path)
            info['representations'].append(record)
        if references or plan:
            info['reference_remote'] = head(v['reference_url']) if plan else download(v['reference_url'], info['reference_path'])
        videos.append(info)
    result = dict(status='DOWNLOAD_PLAN' if plan else 'DOWNLOADED', videos=videos)
    if plan:
        result['known_download_bytes'] = sum((v.get('reference_remote', {}).get('size_bytes') or 0) +
                                            sum(r['remote'].get('size_bytes') or 0 for r in v['representations']) for v in videos)
        print('Known total download GB:', result['known_download_bytes'] / 1e9)
    write_json(work / ('download_plan.json' if plan else 'media_manifest.json'), result)
    return result
