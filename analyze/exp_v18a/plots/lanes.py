"""Observed lane widths and guaranteed proposed shared-domain width comparisons."""
import numpy as np
from matplotlib.ticker import MaxNLocator
from exp_v18a.plots.style import panels, finish


def observed_widths(data):
    rows=data.rows('transform_stats.csv')
    fig,axes=panels()
    for ax,stage,title in zip(axes[0],('P2a','P2b','P3'),('(a) Activation AW','(b) Transformed weight BW','(c) Product PW')):
        group=[r for r in rows if r['stage']==stage]
        physical=np.full(49,np.nan)
        for r in group:
            physical[int(r['coordinate'])]=int(r['physical_register_bits'])
        ax.step(range(49),physical,where='mid',color='#3d3d3d',linestyle='--',label='Physical V18A',linewidth=1.6)
        for mode,color,marker in [('conv1','#3977b8','o'),('conv2','#e7832e','s'),('fc','#669d3b','^')]:
            observed=np.full(49,np.nan)
            for r in group:
                if r['mode']==mode:
                    observed[int(r['coordinate'])]=int(r['observed_required_signed_bits'])
            ax.plot(range(49),observed,color=color,marker=marker,markevery=4,markersize=3,linewidth=1,
                    label=mode.upper() if mode=='fc' else mode.capitalize())
        ax.set_title(title)
        ax.set_xlabel('Shared lane index')
        ax.set_ylabel('Signed bits')
        ax.set_xlim(-0.5,48.5)
        ax.set_xticks([0,8,16,24,32,40,48])
        ax.set_ylim(bottom=0)
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6,integer=True))
        ax.grid(axis='y')
    axes[0,0].legend(loc='lower left',fontsize=8)
    finish(fig,'Observed transform-domain widths / physical lane widths',data.profile_scope()+'. Observed extrema do not prove a safe smaller RTL width; FC has 48 active lanes, so its lane 48 is absent.')
    return [('lane_observed_widths',fig,['transform_stats.csv','profile_metadata.json'],data.profile_scope())]


def selected_widths(data):
    rows=sorted(data.rows('selected_shared_lane_cost.csv'),key=lambda r:int(r['lane']))
    fig,axes=panels()
    for ax,field,title in zip(axes[0],('aw','bw','pw'),('(a) Activation AW','(b) Transformed weight BW','(c) Product PW')):
        x=[int(r['lane']) for r in rows]
        ax.step(x,[int(r['baseline_'+field]) for r in rows],where='mid',color='#4d4d4d',linestyle='--',label='V18A baseline')
        ax.step(x,[int(r['proposed_'+field]) for r in rows],where='mid',color='#3977b8',label='Proposed q-domain')
        ax.set_title(title)
        ax.set_xlabel('Shared lane index')
        ax.set_ylabel('Guaranteed signed bits')
        ax.set_xlim(-0.5,48.5)
        ax.set_xticks([0,8,16,24,32,40,48])
        ax.set_ylim(bottom=0)
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6,integer=True))
        ax.grid(axis='y')
    axes[0,0].legend(loc='lower left',fontsize=8)
    finish(fig,'Shared lane widths: '+data.selected_name(),'All supported input codes and Conv1/Conv2/FC mode union. Proposed widths assume a future q-domain RTL; no candidate RTL or measured ASIC PPA is implied.')
    return [('selected_lane_widths',fig,['selected_shared_lane_cost.csv','selected_candidate.json'],'guaranteed code-range structural model')]
