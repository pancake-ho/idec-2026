# BBB 실시간 화질 전환 시연 도구 (Interactive DASH Representation Demo)

**목적:** 교수님께 BBB의 **실제 2초 onDemand DASH 표현본**을 보여주면서 비트레이트를 수동 조절하고, 가상의 대역폭 예산 변화에 따라 어떤 표현본을 선택할지 시연한다. `dash_img`의 기존 정적 프레임 추출 코드와 **동시에 설치 가능**하며 기존 파일을 수정하지 않는다.

## 기능

- 실제 BBB AVC/MP4 영상의 **재생/일시정지, 탐색, 재생 속도** 조절
- 서버에 실제 다운로드한 공식 MPD의 Representation 목록 자동 로드 (최대 20개)
- **Manual**: 실제 MP4 표현본을 비트레이트별로 즉시 교체. 재생 시간 유지
- **Auto · Budget**: 사용자가 바꾼 가상 대역폭 예산의 80% 이하에서 가능한 가장 높은 Representation을 선택. 재생 중에는 **다음 nominal 2초 경계**에서 교체. 정지 상태는 즉시 변경
- **Low/Medium/High 버튼**: BBB 공식 목표 131,087 / 595,491 / 3,078,587 bps 또는 *다운로드된 것 중 가장 가까운 표현본*으로 전환
- **Side-by-side**: 영상 3개를 같은 시점에 맞춰 재생하고 화면을 클릭하면 상대적 위치를 확대 비교. 디코더/네트워크의 영향으로 소폭 동기 편차 존재
- `HTTP Range` 지원: 웹 브라우저로 큰 MP4를 처음부터 전부 받지 않고 필요한 byte range만 전송
- **다운로드 필요 없음, PyTorch/Flask/GStreamer 미필요**: Python 표준 라이브러리 기반. 브라우저 Chrome/Edge에서 동작

### 정확성 범위

이것은 **실제 DASH 재생·적응 시스템을 완전히 구현한 것이 아니다.**
- 실제 원본 MP4 표현본을 바꿔 플레이하지만, MPD SegmentBase/SIDX를 기반으로 2초 청크를 개별 HTTP 요청하는 DASH ABR 클라이언트가 아니다.
- Auto는 **실제 측정 throughput/buffer** 대신 UI 슬라이더 예산을 입력으로 사용하는 **정책 시연**이다. 실제 네트워크 shaping/패킷 드랍/QoE/SSIM/CNN 추론/RTL 실행은 하지 않는다.
- MPD `bandwidth`는 **선언값**이며 실제 비트레이트나 네트워크에서 측정한 전송률이 아니다.
- 3개 동시 미디어 디코딩은 각자 부하가 있으므로 24fps의 **프레임 정확도까지 보장하지 않는다**. 발표에서 "동일 시점 중심 동기 비교"라고 표현한다.
- 시연 전 기존 `runs/avc4/reports/bbb_alignment.json`의 `passed: true`를 확인하면 reference와 실영상 정합에 대한 독립 검증 근거가 된다. 이 도구가 정확도/모델 검증을 대신하지 않는다.

## 1. 설치 (기존 dash_img 보존)

서버의 `/data/surt321/repos/idec/adv_theme/`로 `dash_img_BBB_LIVE_DEMO_ADDON.zip`를 올린 뒤:

```bash
conda activate lab
cd /data/surt321/repos/idec/adv_theme
unzip -n dash_img_BBB_LIVE_DEMO_ADDON.zip
```

새로운 `dash_img/demo/`만 생성된다. 기존 `dash_img/extract_bbb.py`, `README_KR.md`, `run.sh`, `output/`과 학습/RTL 자료는 건드리지 않는다.

## 2. 준비 상태 점검

```bash
python dash_img/demo/server.py --check
```

기본 미디어 위치는 `adv_theme/runs/assets/media/bbb/rep_XX.mp4`; MPD는 `runs/assets/media/bbb/manifest.mpd`가 있으면 우선하고, 없으면 `configs/BigBuckBunny_2s_onDemand_2014_05_09.mpd`를 쓴다. 다운로더의 `rep_XX.mp4.receipt.json`에 저장된 파일 크기와 일치하면 READY다. `READY`는 SHA-256 재계산이나 모든 프레임 디코딩 검증을 의미하지 않는다. 수동으로 받았지만 receipt가 없는 파일을 이용한다면 `--allow-unreceipted` 사용 가능(신뢰도 낮아짐).

```
02 READY                131.087 kbps  320x240  rep_02.mp4
09 READY                595.491 kbps  854x480  rep_09.mp4
16 READY               3078.587 kbps  1920x1080  rep_16.mp4
```

아직 다운로드 중이라면 `python scripts/run.py download --work runs/assets --references`로 기존 다운로드를 재개할 수 있지만 이 명령은 원본 XZ까지 다운로드하므로 큰 저장 공간이 필요하다. **이미 내려받았으면 재실행하지 않는다.** 전체 다운로드가 완료될 필요는 없지만 목표 비트레이트 3개 이상이 READY여야 풍부한 시연 가능.

## 3. 서버 실행

```bash
python -u dash_img/demo/server.py --port 8765
```

서버 로그에 `Open http://127.0.0.1:8765`가 나오면 정상. SSH 서버에서 직접 GUI 브라우저를 열 필요 없음. **서버 프로세스가 실행 중인 터미널을 닫지 않는다.** 종료는 `Ctrl+C`.

다른 경로를 사용했다면:

```bash
python dash_img/demo/server.py --media-work /absolute/path/to/runs/assets --port 8765
```

## 4. Windows에서 MobaXterm/SSH 포트 포워딩

서버가 원격이므로 Windows 노트북의 브라우저에서 `http://127.0.0.1:8765`를 바로 열 수 없는 경우 SSH 터널을 만든다.

- **MobaXterm:** `Tunneling` → `New SSH tunnel` → Local port `8765`, Remote server `127.0.0.1`, Remote port `8765`, SSH server는 현재 접속 중인 서버의 **실제 호스트명**, SSH login은 서버 계정으로 설정 → Start.
- **Windows PowerShell 대안:**

```powershell
ssh -N -L 8765:127.0.0.1:8765 <계정>@<실제서버주소>
```

그 뒤 Windows Chrome/Edge에서 **http://127.0.0.1:8765** 접속. 서버는 보안을 위해 기본 `127.0.0.1`만 바인딩한다. 공인망에서 `--host 0.0.0.0`로 개방하는 것은 권장하지 않는다.

## 5. 교수님께 보여드릴 시연 순서 (약 90초)

1. `▶ 재생` 후 **Manual**에서 `LOW 131 kbps` 선택: 블록 노이즈/경계 및 디테일 관찰
2. `MID 595 kbps` → `HIGH 3.08 Mbps`: 같은 재생 위치를 유지하면서 영상 표현본 변경
3. `3개 표현본 동시 비교` 체크: 같은 시점 3개 화질 비교. 화면의 디테일 부분 클릭 → 선택 위치 확대
4. `Auto · Budget` 선택. 대역폭 예산을 `350 kbps` → `1000 kbps` → `5000 kbps`로 바꾸어 **정책이 선택하는 화질** 변화를 확인
5. **한계 명시:** "이 슬라이더는 실제 네트워크 부하가 아닌 가상 throughput 예산이며, 모델 정확도와 추론 결과는 아직 연결하지 않았습니다." 이후 팀의 CNN 아키텍처 슬라이드로 전환

UI는 기본 120.5초부터 시작하며, 다른 시점은 `http://127.0.0.1:8765/?t=180.5`처럼 지정할 수 있다. 재생이 끊기면 동일한 시점의 preview 영상을 내려놓고 단일 재생만 시연한다.

## 6. 추가 실행 검사

```bash
python dash_img/demo/tests/smoke_test.py
python -m py_compile dash_img/demo/server.py
```

`smoke_test.py`는 실제 BBB가 아닌 **임시 바이트 파일로 로컬 HTTP Range/API를 검사**하는 개발용 테스트다. 이 테스트 성공을 영상 디코딩 또는 BBB 재생 성공으로 간주하지 말 것.

GStreamer는 서버에 GUI가 있는 경우 아래처럼 설치 여부와 네이티브 플레이백을 점검하는 보조 용도로 사용할 수 있다. SSH만 되는 연구실 서버에서는 브라우저 데모가 훨씬 실용적이다.

```bash
command -v gst-play-1.0  # 없으면 선택적으로 sudo apt install gstreamer1.0-plugins-base-apps
# DISPLAY가 실제로 있는 리눅스 데스크톱에서만
# gst-play-1.0 runs/assets/media/bbb/rep_09.mp4
```

GStreamer는 이 패키지의 필수 의존성이 아니며, 제공 도구의 화질 전환을 GStreamer가 제어하지 않는다.

## 구조

```text
dash_img/                          # 기존 파일 보존
├── extract_bbb.py                  # 기존 정적 PNG 추출, 미수정
├── README_KR.md                    # 기존 문서, 미수정
├── run.sh                          # 기존 실행, 미수정
└── demo/                           # 이번에 추가되는 폴더
    ├── server.py                   # MPD catalog + HTTP Range + video endpoint
    ├── README_KR.md                # 실행/제약/발표 가이드
    ├── run.sh                      # 간단 실행
    ├── static/
    │   ├── index.html             # 대시보드 마크업
    │   ├── style.css              # 대시보드 디자인
    │   └── app.js                 # 수동 전환/가상 예산/동기 비교 로직
    └── tests/
        └── smoke_test.py          # 로컬 HTTP 통합 검사
```
