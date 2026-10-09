"""Parser contracts on SYNTHETIC events. This never runs or validates RTL."""
import csv
from pathlib import Path
import tempfile
import unittest
import numpy as np
from exp_v18a.verification.rtl_compare import compare


class TraceComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.out = Path(self.temporary.name)
        self.expected = self.out / 'expected.npz'
        np.savez(self.expected,
                 conv1_acc_math=np.zeros((1, 3, 24, 24), dtype=np.int64),
                 conv2_partial_math=np.zeros((1, 3, 3, 8, 8), dtype=np.int64),
                 pool1=np.zeros((1, 3, 12, 12), dtype=np.int64),
                 pool2=np.zeros((1, 3, 4, 4), dtype=np.int64),
                 logits=np.zeros((1, 10), dtype=np.int64),
                 predictions=np.zeros(1, dtype=np.int64))
        self.rows = []
        for kind, shape in [('C1RAW', (3, 24, 24)), ('C2RAW', (3, 3, 8, 8)),
                            ('POOL1', (3, 12, 12)), ('POOL2', (3, 4, 4)),
                            ('LOGIT', (10,))]:
            for coordinate in np.ndindex(shape):
                padded = coordinate + (0,) * (4 - len(coordinate))
                self.rows.append([kind, 0, *padded, 0])
        self.rows.extend([['DECISION', 0, 0, 0, 0, 0, 0],
                          ['CYCLES', 0, 0, 0, 0, 0, 1000]])

    def write_trace(self, rows):
        path = self.out / 'synthetic.csv'
        with path.open('w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['kind', 'image', 'a', 'b', 'c', 'd', 'value'])
            writer.writerows(rows)
        return path

    def test_complete_trace(self):
        result = compare(self.expected, self.write_trace(self.rows), self.out, 1)
        self.assertTrue(result['pass_all'])
        self.assertEqual(result['cycles_min'], 1000)

    def test_missing_event_fails(self):
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            compare(self.expected, self.write_trace(self.rows[:-1]), self.out, 1)

    def test_duplicate_event_fails(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            compare(self.expected, self.write_trace(self.rows + [self.rows[0]]), self.out, 1)

    def test_invalid_coordinate_fails(self):
        self.rows[0][2] = 3
        with self.assertRaisesRegex(ValueError, 'coordinate'):
            compare(self.expected, self.write_trace(self.rows), self.out, 1)

    def test_unknown_value_fails(self):
        self.rows[0][-1] = 'X'
        with self.assertRaises(ValueError):
            compare(self.expected, self.write_trace(self.rows), self.out, 1)

    def test_arithmetic_mismatch_fails(self):
        self.rows[0][-1] = 1
        with self.assertRaisesRegex(AssertionError, 'mismatches: 1'):
            compare(self.expected, self.write_trace(self.rows), self.out, 1)


if __name__ == '__main__':
    unittest.main()
