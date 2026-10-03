# Round 5: 의도적 negative test — 결과와 가설 정정

## 설계

`docs/06-sparse-harness-design.md` 끝에서 세운 가설을 검증한다: client0의
`visibility`는 manager0 하나뿐으로 둔 채(single-reachable-slave, `AddressDecoder`가
routingMask=0으로 degenerate하는 바로 그 케이스), `TLFuzzer.overrideAddress`(stimulus)만
전체 4개 manager 범위로 넓혔다 (`TLSparseXbar.ClientSpec(visibility, stimulus)`로
둘을 분리, `patches/0004-add-sparse-xbar-negative-test.patch`).

```scala
TLSparseXbar.ClientSpec(
  visibility = AddressSet(0x0, 0x3ff),   // 선언: manager0만
  stimulus   = AddressSet(0x0, 0xfff))   // 실제 구동: 4개 manager 전체 범위
```

나머지 client1/2/3은 round 4와 동일(unchanged).

## 세웠던 가설 (틀림)

> "client0의 row는 true가 manager0 하나뿐이라 `AddressDecoder`가 routingMask=0으로
> degenerate하므로, 범위 밖 주소도 에러 없이 조용히 manager0로 aliasing될 가능성이
> 높다."

## 실제 결과

```bash
./emulator --max-cycles=2000000 --cycle-count /bin/ls
```
```
[14] %Error: TLMonitor.sv:381: Assertion failed in TOP.TestHarness.UnitTestSuite.tests_0.dut.xbar.monitor.unnamedblk1:
Assertion failed: 'A' channel carries an address illegal for the specified bank visibility
    at Monitor.scala:44 assert(cond, message)
%Error: .../TLMonitor.sv:381: Verilog $stop
Aborting...
```
exit code 1, **cycle 14**에서 거의 즉시 잡힘(round 4의 정상 케이스는 67530 cycle 걸렸던 것과
대조적으로, 위반은 첫 트랜잭션 몇 개 안에서 바로 드러난다).

## 가설이 왜 틀렸는가 — 교훈

`AddressDecoder`의 routingMask degenerate는 "**이 request를 어느 출력 포트로 보낼지**"를
결정하는 라우팅 로직 얘기였다. 하지만 `TLMonitor`는 라우팅 결과와 별개로, **client가
스스로 선언한 `visibility` 목록과 생성한 주소를 직접 대조하는 자체 체크**를 갖고 있다
(`Monitor.scala`의 assert, 메시지 그대로 "illegal for the specified bank visibility").
즉 두 메커니즘은 독립적이다:

1. **라우팅(디코더)**: "이 주소를 어디로 보낼까" — degenerate하면 무조건 유일한
   reachable 출력으로 보낸다 (내 가설이 맞았던 부분).
2. **모니터(검증)**: "이 주소가 애초에 이 client가 보내도 되는 주소인가" — visibility
   선언과 무관하게 생성됐다면 라우팅 여부와 상관없이 **그 자체로 위반**이다 (내가
   놓쳤던 부분. 모니터는 "결과가 틀렸는지"가 아니라 "선언을 어겼는지"를 본다).

다시 말해, 체크리스트(`01-xbar-sparsity-checklist.md`) Section B의 "don't-care
alias" 경고는 **여전히 유효**하지만, 그 위험이 발현되려면 "주소가 visibility 밖인데
TLMonitor의 이 특정 체크를 피해가는" 경로가 필요하다 — 이번 실험에서 쓴 "fuzzer가
직접 visibility 밖 주소를 생성" 경로는 그 체크에 바로 걸린다. 진짜 aliasing 위험은
오히려 **visibility 자체가 실수로 넓게 선언된 경우**(체크리스트 Section A의 false
positive 항목)처럼, 모니터가 통과시킬 수밖에 없는 경로에서 나온다는 뜻이다.

## 체크리스트 반영

`docs/01-xbar-sparsity-checklist.md` Section B의 single-reachable-slave 항목에
아래를 추가해야 한다(다음 업데이트에서):
> `TLMonitor`가 "주소가 declared visibility 안에 있는가"를 독립적으로 검증하므로,
> fuzzer/상위 로직이 visibility 밖 주소를 생성하면 라우팅 aliasing 여부와 무관하게
> 먼저 여기서 잡힌다. 실제 aliasing 위험은 **visibility 선언 자체가 틀린 경우**
> (예: 좁혀야 할 걸 깜빡하고 기본값 그대로 둔 경우, Section A false positive)에서만
> 발현된다 — 이건 이 모니터 체크로는 못 잡는다(선언이 "틀렸다"는 걸 모니터는 모르니까).

## 다음 (round 6, 아직 안 함)

이 체크가 못 잡는 진짜 aliasing 경로를 재현해보려면: **visibility 선언 자체를
의도보다 넓게 주고 stimulus는 그 선언 안에서만** 생성해야 한다 — 즉 "모니터가 보기엔
완전히 정상"인데 실제로는 설계 의도(원래 manager0만 봐야 했는데 선언이 잘못되어 전체를
보게 된 client)와 다른 경우. 이건 모니터로는 절대 못 잡고, 체크리스트 Section A가
요구하는 "독립적으로 도출한 golden matrix와 비교"만이 잡아낼 수 있다는 걸 보여주는
실험이 될 것.
