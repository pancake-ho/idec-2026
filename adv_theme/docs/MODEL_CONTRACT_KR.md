# 모델·정수·RTL 계약

입력은 Y code U8 28×28이다. 학습 시 /256으로 변환하며 추론에 원본·SSIM·비트레이트를 주지 않는다.
모델은 Conv5×5(1→6, valid)→ReLU/Pool2→Conv5×5(6→12, valid)→ReLU/Pool2→FC192→4→argmax다.

| 단계 | shape | 형식 |
|---|---|---|
|Input|1×28×28|unsigned8|
|Conv1|6×24×24|signed32 accumulation|
|Pool1|6×12×12|unsigned8|
|Conv2|12×8×8|signed32 accumulation|
|Pool2|12×4×4|unsigned11|
|FC|4 scores|signed32|
|Decision|0..3|unsigned2|

모든 5×5 kernel의 우하단 2×2는0. 좌상단3×3은 signed8 code[-128,127], side3×2/2×3은 signed6 code[-32,31].
중심 실수 weight scale=2^ew, side=4×2^ew. FC는 별도 2^ewfc와 signed6이다.
입력 scale=2^-8, Pool1=2^ea1, Pool2=2^ea2.
Conv1 bias integer unit=2^(-8+ew1), Conv2=2^(ea1+ew2), FC=2^(ea2+ewfc).
Shift1=ea1+8-ew1, Shift2=ea2-ea1-ew2, 각각0..31.
Pool은 nearest-even 반올림 후 [0,255]/[0,2047] saturate. 음수는0. FC는 softmax 없이 signed32 score argmax,
동률은 작은 ID를 선택한다. Export에서 전체 허용 입력 범위의 누산 bound와 bias가 signed32를 넘으면 거부한다.
학습/가중치/활성 scale은 train-only calibration으로 정한 뒤 QAT에서 고정한다.

PFDW engine은 6×6 input에서 2×2 결과를 낸다. 5×5를3×3/3×2/2×3으로 분해한40 lanes를 사용한다.
중심 inverse는4, side inverse는2로 정확히 복원하며, side scale4를 반영한다.
FC도 같은40-lane multiplier를 사용하고192개 입력은5회,4개 class는20회 요청한다.
동일 sparse direct engine은84 product 구조이고 첫40개를FC와 공유한다.
두 engine은 request→response edge offset6, II1. 내부 v/mode/tag를 정렬하고 bubble을 전달한다.
현재 top은 ISSUE→WAIT_RESULT 방식으로 동시에 여러 tile을 보내지 않는다. engine II를 top 처리율로 쓰지 않는다.

## Top ports

|포트|방향·폭|의미|
|---|---|---|
|clk|in1|posedge|
|rst_n|in1|synchronous active-low reset|
|start|in1|IDLE에서 patch 시작 pulse|
|profile_id|in2 unsigned|0 shared/1 AVC 허용;2/3 fallback+error|
|in_valid|in1|pixel valid|
|pixel_in|in8 unsigned|행 우선784개 Y code|
|in_ready|out1|LOAD에서 수신 가능|
|busy|out1|IDLE 이외|
|out_valid|out1|출력 valid, out_ready까지 hold|
|out_ready|in1|출력 수락|
|class_id|out2 unsigned|0..3|
|logits|out128|{score3,score2,score1,score0}, 각각signed32|
|profile_error|out1|start 시 잘못된 profile을 받았음|

3개의 codec ROM bank는 제거하고 Conv2 weight 하나만 저장한다. profile 입력은 호스트 진단용 interface를 유지한다.
원본 MNIST `chip` interface를 바꾸는 작업은 아니다. 자유주제의 별도 patch-level top이다.
Input buffer784×8, Pool1 buffer864×8, Pool2 buffer192×11을 사용한다.
논리 weight ROM은 q1 150×8, q2 1800×8, qfc768×8이며 zero/unneeded bits 합성 제거는 별도 확인해야 한다.
이 크기를 실제 ROM 면적·power 측정 결과로 해석하지 않는다.

제작 시 검증한 full-top17,099cycles는 입력 stall/output hold 포함. FPGA/ASIC Fmax, Power, Area, latency/energy
측정은 아직 없다. 성능 개선율이나 TOPS/W를 이 산술 수치로 대체하지 않는다.
