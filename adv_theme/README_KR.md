# DASH AVC4: BBB·Elephants Dream 2초 국소 열화 분류

`exp/dash-train`의 DASH 코드(idec-2026 commit `0d345f1`)를 기반으로 만든 모듈화 패키지다.
AVC 단일 shared 모델, 4등급 분류, 실제 DASH 표현본, 원본 기반 local SSIM 라벨을 사용한다.
전체 실행 명령은 [RUN_KR.md](RUN_KR.md), 포트·정수 규칙은 [docs/MODEL_CONTRACT_KR.md](docs/MODEL_CONTRACT_KR.md)에 있다.
`CODE_FULL.md`에는 실행 가능한 소스 전문을 파일별로 모았다.

## 범위

- 공식 BBB/ED onDemand 2초 MPD, MP4 표현본, Xiph 1080p24 Y4M.xz 다운로드(이어받기·hash receipt).
- MPD SegmentBase indexRange의 실제 SIDX로 청크 크기·시작·길이 확인. 마지막 짧은 청크 허용.
- 원본 XZ를 스트림으로 읽어 필요한 Y 프레임만 PNG 캐시에 보존. 전체 88GB raw 저장은 하지 않는다.
- 28×28 압축 Y 입력. 원본 Y는 같은 표현본 해상도로 Pillow bicubic 정합하여 교사 SSIM에만 사용.
- train 구간 최고 bitrate 표현본으로 정합 heuristic 검사. 실패하면 라벨 생성을 중단한다.
- 같은 영상의 같은 2초 구간에서 나온 모든 표현본·패치는 동일 split. 30초 블록 분할, 양끝 2초 제외.
- FP32 학습, train-only calibration, QAT, 정확한 정수 validation으로 checkpoint 선택, 정수 export.
- 같은 가중치의 sparse direct/PFDW RTL, 128bit logits, 4등급 argmax, 학습 weight의 RTL 비교.

**실제 BBB/ED 학습 정확도·codec 적응·V25-H multiplierless 이식·ASAP7 PPA·게이트레벨 검증은 아직 완료된 결과가 아니다.**
제공 검증 결과는 기능 검사이며, 합성 데이터 점수를 실영상 성능으로 쓰지 않는다.
Icarus RTL 시뮬레이션과 FFmpeg 합성 AVC 연결 검사는 실제로 재실행했다.

## 고정 라벨

| ID | 이름 | local SSIM |
|---:|---|---|
|0|Excellent|s ≥ 0.95|
|1|Great|0.90 ≤ s < 0.95|
|2|Good|0.80 < s < 0.90|
|3|Poor|s ≤ 0.80|

AWS MediaConvert의 프레임 SSIM 해석 구간을 참고한 패치 라벨 설계다. AWS가 28×28 CNN 등급을 검증했다는 의미는 아니다.
`dash_cnn/spec.py`가 class 수와 경계의 유일한 실행 정의다. Test 결과에 맞춰 경계를 변경하지 않는다.
SSIM은 11×11 Gaussian sigma1.5, valid 창, population moments, data_range255로 계산한다.

## 모듈

| 경로 | 책임 |
|---|---|
|configs/avc4.json|데이터 URL, 추출량, 블록 split, seed, 정합 gate, 학습 설정|
|src/dash_cnn/data/mpd.py|AVC MPD 및 실제 SIDX|
|src/dash_cnn/data/download.py|다운로드·이어받기·receipt|
|src/dash_cnn/data/media.py|FFprobe, 원본/디코딩 Y 프레임 캐시|
|src/dash_cnn/data/prepare.py|정합 검사와 실제 데이터 생성 orchestration|
|src/dash_cnn/data/labels.py, patches.py, splits.py, audit.py|라벨·패치·분할·무결성|
|src/dash_cnn/models/cnn.py|고정 6/12채널 CNN, mixed precision fake quant|
|src/dash_cnn/training/trainer.py|FP32/QAT·모델 선택·export 검사|
|src/dash_cnn/integer/|정수 Golden Model·산술·export|
|src/dash_cnn/evaluation/|4등급 지표, test, 간단 비교군|
|src/dash_cnn/hardware/generate.py|동일 engine RTL 재생성 및 폭 근거|
|rtl/|두 engine, Booth, 4출력 top|
|tests/|산술·데이터·RTL·학습 export·AVC 연결 검사|
|scripts/run.py|각 모듈의 단일 실행 CLI|
|runs/assets|다운로드 원본·표현본 및 공용 프레임 캐시|
|runs/avc4|실험별 NPZ·학습 로그·가중치·평가 결과|

## 데이터 계약과 제한

2초는 원본 구간의 그룹 단위다. 기본 설정은 매 3번째 구간에서 0.5/1.5초 프레임과 5개 패치를 선택한다.
화면을 28×28로 축소하거나 청크 하나의 정답을 모든 패치에 복사하지 않는다.
고정 local SSIM은 원본을 표현본의 native 해상도로 변환한 기준에 대한 값이다. 다른 encoder의 원래 resize filter와
완전히 일치한다는 보장은 없으며, reference preprocessing을 고정한 재현 가능한 대리 라벨이다.
현재 정합 gate는 시간·기하 정합의 큰 오류를 찾는 train-only heuristic이다. 정확한 encoder preprocessing 증명은 아니다.
`reference_frame_offset=0`, gate correlation0.98/MAE12, 추출량은 실험 설정이며 공식 대회 기준이 아니다.
정합 실패 시 offset나 range를 임의로 바꾸지 말고 alignment report와 프레임 쌍을 먼저 확인한다.

프레임률은 원본 Y4M header와 MP4/MPD가 같아야 한다. 8bit YUV420, CFR, MP4 start_time0만 처리한다.
서로 다른 색 범위를 자동 remap하지 않고 Y code를 보존한다. range 차이도 정합 실패의 원인이 될 수 있다.
파일 split은 두 콘텐츠 내부의 시간 블록 평가다. 원본 콘텐츠가 test에서 완전히 새로운 일반화 실험은 아니다.
다른 파일 hash를 가진 동일 장면까지 자동으로 알아내는 방법도 아니다.

Train/validation의 네 등급 중 하나라도 없으면 학습을 거부한다. SSIM 경계를 바꾸거나 비트레이트를 정답으로
대체하지 않는다. 먼저 실제 클래스 분포를 확인하고 train 추출량/장면 범위를 보완한 뒤 공통 규칙을 적용한다.
새 규칙에는 새 실험 폴더를 사용하며 `--media-work runs/assets`로 대용량 다운로드를 재사용한다.

## 참고

- 데이터: https://dash.itec.aau.at/dash-dataset/
- BBB 2초: https://ftp.itec.aau.at/datasets/DASHDataset2014/BigBuckBunny/2sec/
- ED 2초: https://ftp.itec.aau.at/datasets/DASHDataset2014/ElephantsDream/2sec/
- 원본: https://media.xiph.org/video/derf/
- AWS: https://docs.aws.amazon.com/mediaconvert/latest/ug/per-frame-metrics-analysis.html
- 데이터 인용: Lederer, Müller, Timmerer, Dynamic Adaptive Streaming over HTTP Dataset, ACM MMSys 2012.
