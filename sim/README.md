# sim/ — Verilator 시뮬레이션 환경

이번 라운드 범위는 "빌드됨/의존성 resolve됨"까지다. 아래 명령은 round 2에서
실제로 끝까지 돌릴 명령을 미리 문서화한 것.

## Verilog 생성만 (가장 저렴, 이번 라운드에서 확인)

```bash
make -C . verilog CONFIG=freechips.rocketchip.system.TinyConfig
```

## TLXbar 유닛테스트 하네스 elaborate + verilate (round 2)

`TLXbarUnitTestConfig`가 `third_party/rocket-chip/build.sc`의 `emulator` cross-list에
빠져있어서, 아래 한 줄을 추가해야 한다 (패치로 관리, decision-log 참고):

```scala
("freechips.rocketchip.unittest.TestHarness", "freechips.rocketchip.unittest.TLXbarUnitTestConfig")
```

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export PATH="$HOME/bin:$JAVA_HOME/bin:$PATH"
export VERILATOR_ROOT="$(brew --prefix verilator)/share/verilator"

cd ../third_party/rocket-chip
mill 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].mfccompiler.compile'
mill 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].elf'
```

예상되는 마찰 포인트 (macOS arm64):
- CMakeLists가 `libfesvr`(spike 유래)를 링크하려 함 → `riscv-isa-sim`만 있으면 됨
  (전체 GNU 툴체인 불필요). `SPIKE_ROOT` 환경변수 확인.
- `-Wno-UNOPTTHREADS -Wno-STMTDLY -Wno-LATCH -Wno-WIDTH`에 combinational-loop
  경고는 추가로 끄지 말 것 — 체크리스트 Section E와 직결된 신호일 수 있음.

## 실행 (round 2, 이번엔 실행하지 않음)

```bash
# unittest 하네스는 self-checking, .elf 안 필요:
./out/emulator/.../emulator
```
