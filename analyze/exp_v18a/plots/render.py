"""Render available result families and record exact source provenance."""
from pathlib import Path
import hashlib
import json
from exp_v18a.plots.style import plt, apply_style
from exp_v18a.plots.data import PlotData
from exp_v18a.plots import sensitivity, features, lanes, decisions


def render_all(out, formats=('png','pdf'), dpi=180):
    out=Path(out).resolve()
    if not 72<=dpi<=600:
        raise ValueError('Plot DPI must be 72..600')
    formats=list(dict.fromkeys(formats))
    if not formats or any(f not in ('png','pdf','svg') for f in formats):
        raise ValueError('Plot formats must be png, pdf and/or svg')
    data=PlotData(out)
    target=out/'plots'
    target.mkdir(parents=True,exist_ok=True)
    apply_style()
    families=[
        ('weight_sensitivity',('sensitivity.csv',),lambda d:sensitivity.single_factor_curves(d,True)),
        ('activation_sensitivity',('sensitivity.csv',),lambda d:sensitivity.single_factor_curves(d,False)),
        ('candidate_tradeoff',('sensitivity.csv',),sensitivity.candidate_tradeoff),
        ('channel_class_heatmaps',('channel_class_stats.csv','profile_metadata.json'),features.channel_heatmaps),
        ('feature_separability',('feature_separability.csv','profile_metadata.json'),features.separability),
        ('pooled_activation_distributions',('expected_trace.npz','baseline_margins.csv','profile_metadata.json'),features.pooled_distributions),
        ('baseline_margin_distribution',('baseline_margins.csv','profile_metadata.json'),features.margin_distribution),
        ('weight_channel_ranges',('weight_channel_stats.csv',),features.weight_channel_ranges),
        ('baseline_wrap_events',('wrap_stats.csv','profile_metadata.json'),features.wrap_events),
        ('lane_observed_widths',('transform_stats.csv','profile_metadata.json'),lanes.observed_widths),
        ('selected_lane_widths',('selected_shared_lane_cost.csv','selected_candidate.json'),lanes.selected_widths),
        ('selected_summary',('sensitivity.csv','selected_candidate.json','selected_image_decisions.csv'),decisions.selected_summary),
        ('selected_confusions',('selected_image_decisions.csv','selected_candidate.json'),decisions.selected_confusions),
        ('selected_margin_changes',('selected_image_decisions.csv','selected_candidate.json'),decisions.selected_margins),
    ]
    manifest={'formats':formats,'dpi':dpi,'figures':[],'skipped':[],
              'plotting_does_not_run_inference_or_select_candidates':True,
              'measured_asic_ppa_plotted':False,
              'accuracy_line_axes':'focused percentage range; bars start at zero',
              'note':'Accuracy/margin data use unique images. Internal holdout and full-file descriptive results are not independent MNIST benchmarks.'}
    for family,required,builder in families:
        missing=[name for name in required if not data.has(name)]
        if missing:
            manifest['skipped'].append({'family':family,'reason':'missing result files','files':missing})
            continue
        built=builder(data)
        if not built:
            manifest['skipped'].append({'family':family,'reason':'required metrics are unavailable in this result version'})
        for name,fig,sources,scope in built:
            try:
                files=[]
                for extension in formats:
                    path=target/(name+'.'+extension)
                    fig.savefig(path,dpi=dpi,bbox_inches='tight')
                    files.append(path.name)
                source_records=[{'file':source,'sha256':hashlib.sha256((out/source).read_bytes()).hexdigest()}
                                for source in sources if data.has(source)]
                manifest['figures'].append({'name':name,'files':files,'scope':scope,'sources':source_records})
            finally:
                plt.close(fig)
    if not manifest['figures']:
        raise ValueError('No plottable result files found; run profile, sweep or all first')
    (target/'plot_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    description=[
        '# V18A 그래프 모음','',
        'CSV/JSON/NPZ 결과에서 생성한 정적 그래프입니다. 영어 축·제목을 사용해 서버의 한국어 폰트 설치에 의존하지 않습니다.',
        '색상·마커·선 종류는 `plots/style.py`에서 함께 조정합니다. 숫자 원본과 SHA-256은 `plot_manifest.json`에 기록합니다.',
        '정확도는 고유 이미지 기준이며, 회로 비용은 q-domain 구조 가정입니다. 실제 ASIC PPA 측정은 포함되지 않습니다.','',
    ]
    for item in manifest['figures']:
        description.extend(['## '+item['name'],'', '범위: '+item['scope'],'',
                            ' · '.join('['+f+']('+f+')' for f in item['files']),''])
        if 'png' in formats:
            description.extend(['!['+item['name']+']('+item['name']+'.png)',''])
    if manifest['skipped']:
        description.extend(['## 이 결과 폴더에서 생략한 항목',''])
        description.extend('- '+x['family']+': '+x['reason'] for x in manifest['skipped'])
    (target/'INDEX_KR.md').write_text('\n'.join(description)+'\n',encoding='utf-8')
    result={'figure_count':len(manifest['figures']),'formats':formats,'directory':str(target),
            'manifest':str(target/'plot_manifest.json')}
    print('PLOTS:',result,flush=True)
    return result
