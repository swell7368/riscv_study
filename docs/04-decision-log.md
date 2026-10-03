# Decision Log

## 1. Chipyard를 통째로 쓰지 않는다

Chipyard는 공식적으로 Linux 기반 개발/테스트만 지원한다. `build-setup.sh`가 돌리는
`conda-lock`의 lockfile에 `linux-aarch64` solution이 없어서, Apple Silicon macOS에서는
"lockfile does not contain a solution for the linux-aarch64 platform" 에러로 바로
실패한다 ([chipyard#789](https://github.com/ucb-bar/chipyard/issues/789)).

대안은 Linux VM(Docker/UTM/Lima)인데, 그것만으로 10~20GB 이상의 디스크가 추가로
필요하다. 이번 스코프(크로스바 sparsity 스터디)엔 전체 SoC/부팅 환경이 필요 없으므로
배제한다.

## 2. `emulator/` 디렉터리 기반 튜토리얼은 전부 stale하다

과거 많은 rocket-chip 튜토리얼이 `cd emulator && make` 흐름을 가정하지만, 현재
master에는 `emulator/` 디렉터리가 존재하지 않는다
([discussion #3492](https://github.com/chipsalliance/rocket-chip/discussions/3492)).
지금은 mill(`build.sc`)이 생성하는 CMakeLists를 통해 Verilator의 `verilate()` CMake
함수를 호출하는 방식으로 바뀌었다.

## 3. mill은 반드시 0.11.1을 고정 사용한다

`brew install mill`은 1.1.10을 주는데, rocket-chip의 `build.sc`는 Ammonite 스타일
구문(`import $file.dependencies...`, `Cross.Module2`)으로 작성되어 있어 1.x 파서가
읽지 못한다. rocket-chip의 `overlay.nix`가 0.11.1을 명시적으로 고정하고 있어서,
GitHub 릴리즈의 assembly jar를 직접 받아 `~/bin/mill`에 설치했다.

## 4. sbt는 설치하지 않는다

rocket-chip은 Scala 2.13용으로 Maven Central/Sonatype에 배포된 적이 없다
(2.12용 `edu.berkeley.cs %% rocketchip % 1.2.0`만 존재). 즉 sbt 프로젝트의 라이브러리
의존성으로 끌어올 방법이 없고, 소스를 직접 받아 mill로 빌드해야 한다. 그래서 sbt는
이번 스코프에서 불필요.

## 5. RISC-V GNU 툴체인은 설치했지만, xbar 스터디엔 당장 필요 없다

`TLXbarUnitTestConfig`(`TLRAMXbarTest`, `TLMulticlientXbarTest` 등)는 self-checking
하드웨어 테스트벤치로, RISC-V `.elf` 바이너리를 전혀 요구하지 않는다. 다만 Verilator
링크 단계에서 `libfesvr`(spike 유래)를 요구할 수 있어서, 전체 GNU 툴체인보다 가벼운
`riscv-isa-sim`만으로도 충분할 수 있다. 디스크 여유가 충분해(102GB) 이번엔 전체
`riscv-tools`(gnu toolchain + spike + pk)를 설치했다.

## 5b. rocket-chip 서브모듈 pin

`third_party/rocket-chip`는 커밋 `ece7b9ad544b07df39cd13b6fd7236562a26355d`
(`v1.6-821-gece7b9ad5`)에 고정했다 (shallow, `--depth 1`). `build.sc` 실제 확인 결과:
- `v.chiselCrossVersions` 키는 `"6.7.0"`과 `"source"` 둘뿐 → `rocketchip[6.7.0]`이
  맞는 cross 타겟.
- `object emulator extends Cross[Emulator](...)` 안에 `TLXbarUnitTestConfig`가 실제로
  빠져 있고, `AMBAUnitTestConfig`/`TLSimpleUnitTestConfig`/`TLWidthUnitTestConfig`만
  있음 — Phase 5의 한 줄 패치가 필요하다는 리서치가 코드로 확인됨.

## 5c. `build.sc`의 obsolete `-dedup` 플래그 패치

Chisel 6.7.0 jar에 빌드타임 기록된 `firtoolVersion`은 `1.62.1`(BuildInfo 문자열
상수에서 추출). macOS arm64 네이티브 바이너리가 없어 macOS x64 빌드를 Rosetta로
실행(상세: `docs/03-env-setup-macos-arm64.md` §6).

이 firtool 1.62.1에서 `mfccompiler.compile`(및 `litexgenerate.compile`)이 넘기는
`"-dedup"` 플래그가 인식되지 않아 실패:
```
firtool: Unknown command line argument '-dedup'. Try: 'firtool --help'
firtool: Did you mean '--no-dedup'?
```
dedup은 이미 기본 활성화이고 비활성화만 `--no-dedup`로 가능한 상태라, 명시적
`-dedup` 플래그는 더 이상 유효하지 않다(의미상 no-op이었던 플래그가 완전히
제거됨). `build.sc`에서 두 곳의 `"-dedup",` 라인을 제거 — 동작은 동일(dedup 여전히
기본 켜짐), 그냥 존재하지 않는 플래그를 안 넘기는 것뿐.

패치는 `patches/0001-remove-obsolete-dedup-flag.patch`에 보관. 서브모듈
자체의 git 히스토리에는 커밋하지 않고(서브모듈은 업스트림 추적용), 로컬 워킹트리에만
적용된 상태로 둔다 — 서브모듈을 새로 clone/update할 때마다 이 패치를 다시 적용해야
한다는 뜻.

## 6. `third_party/rocket-chip`로 서브모듈 배치

최상위에 두지 않고 `third_party/` 아래 둔 이유: (1) 우리 자신의 노트/코드와 명확히
구분되어 `git status`가 읽기 쉽고, (2) rocket-chip이 Maven 아티팩트로 소비 불가능하므로
반드시 로컬 소스로 존재해야 한다는 제약을 구조적으로 드러낸다.

## 7. Homebrew trust 이슈 (환경 구축 중 발견)

Homebrew 7.0.7부터 공식 tap이 아닌 formula는 `brew trust`로 명시적으로 신뢰해야
로드된다. `riscv-software-src/riscv` tap 설치 시 "Refusing to load formula ... from
untrusted tap" 에러가 났고, `brew trust --tap riscv-software-src/riscv`로 해결했다.
이 tap은 RISC-V 커뮤니티가 운영하는 신뢰할 수 있는 tap이다.
