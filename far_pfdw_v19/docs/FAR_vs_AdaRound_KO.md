# FAR-PFDW와 AdaRound 최종 비교

## 결론

최종 회로 주제는 **FAR-PFDW: Fan-out-Aware Transform Reuse for PFDW**로 확정한다.
AdaRound는 독립된 후속 양자화 실험으로만 남긴다.

## 대회·연구 적합성 비교

| 기준 | FAR-PFDW | AdaRound |
|---|---|---|
| 현재 V18A에 즉시 적용 | 가능. RTL 스케줄/레지스터 제어 변경 | 불가. 원 FP 모델, calibration data, 학습 코드, 새 weight가 필요 |
| 수치 정확성 | exact. V18A와 동일한 정수 연산 순서 유지 | weight rounding이 바뀌므로 decision 변화 가능 |
| PFDW 적합성 | activation fan-out 3을 직접 이용 | 일반 layer-wise PTQ는 Winograd transform-domain 오차를 직접 모델링하지 않음 |
| 하드웨어 변화 | Conv2 순서, 3-bank 누산, activation bank enable | weight bit-width, scale/zero-point, multiplier/레지스터 폭까지 함께 바꿔야 PPA 효과 발생 |
| 독창성 | 현재 49-lane PFDW/Conv-FC 공유 구조에 특화 | 2020년 공개 PTQ 기법이며 2025년 대회 은상도 삼진양자화 CNN |
| 검증 부담 | V18A와 1000/1000 decision match로 판정 가능 | calibration/test 분리, hidden 일반화, scale 정합, 재학습 없는 정확도 검증 필요 |
| 예상 PPA | area는 3-bank 누산 때문에 소폭 증가 가능, dynamic power 감소가 1차 목표 | W4/W6 RTL까지 성공하면 area/power 잠재력은 큼 |

## V19 FAR의 정확한 구현 정의

1. Conv1은 기존처럼 동일 tile을 `oc=0,1,2` 순으로 사용한다.
2. Conv2를 기존 `(oc,ic)` 순서에서 `(ic,oc)` 순서로 바꿔 동일 tile/input-channel이 세 출력채널로 연속 fan-out되게 한다.
3. Conv2에는 출력채널별 20-bit 누산 bank 3개를 둔다. 각 bank의 덧셈 순서는 여전히 `ic0 -> ic1 -> ic2`다.
4. 엔진의 `p0_a`, `p1_a`, `p2_a_q`는 첫 소비자(`oc==0`)에서만 갱신하고 `oc==1,2`에서는 hold한다. weight 경로는 매 cycle 진행한다.
5. FC activation은 class 0에서 한 번만 갱신하고 class 1..9에서 hold한다.

Conv activation transform **레지스터 갱신 기회**는 576회에서 192회로 66.67% 줄고, FC activation bank 갱신은 10회에서 1회로 줄어든다. 곱셈 수, pipeline request 수, fixed-point slice는 V18A와 같다. 실제 switching/power 감소량은 gate-level activity와 동일 조건 PPA로 확인한다.

## 채택 게이트

- RTL simulation: FAR accuracy 970/1000 이상
- exactness: V18A decision match 1000/1000
- cycle: V18A/V19를 같은 테스트벤치에서 재측정하고, V19가 859 cycle 이하인지 목표 판정
- STA: WNS >= 0, TNS = 0 at 750 ps
- PPA: 같은 ORFS commit/config/SDC에서 `area`와 `energy/image = power * measured_cycles * 750 ps` 기록
- power는 timing MET 결과에서만 비교

V19 FAR이 면적 증가를 상쇄하지 못하거나 power가 감소하지 않으면, 주제를 폐기하는 것이 아니라 물리적 transform folding을 다음 RTL 단계로 진행한다. 단, folding은 FIFO/추가 stage가 생기므로 V19 FAR 결과를 기준선으로 먼저 확보한다.

## AdaRound를 지금 최종 주제로 택하지 않는 이유

AdaRound는 각 weight의 floor/ceil 선택을 layer reconstruction loss로 최적화하는 weight-only PTQ이다. 논문은 소량의 unlabeled data와 soft relaxation으로 4-bit weight 정확도를 회복하지만, 현재 모델은 이미 INT8이고 PFDW는 변환영역 range가 크다. 따라서 새 weight 파일만 만드는 것으로 끝나지 않는다. 실제 PPA 이득을 내려면 Conv/FC 전체의 B operand, Booth parameter, product register, scale 복원 회로까지 좁혀야 한다. 또한 공개 `input_1000.txt`를 calibration에 사용하면 hidden 일반화와 평가 공정성 설명이 약해진다.

## 근거 문헌

- Nagel et al., "Up or Down? Adaptive Rounding for Post-Training Quantization," ICML 2020: https://arxiv.org/abs/2004.10568
- AIMET AdaRound 공식 예제: https://github.com/quic/aimet/blob/develop/Examples/torch/quantization/adaround.py
- Chen et al., "Towards Efficient and Accurate Winograd Convolution via Full Quantization," NeurIPS 2023: https://proceedings.neurips.cc/paper_files/paper/2023/hash/400a2e6a82520b690810b97fd67fcc4e-Abstract-Conference.html
- 2025 CCDC 은상 삼진양자화 CNN: https://ee.kookmin.ac.kr/community/board/ee_news/374?pn=1rss
