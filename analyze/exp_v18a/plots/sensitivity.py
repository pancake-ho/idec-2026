"""Precision curves and candidate tradeoffs with explicit calibration scope."""
import numpy as np
from matplotlib.lines import Line2D
from exp_v18a.plots.data import number
from exp_v18a.plots.style import panels, line, precision_axis, percentage_axis, focused_percentage_axis, finish


def single_factor_curves(data, weight=True):
    table = data.rows('sensitivity.csv')
    baseline = data.baseline()
    roundings = sorted({r['rounding'] for r in table if r['kind'] != 'baseline'})
    outputs = []
    if weight:
        definitions = [('Conv1', 'w1'), ('Conv2', 'w2'), ('FC', 'wfc')]
        all_fields = ['w1', 'w2', 'wfc']
        default = 8
        bits = [8, 7, 6, 5]
    else:
        definitions = [('Pool1', 'a_pool1'), ('Pool2', 'a_pool2')]
        all_fields = ['a_pool1', 'a_pool2']
        default = 11
        bits = [11, 10, 9, 8]
    for rounding in roundings:
        fig, axes = panels()
        axes = axes[0]
        drawn = 0
        exact = []
        all_accuracy=[]
        all_reductions=[]
        for label, field in definitions:
            values = []
            for bit in bits:
                if bit == default:
                    values.append(baseline)
                    continue
                found = [r for r in table if r['rounding'] == rounding
                         and int(r[field]) == bit
                         and all(int(r[f]) == default for f in all_fields if f != field)
                         and (all(int(r[f]) == 11 for f in ['a_pool1', 'a_pool2']) if weight
                              else all(int(r[f]) == 8 for f in ['w1', 'w2', 'wfc']))]
                if len(found) > 1:
                    raise ValueError('Duplicate precision candidate for '+label)
                values.append(found[0] if found else None)
            if not any(v is not None for v in values[1:]):
                continue
            drawn += 1
            accuracy = [100*number(v, 'calibration_candidate_correct')/number(v, 'calibration_images')
                        if v else np.nan for v in values]
            sqnr = [number(v, 'calibration_logit_sqnr_db') if v else np.nan for v in values]
            reduction = [number(v, 'proxy_bitproduct_reduction_pct') if v else np.nan for v in values]
            all_accuracy.extend(accuracy)
            all_reductions.extend(reduction)
            line(axes[0], bits, accuracy, label)
            line(axes[1], bits, sqnr, label)
            line(axes[2], bits, reduction, label)
            exact += [f'{label}:{b}' for b,v in zip(bits[1:],values[1:])
                      if v and int(v['calibration_logit_exact'])]
        if not drawn:
            import matplotlib.pyplot as plt
            plt.close(fig)
            continue
        labels = ['(a) Calibration accuracy', '(b) Calibration logit SQNR', '(c) Shared arithmetic cost']
        ylabs = ['Accuracy (%)', 'SQNR (dB)', 'Bit-product reduction (%)']
        for ax, title, ylabel in zip(axes, labels, ylabs):
            ax.set_title(title)
            ax.set_ylabel(ylabel)
            precision_axis(ax, bits, 'Weight precision (bits)' if weight else 'Pooled activation precision (bits)')
        focused_percentage_axis(axes[0],all_accuracy)
        axes[2].set_ylim(bottom=0)
        if np.nanmax(all_reductions)==0:
            axes[2].set_ylim(0,1)
            axes[2].text(0.5,0.55,'No shared width reduction\nfor these single-layer changes',
                         transform=axes[2].transAxes,ha='center',fontsize=8,color='#4d4d4d')
        axes[0].legend(loc='lower left')
        domain = 'Weight' if weight else 'Pooled activation'
        note = (f"Calibration n={int(baseline['calibration_images'])} unique images; one layer changed at a time. "
                'Accuracy axis is focused. Baseline is exact (SQNR = infinity); exact points are omitted, never replaced by zero. '
                'Cost is a q-domain structural proxy, not measured ASIC area/power.')
        if exact:
            note += ' Additional exact points: '+', '.join(exact)+'.'
        finish(fig, f'{domain} precision sensitivity / {rounding} rounding', note)
        outputs.append((f'{"weight" if weight else "activation"}_sensitivity_{rounding}', fig,
                        ['sensitivity.csv'], 'calibration'))
    return outputs


def candidate_tradeoff(data):
    rows = data.rows('sensitivity.csv')
    fig, axes = panels(1, height=5.0)
    fig.set_size_inches(7.7,5.0)
    ax = axes[0,0]
    rounding_styles = {'floor': ('#3977b8', 'o'), 'even': ('#e7832e', 's'), 'trunc': ('#669d3b', '^')}
    for rounding, (color, marker) in rounding_styles.items():
        for eligible in (True, False):
            selected = [r for r in rows if r['kind'] != 'baseline' and r['rounding'] == rounding
                        and bool(int(r['internal_eligible'])) == eligible]
            if not selected:
                continue
            ax.scatter([number(r, 'proxy_multiplier_bitproduct') for r in selected],
                       [100*number(r,'validation_candidate_correct')/number(r,'validation_images') for r in selected],
                       marker=marker, s=36, edgecolor=color,
                       facecolor=color if eligible else 'none', alpha=0.7)
    baseline = data.baseline()
    bx = number(baseline,'proxy_multiplier_bitproduct')
    by = 100*number(baseline,'validation_candidate_correct')/number(baseline,'validation_images')
    ax.scatter([bx],[by],color='#343434',marker='*',s=145,zorder=5)
    ax.annotate('Baseline', (bx,by),xytext=(-6,-17),textcoords='offset points',ha='right',fontsize=9)
    if data.has('selected_candidate.json'):
        chosen = data.candidate(data.selected_name())
        cx = number(chosen,'proxy_multiplier_bitproduct')
        cy = 100*number(chosen,'validation_candidate_correct')/number(chosen,'validation_images')
        ax.scatter([cx],[cy],color='#8d6a1a',marker='*',s=160,zorder=6)
        ax.annotate('Selected: '+chosen['candidate'],(cx,cy),xytext=(5,9),
                    textcoords='offset points',fontsize=8)
    handles = [Line2D([],[],color=c,marker=m,linestyle='none',label=r)
               for r,(c,m) in rounding_styles.items() if any(x['rounding']==r and x['kind']!='baseline' for x in rows)]
    handles += [Line2D([],[],color='#606060',marker='o',linestyle='none',label='Internal rule: pass'),
                Line2D([],[],color='#606060',marker='o',markerfacecolor='none',linestyle='none',label='Internal rule: fail')]
    ax.legend(handles=handles,loc='lower left',fontsize=8)
    ax.set_xlabel(r'Shared multiplier $\sum(AW\times BW)$ [structural proxy]')
    ax.set_ylabel('Validation accuracy (%)')
    percentage_axis(ax)
    xs = [number(r,'proxy_multiplier_bitproduct') for r in rows]
    ax.set_xlim(min(xs)-0.08*(max(xs)-min(xs)+1), max(xs)+0.08*(max(xs)-min(xs)+1))
    finish(fig, 'Candidate accuracy / arithmetic cost tradeoff',
           f"Validation n={int(baseline['validation_images'])} unique images; {len(rows)} candidates. "
           'Coincident points overlap without jitter. Passing the internal rule is not an official gate-level pass. No measured PPA is plotted.')
    return [('candidate_tradeoff',fig,['sensitivity.csv','selected_candidate.json'],'validation')]
