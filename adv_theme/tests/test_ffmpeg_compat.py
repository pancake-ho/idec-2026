"""FFmpeg capability detection and sparse frame identity, including legacy -vsync 0."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.data import media

class CapabilityTests(unittest.TestCase):
    def tearDown(self):
        media._ffmpeg_info.cache_clear()

    def inspect(self, help_text, stderr=False, returncode=0):
        result = SimpleNamespace(returncode=returncode,
                                 stdout='' if stderr else help_text,
                                 stderr=help_text if stderr else '')
        with patch.object(media, 'run', return_value='ffmpeg version fixture\n'), \
             patch.object(media.subprocess, 'run', return_value=result):
            return media._ffmpeg_info('/fixture/ffmpeg')

    def test_modern_preferred_if_both_supported(self):
        self.assertEqual(self.inspect('-vsync old\n-fps_mode mode\n')[2],
                         ('-fps_mode', 'passthrough'))

    def test_legacy_help_on_stderr(self):
        self.assertEqual(self.inspect('  -vsync sync\n', stderr=True)[2], ('-vsync', '0'))

    def test_prose_does_not_count_as_supported_option(self):
        self.assertEqual(self.inspect('Use -fps_mode instead.\n-vsync mode\n')[2], ('-vsync', '0'))

    def test_missing_passthrough_option_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'neither'):
            self.inspect('-r rate\n')

    def test_help_failure_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'Cannot inspect'):
            self.inspect('broken help', stderr=True, returncode=1)

@unittest.skipUnless(shutil.which('ffmpeg'), 'ffmpeg is required for real decoder checks')
class SparseDecodeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        raw = cls.root / 'reference.y4m'
        h, w, count = 48, 64, 21
        yy, xx = np.indices((h, w))
        with raw.open('wb') as f:
            f.write(f'YUV4MPEG2 W{w} H{h} F24:1 Ip A1:1 C420jpeg\n'.encode())
            for n in range(count):
                y = (16 + ((xx * 3 + yy * 5 + n * 17) % 220)).astype(np.uint8)
                f.write(b'FRAME\n' + y.tobytes() + bytes([128]) * (w * h // 2))
        cls.video = cls.root / 'source.mp4'
        cls.info = media.ffmpeg_info()
        media.run([cls.info['path'], '-v', 'error', '-y', '-i', str(raw), '-an',
                   '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', str(cls.video)])
        cls.indices = [0, 1, 4, 12, 20]
        cls.full = cls.root / 'full'
        media.decoded_cache(cls.video, list(range(count)), cls.full)
        p = subprocess.run([cls.info['path'], '-hide_banner', '-h', 'full'], capture_output=True, text=True, check=True)
        cls.help_text = p.stdout + '\n' + p.stderr

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def check_sync(self, sync):
        target = self.root / sync[0].lstrip('-')
        info = dict(self.info, frame_sync_args=list(sync))
        with patch.object(media, 'ffmpeg_info', return_value=info):
            media.decoded_cache(self.video, self.indices, target)
        self.assertEqual(sorted(p.stem for p in target.glob('*.png')),
                         [f'{i:08d}' for i in self.indices])
        for i in self.indices:
            np.testing.assert_array_equal(media.read_y(target / f'{i:08d}.png'),
                                          media.read_y(self.full / f'{i:08d}.png'))
        # Reuse caches written before this patch, which have no FFmpeg metadata.
        media.write_json(target / 'cache.json', dict(source_sha256=media.sha256(self.video), indices=self.indices))
        with patch.object(media, 'ffmpeg_info', return_value=info), \
             patch.object(media, 'run', side_effect=AssertionError('valid cache was decoded again')):
            media.decoded_cache(self.video, self.indices, target)

    def test_modern_sparse_frames_equal_full_decode(self):
        if '-fps_mode' not in self.help_text:
            self.skipTest('installed FFmpeg has no -fps_mode')
        self.check_sync(('-fps_mode', 'passthrough'))

    def test_legacy_sparse_frames_equal_full_decode(self):
        if '-vsync' not in self.help_text:
            self.skipTest('installed FFmpeg has no -vsync')
        self.check_sync(('-vsync', '0'))

if __name__ == '__main__':
    unittest.main(verbosity=2)
