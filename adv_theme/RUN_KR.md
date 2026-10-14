# 전체 실행 명령

모든 실험 명령의 현재 폴더는 `adv_theme`다. 아래 설치 단계는 서버에 ZIP을 업로드한 뒤 실행한다.
기존 `lab`처럼 PyTorch가 설치된 Python 환경을 사용해도 된다. 새 가상환경 생성은 필수가 아니다.
기존 지정주제의 `rtl/`, `reference/`, `data/`, `synthesis/`는 이 패키지의 설치 대상이 아니다.

## 0. 설치

ZIP을 `/data/surt321/repos/idec/`에 올린 뒤:

```bash
cd /data/surt321/repos/idec
python - <<'INSTALL'
from pathlib import Path
import shutil, tempfile, zipfile
repo = Path.cwd()
current = repo / 'adv_theme'
backup = repo / 'adv_theme_before_avc4_20261014'
if backup.exists():
    raise SystemExit('Backup already exists. Stop and choose a different backup name before installing.')
with zipfile.ZipFile(repo / 'DASH_AVC4_modular_20261014.zip') as z:
    for name in z.namelist():
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or not name.startswith('adv_theme/'):
            raise SystemExit('Unexpected archive path; stop installation.')
    with tempfile.TemporaryDirectory(dir=repo) as temp:
        z.extractall(temp)
        source = Path(temp) / 'adv_theme'
        if not (source / 'scripts/run.py').is_file():
            raise SystemExit('Package is incomplete.')
        if current.exists():
            current.rename(backup)
        try:
            shutil.move(str(source), str(current))
        except Exception:
            if backup.exists() and not current.exists():
                backup.rename(current)
            raise
print('Installed:', current)
INSTALL
cd adv_theme
python -m pip install -r requirements.txt
python scripts/run.py doctor
```

설치 블록이 실패하면 다음 단계로 넘어가지 말고 오류를 확인한다. 기존 폴더를 보관한 뒤 새 `adv_theme`를 배치하는 방식이다.
PyTorch가 없는 경우:

```bash
python -m pip install -r requirements-train.txt
```

검증 환경은 Python3.12, NumPy, Pillow, PyTorch2.5.1+cpu, FFmpeg6.1.1, Icarus12.0다.
GPU 학습은 현재 사용 중인 CUDA PyTorch 설치를 유지한다. 실제 GPU 실행은 이 패키지 제작 시 검증하지 않았다.
`doctor`는 설치 정보를 출력한다. 학습 전에 `torch_installed`를, GPU 사용 전에 `cuda_available`을 확인한다.
FFmpeg·FFprobe 및 libx264 encoder, Icarus/vvp는 OS에 있어야 한다. Ubuntu에서 필요한 경우:

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg iverilog unzip
```

## 1. 먼저 기능 검사

```bash
python scripts/run.py verify --work runs/selftest
python scripts/run.py verify-rtl --work runs/selftest
```

기대: 산술 JSON `PASS`, 데이터 단위검사 `OK`, engine 256건 및 전체 top 5회 `PASS`.
전체 top의 약17,099 cycle에는 입력 bubble·출력 hold가 들어 있다. compute-only latency나 throughput으로 쓰지 않는다.

선택적으로 FFmpeg/XZ/SIDX 연결 전체를 합성 영상으로 확인:

```bash
python tests/check_video_pipeline.py --out runs/selftest/video_pipeline.json
```

## 2. 다운로드 계획과 실제 확보

```bash
python scripts/run.py plan --work runs/assets
python scripts/run.py download --work runs/assets --references
```

`plan`은 MPD를 받고 원격 파일 크기를 조회한다. `download_plan.json`의 전체 용량을 먼저 확인한다.
공식 원본 XZ 두 개만 약18.5GB이며 MP4 표현본·프레임 캐시·실험 결과 공간이 추가로 필요하다.
전체 raw88GB를 따로 생성하지 않는다. 원본 다운로드와 XZ 프레임 추출은 오래 걸릴 수 있다.
전송 중 끊기면 같은 `download` 명령을 다시 실행한다. `.part`를 이어 받고 완료 파일은 hash receipt로 검증한다.
중단된 명령 뒤에는 다음 단계로 넘어가지 않는다. 다른 인터넷 MP4를 원본으로 자동 대체하지 않는다.

## 3. 정합·패치·라벨·분할

```bash
python scripts/run.py prepare --media-work runs/assets --work runs/avc4
python scripts/run.py audit --work runs/avc4
```

확인할 파일:

- `runs/avc4/reports/bbb_alignment.json`, `ed_alignment.json`: `passed: true`.
- `runs/avc4/reports/dataset_audit.json`: 실제 train/validation/test 클래스 분포, 해상도, 마지막 구간.
- `runs/avc4/reports/audit_recheck.json`: 구간 그룹 중복과 temporal gap 검사.

정합 실패는 실행을 중단한다. report를 첨부해 원본 offset·영상 버전·색 범위부터 점검한다.
Train/validation은 class0/1/2/3 표본이 모두 있어야 한다. Test에 빠진 class가 있으면 그 등급의 성능을 검증했다고
주장하지 않는다. Severe 표본이 없을 때 severe→excellent 오류율은 0 대신 `null`을 출력한다.

## 4. 학습 진입 확인

실영상 학습 전에 합성 데이터로 학습/export 연결을 확인하고 싶을 때:

```bash
python scripts/run.py smoke --work runs/training_smoke
python scripts/run.py train --work runs/training_smoke --base-epochs 2 --qat-epochs 2 --device cpu
python scripts/run.py verify-export --work runs/training_smoke
```

`SYNTHETIC_SMOKE_ONLY`가 정상 출력이다. 이 점수는 화질 예측 정확도가 아니다.

## 5. 실제 학습과 비교군

```bash
python scripts/run.py controls --work runs/avc4
python scripts/run.py train --work runs/avc4 --device cuda:0
```

`cuda:0`은 해당 Python 환경에서 보이는 첫 GPU다. GPU가 없으면 `--device cpu`로 바꾼다.
기본 학습은 FP32 40epoch→QAT15epoch다. Adapter 학습은 현재 AVC-only 실험에서 사용하지 않는다.
파일 로그가 필요하면 `tee`보다 종료 코드를 명확히 확인할 수 있도록:

```bash
mkdir -p runs/avc4/logs
python -u scripts/run.py train --work runs/avc4 --device cuda:0 > runs/avc4/logs/train.log 2>&1
```

이는 위 학습 명령의 대안이다. 두 학습 명령을 연속 실행하지 않는다. 학습 완료 뒤:

- `runs/avc4/models/final/history.csv`
- `runs/avc4/models/final/training_report.json`
- `runs/avc4/models/final/integer/weights_int.npz`, `.mem`, `params.svh`
- `runs/avc4/models/final/qat.pt`

모델 선택은 validation만 사용한다. QAT checkpoint의 선택은 정확한 정수 추론 macro-F1 기준이다.
이미 있는 모델 폴더를 덮어쓰거나 resume하지 않는다. 새 실험에는 새 `--work` 폴더를 사용한다.
정확도 손실 분리를 위해 같은 데이터·seed에서 별도 variant를 학습할 수 있다:

```bash
python scripts/run.py train --work runs/avc4 --variant dense8 --device cuda:0
python scripts/run.py train --work runs/avc4 --variant mask8 --device cuda:0
python scripts/run.py train --work runs/avc4 --variant mixed11 --device cuda:0
```

RTL은 `final`만 지원한다. 위 비교군은 Python 모델의 정확도 영향 분석용이다.

## 6. 학습 weight의 RTL 일치와 test

```bash
python scripts/run.py verify-export --work runs/avc4
python scripts/run.py evaluate --work runs/avc4
```

확인: `runs/avc4/reports/export_rtl.json`, `final_test.json`, `final_test_predictions.npz`.
Macro-F1·4×4 confusion·class support/recall·severe→excellent·등급 절대오차·콘텐츠별 지표를 출력한다.
Test를 본 뒤 경계나 모델을 반복 수정하면서 같은 test를 최종 성능으로 쓰지 않는다.
현재 split은 같은 두 콘텐츠 안의 분리 구간이다. 새로운 콘텐츠 일반화는 별도의 이후 실험이다.

## 7. 선택: 동일 모델 direct/PFDW 합성 입력

```bash
python scripts/run.py flow --work runs/avc4 --engine direct
python scripts/run.py flow --work runs/avc4 --engine pfdw
```

ORFS가 실제 설치되어 있을 때:

```bash
make -C "$ORFS_ROOT/flow" DESIGN_CONFIG="$PWD/runs/avc4/build/direct/config.mk"
make -C "$ORFS_ROOT/flow" DESIGN_CONFIG="$PWD/runs/avc4/build/pfdw/config.mk"
```

입력 생성만 검증했으며 이 명령의 ASAP7 PPA 결과는 아직 없다. clock1000은 ASAP7 ps 단위를 가정한
시작값이므로 실제 Liberty 단위를 확인하고 팀의 고정 SDC·tool commit으로 맞춘다.
이 단계는 V25-H multiplierless 구조가 아니라 동일 DASH 정수 모델의 direct/PFDW 비교다.
게이트레벨 일치와 동일 activity 전력도 후속 측정 사항이다.

## 지금 첨부하면 좋은 실행 결과

우선 다운로드/준비 단계까지 완료한 뒤 아래만 첨부하면 다음 점검을 진행할 수 있다.

1. `reports/bbb_alignment.json`, `reports/ed_alignment.json`
2. `reports/dataset_audit.json`, `reports/audit_recheck.json`
3. 실패했다면 해당 명령의 오류 로그 전문

대용량 원본 파일 자체를 첨부할 필요는 없다.
