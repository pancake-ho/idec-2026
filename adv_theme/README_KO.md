# DASH-AdaptCNN v1.0 - 경희 야호

**압축 영상의 국소 열화를 감지하는, 공통 희소 구조 기반 codec 적응형 CNN 가속기.**

친구의 DASH 응용 제안과 V18A 정밀도 분석을 결합한 단일 모델 설계 및 실행 패키지다.
설계·학습 코드·정수 추론·직접 합성곱/PFDW RTL과 합성 입력 생성기를 포함한다.
**실제 영상으로 학습한 가중치, 실영상 정확도, Vivado/ASAP7/OpenROAD PPA는 아직 없다.**
`tests/fixtures`의 가중치는 수치 검증용 난수이며 배포용 모델이 아니다.
완료한 검증은 `results`의 JSON과 설명서에 기록했다.

## 먼저 읽기

- `docs/DASH_AdaptCNN_Final_Design.pdf`: 모델 설명과 대회 연계, 검증 상태.
- `docs/MODEL_SPEC_KO.md`: 입출력·정수 산술·적응·평가 규격 전체.
- `docs/RTL_CONTRACT_KO.md`: 인터페이스와 RTL 구현 범위, 측정 방법.

## 고정된 최종 모델

입력 `28x28x1 uint8` → Conv5x5(1→6) → MaxPool2 → Conv5x5(6→12)
→ MaxPool2 → FC192→3 → argmax. Padding은 valid다.
등급은 같은 위치 원본/압축 패치의 local SSIM에 기반한다: 낮음 ≥0.97, 중간 ≥0.90, 높음 <0.90.
이는 객관 지표의 대리 라벨이며 사람의 주관적 화질 점수와 동일하지 않다.

- 공통 21-tap mask, 모든 profile에서 우하단 2x2 가중치가 0.
- 3x3 W8 / 3x2·2x3 W6 / FC W6. Side block의 상대 scale은 4.
- Pool1 U8, Pool2 U11, nearest-even rounding. 누산/score signed32.
- Profile 0: shared fallback, 1: AVC, 2: HEVC. Host가 codec 정보로 선택.
- Conv2 rank-2 adapter만 학습하고 오프라인 융합. 모든 profile은 같은 mask·scale·정밀도를 유지.
- 두 RTL top은 같은 최종 정수 모델을 구현한다. 최적화 전후 가중치와 출력이 동일하다.

## 실행 환경

Python 3.12 / NumPy, 학습에는 PyTorch 2.5.1, 영상 준비에는 FFmpeg(libx264/libx265/ffv1),
RTL 검증에는 Icarus Verilog 11.0+와 vvp가 필요하다. 가상환경 사용을 권장한다.

```bash
python -m pip install -r requirements.txt
python -m pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
python tests/check_python.py
python tests/run_rtl.py
```

특정 경로의 툴을 사용할 경우 `run_rtl.py --iverilog PATH --vvp PATH --ivl-base PATH`를 쓴다.
모든 명령은 이 폴더에서 실행한다. 명령 실패 시 다음 단계로 진행하지 않는다.

## 실제 영상으로 학습하기

원본 콘텐츠별로 train/validation/test를 먼저 나누어 CSV를 작성한다. 같은 콘텐츠의
다른 편집본·압축본을 다른 split에 넣지 않는다. 예제 CSV 경로는 실제 파일로 교체한다.
초기 검증 후에는 다양한 독립 콘텐츠 수를 늘린다. 한 작품의 많은 패치는 독립 작품 수를 대체하지 않는다.

```bash
python src/prepare_videos.py --sources examples/sources.csv --out run/data
python src/baselines.py --train run/data/train.npz --validation run/data/validation.npz --out run/controls
python src/train.py --train run/data/train.npz --validation run/data/validation.npz --out run/final
```

`dataset_audit.json`에서 class/codec별 샘플 분포를 확인한다. 특정 등급이 비면 압축 강도와
콘텐츠를 train 기준으로 보완한 뒤 모든 split에 동일 생성 규칙을 적용한다. Test를 보고 경계를 조정하지 않는다.
원본은 라벨 생성에만 사용하며 CNN 입력에 포함되지 않는다. 데이터는 영상 전체를 인코딩한 후 패치를 자른다.

학습 단계는 FP32 40 epoch → QAT 15 epoch → adapter QAT 15 epoch다. Train-only calibration으로
scale을 정한 뒤 고정한다. Validation macro-F1이 좋아지고 severe→low 오판이 늘지 않는 adapter만 채택한다.
채택하지 않은 codec은 해당 bank를 shared 가중치로 export한다. Test는 학습 코드가 읽지 않는다.

`run/final/adapted`에 정수 가중치, `.mem`, `params.svh`, checkpoint가 생성된다.
`run/final/shared`는 적응 효과 비교용이다. 채택 후 독립 test는 한 번 평가한다.

```bash
python src/evaluate.py --model run/final/adapted/weights_int.npz --train run/data/train.npz --validation run/data/validation.npz --test run/data/test.npz --out run/test_metrics.json
python tests/check_export_rtl.py --weights run/final/adapted --data run/data/validation.npz --out run/export_rtl.json
```

## 정확도 손실을 분리하는 비교 실험

`train.py --variant dense8`, `mask8`, `mixed11`을 별도 출력 폴더에서 같은 split/seed로 실행한다.
Dense8→mask8은 mask 효과, mask8→mixed11은 W8/W6 및 FC W6 효과,
mixed11→final은 Pool1 U11→U8 효과다. 이는 비교군이며 최종 RTL은 `final`만 지원한다.
각 비교는 seed 2026/2027/2028 등 동일 seed 세트로 수행한다. 비교군별 재학습 결과에는 학습 변동성이 포함된다.

내부 권장 채택 기준: dense8 대비 validation macro-F1 하락 1 percentage point 이내,
metadata/간단 특징보다 시각 정보의 이득 확인, severe→low 오류 확인, 동일 모델 RTL 일치,
요구 처리량에서 PPA 이득 확인. 이 기준은 대회 공식 배점/합격 기준이 아니다.
기준 미달이면 현재 모델을 검증 완료 모델로 보고하지 말고 원인을 분석해 버전을 갱신한다.

## RTL/PPA 실행 준비

```bash
python flow/prepare_flow.py --weights run/final/adapted --engine direct --out build/direct
python flow/prepare_flow.py --weights run/final/adapted --engine pfdw --out build/pfdw
make -C "$ORFS_ROOT/flow" DESIGN_CONFIG="$PWD/build/direct/config.mk"
make -C "$ORFS_ROOT/flow" DESIGN_CONFIG="$PWD/build/pfdw/config.mk"
```

OpenROAD-flow-scripts와 ASAP7은 별도 설치가 필요하다. 팀의 고정 commit·corner·단계로 맞춘다.
기본 SDC period=1000은 ASAP7의 ps 단위를 가정한 시작 제약이다. Liberty 단위를 실제 log에서 확인한다.
Vivado 2024.1 비교는 생성 폴더의 `vivado.tcl`에 동일 FPGA PART를 전달한다.
템플릿의 vectorless power를 실측 전력으로 부르지 않는다. 실제 test activity를 넣은 비교가 추가로 필요하다.
`flow/ppa_results_template.csv`는 모두 미측정 상태다.

## 재현용 smoke test

```bash
python tests/make_smoke_data.py --out smoke/data
python src/train.py --train smoke/data/train.npz --validation smoke/data/validation.npz --out smoke/model --base-epochs 2 --qat-epochs 2 --adapt-epochs 2 --synthetic-smoke
```

이 데이터는 인위적 영상 잡음으로 만든 기능 검사 자료다. 실제 codec·품질 성능 검증에 사용하지 않는다.
원본 영상 데이터와 학습 가중치를 제공받지 않은 상태에서 정확도를 지어내지 않도록 기능 검증 결과만 포함했다.
