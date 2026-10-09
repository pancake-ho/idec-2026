"""Selected-candidate accuracy, unique-image decisions and numerical margins."""
import numpy as np
from matplotlib.ticker import MaxNLocator
from exp_v18a.plots.data import number
from exp_v18a.plots.style import panels, finish, COLORS, percentage_axis, annotate_bars


def selected_summary(data):
    selected=data.document('selected_candidate.json')
    row=data.candidate(data.selected_name())
    decisions=data.unique_decisions()
    fig,axes=panels(height=4.4)
    ax=axes[0,0]
    counts=[]
    denominators=[]
    for split in ('calibration','validation'):
        counts.append((int(row[split+'_baseline_correct']),int(row[split+'_candidate_correct'])))
        denominators.append(int(row[split+'_images']))
    hold=selected['holdout']
    counts.append((hold['baseline_correct'],hold['candidate_correct']))
    denominators.append(hold['images'])
    x=np.arange(3)
    for index,label,shift in [(0,'Baseline',-0.18),(1,'Selected',0.18)]:
        values=[100*p[index]/n for p,n in zip(counts,denominators)]
        bars=ax.bar(x+shift,values,width=0.36,color=COLORS[label.lower()],label=label,zorder=3)
        for bar,p,n in zip(bars,counts,denominators):
            ax.text(bar.get_x()+bar.get_width()/2,bar.get_height()+1,f'{p[index]}/{n}',
                    ha='center',va='bottom',fontsize=8)
    ax.set_xticks(x,['Cal.','Val.','Holdout'])
    percentage_axis(ax)
    ax.set_ylabel('Accuracy (%)')
    ax.set_title('(a) Internal split accuracy')
    ax.legend(loc='lower left',fontsize=8)
    ax=axes[0,1]
    before=np.array([int(r['baseline_correct']) for r in decisions],dtype=bool)
    after=np.array([int(r['selected_correct']) for r in decisions],dtype=bool)
    changed=np.array([r['baseline_pred']!=r['selected_pred'] for r in decisions])
    changes=[int(np.sum(~before&after)),int(np.sum(before&~after)),int(np.sum(~before&~after&changed))]
    bars=ax.bar(range(3),changes,color=[COLORS['selected'],COLORS['broken'],'#888888'],zorder=3)
    annotate_bars(ax,bars,'{:.0f}')
    ax.set_xticks(range(3),['Fixed','Broken','Wrong to\nother wrong'])
    ax.set_ylim(0,max(1,max(changes))*1.35)
    ax.set_ylabel('Unique image count')
    ax.yaxis.set_major_locator(MaxNLocator(nbins=5,integer=True))
    ax.set_title('(b) Decision changes')
    ax.grid(axis='y',zorder=0)
    ax=axes[0,2]
    base=data.baseline()
    keys=['p2_register_bits','p3_register_bits','multiplier_bitproduct']
    candidate_cost=selected['shared_cost_proxy']
    ratios=[100*candidate_cost[k]/number(base,'proxy_'+k) for k in keys]
    ax.bar(np.arange(3)-0.18,[100]*3,width=0.36,color=COLORS['baseline'],label='Baseline',zorder=3)
    bars=ax.bar(np.arange(3)+0.18,ratios,width=0.36,color=COLORS['selected'],label='Proposed',zorder=3)
    annotate_bars(ax,bars,'{:.1f}')
    ax.set_xticks(range(3),['P2 bits','P3 bits','AW x BW'])
    ax.set_ylim(0,115)
    ax.set_ylabel('Structural cost (baseline = 100%)')
    ax.set_title('(c) Proposed arithmetic structure')
    ax.grid(axis='y',zorder=0)
    finish(fig,'Selected candidate: '+data.selected_name(),
           f"Decision changes: all {len(decisions)} unique images, descriptive (selection data included). "
           'Holdout is small and internal. Cost ratios assume a future q-domain RTL; no ASIC PPA is measured.')
    return [('selected_accuracy_decisions_cost',fig,['sensitivity.csv','selected_candidate.json','selected_image_decisions.csv'],'internal split / all-unique descriptive / structural proxy')]


def selected_confusions(data):
    decisions=data.unique_decisions()
    matrices=[np.zeros((10,10),dtype=int) for _ in range(3)]
    for row in decisions:
        label,before,after=(int(row[k]) for k in ('label','baseline_pred','selected_pred'))
        if not all(0<=v<10 for v in (label,before,after)):
            raise ValueError('Class outside 0..9')
        matrices[0][label,before]+=1
        matrices[1][label,after]+=1
        matrices[2][before,after]+=1
    fig,axes=panels(height=4.7)
    maximum=max(m.max() for m in matrices)
    for index,(ax,matrix,title) in enumerate(zip(axes[0],matrices,('(a) Baseline','(b) Selected','(c) Prediction transitions'))):
        im=ax.imshow(matrix,cmap='Blues',vmin=0,vmax=maximum,aspect='equal')
        for r in range(10):
            for c in range(10):
                if matrix[r,c]:
                    ax.text(c,r,str(matrix[r,c]),ha='center',va='center',fontsize=8,
                            color='white' if matrix[r,c]>maximum/2 else '#242424')
        ax.set_xticks(range(10))
        ax.set_yticks(range(10))
        ax.set_xlabel('Predicted class' if index<2 else 'Selected predicted class')
        ax.set_ylabel('True class' if index<2 else 'Baseline predicted class')
        ax.set_title(title)
        fig.colorbar(im,ax=ax,fraction=0.046,pad=0.04)
    finish(fig,'Classification and decision transitions',
           f'All {len(decisions)} unique images, descriptive; selection images included. Shared count color scale; unlabelled cells are zero. Selected configuration: '+data.selected_name()+'.')
    return [('selected_confusions',fig,['selected_image_decisions.csv','selected_candidate.json'],'all-unique descriptive')]


def selected_margins(data):
    rows=data.unique_decisions()
    if not rows or 'baseline_trueclass_margin' not in rows[0]:
        return []
    before=np.array([number(r,'baseline_trueclass_margin') for r in rows])
    after=np.array([number(r,'selected_trueclass_margin') for r in rows])
    delta=after-before
    fig,axes=panels(2,height=4.5)
    ax=axes[0,0]
    ax.scatter(before,after,color=COLORS['selected'],s=22,alpha=0.7)
    low=min(before.min(),after.min())
    high=max(before.max(),after.max())
    pad=max(50,(high-low)*0.04)
    ax.plot([low-pad,high+pad],[low-pad,high+pad],linestyle='--',color='#4d4d4d',label='Unchanged margin')
    ax.set_xlim(low-pad,high+pad)
    ax.set_ylim(low-pad,high+pad)
    ax.set_xlabel('Baseline true-class margin')
    ax.set_ylabel('Selected true-class margin')
    ax.set_title('(a) Margin preservation')
    ax.legend(loc='upper left',fontsize=8)
    ax=axes[0,1]
    changed=np.array([r['baseline_pred']!=r['selected_pred'] for r in rows])
    order=np.argsort(delta,kind='stable')
    rank=np.arange(1,len(rows)+1)
    for flag,color,marker,label in [(False,COLORS['selected'],'o','Same decision'),(True,COLORS['broken'],'x','Changed decision')]:
        mask=changed[order]==flag
        if not mask.any():
            continue
        ax.scatter(rank[mask],delta[order][mask],c=color,marker=marker,s=24,label=label)
    ax.axhline(0,color='#4d4d4d',linestyle='--',linewidth=0.8)
    ax.set_xlabel('Image rank (ascending margin change)')
    ax.set_ylabel('Selected minus baseline margin')
    ax.set_title('(b) Margin change by image')
    ax.legend(loc='upper left',fontsize=8)
    finish(fig,'Candidate classification-margin changes',
           f'All {len(rows)} unique images, descriptive (selection images included); '+data.selected_name()+'. Numerical margin changes do not alone prove generalization.')
    return [('selected_margin_changes',fig,['selected_image_decisions.csv','selected_candidate.json'],'all-unique descriptive')]
