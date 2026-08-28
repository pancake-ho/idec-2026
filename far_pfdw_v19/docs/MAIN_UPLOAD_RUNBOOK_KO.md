# `idec-2026/main` 업로드 및 실행 Runbook

## 0. 검토 기준

- 저장소: `https://github.com/pancake-ho/idec-2026`
- 기본 브랜치: `main`
- 검토한 HEAD: `93eb5ed72e7f7e645aafb3adb0cadfe30777e0a6`
- 검토 시점의 최신 커밋 메시지: `코드 최신화`
- 기존 최상위: `.gitattributes`, `.gitignore`, `analyze/`, `baseline/`,
  `data/`, `verilog/`

이 패키지는 `far_pfdw_v19/`만 추가한다. 기존 RTL과 데이터는 덮어쓰지 않는다.

## 1. 저장소 준비

새로 clone하는 경우:

```bash
git clone https://github.com/pancake-ho/idec-2026.git
cd idec-2026
git switch main
git pull --ff-only origin main
```

이미 clone한 경우에는 작업물을 먼저 확인한다.

```bash
cd /path/to/idec-2026
git status --short
git fetch origin
git switch main
git pull --ff-only origin main
```

`git status --short`에 본인 작업이 표시되면 먼저 commit 또는 stash한 뒤
진행한다. `reset --hard`, 강제 push, rebase로 기존 팀 작업을 지우지 않는다.

## 2. 패키지 배치

다운로드한 ZIP의 절대 경로를 사용한다.

```bash
unzip -q /absolute/path/to/idec-2026_far_pfdw_v19_main_ready.zip -d .
test -f far_pfdw_v19/README_KO.md
```

정상 배치 후 구조는 `idec-2026/far_pfdw_v19/...`이다. ZIP을 두 번 풀어
`far_pfdw_v19/far_pfdw_v19`가 되면 잘못된 것이다.

## 3. 업로드 전 정적 점검

```bash
./far_pfdw_v19/scripts/preflight.sh
git status --short
git diff --check
git diff --stat
```

예상 `git status`는 `?? far_pfdw_v19/` 하나뿐이다. 기존 `verilog/`, `data/`,
`analyze/`가 수정되었다면 원인을 확인한 뒤 중단한다.

## 4. Vivado RTL 검증

Vivado 2024.1 설정 스크립트 위치는 설치 환경에 맞게 바꾼다.

```bash
source /tools/Xilinx/Vivado/2024.1/settings64.sh
xvlog -version
```

가장 중요한 동일성 테스트부터 수행한다.

```bash
./far_pfdw_v19/scripts/run_vivado_rtl.sh ab
./far_pfdw_v19/scripts/run_vivado_rtl.sh cycle_ab
./far_pfdw_v19/scripts/run_vivado_rtl.sh far
```

그 다음 현재 `main/verilog` baseline과 비교한다.

```bash
./far_pfdw_v19/scripts/run_vivado_rtl.sh repo_baseline
./far_pfdw_v19/scripts/run_vivado_rtl.sh cycle_repo_baseline
```

로그 위치:

```text
far_pfdw_v19/build/vivado/<test-name>/xvlog.log
far_pfdw_v19/build/vivado/<test-name>/xelab.log
far_pfdw_v19/build/vivado/<test-name>/xsim.log
```

판정 순서는 아래와 같다.

1. `ab`: `Decision match : 1000 / 1000`
2. `far`: `Correct : 970 / 1000` 이상
3. 모든 테스트: `TIMEOUT`, `$fatal`, `ERROR` 없음
4. `cycle_ab`: V18A/V19 min·max·avg cycle 기록
5. `repo_baseline`: 현재 main baseline과 decision/accuracy 차이 기록

정확성 실패 상태에서 PPA 결과만 채택하지 않는다.

## 5. OpenROAD PPA A/B

ORFS는 V18A와 V19를 같은 checkout으로 실행해야 한다. 현재 ORFS 공식
out-of-tree 호출 형식인 `make --file=<flow/Makefile> DESIGN_CONFIG=...`를
스크립트가 사용한다.

```bash
export ORFS_FLOW_DIR=/absolute/path/to/OpenROAD-flow-scripts/flow
git -C "$ORFS_FLOW_DIR" rev-parse HEAD
./far_pfdw_v19/scripts/run_orfs_ab.sh
./far_pfdw_v19/scripts/ppa_summary.sh
```

주요 결과:

```text
far_pfdw_v19/reports/asap7/chip_v18a_far_ab/base/metadata.json
far_pfdw_v19/reports/asap7/chip_v19_far/base/metadata.json
far_pfdw_v19/build/orfs/ppa_summary.csv
far_pfdw_v19/build/orfs/ppa_summary.md
```

PPA 판정:

1. 두 설계 모두 setup `WNS >= 0`, `TNS = 0`
2. timing을 만족한 run끼리 area와 power 비교
3. V19 cycle 실측값으로 latency 계산: `cycles × 0.75 ns`
4. energy/image 계산: `power(mW) × latency(ns) / 1000`
5. ORFS commit, SDC, clock, density가 같은지 로그와 config로 확인

과거 V18A 수치인 area `17,102.587860 um^2`, power `103 mW`, WNS
`+11.5633 ps`는 참고만 한다. 최종 표에는 같은 ORFS checkout에서 재실행한
A/B 값만 사용한다.

## 6. Gate-level 회귀

ORFS V19 netlist 예:

```bash
V19_NETLIST="$PWD/far_pfdw_v19/results/asap7/chip_v19_far/base/6_final.v"
ASAP7_MODEL=/absolute/path/to/asap7_cells.v
./far_pfdw_v19/scripts/run_vivado_gate.sh "$V19_NETLIST" "$ASAP7_MODEL"
```

사용 환경에서 `glbl.v`가 필요하면 세 번째 인수로 넘긴다.

```bash
./far_pfdw_v19/scripts/run_vivado_gate.sh \
  "$V19_NETLIST" "$ASAP7_MODEL" /path/to/glbl.v
```

## 7. `main` commit 및 push

사용자가 요청한 직접 `main` 업로드 순서는 다음과 같다. push 직전에 원격이
움직였는지 다시 확인한다.

```bash
git fetch origin
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git add far_pfdw_v19
git diff --cached --check
git diff --cached --stat
git commit -m "feat: add FAR-PFDW V19 A/B and PPA flow"
git push origin main
```

`test`가 실패하면 commit/push하지 말고 아래처럼 최신 main을 반영한 뒤 테스트를
다시 확인한다.

```bash
git pull --rebase origin main
./far_pfdw_v19/scripts/preflight.sh
git push origin main
```

팀 저장소에서 더 안전하게 운영하려면 feature branch와 PR을 사용한다.

```bash
git switch -c feat/far-pfdw-v19
git add far_pfdw_v19
git commit -m "feat: add FAR-PFDW V19 A/B and PPA flow"
git push -u origin feat/far-pfdw-v19
```

## 8. push 후 확인

```bash
git fetch origin
git log -1 --oneline origin/main
git status --short
```

GitHub에서 `far_pfdw_v19/README_KO.md`가 보이고, 로컬 `git status`가 비어
있으면 업로드가 끝난 것이다. `build/`, `logs/`, `reports/`, `results/`는
중첩 `.gitignore`로 제외되므로 실험 산출물이 main에 섞이지 않는다.
