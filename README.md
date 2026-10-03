# riscv_study — RISC-V TileLink Xbar Sparsity Study

RocketChip의 TileLink crossbar(`TLXbar`)가 만들어내는 **sparse connectivity**를 공부하고,
그걸 검증하는 체크리스트를 작성하기 위한 레포입니다.

## 범위 (현재 라운드)

- [x] 로컬 환경 구축 (JDK, mill, Verilator, RISC-V 툴체인)
- [x] `docs/01-xbar-sparsity-checklist.md` 작성
- [x] rocket-chip을 서브모듈로 연결하고 Verilog 생성까지 "빌드됨" 확인
- [x] `TLXbarUnitTestConfig`를 `emulator` cross-list에 패치로 추가하고 verilate까지
      완료 (네이티브 arm64 `emulator` 바이너리 빌드됨, 아직 실행은 안 함)
- [x] 빌드된 바이너리를 실행해 6개 테스트(`TLJbarTest`, `TLRAMXbarTest`×3,
      `TLMulticlientXbarTest`, `TLMasterMuxTest`) 전부 통과 확인 (201782 cycles,
      결과: [`docs/05-round3-first-run-results.md`](docs/05-round3-first-run-results.md))
      — 단, 전부 **dense** 베이스라인. sparse variant는 아직.
- [x] `TLFilter`로 `visibility`를 진짜로 좁힌 sparse-visibility 하네스
      (`TLSparseXbarTest`) 구현, 비대칭 sparse 패턴(client0: 단일 reachable manager
      포함)으로 67530 cycles에서 통과 확인 — 상세:
      [`docs/06-sparse-harness-design.md`](docs/06-sparse-harness-design.md)
- [x] 의도적 negative test — client0의 stimulus를 visibility보다 넓혀봤더니
      "조용히 aliasing"이 아니라 **`TLMonitor`가 cycle 14에서 즉시 assertion으로
      잡음** (가설 정정 포함, 상세: [`docs/07-negative-test-results.md`](docs/07-negative-test-results.md))
- [ ] (다음 라운드) `TLMonitor`가 못 잡는 진짜 aliasing 경로 — visibility **선언
      자체**가 틀린 경우(모니터는 선언을 사실로 믿으므로 무사통과) 재현, golden
      matrix 비교로만 잡힘을 실증
- [ ] (다음 라운드) 파형(VCD) 확인 필요시 `make debug`로 디버그 빌드 재생성

## 호스트 가정

- macOS 15.6 (Apple Silicon, arm64)
- Homebrew로 모든 툴체인 설치

## 왜 Chipyard를 안 썼는가

Chipyard는 Linux에서만 테스트되고, `build-setup.sh`가 쓰는 conda-lock 파일에
`linux-aarch64` solution이 없어 Apple Silicon에서 곧바로 실패합니다
([chipyard#789](https://github.com/ucb-bar/chipyard/issues/789)). Linux VM을 새로
띄우는 비용(10~20GB+)도 이번 스코프엔 과합니다.

대신 **standalone rocket-chip + mill 0.11.1(고정) + Verilator**로 간다 — rocket-chip에는
이미 `TLXbarUnitTestConfig`라는 self-checking 크로스바 전용 테스트벤치가 있어서, RISC-V
바이너리나 전체 SoC 부팅 없이도 크로스바 자체를 스터디할 수 있습니다.

자세한 배경은 [`docs/04-decision-log.md`](docs/04-decision-log.md) 참고.

## 버전

| 도구 | 버전 |
|---|---|
| JDK | OpenJDK 17 (Homebrew) |
| mill | 0.11.1 (pinned — `brew`의 mill 1.x는 rocket-chip의 `build.sc`를 못 읽음) |
| Verilator | 5.052 |
| Scala | 2.13.12 (rocket-chip 고정) |
| Chisel | 6.7.0 (rocket-chip 고정) |

## Quickstart

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export PATH="$HOME/bin:$JAVA_HOME/bin:$PATH"   # ~/bin/mill, JDK17

./scripts/check-env.sh                 # 툴체인/레포 상태 확인
make -C third_party/rocket-chip verilog CONFIG=freechips.rocketchip.system.TinyConfig
```

체크리스트 본문: [`docs/01-xbar-sparsity-checklist.md`](docs/01-xbar-sparsity-checklist.md)
