# Round 6: "모니터가 못 잡는" 경로 재현 — 결과

## 설계

round 5에서 "모니터가 못 잡는 진짜 aliasing 위험은 visibility **선언 자체**가
틀린 경우"라고 결론 냈다. 이걸 재현하려고 client0의 `visibility`를 **일부러
틀리게** 선언했다 (`patches/0005-add-sparse-xbar-aliasing-test.patch`):

```scala
visibility = Seq(
  AddressSet(0x0,    0x3ff), // manager0의 진짜 범위
  AddressSet(0x1000, 0x3ff)  // 아무 manager도 claim 안 한, 완전히 비어있는 주소 영역 -- "실수"
),
stimulus = AddressSet(0x1000, 0x3ff)  // 자극은 그 "실수" 영역 안에서만 생성
```

핵심: 두 visibility 엔트리는 서로 겹치지 않고(diplomacy의 유일한 요구사항 —
pairwise disjoint), `AddressSet(0x1000, 0x3ff)`는 다른 어떤 manager의 범위와도
안 겹쳐서 reachability는 여전히 manager0 하나뿐이다(single-reachable-slave 유지).
즉 **구조적으로 완전히 유효한 선언**이면서, 의미상으로는 "존재하지 않는 영역을
볼 수 있다"고 거짓말하는 선언이다. 자극은 그 거짓말 영역 안에서만 생성했으므로
round 5의 `TLMonitor` visibility 체크는 통과할 수밖에 없다 — 그 체크는 "선언과
일치하는가"만 보기 때문.

## 결과

```bash
./emulator --max-cycles=2000000 --cycle-count /bin/ls
```
```
[500015] %Error: TLSparseXbarTest.sv:102: Assertion failed in TOP.TestHarness.UnitTestSuite.tests_0:
Assertion failed: UnitTest TLSparseXbarTest timed out
    at UnitTest.scala:34 assert(!timed_out, s"UnitTest $testName timed out")
```
exit code 1, **cycle 500015** (정확히 timeout 예산 500000 근처)에서 "타임아웃"으로
멈췄다. **`TLMonitor`의 "illegal for visibility" 류 assertion은 전혀 발생하지
않았다** — round 5와 결정적으로 다른 지점이다.

## 해석

예측이 부분적으로 맞았다: 모니터 체크는 실제로 통과했다(선언을 어기지 않았으니까).
하지만 "조용히 성공"도 아니었다 — **조용히 멈췄다**. client0이 `io.finished`를
절대 올리지 못해 `UnitTestSuite`의 AND-reduce가 영원히 `s_busy`에 머물렀고,
`UnitTest`에 내장된 타임아웃 워치독(`assert(!timed_out, ...)`)만이 "뭔가 끝나지
않았다"는 사실 자체를 잡아냈다 — *왜* 끝나지 않았는지는 전혀 설명하지 않은 채로.

구체적으로 어느 단계(`TLFragmenter`? `TLRAM`의 내부 디코드? 더 안쪽의 다른
`TLMonitor`?)에서 요청이 삼켜졌는지는 이번 라운드에서 끝까지 추적하지 않았다 —
아래 "다음"에 남겨둔다. 지금 확실히 말할 수 있는 것:

1. **라우팅은 예측대로 degenerate했다** — manager0가 유일한 reachable 출력이라
   주소 검사 없이 그쪽으로 갔을 것이다(round 4/5에서 이미 구조적으로 확인한 내용).
2. **그 결과로 생긴 요청이 끝까지 응답받지 못했다** — manager0의 `TLRAM`은
   `AddressSet(0,0x3ff)`만 백업하는데, 0x1000대 주소가 거기 도달하면 (a) 더 안쪽의
   `TLMonitor`가 조용히 걸려서 응답을 안 내보냈거나, (b) `TLFragmenter`가 자기
   범위 밖 주소를 받고 멈췄을 가능성이 있다 — 어느 쪽이든 **밖으로 드러나는
   증상은 동일: "타임아웃"뿐, 원인 메시지 없음.**
3. **체크리스트 Section G("타임아웃 워치독")가 바로 이런 상황을 위한 것이었다.**
   워치독이 없었다면 이 시뮬레이션은 영원히(또는 max-cycles까지) 멈춰있었을 것이고,
   "통과했나?"조차 판단할 수 없었을 것이다.

## 교훈 (round 5 결론의 보강)

- "모니터가 못 잡는다" ≠ "아무 증상도 없다". 이번 경우 증상은 **deadlock/hang**으로
  나타났다 — round 5가 보여준 "즉시 assertion"과는 질적으로 다른 실패 모드다.
- 체크리스트가 Section A에서 요구한 "독립적으로 도출한 golden matrix와 비교"는
  여기서도 유효한 방어선이다: golden matrix를 미리 계산해놨다면 "client0의
  visibility에 0x1000-0x13ff라는, 어떤 manager도 없는 영역이 들어있다"는 것 자체가
  리뷰 시점에 바로 이상하게 보였을 것 — **시뮬레이션을 돌리기 전에** 잡을 수 있는
  종류의 버그였다.
- 반대로 이 실험은 "타임아웃 워치독 없이 sparse xbar를 테스트하면 안 된다"는
  체크리스트 Section G 항목의 실전 근거가 됐다.

## 다음 (round 7, 아직 안 함)

- 정확히 어느 모듈(`TLFragmenter` vs 더 안쪽 `TLMonitor` vs `TLRAM` 자체)에서
  요청이 멈췄는지 파형(VCD)으로 추적 — `make debug` 디버그 빌드 필요
  (`EMULATOR DEBUG OPTIONS`는 "only supported in debug build").
- `--verbose`로 cycle-by-cycle 로그를 받아서 client0의 A-channel이 valid인데
  언제부터 ready가 안 오는지 직접 확인.
