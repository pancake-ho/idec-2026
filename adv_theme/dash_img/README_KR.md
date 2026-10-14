# BBB MPEG-DASH: 발표용 동일 프레임 추출

이 코드는 `adv_theme/runs/assets/media/bbb/rep_XX.mp4`에 이미 다운로드된 **실제 AVC 표현본**에서 동일 프레임을 추출한다. 자료 다운로드·모델 학습·RTL 합성 코드는 전혀 수정하지 않는다.

## 준비 (서버에서)

```bash
conda activate lab
cd /data/surt321/repos/idec/adv_theme
command -v ffmpeg
command -v ffprobe
python -c 'from PIL import Image; print("Pillow OK")'
```

`dash_img` 폴더를 **`adv_theme` 바로 아래**에 배치한다. `python -m pip install Pillow`는 Pillow 미설치 시에만 실행한다.

## 1. 먼저 다운로드 완료 여부 확인

```bash
python dash_img/extract_bbb.py --list
```

각 MPD 레코드는 `rep_XX`, 명시적 `bandwidth`, 해상도, `READY`/`MISSING`/`NO RECEIPT` 상태를 출력한다. `READY`는 파일 크기와 download receipt의 크기가 일치함을 뜻하며, SHA-256을 매번 재계산했다는 뜻은 아니다. 실제 디코딩 전에 ffprobe로 추가 확인한다.

## 2. 정확히 지정한 저·중·고 표현본과 동일 프레임

```bash
python dash_img/extract_bbb.py \
    --media-work runs/assets \
    --time 120.5 \
    --targets 131087,595491,3078587 \
    --strategy exact
```

선택값은 이 패키지의 공식 BBB MPD 기준: low `rep_02`(131.087 kbps, 320×240), medium `rep_09`(595.491 kbps, 854×480), high `rep_16`(3078.587 kbps, 1920×1080)이다. `--time 120.5`는 24fps 기준 **0부터 시작하는 디코딩 프레임 #2892**이다. 서버에서 파일이 실제 존재해야 하고 FFprobe 결과가 MPD 속성과 같아야 한다.

미완료 상태라면 다운로드 완료를 기다린다. 명시적으로 다른 세 파일을 사용해도 된다면 `--strategy nearest`를 전달할 수 있다. 이 경우 스크립트는 파일이 완료된 3개 표현본 중 목표 비트레이트에 가까운 조합을 고르고 **실제 선택값을 콘솔과 metadata에 기록**한다. 재현성 높은 발표에는 `exact` 권장.

```bash
# 미리보기 후보만 다른 시간으로 추출하고 싶을 때
python dash_img/extract_bbb.py --time 180.5 --targets 131087,595491,3078587

# 다운로드 경로가 기본값과 다를 때
python dash_img/extract_bbb.py --media-work /absolute/path/to/runs/assets --time 120.5

# 수동으로 넣은 MP4에 receipt가 없을 때만 (검증 신뢰도 낮아짐)
python dash_img/extract_bbb.py --allow-unreceipted --time 120.5
```

## 3. 출력

`dash_img/output/` 안에 저·중·고 개별 PNG, 3개를 합친 비교 PNG, 동일 비율 ROI 확대 비교 PNG, 모든 비트레이트·해상도·프레임 정보가 있는 metadata JSON을 만든다. `bbb_comparison_t120p500s_f002892.png`를 PPT의 왼쪽 영역에 사용하자. 품질 차이가 잘 보이지 않으면 `bbb_comparison_zoom_...png`도 비교해보자. 확대 위치는 `--roi 0.40,0.30,0.22,0.22`로 조정한다.

`--time`에 따른 파일 이름이 달라지므로 기존 결과는 지우지 않는다. 같은 시간/같은 옵션을 다시 실행하면 해당 이름의 추출 PNG·합성 PNG만 갱신한다.

## 주의

- 이 비교는 `same frame index`와 같은 24 fps를 보장한다. 단, 서로 다른 해상도의 영상은 인코더가 다르게 리사이즈했을 수 있다.
- MPD의 bandwidth는 **해당 표현본의 선언 비트레이트**다. 순간 비트레이트나 실제 SSIM은 아니다.
- 4등급 화질 정답은 학습 파이프라인의 원본 기준 **local SSIM**으로 계산하며, 이 PPT의 low/mid/high와 직접 동일시하지 않는다.
- 프레임 출력 PNG는 decode 결과이고 임의의 블러/열화를 추가하지 않는다.
- 스크립트는 계산 후 저장된 MP4를 읽을 뿐, 다운로드, 학습, 서버 실행 job을 건드리지 않는다.
