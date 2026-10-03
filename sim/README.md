# sim/ — Verilator 시뮬레이션 환경

## Verilog 생성만 (round 1에서 확인)

```bash
make -C . verilog CONFIG=freechips.rocketchip.system.TinyConfig
```

## TLXbar 유닛테스트 하네스 elaborate + verilate (round 2 — 완료, 바이너리 빌드까지 확인됨)

`TLXbarUnitTestConfig`가 `third_party/rocket-chip/build.sc`의 `emulator` cross-list에
빠져있어서, 아래 한 줄을 추가했다 (`patches/0002-add-tlxbar-unittest-config.patch`):

```scala
("freechips.rocketchip.unittest.TestHarness", "freechips.rocketchip.unittest.TLXbarUnitTestConfig")
```

실제로 통한 전체 명령 (mill 데몬을 처음 띄울 때부터 아래 env var가 잡혀있어야 함 —
`--no-server`로 데몬 캐싱 문제를 피하는 게 안전):

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export PATH="$HOME/bin:$JAVA_HOME/bin:$PATH"
export VERILATOR_ROOT="$(brew --prefix verilator)/share/verilator"
export SPIKE_ROOT="/opt/homebrew/opt/riscv-isa-sim"

cd ../third_party/rocket-chip
mill --no-server 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].mfccompiler.compile'
mill --no-server 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].elf'
```

겪은 마찰 포인트 (전부 `docs/03-env-setup-macos-arm64.md`에 상세 기록):
- `firtool`이 PATH에 없음 → Chisel 6.7.0이 기록한 `firtoolVersion=1.62.1`을
  Rosetta로 설치 (arm64 네이티브 바이너리가 없어서).
- `build.sc`가 넘기는 `-dedup` 플래그가 firtool 1.62.1에서 제거됨 → 패치로 제거
  (`patches/0001-remove-obsolete-dedup-flag.patch`).
- `SPIKE_ROOT` 미설정 시 `RISCV` 환경변수 요구 → `riscv-isa-sim`의 brew prefix로 설정.
- mill이 **백그라운드 데몬**으로 떠서 이전 env var를 캐싱 — 데몬을 죽이거나
  `--no-server`로 실행해야 새 env var가 반영됨.
- CMake가 Ninja generator를 요구 → `brew install ninja`.

결과: `out/emulator/freechips.rocketchip.unittest.TestHarness/freechips.rocketchip.unittest.TLXbarUnitTestConfig/verilator/elf.dest/emulator`
(Mach-O 64-bit arm64, 네이티브) 바이너리 빌드 성공.

## 실행 (round 3 — 아직 안 함)

```bash
# unittest 하네스는 self-checking, .elf 안 필요:
./out/emulator/freechips.rocketchip.unittest.TestHarness/freechips.rocketchip.unittest.TLXbarUnitTestConfig/verilator/elf.dest/emulator
```
`TLRAMXbarTest`/`TLMulticlientXbarTest`/`TLJbarTest`/`TLMasterMuxTest`가 끝까지
통과하는지, 체크리스트 Section H에서 설계한 sparse-visibility variant를 직접 만들어
비교하는 게 round 3 목표.
