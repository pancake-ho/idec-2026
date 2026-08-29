# PFDW V20 전체 검증·PPA 실행 절차

## 0. 고정 기준

- 프로젝트 코드: `pancake-ho/idec-2026`
- V20 시작점: `main@16773f4a0f820f1673a0d1ebbd658feca0f7004c`
- 동결 기능/PPA 기준: `far_pfdw_v19/reference_v18a`
- ORFS: `a5ff7ef7dac4338e6e5fad7710b85fc6c8f3503c`
- OpenROAD native: `6b9d7fb806c0e769b548989d4049d8d0355ed487`
- PDK/조건: ASAP7, 750 ps, utilization 40%, place density 0.65

V19는 V18A보다 area `+5.72%`, power `+0.13%`, WNS가 더 나빠졌으므로
V20은 V19가 아니라 V18A에서 분기한다.

## 1. 빠른 정적·Python 게이트

저장소 루트에서 실행한다.

```bash
python3 far_pfdw_v20/scripts/generate_rtl.py
bash far_pfdw_v20/scripts/check_source.sh
python3 far_pfdw_v20/scripts/search_pow2_mp.py
```

예상 선택은 다음과 같다.

```text
W5 ('floor', 'trunc', 'even'): correct=980/1000
SELECTED: W5 shift=3 modes=(floor,trunc,even)
```

이 단계는 신경망 산술의 비트정확 사전검증이다. 파이프라인과 생성 RTL의
동일성은 다음 Vivado 단계에서 별도로 통과해야 한다.

## 2. Windows Vivado 2024.1 RTL 전체 검증

PowerShell에서 저장소 루트로 이동한 뒤 다음 순서로 실행한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\far_pfdw_v20\scripts\run_vivado_rtl.ps1 -TestName v20
powershell -ExecutionPolicy Bypass -File .\far_pfdw_v20\scripts\run_vivado_rtl.ps1 -TestName ab
powershell -ExecutionPolicy Bypass -File .\far_pfdw_v20\scripts\run_vivado_rtl.ps1 -TestName cycle_ab
powershell -ExecutionPolicy Bypass -File .\far_pfdw_v20\scripts\run_vivado_rtl.ps1 -TestName repo_baseline
powershell -ExecutionPolicy Bypass -File .\far_pfdw_v20\scripts\run_vivado_rtl.ps1 -TestName cycle_repo_baseline
```

로그는 각 `build/vivado/<test>/xsim.log`에 남는다. `xvlog.log`를 직접
`Tee-Object` 대상으로 사용하지 않아 Windows 파일 잠금 충돌을 피한다.

필수 판정:

| Gate | 기준 |
|---|---:|
| V20 정확도 | 970/1000 이상; Python 예상 980/1000 |
| X/Z, timeout, fatal | 0 |
| V20 cycle | V18A 859보다 증가 금지 |
| 기준 RTL | V18A 또는 repo baseline 970/1000 정확히 재현 |

양자화 후보이므로 V18A와 1000/1000 decision-identical일 필요는 없다. 대회
목표인 정답 수 비퇴행이 correctness hard gate다.

## 3. cycle 로그를 Seraph 저장소에 복사

Windows와 Seraph 저장소가 별도이면 `cycle_ab/xsim.log`를 다음 위치로 옮긴다.

```text
/data/surt321/repos/idec/far_pfdw_v20/build/vivado/cycle_ab/xsim.log
```

이 파일이 없으면 PPA는 가능하지만 latency와 energy/image는 `N/A`가 된다.

## 4. Seraph 제출

로그 디렉터리를 만든 뒤 저장소 루트에서 제출한다.

```bash
mkdir -p logs
sbatch far_pfdw_v20/run/seraph_v20_full.sbatch
```

진행 확인:

```bash
squeue -j "$JOB_ID"
tail -f "logs/pfdw-v20-ppa-${JOB_ID}.out"
```

두 설계는 16 CPU를 8+8로 나누어 병렬 실행한다. `--gres=gpu:1`은 학부생
partition의 29 GB 메모리 할당 조건이며 OpenROAD 계산 자체는 GPU CUDA를
사용하지 않는다. 순차 실행이 필요하면 제출 전에 `ORFS_AB_PARALLEL=0`을
내보내되 총 경과 시간은 두 full flow의 합이 된다.

## 5. 완료 확인과 판정

```bash
sacct -j "$JOB_ID" --format=JobID,JobName,State,ExitCode,Elapsed,MaxRSS,NodeList
cat far_pfdw_v20/build/orfs/ppa_summary.md
sed -n '1,10p' far_pfdw_v20/build/orfs/ppa_summary.csv
```

ORFS가 정상 완료되면 다음 zero-delay gate simulation 묶음도 자동 생성된다.

```text
far_pfdw_v20/build/orfs/gate_bundle/
├── chip_v20_pow2_final.v
├── SHA256SUMS
└── stdcell/                 # ASAP7 Verilog cell models
```

## 6. Windows Vivado post-route netlist 검증

Seraph에서 생성된 `gate_bundle` 디렉터리를 Windows의 동일한
`far_pfdw_v20/build/orfs/` 아래로 복사한 후 실행한다.

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\far_pfdw_v20\scripts\run_vivado_gate.ps1
```

다른 위치에 복사했다면 경로를 명시한다.

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\far_pfdw_v20\scripts\run_vivado_gate.ps1 `
  -Netlist "D:\pfdw_gate\chip_v20_pow2_final.v" `
  -StdcellDir "D:\pfdw_gate\stdcell"
```

이 검증은 SDF를 쓰지 않는 zero-delay 기능 검증이다. `Correct >= 970`,
`RESULT: PASS`, `TIMEOUT/FATAL/ERROR 없음`을 확인한다. 실제 타이밍 판정은
ORFS의 WNS/TNS가 담당하며, gate test는 합성·배치배선 netlist가 1000장 기능을
유지했는지 독립적으로 확인한다. 스크립트는 공식 ASAP7 SEQ 모델과 모듈명이
겹치는 ORFS의 Verilator 보조 파일 `dff.v`만 자동 제외한다.

## 7. 최종 승격 판정

V20 승격 조건은 아래 순서로 판정한다.

1. Vivado 정확도 970/1000 이상, timeout/fatal 없음.
2. 기준 정확도 970/1000 재현 및 V20 cycle 수가 V18A보다 증가하지 않음.
3. ORFS 최종 netlist gate simulation 정확도 970/1000 이상.
4. 동일 ORFS/SDC에서 area가 V18A보다 감소.
5. estimated Fmax가 V18A보다 악화되지 않음.
6. timing이 닫힌 경우 power·energy도 비교한다. timing 미달 power는 잠정치다.

하나라도 hard gate를 통과하지 못하면 V18A를 유지하고 해당 단계 로그에서
다음 병목을 특정한다. AI/QAT/LoRA는 이 플로우의 원인 진단을 대신하지 않는다.
