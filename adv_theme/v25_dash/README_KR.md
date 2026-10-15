# V25-H를 DASH 4등급 분류에 적용하는 1차 기능 검증

이 패키지는 기존 `adv_theme` 안에 `v25_dash/`를 추가한다. 기존의 BBB·ED 2초 데이터, 라벨, 시간 분할, 정합 결과를 재사용한다. 새 CLI는 `python v25_dash/run.py`이며 실험 결과는 `runs/v25_avc4`에 기록한다. 설치·실행 명령은 패키지 루트의 `RUN_KR.md`에 있다.

## 이번 구현에서 V25가 쓰이는 위치

원본은 [pancake-ho/idec-2026의 고정 커밋](https://github.com/pancake-ho/idec-2026/tree/0d345f1bb658d5772868c7ef939ac592b7a2bb19)이다. `exp/dash-train`에서 확인한 **V25-H**를 선택했다. `V25`의 여러 탐색 후보를 혼합하지 않는다.

| 구성 | DASH 적용 |
|---|---|
| V25-H의 살아 있는 Conv1 2채널, Conv2 3채널 | `1→2→3`, 5×5 valid convolution, 각 층 2×2 max pool |
| Pool2의 CHW 48개 특징 | FC 입력 48개 유지, 출력은 MNIST 10개에서 DASH 4개로 변경 |
| 5×5를 네 블록으로 분해하는 49-lane 변환 | 동일한 B/G/A 행렬과 lane 순서. 원본 Python과 자동 대조 |
| W5/W6/W6, A8/A8 | Conv1 5비트, Conv2·FC 6비트. Pool 출력 U8 |
| T16/8/8 | 양자화 전 단계의 8비트 정수 코드에서 작은 가중치를 제거. QAT 중 다시 살아날 수 있음 |
| Conv 변환 계수 PoT1 | 공간 커널에 G를 적용한 **뒤** 계수를 0 또는 signed power of two로 코딩 |
| FC SP2 | 서로 다른 signed power 두 항의 합. RTL은 클래스마다 두 번 요청 |
| V25-H 스트리밍 제어기 | 원본을 고정해 템플릿으로 사용. 6×6 sliding window, 7행 버퍼, C1/C2 overlap, 단계별 writeback 유지 |
| 계수별 비트 폭 축소 | 새 DASH 계수와 모든 입력 0…255의 구간 경계로 재계산 |

모델은 입력 `1×28×28 → Conv1 2×24×24 → Pool1 2×12×12 → Conv2 3×8×8 → Pool2 3×4×4 → FC48→4`이며 학습 파라미터는 **401개**다. MNIST 가중치를 그대로 가져오지 않고 DASH train으로 재학습한다. 지정주제에서 만든 구조·계수 코딩·스트리밍 제어 방법을 자유주제에 적용하는 것이다.

`model.py`가 학습 모델, `coding.py`가 PoT/SP2 코드북, `integer.py`가 독립 정수 golden, `hardware.py`가 계수별 RTL 생성기, `verify.py`가 실제 시뮬레이션 검증, `flow.py`가 PPA 입력 생성 담당이다. `source_v25h/`는 출처·행렬 대조용 원본이며 그대로 DASH top으로 합성하는 디렉터리가 아니다.

## 세 단계 학습

| 단계 | 역할 | 다음 단계 입력 |
|---|---|---|
| `fp32` | 작은 V25 구조로 4등급 학습이 가능한지 확인 | 가장 높은 validation macro-F1 체크포인트 |
| `int8` | 같은 구조의 dense W8/A8 QAT. before 기준 | 가장 높은 validation macro-F1 체크포인트 |
| `v25h` | W566/A88 + T16/8/8 + TD PoT1 + FC SP2 QAT | 독립 정수 export와 after RTL |

불균형 train에는 inverse-frequency sampling을 적용하고 손실은 가중치 없는 cross entropy를 쓴다. validation/test는 원래 분포 그대로 평가한다. 각 단계는 epoch 0과 학습 epoch를 함께 비교해 validation macro-F1 최대값을 선택한다. 동점은 먼저 나온 체크포인트를 유지한다. `calibrated_val_F1`은 양자화 단계 진입 직후 성능이다. QAT가 이보다 개선되지 않으면 `best_epoch=0`일 수 있다.

기본 FP32 40 epoch, INT8 QAT 15 epoch, V25 QAT 15 epoch다. 양자화 scale은 train에서 뽑은 1,024개 패치와 현재 가중치로 한 번 정하고 해당 QAT 단계 동안 고정한다. train 명령은 test NPZ를 열지 않는다. 실제 출력 정수로 validation을 평가하며 FP32→정수→코딩의 손실을 분리해서 볼 수 있다.

기존 6/12채널 masked 모델과 dense8 결과는 진단 참고 자료다. 이 코드의 before/after는 같은 2/3채널 V25 구조 안에서 비교한다. 기존 `runs/avc4`의 checkpoint를 새 구조로 로드하지 않는다.

## DASH에 맞춰 바뀐 수치 계약

원본 V25-H의 MNIST 고정 restore shift, wrap, score slice를 새로운 학습값에 그대로 적용하면 다른 모델을 실행하게 된다. 여기서는 2의 거듭제곱 scale을 train으로 정하고 다음 계약을 Python·정수·RTL에 동일하게 적용했다.

- 입력은 기존 패치의 Y U8 값이다. 학습 시 `x/256`으로 정규화한다. 참조 영상·SSIM·비트레이트는 추론 입력이 아니다.
- Conv 변환은 블록별 역변환 합을 각각 `/4`, `/2`, `/2`, `/1`로 **floor**한 다음 입력 채널을 합산한다.
- bias는 해당 층 accumulator 단위의 signed32다. activation은 round-to-nearest-even 후 ReLU 및 U8 saturation이다. 네 FC 점수도 signed32이며 동점 argmax는 가장 작은 클래스 ID다.
- `v25h`에서는 변환 계수 코딩 때문에 일반적인 공간 5×5 convolution이 golden이 아니다. transformed-domain QAT와 독립 정수 모델을 비교한다. `int8`에서는 공간 convolution과 49-lane 결과가 정확히 같아야 한다.
- PoT/SP2 최근접 코딩의 동점은 항 수가 적은 값, 절댓값이 작은 값, 수치가 작은 값 순서로 선택한다. Conv의 원본 lane 규칙을 따르며 FC에도 같은 규칙을 적용했다. 원본 scalar FC의 단순 작은 수치 우선 동점 규칙과는 차이가 있다.
- `range_proof.json`은 관측한 샘플 최댓값이 아니라 **모든 입력 바이트 조합**에 대한 보수적 구간 경계다. export 때 signed32를 넘을 가능성이 있으면 실패한다.

V25의 제한된 폭 FC carry 경로는 현재의 signed32 DASH bias/score 계약으로 대체했다. 따라서 이번 포팅은 V25-H 구조와 PPA 기법의 재사용이며 원본 MNIST 연산 전체의 bit-identical 복제라는 주장은 하지 않는다.

## 데이터 의미와 판정 범위

기존 `dash_cnn/data/audit.py`를 재사용해 패치 형식, SSIM 라벨, segment/sample 분리, 시간 guard를 검사한다. 클래스 ID는 `0 excellent (SSIM≥0.95)`, `1 great (0.90≤SSIM<0.95)`, `2 good (0.80<SSIM<0.90)`, `3 poor (SSIM≤0.80)`다. 이는 원래 만든 local 28×28 Y SSIM teacher의 네 등급을 따르는 것이며 AWS의 서비스 전체 점수와 동일하게 측정했다는 의미는 아니다.

BBB·ED 동일 콘텐츠의 시간 분할 실험이다. 새 콘텐츠 일반화, 주관적 MOS, segment 전체 VQA는 아직 검증 대상이다. `poor` 검출은 recall과 precision/혼동행렬을 함께 봐야 한다. test accuracy만으로 성공을 판단하지 않는다. 이번 1차 목표는 작은 V25 모델의 분류 가능성, 코딩 손실, Python/정수/RTL 정합을 확인하는 것이다. DASH 플레이어/ABR 제어 연결은 다음 단계다.

## 실제 RTL 검증과 인터페이스

`verify-export`는 validation의 등급별 대표 4개와 0/255/checkerboard 경계 입력을 사용한다. test 결과를 보고 RTL/가중치를 선택하지 않는다.

1. QAT 모델과 독립 정수 모델의 Pool1·Pool2·네 점수·argmax를 대조한다.
2. INT8은 공간/변환 연산을, V25-H는 MUL/SHIFT 정수 연산을 대조한다.
3. Icarus로 실제 생성 RTL을 컴파일하고 engine 192개 요청을 확인한다. 모든 convolution/FC coefficient tag, 연속 요청과 bubble, 6-cycle response latency를 검사한다.
4. 실제 top에서 두 Pool의 값, 네 점수, decision, commit 수, reset 반복 및 mid-patch reset을 확인한다.

top은 원본 V25 스트림 규약을 따른다. active-low **동기 reset**을 걸고 해제한 뒤 prime 1 cycle을 기다리고, row-major 순서의 784 바이트를 매 cycle 넣는다. `valid_out_6`은 결과를 1 cycle 알리고, `decision[1:0]`과 `logits[127:0]`에 결과가 남는다. 다음 패치는 reset 후 입력한다. `logits[31:0]`이 클래스 0이다. 입력 stall/backpressure를 지원하는 이전 40-lane top과 인터페이스가 다르다.

RTL에는 학습 후 고정된 계수가 들어간다. 새로 학습하면 `verify-export`에서 RTL을 다시 만든다. 합성 데이터로 확인한 top latency는 INT8 830 cycle, V25 SP2 834 cycle이었다. 이 숫자는 첫 입력부터 결과까지의 cycle이며 Fmax나 PPA 개선율이 아니다.

## PPA 비교 준비

`flow`는 검증한 RTL의 hash가 같을 때만 before/after 및 후보 MUL ablation 입력을 생성한다.

| 폴더 | 의미 |
|---|---|
| `before_int8_mul` | 2/3채널 dense W8/A8, multiplier backend |
| `after_v25h_shift` | 2/3채널 W566/A88, pruning·PoT/SP2, shift backend |
| `ablation_v25h_mul` | after와 동일한 코딩 계수, multiplier backend. 계수 코딩과 backend 효과 구분용 |

before/after는 가중치·코딩까지 바뀌므로 각각의 정확도와 PPA를 함께 보고한다. 두 설계 모두 고정 계수를 쓰며 동일한 입출력, 목표 주기, 공정/FPGA part, flow stage, tool revision으로 비교해야 한다. 합성기가 multiplier를 shift로 최적화할 수 있으므로 ablation의 개선율은 실제 결과로 판단한다.

ORFS 입력은 공식 [flow 설정](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html), [slang frontend 변수](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html)를 따른다. SystemVerilog unpacked array 때문에 slang가 포함된 Yosys가 필요하다. ASAP7 SDC는 ps를 기본값으로 만들며 설치한 Liberty 단위는 [OpenSTA `report_units`](https://openroad.readthedocs.io/en/latest/main/src/sta/doc/Examples.html)로 확인한다. Vivado 입력은 ns다. 동일 activity를 주지 않은 power report는 vectorless 추정이다.

지금 제공하는 것은 검증된 RTL과 flow **입력 파일**이다. Vivado/OpenROAD 합성·배치배선 및 Fmax·Power·Area 수치는 아직 측정하지 않았다.
