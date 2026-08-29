# PFDW V20 — W5 power-of-two hardware-aware quantization

V20은 실패한 V19 상태 보존 최적화를 더 수정하지 않고, PPA가 더 좋은 동결
V18A에서 시작한다. 공용 49-lane Booth 가중치 경로를 signed 8-bit에서 5-bit로
줄이고 모든 계층에서 `2^3` 스케일을 MAC 뒤 배선 shift로 복원한다.

| 계층 | W5 변환 | 이유 |
|---|---|---|
| Conv1 | floor | 상위 5비트 선택만 필요 |
| Conv2 | truncate-to-zero | 저비트 존재 시 음수에 1을 더하는 소형 보정 |
| FC | nearest-even | 편향을 줄이되 scale multiplier/divider는 없음 |

1000장 bit-exact Python 사전검증은 V18A `970/1000`, V20 `980/1000`이다.
W4 최선은 `950/1000`이므로 W5가 정확도 비퇴행 조건을 만족하는 최소 폭이다.

구현은 `scripts/generate_rtl.py`가 동결 V18A의 정확한 패턴을 검증한 뒤 V20
RTL과 전용 testbench를 생성한다. 생성 결과도 저장소에 포함되며 `--check`로
source/generator drift를 차단한다.

가장 짧은 실행은 다음과 같다.

```bash
python3 far_pfdw_v20/scripts/generate_rtl.py
bash far_pfdw_v20/scripts/check_source.sh
python3 far_pfdw_v20/scripts/search_pow2_mp.py
```

Vivado와 Seraph full ORFS 절차, 통과 기준, 로그 위치는
[`docs/FULL_RUN_KO.md`](docs/FULL_RUN_KO.md)를 따른다.

아직 이 브랜치에서 완료되지 않은 증거는 Vivado RTL, ORFS PPA, post-route
netlist gate 결과다. Python `980/1000`은 후보 선택 근거이며 RTL과 gate의
1000장 결과로 최종 확인한다.
