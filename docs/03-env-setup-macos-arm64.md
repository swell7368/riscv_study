# 환경 설정 노트 (macOS arm64, Apple M1, macOS 15.6.1)

실제로 이 머신에서 통한 명령과 겪은 문제를 그대로 기록한다. 배경 설명/이유는
[`04-decision-log.md`](04-decision-log.md) 참고.

## 0. 사전 조건: 디스크 정리

설치 시작 전 3.3GB만 남아있었음. `~/Library/Application Support/Notion/notionAssetCache-v2`
가 78GB를 차지하고 있어 (Notion 데스크톱 앱의 로컬 자산 캐시 — 실제 데이터인
`notion.db`는 3.1MB뿐) Notion을 정상 종료(`osascript -e 'quit app "Notion"'`) 후
삭제하여 102GB 확보.

```bash
df -g /System/Volumes/Data | awk 'NR==2{print $4" GB available"}'
du -sh ~/Library/Application\ Support/*/  | sort -rh | head
```

## 1. Git 신원

`~/.gitconfig`가 없는 상태였음 (`git config --global --list`가 비어있었다):
```bash
git config --global user.name  "swell7368"
git config --global user.email "swell7368@gmail.com"
git config --global init.defaultBranch main
```

## 2. JDK 17

```bash
brew install openjdk@17
```
`openjdk@17`은 keg-only라 PATH/JAVA_HOME을 직접 잡아줘야 함:
```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
```
`~/.zshrc`에 영구 추가. **주의**: Bash 툴로 명령을 돌릴 때는 매번 새 쉘이라 `.zshrc`가
자동 적용되지 않으므로, 이후 모든 mill/java 호출 앞에 export를 반복해야 했다.

## 3. mill 0.11.1 (고정 버전)

```bash
mkdir -p ~/bin
curl -L -o ~/bin/mill https://github.com/com-lihaoyi/mill/releases/download/0.11.1/0.11.1-assembly
chmod +x ~/bin/mill
export PATH="$HOME/bin:$PATH"
```
처음 `mill --version`을 JAVA_HOME 없이 돌렸을 때 "Unable to locate a Java Runtime"
에러 — JAVA_HOME/PATH를 같은 쉘에서 먼저 export해야 함.

## 4. Verilator / cmake / dtc

```bash
brew install verilator cmake dtc
```
문제 없이 바이너리 바틀로 설치됨 (Verilator 5.052, cmake 4.4.3, dtc 1.8.1).

## 5. RISC-V 툴체인

```bash
brew tap riscv-software-src/riscv
```
여기서 Homebrew 7.0.7의 새 보안 기능에 걸림:
```
Error: Refusing to load formula riscv-software-src/riscv/riscv-tools from untrusted tap riscv-software-src/riscv.
```
해결:
```bash
brew trust --tap riscv-software-src/riscv
brew install riscv-tools
```
arm64_sequoia 바이너리 바틀로 설치되어 소스 빌드(수 GB, 수십 분) 없이 끝남.
`riscv64-unknown-elf-gcc`, `spike`는 PATH에 바로 잡힘. `pk`는 별도 바이너리명
(`riscv64-unknown-elf-pk` 등)으로 설치되어 `which pk`로는 안 보임 — 이번 스코프에선
불필요하므로 무시.

## 6. firtool 설치 (수동, PATH 필요)

`make verilog`/`mill emulator[...].mfccompiler.compile`를 돌리면 rocket-chip의
`build.sc`가 `os.proc("firtool", ...)`로 **PATH 위의 bare `firtool` 커맨드**를 직접
호출한다 — Chisel 내부의 firtool-resolver(자동 다운로드)는 이 경로에서 쓰이지 않는다.
처음 돌렸을 때 다음 에러로 실패:
```
java.io.IOException: Cannot run program "firtool" ... No such file or directory
```

필요한 정확한 버전은 Chisel 6.7.0 jar에 빌드타임에 기록된 `firtoolVersion`을 추출해서
확인했다(`chisel3.BuildInfo$`의 문자열 상수 = `1.62.1`):
```bash
cd /tmp && mkdir biextract && cd biextract
jar xf <chisel_2.13-6.7.0.jar> 'chisel3/BuildInfo$.class'
python3 -c "
import re
data = open('chisel3/BuildInfo\$.class','rb').read()
for s in re.findall(rb'[\x20-\x7e]{4,}', data):
    print(s)
" | grep -E '^\d+\.\d+\.\d+$'
```

macOS arm64용 firtool 1.62.1 네이티브 바이너리는 없고 (`circt` 릴리즈에 macos-x64만
존재), Rosetta 2로 x64 바이너리를 그대로 실행했다 — 이 머신엔 Rosetta가 이미 설치돼
있어 추가 설치 불필요했다:
```bash
curl -sL -o /tmp/firrtl-bin-macos-x64.tar.gz \
  https://github.com/llvm/circt/releases/download/firtool-1.62.1/firrtl-bin-macos-x64.tar.gz
tar -xzf /tmp/firrtl-bin-macos-x64.tar.gz -C /tmp
mkdir -p ~/.local/firtool-1.62.1
mv /tmp/firtool-1.62.1-*/* ~/.local/firtool-1.62.1/
ln -sf ~/.local/firtool-1.62.1/bin/firtool ~/bin/firtool
```
`firtool --version` → `CIRCT firtool-1.62.1-1-gdf5ed6ea5` 확인됨.

## 7. 확인 완료 (이번 라운드 하드 게이트, 전부 통과)

```
$ ./scripts/check-env.sh
...
== 결과: 11 OK / 0 FAIL ==
```
- `mill rocketchip[6.7.0].compile` — hardfloat/cde/diplomacy/rocketchip 322개 Scala
  소스 전부 컴파일 성공 (warning만 있고 에러 없음).
- `mill emulator[...TestHarness,...TinyConfig].mfccompiler.compile` — firtool
  1.62.1(Rosetta) 패치 후 성공, `.sv` 216개 생성됨.

## 8. Round 2: TLXbarUnitTestConfig verilate

`build.sc`의 `emulator` cross-list에 `TLXbarUnitTestConfig` 추가
(`patches/0002-add-tlxbar-unittest-config.patch`). 그 후 겪은 문제들:

1. **`SPIKE_ROOT`가 잡혔는데도 "NoSuchElementException: RISCV" 에러 반복.**
   원인: mill은 기본적으로 **백그라운드 서버(데몬)**로 동작해서, 같은 디렉터리에서
   처음 실행했을 때의 환경변수를 계속 캐싱한다. 이후 셸에서 `export SPIKE_ROOT=...`를
   새로 해도 데몬은 그걸 못 본다.
   ```bash
   ps aux | grep MillServerMain   # 살아있는 데몬 PID 확인
   kill -9 <pid1> <pid2>          # 데몬 전부 종료
   mill --no-server '...'         # 데몬 없이(또는 새 데몬으로) 재실행
   ```
2. **`CMake Error: ... unable to find ... "Ninja"`.** rocket-chip의 Verilator
   CMake 플로우가 Ninja generator를 쓴다. `brew install ninja`로 해결.

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export PATH="$HOME/bin:$JAVA_HOME/bin:$PATH"
export VERILATOR_ROOT="$(brew --prefix verilator)/share/verilator"
export SPIKE_ROOT="/opt/homebrew/opt/riscv-isa-sim"
mill --no-server 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].elf'
```

verilate 성공 결과:
```
[30/32] Linking CXX executable emulator
```
바이너리: `out/emulator/freechips.rocketchip.unittest.TestHarness/freechips.rocketchip.unittest.TLXbarUnitTestConfig/verilator/elf.dest/emulator`
(Mach-O 64-bit arm64 네이티브 실행파일 — Verilator 자체가 생성하는 C++는 네이티브
arm64로 컴파일되므로 firtool과 달리 Rosetta 불필요).

## 9. 아직 안 해본 것 (round 3로 미룸)

- 생성된 `emulator` 바이너리를 실제로 실행해서 `TLRAMXbarTest`/`TLMulticlientXbarTest`
  등이 끝까지 통과하는지 확인
- `src/main/scala/xbarstudy/`에 직접 sparse-visibility 하네스 구현 (체크리스트
  Section H에서 설계한 대로 `visibility`를 좁힌 variant)
