"""Read existing result files. Plotting never runs inference or selects a candidate."""
from dataclasses import dataclass
from pathlib import Path
import csv
import json
import numpy as np


def number(row, field):
    value = row[field]
    return float(value) if value not in ('', None) else np.nan


@dataclass
class PlotData:
    out: Path

    def __post_init__(self):
        self.out = Path(self.out).resolve()
        self._tables = {}
        self._json = {}

    def has(self, *names):
        return all((self.out / name).is_file() for name in names)

    def rows(self, name):
        if name not in self._tables:
            with (self.out / name).open(encoding='utf-8', newline='') as f:
                self._tables[name] = list(csv.DictReader(f))
        return self._tables[name]

    def document(self, name):
        if name not in self._json:
            self._json[name] = json.loads((self.out / name).read_text(encoding='utf-8'))
        return self._json[name]

    def profile_scope(self):
        meta = self.document('profile_metadata.json')
        return f"{meta['split']}; n={meta['unique_images']} unique images"

    def profile_ids(self):
        rows = self.rows('baseline_margins.csv')
        ids = np.array([int(r['image_index']) for r in rows], dtype=int)
        if len(np.unique(ids)) != len(ids):
            raise ValueError('Profile contains duplicated image indices')
        return ids

    def tensor(self, name, ids):
        with np.load(self.out / 'expected_trace.npz', allow_pickle=False) as f:
            return f[name][ids]

    def selected_name(self):
        return self.document('selected_candidate.json')['configuration']['name']

    def candidate(self, name):
        matches = [r for r in self.rows('sensitivity.csv') if r['candidate'] == name]
        if len(matches) != 1:
            raise ValueError('Expected exactly one sensitivity row for '+name)
        return matches[0]

    def baseline(self):
        return self.candidate('baseline')

    def unique_decisions(self):
        rows = self.rows('selected_image_decisions.csv')
        ids = [int(r['image_index']) for r in rows]
        if len(set(ids)) != len(ids):
            raise ValueError('Selected image table must contain unique representatives')
        return rows
