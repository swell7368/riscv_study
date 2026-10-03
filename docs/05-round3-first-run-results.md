# Round 3: 첫 실제 시뮬레이션 실행 결과

## 실행 방법

이 harness(`freechips.rocketchip.unittest.TestHarness`)는 `success` 신호 하나만
노출하고 HTIF/메모리 포트가 없다. 그런데 공용 C++ 드라이버(`emulator.cc`)는 CLI에서
항상 "BINARY" 인자를 요구한다(`No binary specified for emulator` 체크). unittest
harness는 그 바이너리를 실제로 읽거나 실행하지 않으므로, **아무 파일이나 더미로
넘겨도 된다**(유효한 ELF가 아니어도 무시됨 — harness에 로드할 메모리 자체가 없음):

```bash
cd third_party/rocket-chip/out/emulator/freechips.rocketchip.unittest.TestHarness/freechips.rocketchip.unittest.TLXbarUnitTestConfig/verilator/elf.dest
./emulator --max-cycles=2000000 --cycle-count /bin/ls
```

`--cycle-count`를 꼭 붙여야 한다 — `emulator.cc`가 `*** PASSED ***`를 찍는 조건이
`verbose || print_cycles`라서, 안 붙이면 성공해도 **아무 출력 없이 exit 0**으로
끝나 성공인지 타임아웃 전 조기종료인지 구분이 안 된다.

## 결과

```
This emulator compiled with JTAG Remote Bitbang client. To enable, use +jtag_rbb_enable=1.
Listening on port 55036
*** PASSED *** Completed after 201782 cycles
```
exit code 0, max-cycles(2,000,000)의 10% 수준에서 조기 종료 — 타임아웃이 아니라
`tile->io_success`가 실제로 올라가서 끝난 것.

## 이게 의미하는 것

`TLXbarUnitTestConfig`(`WithTLXbarUnitTests`, `WithTestDuration(10)`)가 돌리는
6개 테스트 전부가 `UnitTestSuite`의 `tests_finished = VecInit(tests.map(_.io.finished)).reduce(_&&_)`를
통과해야만 `io.success`가 true가 된다 (`UnitTestSuite`, 내부 FSM
`s_idle→s_start→s_busy→s_done`). 즉 아래 6개가 전부 **assertion 없이, 끝까지, 성공적으로**
돌았다는 뜻:

| 테스트 | 파라미터 (txns/timeout, `TestDurationMultiplier=10` 반영) |
|---|---|
| `TLJbarTest` | 3×2, txns=5000, timeout=500000 |
| `TLRAMXbarTest` | N=1, txns=5000, timeout=500000 |
| `TLRAMXbarTest` | N=2, txns=5000, timeout=500000 |
| `TLRAMXbarTest` | N=8, txns=5000, timeout=500000 |
| `TLMulticlientXbarTest` | 4×4, txns=2000, timeout=500000 |
| `TLMasterMuxTest` | txns=5000, timeout=500000 |

각 테스트 내부에서 `TLFuzzer`가 랜덤 트랜잭션을 쏘고, `TLRAMModel`이 scoreboard로
ordering/data를 검증하고, `TLMonitor`가 프로토콜 assertion을 체크한다 — 하나라도
위반되면 Verilator가 `assert`로 즉시 비정상 종료(fatal)하거나 dtm/jtag exit_code가
nonzero가 되어 `*** FAILED ***`로 찍혔을 것이다. 그런 게 전혀 없었다.

**체크리스트(`01-xbar-sparsity-checklist.md`) Section H의 "dense 베이스라인을 먼저
돌린다"가 바로 이 결과다** — 단, 이 6개는 전부 **dense** 설정이다(`TLFuzzer`가
`visibility`를 좁히지 않음). Section H가 요구하는 "진짜 sparse variant"(`visibility`를
좁힌 커스텀 `src/main/scala/xbarstudy/` 하네스)는 아직 만들지 않았다 — 그게 round 4.

## 다음 (round 4)

- `src/main/scala/xbarstudy/`에 `visibility`를 좁힌 sparse-visibility 하네스 작성
  (체크리스트 Section H 참고) — 지금 확인한 dense 베이스라인과 비교
- 파형(VCD) 확인이 필요하면 `make debug`(디버그 빌드)로 다시 verilate해야 함
  (`EMULATOR DEBUG OPTIONS`는 "only supported in debug build"라고 `--help`에 명시됨)
