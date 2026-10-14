"""Data tests exercise real split/label/SIDX/cache failure modes, not implementation copies."""
import copy
import json
import lzma
import struct
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.data.mpd import parse_mpd, parse_sidx
from dash_cnn.data.media import reference_cache, read_y
from dash_cnn.data.labels import grade
from dash_cnn.data.audit import validate_splits
from dash_cnn.data.splits import assignments, segment_split
from dash_cnn.evaluation.metrics import metrics
from make_smoke_data import dataset

class DataTests(unittest.TestCase):
    def test_official_manifests(self):
        for name in ('BigBuckBunny', 'ElephantsDream'):
            p = ROOT / 'configs' / (name + '_2s_onDemand_2014_05_09.mpd')
            r = parse_mpd(p, 'https://example.test/2sec/manifest.mpd')
            self.assertEqual(len(r), 20); self.assertEqual(r[0].fps, 24)
            self.assertTrue(all(a.bandwidth <= b.bandwidth for a, b in zip(r, r[1:])))
            self.assertTrue(r[0].url.startswith('https://example.test/2sec/'))

    def test_sidx_actual_short_tail(self):
        entries = struct.pack('>III', 1000, 2000, 0x90000000) + struct.pack('>III', 345, 1500, 0x90000000)
        body = b'\0\0\0\0' + struct.pack('>IIIIHH', 1, 1000, 0, 9, 0, 2) + entries
        box = struct.pack('>I4s', len(body) + 8, b'sidx') + body
        rows = parse_sidx(box, 100)
        self.assertEqual([x['duration'] for x in rows], [2, 1.5])
        self.assertEqual(rows[0]['offset'], 100 + len(box) + 9)
        self.assertEqual(rows[1]['size_bytes'], 345)
        with self.assertRaises(ValueError): parse_sidx(box[:-1])

    def test_boundaries(self):
        self.assertEqual([grade(x) for x in (.8, .8000001, .90, .95)], [3, 2, 1, 0])
        with self.assertRaises(ValueError): grade(float('nan'))

    def test_segment_leakage(self):
        a, b = dataset('train', 0), dataset('validation', 100)
        validate_splits(a, b)
        b['group_id'][0] = a['group_id'][0]
        with self.assertRaises(ValueError): validate_splits(a, b)

    def test_temporal_gap(self):
        a, b = dataset('train', 0), dataset('validation', 100)
        b['segment_start'][0] = 47.0
        with self.assertRaises(ValueError): validate_splits(a, b)

    def test_labels_cannot_be_reassigned(self):
        a = dataset('train', 0); a['y'][0] = 3
        with self.assertRaises(ValueError): validate_splits(a)

    def test_missing_severe_is_not_zero_error(self):
        m = metrics(np.array([0, 1, 2]), np.array([0, 1, 2]))
        self.assertIsNone(m['severe_missed_as_excellent']); self.assertFalse(m['all_classes_present'])
        m = metrics(np.array([3, 3]), np.array([0, 3])); self.assertEqual(m['severe_missed_as_excellent'], .5)

    def test_reference_stream_cache(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'r.y4m.xz'; frames = [np.full((32, 32), i * 50, np.uint8) for i in range(3)]
            with lzma.open(p, 'wb') as f:
                f.write(b'YUV4MPEG2 W32 H32 F24:1 Ip A1:1 C420jpeg\n')
                for y in frames: f.write(b'FRAME\n' + y.tobytes() + bytes(32 * 32 // 2))
            info = reference_cache(p, [0, 2], Path(d) / 'cache')
            self.assertEqual(info['fps'], 24); self.assertTrue(np.array_equal(read_y(Path(d) / 'cache/00000002.png'), frames[2]))

    def test_guarded_block_split(self):
        cfg = dict(seed=2026, block_seconds=30, guard_seconds=2, validation_fraction=.15, test_fraction=.15)
        table = assignments('bbb', 600, cfg)
        self.assertIsNone(segment_split(dict(start=0., duration=2.), 600, table, cfg))
        self.assertIsNone(segment_split(dict(start=28., duration=2.), 600, table, cfg))
        self.assertIsNotNone(segment_split(dict(start=4., duration=2.), 600, table, cfg))

if __name__ == '__main__': unittest.main(verbosity=2)
