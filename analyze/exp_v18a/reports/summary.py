"""Small machine-readable and human-readable completion report."""
from exp_v18a.io.common import json_write

def write_summary(out,audit,validation,profile,sweep):
    value=dict(dataset=audit,validation=validation,profile=profile,sweep=sweep)
    json_write(out/'summary.json',value)
    text=["# PFDW V18A 분석 결과",'',
          f"- 원본 이미지: {audit['image_count']} / 고유 이미지: {audit['unique_image_count']}",
          f"- 분할: {audit['split_sizes']} / seed={audit['seed']}",
          f"- Reference–V18A 기능 모델 중간값: {'PASS' if validation['reference_v18a_all_fields_equal'] else 'FAIL'}",
          f"- 원본 파일 기준 정확도: {validation['supplied_correct']}/{validation['supplied_images']}",
          f"- 고유 이미지 기준 정확도: {validation['unique_correct']}/{validation['unique_images']}",
          f"- 프로파일 범위: {profile['profile_split']}",
          f"- 선택 후보: {sweep['selected_candidate']}",
          f"- 선택 이후 holdout: {sweep['holdout_correct']}/{sweep['holdout_images']}",
          f"- 선택 후보 원본 파일 결과(탐색에 사용된 이미지 포함): {sweep['supplied_correct']}/{audit['image_count']}",
          '',"## 해석",'',
          '이 결과는 제공 파일 안의 제한된 고유 이미지를 이용한 내부 탐색이다. 독립 MNIST 평가가 아니다.',
          'Feature 지표는 클래스별 centroid scatter이며 DDAMQ 원문 알고리즘을 그대로 구현한 것이 아니다.',
          '정밀도 후보는 균일한 레이어별 power-of-two step PTQ다. 원본 가중치와 RTL 파일을 변경하지 않았다.',
          '비용 표는 미래 q-domain RTL의 P2/P3 구조 지표다. 실제 chip 면적·전력·Fmax 개선 수치가 아니다.',
          'Vivado RTL 추적 비교, ASAP7 netlist 시뮬레이션 및 동일 조건 PPA 측정은 별도 단계다.',
          'Holdout 결과를 보고 다른 후보를 재선택하면 이 holdout은 더 이상 미사용 검증 집합이 아니다.',
          '',"## 먼저 볼 파일",'',
          '1. dataset_audit.json / dataset_membership.csv',
          '2. model_validation.json / wrap_stats.csv',
          '3. channel_class_stats.csv / feature_separability.csv / transform_stats.csv',
          '4. sensitivity.csv / selected_candidate.json / selected_image_decisions.csv',
          '5. selected_shared_lane_cost.csv / rtl_trace_comparison.json(실행 후 생성)',
          '6. plots/INDEX_KR.md / plots/*.png / plots/*.pdf (기본 자동 생성)',
          '']
    (out/'SUMMARY_KR.md').write_text('\n'.join(text),encoding='utf-8')
