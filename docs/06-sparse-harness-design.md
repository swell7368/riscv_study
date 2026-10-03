# Round 4: Sparse-visibility 하네스 설계와 결과

## 왜 `TLFuzzer.overrideAddress`만으로는 sparsity가 안 생기는가

round 3에서 돌린 `TLMulticlientXbarTest(4,4)`는 4개 fuzzer 전부가 **dense**하다.
`TLFuzzer`의 `overrideAddress`는 **생성되는 자극(stimulus) 주소**만 제한할 뿐,
diplomacy가 `reachableIO`를 계산할 때 쓰는 `TLMasterParameters.visibility`는
그대로 기본값(`Seq(AddressSet(0, ~0))`, 전체)으로 남는다
(`src/main/scala/tilelink/Fuzzer.scala`의 `clientParams` 생성 코드 확인 — `visibility`를
받는 파라미터가 없다). 즉 `overrideAddress`만 바꾸면 "좁은 범위의 주소만 생성하는
dense xbar"가 될 뿐, diplomacy 수준에서 진짜 pruning이 일어나는 **sparse xbar**가
되지는 않는다.

## 어떻게 진짜 sparsity를 만들었는가

체크리스트(`01-xbar-sparsity-checklist.md`) Section B 마지막 항목 "TLFilter에 의한
sparsification"을 그대로 적용했다. `TLFilter`의 `cfilter`(client-side filter)는
업스트림 client의 `TLMasterParameters`를 받아 **capability를 제거만 하는** 새
파라미터를 돌려줄 수 있는데, 여기서 `visibility`를 좁은 `AddressSet`으로 덮어쓰면
diplomacy가 이후 `reachableIO` 계산에 그 좁은 visibility를 그대로 쓴다:

```scala
val filter = LazyModule(new TLFilter(cfilter = { c =>
  Some(c.v1copy(visibility = Seq(vis)))
}))
xbar.node := TLDelayer(0.1) := filter.node := fuzz.node
```

`TLFuzzer(txns, overrideAddress = Some(vis))`로 자극도 같은 범위로 제한해서, 체크리스트가
경고한 "visibility 밖 주소를 생성해서 TLMonitor가 DUT가 아니라 테스트벤치를 잡게 되는"
상황을 피했다.

새 코드: `third_party/rocket-chip/src/main/scala/unittest/SparseXbarTest.scala`
(`TLSparseXbar`/`TLSparseXbarTest`). 기존 `TLMulticlientXbar`와 다른 점 하나 더:
`io.finished := fuzzers.last.module.io.finished`(마지막 fuzzer만 봄, upstream의
기존 관례)가 아니라 `fuzzers.map(_.module.io.finished).reduce(_ && _)`로 **전체**
client가 끝나야 성공으로 친다 — 어느 한 client가 starve되는 걸 놓치지 않기 위해.

## Connectivity matrix (의도 + 실제)

4개 manager, `AddressSet(0x400*n, 0x3ff)` (n=0..3), 기존 `TLMulticlientXbar`와
동일한 주소 배치:

| client | visibility | manager0 (0x000-0x3ff) | manager1 (0x400-0x7ff) | manager2 (0x800-0xbff) | manager3 (0xc00-0xfff) |
|---|---|---|---|---|---|
| 0 | `AddressSet(0x0, 0x3ff)` | **T** | F | F | F |
| 1 | `AddressSet(0x0, 0x7ff)` | **T** | **T** | F | F |
| 2 | `AddressSet(0x800, 0x7ff)` | F | F | **T** | **T** |
| 3 | `AddressSet(0x0, 0xfff)` | **T** | **T** | **T** | **T** |

이 패턴을 고른 이유:
- **client0은 체크리스트에서 "가장 가치 높은 단일 체크"로 꼽은 single-reachable-slave
  케이스** (row에 true가 정확히 1개 — `AddressDecoder`가 routingMask=0으로 degenerate,
  모든 주소가 무조건 manager0로 라우팅됨).
- client1/client2는 서로 겹치지 않는 2개씩 — 일반적인 block-diagonal 스타일 sparsity.
- client3은 의도적으로 **dense**로 남겨서, 같은 xbar 안에 sparse와 dense client가
  섞여 있는 더 현실적인(비대칭) 상황을 만들었다 — manager0는 입력 3개(client0,1,3)를
  경쟁해야 하고 manager2는 입력 2개(client2,3)만 경쟁 — Section D(arbitration/fairness)의
  비대칭 fan-in 체크와도 자연스럽게 맞물린다.

## 실행 결과

```bash
cd third_party/rocket-chip/out/emulator/freechips.rocketchip.unittest.TestHarness/freechips.rocketchip.unittest.TLSparseXbarUnitTestConfig/verilator/elf.dest
./emulator --max-cycles=2000000 --cycle-count /bin/ls
```
```
*** PASSED *** Completed after 67530 cycles
```
(round 3의 dense `TLXbarUnitTestConfig`는 201782 cycles — 이 sparse config는 테스트가
1개뿐이라 더 빨리 끝남. 숫자 자체보다 "타임아웃이 아니라 조기 종료"라는 게 중요.)

`TLMonitor` assertion 위반 없이, `UnitTestSuite`의 `io.finished` AND-reduce 조건으로
깨끗하게 통과했다 — client0(단일 reachable manager)을 포함한 비대칭 sparse 패턴이
assertion 위반 없이 동작함을 실제 시뮬레이션으로 확인.

## 패치 반영

`patches/0003-add-sparse-xbar-unittest.patch`:
- `src/main/scala/unittest/SparseXbarTest.scala` (신규) — `TLSparseXbar`/`TLSparseXbarTest`
- `src/main/scala/unittest/Configs.scala` — `WithTLSparseXbarUnitTests`,
  `TLSparseXbarUnitTestConfig`
- `build.sc` — `emulator` cross-list에 `TLSparseXbarUnitTestConfig` 추가

## 아직 안 해본 것 (round 5)

체크리스트 Section H가 요구하는 **의도적 negative test**: client0의 `overrideAddress`를
자기 `visibility`보다 넓게(예: 전체 범위) 줘서 실제로 무슨 일이 일어나는지 확인.
예상(체크리스트 Section B 기반 가설, 아직 검증 안 됨): client0의 row는 true가
manager0 하나뿐이라 `AddressDecoder`가 routingMask=0으로 degenerate하므로, 범위
밖 주소도 **에러 없이 조용히 manager0로 aliasing**될 가능성이 높다 — 이게 바로
체크리스트가 "don't-care alias" 섹션에서 경고한 바로 그 상황. 지금 당장은 안 하고
다음으로 미룸.
