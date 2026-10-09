"""Shared paper-style colors, markers, panel layout and headless rendering."""
from pathlib import Path
import os
import tempfile
import textwrap

cache = Path(os.environ.get('MPLCONFIGDIR', Path(tempfile.gettempdir()) / 'pfdw_v18a_matplotlib'))
cache.mkdir(parents=True, exist_ok=True)
os.environ.setdefault('MPLCONFIGDIR', str(cache))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

COLORS = {'Conv1': '#3977b8', 'Conv2': '#e7832e', 'FC': '#669d3b',
          'Pool1': '#3977b8', 'Pool2': '#e7832e',
          'baseline': '#4d4d4d', 'selected': '#3977b8', 'broken': '#bd593d'}
SERIES = {'Conv1': ('o', '-'), 'Conv2': ('s', ':'), 'FC': ('^', '--'),
          'Pool1': ('o', '-'), 'Pool2': ('s', ':')}


def apply_style():
    plt.rcParams.update({
        'font.family': 'DejaVu Serif', 'font.size': 10,
        'axes.titlesize': 11, 'axes.labelsize': 10,
        'xtick.labelsize': 9, 'ytick.labelsize': 9, 'legend.fontsize': 9,
        'axes.edgecolor': '#8a8a8a', 'axes.linewidth': 0.7,
        'grid.color': '#e1e1e1', 'grid.linewidth': 0.5,
        'figure.facecolor': 'white', 'axes.facecolor': 'white',
        'lines.linewidth': 1.5, 'lines.markersize': 5,
        'pdf.fonttype': 42, 'ps.fonttype': 42,
        'savefig.facecolor': 'white', 'axes.unicode_minus': True,
    })


def panels(count=3, rows=1, height=None):
    apply_style()
    fig, axes = plt.subplots(rows, count, figsize=(4.1 * count, height or (3.8 * rows)),
                             squeeze=False)
    return fig, axes


def line(ax, x, y, label):
    marker, linestyle = SERIES[label]
    ax.plot(x, y, color=COLORS[label], marker=marker, linestyle=linestyle, label=label)
    ax.grid(axis='y', zorder=0)


def precision_axis(ax, bits, label):
    ax.set_xticks(bits)
    ax.set_xlim(max(bits) + 0.15, min(bits) - 0.15)
    ax.set_xlabel(label)


def percentage_axis(ax):
    ax.set_ylim(0, 110)
    ax.set_yticks([0, 20, 40, 60, 80, 100])
    ax.grid(axis='y', zorder=0)


def focused_percentage_axis(ax, values):
    """Focused range for line charts only; no truncated bar baselines."""
    values=np.asarray(values,dtype=float)
    finite=values[np.isfinite(values)]
    low=max(0,5*np.floor((finite.min()-1)/5)) if len(finite) else 0
    high=min(100,5*np.ceil((finite.max()+1)/5)) if len(finite) else 100
    ax.set_ylim(low,high+1)
    ax.set_yticks(np.linspace(low,high,6))
    ax.grid(axis='y',zorder=0)


def finish(fig, title, note):
    fig.suptitle(title, y=0.985, fontsize=13)
    caption = '\n'.join(textwrap.wrap(note, width=int(fig.get_figwidth() * 14)))
    fig.text(0.02, 0.015, caption, ha='left', va='bottom', fontsize=8)
    lines = caption.count('\n') + 1
    bottom = min(0.30, (0.25 + 0.14 * lines) / fig.get_figheight())
    fig.tight_layout(rect=(0, bottom, 1, 0.91), w_pad=2.0, h_pad=2.0)


def annotate_bars(ax, bars, fmt='{:.1f}'):
    for bar in bars:
        value = bar.get_height()
        if np.isfinite(value):
            ax.annotate(fmt.format(value), (bar.get_x() + bar.get_width()/2, value),
                        xytext=(0, 3), textcoords='offset points', ha='center', fontsize=8)
