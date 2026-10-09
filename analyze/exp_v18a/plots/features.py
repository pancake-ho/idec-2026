"""Channel/class heatmaps, raw pooled distributions and baseline diagnostics."""
import numpy as np
from matplotlib.ticker import MaxNLocator
from exp_v18a.plots.data import number
from exp_v18a.plots.style import panels, finish, COLORS, annotate_bars


def channel_heatmaps(data):
    rows = data.rows('channel_class_stats.csv')
    fig, axes = panels(3, rows=2, height=7.2)
    specifications = [('mean', 'Mean'), ('std', 'Standard deviation'), ('zero_ratio', 'Zero ratio (%)')]
    for ri,tensor in enumerate(('pool1','pool2')):
        for ci,(field,title) in enumerate(specifications):
            array = np.full((10,3),np.nan)
            for row in rows:
                if row['tensor']==tensor and int(row['label'])>=0:
                    array[int(row['label']),int(row['channel'])] = number(row,field)*(100 if field=='zero_ratio' else 1)
            if np.isnan(array).any():
                raise ValueError('Missing class/channel heatmap cell for '+tensor)
            ax = axes[ri,ci]
            kwargs = {'vmin':0,'vmax':100} if field=='zero_ratio' else {}
            im = ax.imshow(array,aspect='auto',cmap='Blues',**kwargs)
            ax.set_xticks([0,1,2],['C0','C1','C2'])
            ax.set_yticks(range(10))
            ax.set_xlabel('Channel')
            ax.set_ylabel('Digit class')
            ax.set_title(f'{tensor.capitalize()}: {title}')
            fig.colorbar(im,ax=ax,fraction=0.046,pad=0.04)
    finish(fig,'Class / channel feature statistics',
           data.profile_scope()+'. Mean/std color scales are independent per panel; zero-ratio scales are shared (0-100%).')
    return [('channel_class_heatmaps',fig,['channel_class_stats.csv','profile_metadata.json'],data.profile_scope())]


def separability(data):
    rows = data.rows('feature_separability.csv')
    fig, axes = panels(1, height=4.5)
    fig.set_size_inches(7.0,4.5)
    ax = axes[0,0]
    x = np.arange(4)
    for tensor,shift in [('pool1',-0.18),('pool2',0.18)]:
        values=[]
        for channel in (-1,0,1,2):
            found=[r for r in rows if r['tensor']==tensor and int(r['channel'])==channel]
            if len(found)!=1:
                raise ValueError('Invalid scatter-ratio row for '+tensor)
            values.append(number(found[0],'between_over_within'))
        bars=ax.bar(x+shift,values,width=0.36,color=COLORS[tensor.capitalize()],label=tensor.capitalize(),zorder=3)
        annotate_bars(ax,bars,'{:.2f}')
    ax.set_xticks(x,['All channels','C0','C1','C2'])
    ax.set_ylabel('Between-class / within-class scatter')
    ax.set_ylim(bottom=0)
    ax.margins(y=0.2)
    ax.grid(axis='y',zorder=0)
    ax.legend(loc='upper right')
    finish(fig,'Class centroid separability',data.profile_scope()+'. Full spatial vectors; a descriptive ratio, not the DDAMQ bit-allocation formula or a precision guarantee.')
    return [('feature_separability',fig,['feature_separability.csv','profile_metadata.json'],data.profile_scope())]


def pooled_distributions(data):
    ids=data.profile_ids()
    fig,axes=panels(3,rows=2,height=6.7)
    for ri,tensor in enumerate(('pool1','pool2')):
        array=data.tensor(tensor,ids)
        for channel in range(3):
            ax=axes[ri,channel]
            values=array[:,channel].reshape(-1)
            hist,edges=np.histogram(values,bins=np.linspace(0,2048,33))
            fractions=hist/len(values)
            # Empty bins stay empty on a log scale. No positive pseudo-counts.
            ax.bar(edges[:-1],fractions,width=np.diff(edges),align='edge',
                   color=COLORS[tensor.capitalize()],edgecolor='white',linewidth=0.3)
            ax.set_yscale('log')
            ax.set_ylim(0.8/len(values),1.2)
            ax.set_xlim(0,2048)
            ax.set_xticks([0,512,1024,1536,2048])
            ax.set_xlabel('Unsigned pooled value')
            ax.set_ylabel('Bin fraction (log scale)')
            ax.set_title(f'{tensor.capitalize()} / C{channel}')
            ax.text(0.96,0.96,f'Zero: {100*np.mean(values==0):.2f}%\nElements: {len(values):,}',
                    transform=ax.transAxes,ha='right',va='top',fontsize=8)
    finish(fig,'Pooled activation distributions',data.profile_scope()+'. 32 equal-width bins over [0,2048); zeros included. Each panel uses its own element denominator; empty bins are not drawn on the log scale.')
    return [('pooled_activation_distributions',fig,['expected_trace.npz','baseline_margins.csv','profile_metadata.json'],data.profile_scope())]


def margin_distribution(data):
    rows=data.rows('baseline_margins.csv')
    fig,axes=panels(2,height=4.2)
    labels=np.array([int(r['label']) for r in rows])
    margins=np.array([int(r['trueclass_margin']) for r in rows])
    groups=[margins[labels==c] for c in range(10)]
    axes[0,0].boxplot(groups,positions=range(10),widths=0.55,showfliers=True,
                      medianprops={'color':COLORS['Pool1'],'linewidth':1.5})
    axes[0,0].set_xticks(range(10))
    sizes=[len(group) for group in groups]
    axes[0,0].set_xlabel(f'True digit class (n={sizes[0]} per class)' if len(set(sizes))==1 else 'True digit class')
    axes[0,0].set_ylabel('True-class logit margin')
    axes[0,0].set_title('(a) Margin by class')
    order=np.argsort(margins,kind='stable')
    correct=np.array([r['label']==r['prediction'] for r in rows])[order]
    rank=np.arange(1,len(rows)+1)
    for good,color,marker,label in [(True,COLORS['selected'],'o','Correct'),(False,COLORS['broken'],'x','Incorrect')]:
        mask=correct==good
        axes[0,1].scatter(rank[mask],margins[order][mask],c=color,marker=marker,s=24,label=label)
    axes[0,1].set_xlabel('Image rank (ascending margin)')
    axes[0,1].set_ylabel('True-class logit margin')
    axes[0,1].set_title('(b) Ordered image margins')
    axes[0,1].legend(loc='lower right')
    for ax in axes[0]:
        ax.axhline(0,color='#555555',linestyle='--',linewidth=0.8)
        ax.grid(axis='y')
    note=data.profile_scope()+'. Margin = true-class logit minus largest competing logit; box whiskers use 1.5 IQR, not confidence intervals. Zero margins can contain ties.'
    if len(set(sizes))!=1:
        note+=' Class sizes (0..9): '+str(sizes)+'.'
    finish(fig,'Baseline classification margins',note)
    return [('baseline_margin_distribution',fig,['baseline_margins.csv','profile_metadata.json'],data.profile_scope())]


def weight_channel_ranges(data):
    rows=data.rows('weight_channel_stats.csv')
    fig,axes=panels()
    for ax,tensor,label in zip(axes[0],('conv1_w','conv2_w','fc_w'),('Conv1','Conv2','FC')):
        group=sorted([r for r in rows if r['tensor']==tensor],key=lambda r:int(r['output_channel']))
        x=np.array([int(r['output_channel']) for r in group])
        mean=np.array([number(r,'mean') for r in group])
        ax.vlines(x,[number(r,'min') for r in group],[number(r,'max') for r in group],color='#b1b1b1',label='Min / max')
        ax.vlines(x,[number(r,'p01') for r in group],[number(r,'p99') for r in group],color=COLORS[label],linewidth=4,label='P01 / P99')
        ax.scatter(x,mean,c='#282828',s=20,zorder=3,label='Mean')
        ax.axhline(0,color='#555555',linewidth=0.7,linestyle='--')
        ax.set_xticks(x)
        ax.set_ylim(-135,135)
        ax.set_xlabel('Output channel / FC class')
        ax.set_ylabel('Signed weight value')
        ax.set_title(label)
        ax.grid(axis='y')
    axes[0,0].legend(loc='lower left',fontsize=8)
    finish(fig,'Original weight distributions by output channel','Original signed 8-bit parameter values. Lines show min/max and the 1st/99th percentiles; they are not statistical confidence intervals.')
    return [('weight_channel_ranges',fig,['weight_channel_stats.csv'],'original parameters')]


def wrap_events(data):
    rows=data.rows('wrap_stats.csv')
    fig,axes=panels(2,height=4.5)
    names=[r['location'].replace('_',' ') for r in rows]
    for ax,field,title in zip(axes[0],('changed_elements','affected_unique_images'),('(a) Wrapped values','(b) Affected unique images')):
        values=[int(r[field]) for r in rows]
        y=np.arange(len(rows))
        bars=ax.barh(y,values,color=COLORS['selected'])
        ax.set_yticks(y,names)
        ax.invert_yaxis()
        ax.set_xlim(0,max(1,max(values))*1.4)
        ax.set_xlabel('Count')
        ax.xaxis.set_major_locator(MaxNLocator(nbins=5,integer=True))
        ax.set_title(title)
        for bar,row in zip(bars,rows):
            count=int(row[field])
            denominator=int(row['elements']) if field=='changed_elements' else data.document('profile_metadata.json')['unique_images']
            ax.text(count+0.02*ax.get_xlim()[1],bar.get_y()+bar.get_height()/2,
                    f'{count}/{denominator:,}',va='center',fontsize=8)
    finish(fig,'Original fixed-point wrap events',data.profile_scope()+'. These wraps belong to baseline arithmetic. Observing wrap does not authorize replacing it with saturation.')
    return [('baseline_wrap_events',fig,['wrap_stats.csv','profile_metadata.json'],data.profile_scope())]
