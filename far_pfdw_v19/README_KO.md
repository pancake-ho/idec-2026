# FAR-PFDW V19 — `idec-2026` 통합 패키지

이 디렉터리는 `pancake-ho/idec-2026`의 기존 `verilog/`, `data/`,
`analyze/`, `baseline/`을 수정하지 않고 추가되는 독립 A/B 검증 묶음이다.
검토 기준은 2026-08-28의 `main` 커밋
`93eb5ed72e7f7e645aafb3adb0cadfe30777e0a6`이다.

## 구현 주제

**FAR-PFDW (Fan-out-Aware Reuse PFDW)**: 산술식과 8-bit 파라미터는 V18A와
동일하게 유지하면서 Conv2 실행 순서를 `(pr, pc, oc, ic)`에서
`(pr, pc, ic, oc)`로 바꾼다. 같은 activation tile을 `oc=0,1,2`가 연속
소비하도록 하여 activation operand 및 transform register의 불필요한 갱신을
줄인다.

- Conv2/FC 요청 수와 곱셈 수는 바꾸지 않는다.
- Conv2 activation update 기회는 이론상 `576 -> 192`로 줄어든다.
- FC activation은 class 0에서만 적재하고 class 1~9에서 유지한다.
- V18A의 correction-row Booth, 49-lane P0-P6 파이프라인, fixed-point slicing을
  유지한다.
- Conv2 출력 채널별 누산 bank 때문에 약 160-bit 상태가 추가된다. 이 비용보다
  operand/register switching 감소가 큰지는 반드시 동일 조건 PPA로 판정한다.

## 저장소 의존성

- 입력과 파라미터: 저장소 루트의 `data/`
- 현재 저장소 baseline 비교: 저장소 루트의 `verilog/`
- 고정 A/B 기준: 이 디렉터리의 `reference_v18a/`

`data/`의 27개 파일은 검토한 `main`과 전달 패키지가 Git blob hash까지
동일했으므로 중복 저장하지 않는다. 반면 현재 `verilog/`는 옛 전달 패키지의
baseline과 hash가 다르므로 baseline 테스트는 항상 저장소의 최신 파일을
컴파일한다.

## 가장 짧은 검증 순서

Vivado 2024.1 환경을 먼저 활성화한 뒤 저장소 루트에서 실행한다.

```bash
./far_pfdw_v19/scripts/preflight.sh
./far_pfdw_v19/scripts/run_vivado_rtl.sh ab
./far_pfdw_v19/scripts/run_vivado_rtl.sh cycle_ab
./far_pfdw_v19/scripts/run_vivado_rtl.sh far
./far_pfdw_v19/scripts/run_vivado_rtl.sh repo_baseline
./far_pfdw_v19/scripts/run_vivado_rtl.sh cycle_repo_baseline
```

필수 correctness gate는 다음과 같다.

| 항목 | 통과 기준 |
|---|---:|
| FAR 정확도 | 970/1000 이상 |
| FAR vs frozen V18A decision match | 1000/1000 |
| FAR invariant monitor | 위반 0건 |
| V19 cycle | 실측 기록 후 V18A와 비교 |

`859 cycles`는 과거 합성 결과의 참조값이지 이 RTL의 미실측 결과가 아니다.
V19의 합성/PPA 수치를 보고서에 적기 전에 위 테스트를 실제 환경에서 통과시켜야
한다.

## PPA A/B

```bash
export ORFS_FLOW_DIR=/absolute/path/to/OpenROAD-flow-scripts/flow
./far_pfdw_v19/scripts/run_orfs_ab.sh
./far_pfdw_v19/scripts/ppa_summary.sh
```

두 설계는 ASAP7, 750 ps, 같은 utilization/place density/ORFS commit으로
실행된다. `ppa_summary.sh`는 ORFS `metadata.json`과 cycle log를 읽어 area,
cells, sequential cells, power, WNS/TNS, latency, energy/image를 CSV와 Markdown으로
정리한다.

전체 업로드·실행·판정 순서는 `docs/MAIN_UPLOAD_RUNBOOK_KO.md`를 따른다.

## 디렉터리

- `rtl/`: V19 FAR 합성 RTL 및 `chip` wrapper
- `reference_v18a/`: 변경하지 않는 V18A A/B 기준
- `tb/`: 1000-image correctness/cycle/gate-level 테스트벤치
- `orfs/`: V18A/V19 동일 조건 config와 SDC
- `scripts/`: preflight, Vivado, ORFS, PPA 요약 자동화
- `docs/`: 연구 비교와 main 업로드 runbook

## 현재 확인 범위

정적 구조, 모듈 연결, shell/Python 문법, 저장소 경로와 데이터 hash는 점검했다.
현재 생성 환경에는 Vivado/OpenROAD/Slang/iverilog가 없어 RTL simulation과
실제 PPA는 실행하지 못했다. 따라서 산출 수치는 비워 두며, 실행 후 생성되는
로그와 `build/orfs/ppa_summary.md`가 최종 근거다.
