# TLXbar 코드 Walkthrough (초안)

`third_party/rocket-chip/src/main/scala/tilelink/Xbar.scala`의 핵심 로직을 따라가며
남기는 주석. 체크리스트(`01-xbar-sparsity-checklist.md`)의 각 섹션이 참조하는
실제 코드 위치를 기록하는 용도 — round 2에서 서브모듈이 실제로 들어오면 라인
번호까지 채워 넣는다.

## 다루게 될 것 (round 2에서 채움)

- [ ] `reachableIO`/`probeIO`/`releaseIO` 계산 전체 흐름
- [ ] `AddressDecoder` + `routingMask`/`widen` — don't-care alias가 만들어지는 지점
- [ ] `mapInputIds`/`assignRanges` — source ID range 할당 알고리즘
- [ ] `relabeler()` — FIFO 도메인 relabeling
- [ ] `outputPortFns` — decoder row-sharing 메커니즘
- [ ] tie-off 코드 (`DontCare`, `ready := false.B`)
- [ ] `TLRAMXbar`/`TLMulticlientXbar` — 기본 제공 테스트 하네스 구조

## 참고

- 소스: https://github.com/chipsalliance/rocket-chip/blob/master/src/main/scala/tilelink/Xbar.scala
- 테스트: https://github.com/chipsalliance/rocket-chip/blob/master/src/main/scala/unittest/Configs.scala
