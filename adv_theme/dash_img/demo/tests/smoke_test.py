#!/usr/bin/env python3
"""No-dependency HTTP / MPD / Range regression checks, no real BBB required."""
from __future__ import annotations
import importlib.util
import json
import tempfile
import threading
import urllib.error
import urllib.request
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / 'server.py'
spec = importlib.util.spec_from_file_location('bbb_demo_server', APP)
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)

MPD = '''<?xml version="1.0"?><MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT8.0S"><Period><AdaptationSet maxFrameRate="24"><Representation id="low" codecs="avc1.42c00d" width="320" height="240" bandwidth="131087" /><Representation id="mid" codecs="avc1.42c015" width="854" height="480" bandwidth="595491" /><Representation id="high" codecs="avc1.42c032" width="1920" height="1080" bandwidth="3078587" /></AdaptationSet></Period></MPD>'''


def read(url, hdr=None, method='GET'):
    with urllib.request.urlopen(urllib.request.Request(url, headers=hdr or {}, method=method), timeout=8) as resp:
        return resp.status, dict(resp.headers), resp.read()


def main():
    with tempfile.TemporaryDirectory(prefix='bbb_demo_smoke_') as td:
        root = Path(td)
        work = root / 'runs/assets'
        media = work / 'media/bbb'
        media.mkdir(parents=True)
        mpd = root / 'bbb.mpd'
        mpd.write_text(MPD)
        data = bytes([i % 251 for i in range(10_000)])
        for idx in (0, 1, 2):
            path = media / f'rep_{idx:02}.mp4'
            path.write_bytes(data)
            Path(str(path) + '.receipt.json').write_text(json.dumps({'size_bytes': len(data)}))
        catalog, lookup = server_module.build_catalog(root, work, mpd)
        assert len(lookup) == 3
        assert catalog['representations'][1]['bandwidth'] == 595491
        assert catalog['duration'] == 8
        app = server_module.DemoServer(('127.0.0.1', 0), catalog, lookup)
        url = f'http://127.0.0.1:{app.server_port}'
        worker = threading.Thread(target=app.serve_forever, daemon=True)
        worker.start()
        try:
            status, _, reply = read(url + '/api/health')
            assert status == 200 and json.loads(reply)['available'] == 3
            status, headers, reply = read(url + '/api/manifest')
            assert json.loads(reply)['representations'][2]['width'] == 1920
            status, headers, reply = read(url + '/media/1', {'Range': 'bytes=10-109'})
            assert status == 206 and headers['Content-Range'] == 'bytes 10-109/10000'
            assert reply == data[10:110]
            status, headers, reply = read(url + '/media/1', {'Range': 'bytes=-20'})
            assert status == 206 and reply == data[-20:]
            status, headers, reply = read(url + '/media/1', method='HEAD')
            assert status == 200 and headers['Content-Length'] == '10000' and not reply
            for asset in ('/', '/app.js', '/style.css'):
                assert read(url + asset)[0] == 200
            for endpoint in ('/media/55', '/media/%2e%2e/secret'):
                try:
                    read(url + endpoint)
                    raise AssertionError('Expected 404 for ' + endpoint)
                except urllib.error.HTTPError as e:
                    assert e.code == 404
            try:
                read(url + '/media/1', {'Range': 'bytes=15000-'})
                raise AssertionError('Expected 416')
            except urllib.error.HTTPError as e:
                assert e.code == 416
        finally:
            app.shutdown()
            worker.join(timeout=3)
            app.server_close()
    print('PASS: MPD order, receipts, API, static, HTTP range (incl suffix), HEAD, 404, 416')

if __name__ == '__main__':
    main()
