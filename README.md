# riscv_study — RISC-V TileLink Xbar Sparsity Study

RocketChip의 TileLink crossbar(`TLXbar`)가 만들어내는 **sparse connectivity**를 공부하고,
그걸 검증하는 체크리스트를 작성하기 위한 레포입니다.

## 범위 (현재 라운드)

- [x] 로컬 환경 구축 (JDK, mill, Verilator, RISC-V 툴체인)
- [x] `docs/01-xbar-sparsity-checklist.md` 작성
- [x] rocket-chip을 서브모듈로 연결하고 Verilog 생성까지 "빌드됨" 확인
- [ ] (다음 라운드) 실제 Verilator 시뮬레이션을 끝까지 실행, 파형 확인
- [ ] (다음 라운드) `src/main/scala/xbarstudy/`에 직접 sparse-visibility 하네스 구현

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
