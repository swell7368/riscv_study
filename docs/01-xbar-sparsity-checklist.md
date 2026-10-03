# RISC-V TileLink Xbar Sparsity 검증 체크리스트

대상: `freechips.rocketchip.tilelink.TLXbar` (`third_party/rocket-chip/src/main/scala/tilelink/Xbar.scala`)

## 0. Sparsity란 무엇인가

M개의 master(client-side edge, `edgesIn`)와 N개의 slave(manager-side edge, `edgesOut`)를
연결하는 TileLink crossbar가 **dense**하다는 건 모든 master가 모든 slave에 도달 가능한
M×N 완전연결 상태를 뜻한다 — 이 경우 arbiter 입력과 주소 디코더가 M×N개 필요하다.
실제 SoC는 보통 **sparse**하다: DMA는 DRAM과 특정 주변장치에만 도달해야 하고, 디버그
master는 컨트롤 버스에만 도달해야 한다.

diplomacy는 이 sparsity를 elaboration 시점에 **자동으로** 계산한다 — 각 client가
선언한 주소 **visibility**와 각 manager가 선언한 **address** 범위를 교차시켜서,
true인 엔트리에 대해서만 arbiter/decoder/ID 라우팅 로직을 생성한다. 즉 sparsity는
area/timing 최적화이면서 동시에 **정합성 계약**이다 — pruning된 경로는 "도달 불가능이
보장된 경로"이고, 이 보장이 깨지면 디자인은 에러 없이 조용히 실패하거나 deadlock에
빠진다.

근거 코드(`Xbar.scala`):
```scala
val reachableIO = edgesIn.map { cp => edgesOut.map { mp =>
  cp.client.clients.exists { c => mp.manager.managers.exists { m =>
    c.visibility.exists { ca => m.address.exists { ma =>
      ca.overlaps(ma) }}}}}}

val probeIO = (edgesIn zip reachableIO).map { case (cp, reachableO) =>
  (edgesOut zip reachableO).map { case (mp, reachable) =>
    reachable && cp.client.anySupportProbe &&
    mp.manager.managers.exists(_.regionType >= RegionType.TRACKED) }}

val releaseIO = (edgesIn zip reachableIO).map { case (cp, reachableO) =>
  (edgesOut zip reachableO).map { case (mp, reachable) =>
    reachable && cp.client.anySupportProbe && mp.manager.anySupportAcquireB }}

val connectAIO = reachableIO   // A: master -> slave 요청
val connectBIO = probeIO       // B: slave -> master probe
val connectCIO = releaseIO     // C: master -> slave release
val connectDIO = reachableIO   // D: slave -> master 응답
val connectEIO = releaseIO     // E: master -> slave grant-ack
```

기억해야 할 3가지:
1. **5개의 서로 다른 connectivity matrix**가 존재한다(A/B/C/D/E). B/C/E는 A/D의
   엄격한 부분집합이다 — A에서 sparse한 설계가 B/C/E에서는 훨씬 더 sparse할 수 있다.
2. **visibility가 sparsity를 결정하는 유일한 손잡이다.** `TLMasterParameters.visibility`
   기본값은 `Seq(AddressSet(0, ~0))`(전체) → 기본적으로 dense. visibility를 좁혀야만
   sparsity가 생긴다. `Parameters.scala`는 `require(!visibility.isEmpty)`와 visibility
   쌍이 겹치지 않아야 함을 강제한다.
3. **주소 디코더는 "구분"을 위해 최소화되지, "검증"을 위해 만들어지지 않는다.**
   `AddressDecoder(filter(port_addrs, connectO))`는 연결된 포트들을 서로 구분하는
   최소 비트마스크를 찾을 뿐, 주소의 유효성을 검증하지 않는다. 이후
   `AddressSet.unify(seq.map(_.widen(~routingMask)))`로 각 route가 넓혀진다. 그 결과
   연결된 어떤 manager의 실제 범위 밖 주소도 "어딘가로" 라우팅된다(don't-care alias).
   **이게 sparse crossbar에서 가장 풍부한 버그 소스다.**

---

## A. Connectivity matrix 정확성 (elaboration-time, 정적 검증)

- [ ] DUT config의 5개 매트릭스(`reachableIO`/`probeIO`/`releaseIO` ≒
  `connectAIO`~`EIO`)를 M×N boolean grid로 덤프한다. config별로 커밋해서 변경이
  리뷰 가능한 diff로 남도록 한다.
- [ ] **독립적으로 도출한 golden matrix와 비교**한다. 같은 Scala 표현식을 다시 돌려서
  "자기 자신과 일치"하는 걸 증명하는 건 아무 의미 없다 — 아키텍처 스펙의 주소맵과
  master별 도달 의도로부터 스프레드시트/Python/DTS 파싱 등 **다른 표현**으로 기대값을
  만든다.
- [ ] **false negative(누락된 연결) 없음을 확인.** 아키텍처가 요구하는 모든
  (master, slave) 쌍에 대해 매트릭스 엔트리가 true인지 assert한다. false negative가
  더 위험한 쪽이다 — 해당 경로가 조용히 tie-off(`ready := false.B`)되어 그쪽을 향한
  트랜잭션이 영원히 멈춘다.
- [ ] **false positive(불필요한 연결) 없음을 확인.** 특히 `visibility`를 좁히는 걸
  빠뜨려서 기본값(`AddressSet(0, ~0)`)이 그대로 남은 master가 있는지 감사한다 —
  의도치 않게 dense해지는 가장 흔한 원인.
- [ ] **B/C/E 매트릭스를 A로부터 추론하지 말고 별도로 검증한다.** `probeIO`가
  "master가 `anySupportProbe`이고 manager의 `regionType >= RegionType.TRACKED`인
  경우에만" true인지 확인. `releaseIO`는 "`anySupportProbe && anySupportAcquireB`".
  coherent master가 uncached peripheral을 향하면 A/D는 true, B/C/E는 false여야 한다.
- [ ] **`endSinkId`가 degenerate하게 축소되는지 확인.** AcquireB를 지원하는 manager가
  하나도 없으면 B/C/E가 전부 비어야 하고, 이때 `endSinkId`가 0에 가깝게 줄어야 한다.
  nonzero `endSinkId`가 남아있으면 manager 파라미터 설정 실수를 의심.
- [ ] **decoder row-sharing 확인.** `outputPortFns`는 `requiredAC =
  (connectAIO ++ connectCIO).distinct`로 키를 잡는 `Map[Vector[Boolean], ...]`이다.
  connectivity row가 **동일한** master들은 디코더를 공유해야 하고(면적 이득), row가
  **다른** master들은 별도 디코더를 가져야 한다(정합성 요구사항). 모든 master의 row가
  우연히 전부 달라 공유 최적화가 사라진 config를 의심한다.
- [ ] **visibility 비겹침/비공백 확인.** `TLMasterParameters`의 `require`가 실제로
  발동하는지 — 겹치는 visibility, 비어있는 visibility를 가진 config로 negative test.
- [ ] **diplomacy 그래프를 독립적으로 walk한다.** `LazyModule.graphML`이 전체
  node/edge 그래프를 뽑아준다. 이걸 로드해서 edge set이 의도한 sparse topology와
  일치하는지, 자동 바인딩(`:=*`/`:*=`)이 의도치 않은 `TLXbar`를 끼워넣지 않았는지
  확인한다.

## B. Address decoding/routing (aliasing 함정)

- [ ] **master별 `routingMask`와 widen된 `route_addrs`를 명시적으로 계산한다.**
  그 다음 각 master에 대해 "어느 주소 범위가 어느 출력으로 매핑되는지" 나열한다 —
  manager가 선언한 범위가 아니라 **widen된** 범위를 기록해야 한다.
- [ ] **모든 don't-care alias를 특정하고 문서화한다.** widen된 `route_addrs` 안에
  있지만 실제 manager의 `AddressSet` 밖인 주소들을 찾는다. 이게 "일어나선 안 되는데
  일어나면 라우팅되는" 주소들이다. 각각에 대해 "왜 해당 master가 이 주소를 생성할 수
  없는지" 근거를 적는다.
- [ ] **디코더가 minimal하면서 sufficient한지 확인.** `AddressDecoder`는 그 row의
  연결된 포트들을 구분하는 최소 비트마스크를 만들어야 한다. sufficiency는 widen된
  route set들이 pairwise disjoint한지로 확인한다 — 겹치면 두 출력이 같은 주소를
  주장하는 셈이라 one-hot 가정이 깨진다.
- [ ] **단일 도달가능 slave의 degenerate case.** master의 row에 true가 정확히 1개면,
  `AddressDecoder`는 비트마스크 0으로 끝나서 라우팅 조건이 "항상 true"가 된다 — 즉
  그 master가 보내는 **모든** 주소가 그 한 slave로 간다. 이게 의도한 것인지, 그리고
  범위 밖 접근이 상위(`TLMonitor`, 에러 디바이스, `TLFilter`)에서 잡히는지 명시적으로
  확인한다. **이 체크리스트 전체에서 가장 가치 높은 단일 항목.**
  > **round 5 실측 (`docs/07-negative-test-results.md`):** 실제로 client의
  > 선언된 visibility보다 넓은 주소를 생성시켜봤더니, `TLMonitor`가 "'A' channel
  > carries an address illegal for the specified bank visibility" assertion으로
  > cycle 14에서 즉시 잡았다 — 라우팅 디코더의 degenerate 여부와 **무관하게**,
  > 모니터는 생성된 주소를 client가 선언한 visibility 목록과 직접 대조한다. 즉
  > "fuzzer/상위 로직이 visibility 밖 주소를 만드는" 경로는 이 체크로 방어된다.
  > 반면 이 체크가 **못 잡는** 경로는 "visibility 선언 자체가 틀린 경우"(Section A의
  > false positive — 좁혀야 하는데 깜빡하고 기본값으로 둔 경우)다. 모니터는 선언을
  > 사실로 믿고 그 안에서만 검증하므로, 선언 자체의 오류는 Section A가 요구하는
  > "독립적으로 도출한 golden matrix와 비교"로만 잡힌다.
- [ ] **도달가능 slave가 0개인 case.** row 전체가 false인 master는 설정 버그다.
  elaboration이 크게 실패하거나, 명시적으로 tie-off되고 문서화되어 있는지 확인.
- [ ] **1×1 identity path.** master 1개, slave 1개면 arbiter/decoder 없이 pass-through로
  degenerate해야 한다.
- [ ] **manager 주소맵의 hole.** manager들 사이 주소 공백으로 가는 접근이 widening으로
  이웃에 alias되지 않고, 의도적인 에러 슬레이브(`TLError`)로 가는지 확인.
- [ ] **`TLFilter`에 의한 sparsification도 동일하게 동작하는지.** `TLFilter`는 capability를
  "제거"만 할 수 있다(`require`들이 `c.sourceId.contains(o.sourceId)`,
  `m.address.contains(...)`, `o.regionType <= m.regionType` 등을 강제). xbar 앞에
  `TLFilter`를 끼워서 매트릭스가 기대대로 sparsify되는지, A뿐 아니라 coherence 채널도
  일관되게 sparsify되는지 확인.

## C. ID 라우팅 (sparsity 하의 source/sink ID 공간)

- [ ] **Source-ID range 할당.** `TLXbar.mapInputIds` → `assignRanges`가 각 master의
  `endSourceId`를 **2의 거듭제곱으로 올림**하고(`pow2Sizes`), 크기순 정렬 후
  `scanRight`로 패킹한다. range가 disjoint하고 모든 master를 커버하는지, 다운스트림
  위젯이 기대하는 `endSourceId`가 나오는지 확인. `endSourceId = 33`인 master가 64칸을
  소비하는 식의 낭비량도 체크.
- [ ] **역방향 채널은 주소가 아니라 ID로 라우팅된다.** `requestDOI`는
  `inputIdRanges.map(_.contains(o.d.bits.source))`, `requestBOI`도 마찬가지. **sparse한
  B 매트릭스**에서, ID-range 조건과 `connectBOI` 마스크가 일치하는지 — slave가 자신과
  연결되지 않은 master로 해석되는 source ID의 B/D beat를 절대 보내지 않는지 assertion
  추가.
- [ ] **E 채널의 sink-ID 라우팅.** `requestEIO`는
  `outputIdRanges.map(_.contains(i.e.bits.sink))`. sparse E 매트릭스에서 sink 공간이
  **연결된** slave들에만 분할되는지, GrantAck이 오라우팅되지 않는지 확인.
- [ ] **sparsity로 인한 ID aliasing.** `requestBOI`/`requestDOI`의 디코더도 최소화될 수
  있다. 그런 최소화 후에도 두 master의 source range가 구분 불가능해지지 않는지 확인.
- [ ] **`TLSourceShrinker`/`AXI4IdIndexer`와의 상호작용.** ID-narrowing 위젯이 sparse
  leg에 있다면, 줄어든 ID 공간이 sparse 역경로를 통해 여전히 round-trip하는지 확인.

## D. Arbitration/fairness (sparse 입력 간)

- [ ] **arbiter 폭이 M이 아니라 해당 컬럼의 true-count와 같은지.** 각 출력 포트의
  arbiter는 그 컬럼에서 true인 엔트리 수만큼의 입력만 가져야 한다 — 의도만 믿지 말고
  생성된 RTL의 mux/arbiter 입력 개수를 직접 센다.
- [ ] **비대칭 fan-in에서의 round-robin fairness.** sparsity로 컬럼마다 폭이 달라진다
  (한 출력엔 1개 master, 다른 출력엔 N개 master가 경쟁). master별 처리량을 측정하고,
  row로부터 기대되는 bandwidth share와 비교해서 구조적 starvation이 없는지 확인.
- [ ] **`lowestIndexFirst` 우선순위 역전.** fixed-priority 정책에서, pruning이 인덱스를
  바꾼다 — 의도한 우선순위 master가 더 이상 그 컬럼의 index 0이 아닐 수 있다. 주소맵이
  바뀔 때마다 조용히 회귀하기 쉬운 지점.
- [ ] **arbitration이 출력별로 독립적인지.** 막힌 slave의 arbiter가 공유 디코드
  로직으로 인해 무관한 출력의 grant를 막지 않는지 확인.
- [ ] **burst/beat 원자성.** arbiter가 멀티비트 메시지 전체에 대해 grant를 유지하고
  두 master의 beat를 인터리빙하지 않는지 — 폭 1인 sparse 컬럼에서도(naive 코드가
  lock을 스킵하는 경우가 있음).
- [ ] **`ForceFanout` 파라미터와 sparsity의 상호작용.**

## E. Tie-off/back-pressure 정합성 (sparse 포트별)

- [ ] **연결 안 된 A/C 입력은 ready-false.** 코드: `filter(portsAOI(o),
  connectAOI(o).map(!_)) foreach { r => r.ready := false.B }`. 생성된 RTL에서 이게
  상수인지(floating이 아닌지) 확인.
- [ ] **degenerate 포트가 올바르게 DontCare 처리되는지.** 코드: `in(i).a := DontCare;
  io_in(i).a.valid := false.B; io_in(i).a.ready := true.B`. firtool 최적화 후
  `DontCare`가 실제 데이터패스로 새지 않는지 **Verilog를 직접 확인**하고, Verilator의
  `--x-assign unique` 하의 X-propagation이 진짜 버그를 가리지 않는지 확인.
- [ ] **sparse decode를 통한 조합 ready→valid 루프가 없는지.** pruning으로 입력의
  `ready`가 자기 `valid`의 decode 결과에 의존하게 될 수 있다. Verilator의
  UNOPTFLAT/combinational-loop 경고가 탐지기다 — 무턱대고 전부 끄지 말 것(mill
  플로우가 이미 `-Wno-UNOPTTHREADS -Wno-STMTDLY -Wno-LATCH -Wno-WIDTH`를 끄고 있으니
  거기 루프 경고를 추가하지 않도록 주의).
- [ ] **back-pressure 독립성.** 한 sparse leg의 slave가 꽉 차도, 그 slave와 연결 안 된
  master는 영향받지 않아야 한다 — slave 0을 포화시키고, slave 0을 제외한 row를 가진
  master가 풀 처리량을 유지하는지 directed test로 확인.
- [ ] **sparsity가 제거했어야 할 head-of-line blocking.** master X가 slave A만
  도달한다면, 밀린 slave B가 X를 전혀 막아선 안 된다. 막는다면 pruning이 ready 경로에
  제대로 반영 안 된 것.
- [ ] **reset 동작.** tie-off된 채널에서 reset 중/직후 spurious valid가 없는지, mill
  플로우가 정의하는 `done_reset`(`STOP_COND=$c("done_reset")`) 게이팅이 reset-window
  위반을 가리고 있지 않은지.

## F. Parameter negotiation/diplomacy (2단계 elaboration)

- [ ] **`beatBytes` 일치.** `require(port.beatBytes == seq(0).beatBytes, ...)`가 의도적으로
  mismatch된 sparse config에서 실제로 발동하는지, 그리고 폭 변환이 필요한 leg에
  `TLWidthWidget`이 있는지 확인.
- [ ] **상향 manager-parameter union이 연결된 manager로만 제한되는지.** master가 보는
  `maxTransfer`, `supportsGet/PutFull/PutPartial/Arithmetic/Logical/Hint`,
  `supportsAcquireB/T`가 전체 union이 아니라 **자기 row**만 반영하는지. 도달 불가능한
  slave의 capability가 보이면, 어떤 reachable slave도 처리 못할 트랜잭션을 생성하게
  된다 — negotiation 오류.
- [ ] **하향 client-parameter union도 마찬가지로 제한되는지.** 각 manager는 자신에게
  도달 가능한 client들만의 union을 봐야 한다 — `endSourceId`, `anySupportProbe`,
  생성된 `TLMonitor` assumption에 영향.
- [ ] **FIFO 도메인 relabeling.** `TLXbar.relabeler()`가 `mutable.HashMap[Int,Int]`와
  단조증가 `idFactory`로 포트별 새 FIFO ID를 할당한다. sparsification 후에도 FIFO
  순서 보장이 유지되는지(xbar 전에 같은 FIFO 도메인이던 두 master가 후에도 하나의
  도메인에 남는지), `requestFifo` 클라이언트가 유효한 `fifoId`를 받는지 확인. 순서
  복원이 필요하면 `TLFIFOFixer` 배치 확인.
- [ ] **transfer-size narrowing.** sparse config에 필요한 최소 폭으로 자동 축소되었는지,
  이 과정에서 필요한 capability가 조용히 빠지지 않았는지.
- [ ] **`AddressAdjuster`/`RegionReplication`/`BankBinder`와의 상호작용.** banking/address
  adjustment가 있다면, connectivity matrix가 그 변환 **이후**의 최종 주소맵 기준으로
  계산되는지 확인.
- [ ] **diplomacy 자체에 대한 negative test.** 의도적으로 깨뜨린 config(빈 visibility,
  아무것도 안 겹치는 visibility, mismatched `beatBytes`, untracked region만 보는
  coherent master)로 elaboration이 조용히 잘못된 하드웨어를 만드는 대신 명확한
  메시지로 실패하는지 확인. 각 예상 실패 메시지를 regression test로 캡처.

## G. Deadlock/livelock/starvation (축소된 연결성 하에서)

- [ ] **sparse fabric을 통한 순환 의존성이 없는지.** A-channel credit, D-channel
  return, B/C/E coherence loop의 자원 의존 그래프가 acyclic함을 보인다. sparsity는
  보통 edge를 제거해 이걸 돕지만, 공유 버퍼를 통해 새 cycle이 생기지 않았는지 확인.
- [ ] **부분 B/C/E 연결에서의 coherence-channel deadlock.** 전형적인 sparse-xbar
  위험: master가 Acquire는 보낼 수 있는데(A 연결) Probe 역경로(B)가
  `regionType < TRACKED`로 pruning되었거나, Release(C)가 `!anySupportAcquireB`로
  pruning된 경우. 어떤 도달가능 상태도 pruning된 채널을 요구하지 않는지 확인.
- [ ] **sparse leg별 buffer/credit 사이징.** 연결된 모든 leg에 `TLBuffer` 깊이가
  충분한지, pruning된 leg의 버퍼가 실제로 제거되어 면적을 안 먹는지.
- [ ] **타임아웃 워치독.** 유닛테스트 하네스는 명시적 `timeout`을 받는다(예:
  `TLRAMXbarTest(nManagers, txns=5000, timeout=500000)`). sparse 테스트에도 타임아웃을
  둬서 deadlock이 "실패"로 드러나게, 그냥 시뮬레이션이 멈춰버리지 않게 한다.
- [ ] **livelock/forward progress.** 지속적인 경쟁 하에서도 모든 master가 결국 완료되는지
  — master별 완료 카운트가 장시간 돌려도 단조 증가하는지 assert.
- [ ] **극단적으로 치우친 sparsity에서의 starvation 스트레스.** row 폭 1인 master와
  row 폭 N인 master를 동시에 포화.

## H. 시뮬레이션 기반 검증: 커버리지와 자극

- [ ] **rocket-chip이 기본 제공하는 하네스를 dense 베이스라인으로 먼저 돌린다.**
  `TLRAMXbar(nManagers, txns)`는 `xbar.node := TLDelayer(0.1) := model.node := fuzz.node`로
  구성되고 manager는 `AddressSet(0x0 + 0x400*n, 0x3ff)`에 위치; `TLMulticlientXbar
  (nManagers, nClients, txns)`는 M개의 fuzzer를 하나의 xbar에 연결한다. 둘 다
  **dense**하다(`TLFuzzer`가 `visibility`를 기본값인 전체로 남겨둠). 이걸 먼저 known-good
  레퍼런스로 돌린다.
- [ ] **`visibility`를 좁혀서 진짜 sparse variant를 만든다.** `TLMulticlientXbar`를
  복사해서 각 fuzzer의 client 파라미터에 명시적
  `visibility = Seq(AddressSet(...))`을 줘서 도달해야 할 manager만 보게 한다. 이게
  최소한이면서 가장 정확하게 diplomacy sparsity를 만드는 방법이다.
- [ ] **자극을 visibility에 맞게 제약한다.** `TLFuzzer`는 `overrideAddress:
  Option[AddressSet]`를 받는다. 이걸 써서 fuzzer가 해당 master의 visibility 안
  주소만 생성하게 한다 — 안 그러면 `TLMonitor`가 (정당하게) out-of-visibility 요청에
  대해 fire해서 DUT가 아니라 테스트벤치를 디버깅하게 된다. 그 다음 **별도의 의도적
  negative test**로 제약을 풀고 monitor가 그걸 잡는지 확인.
- [ ] **`TLRAMModel`을 scoreboard로 유지한다.** `TLRAMModel("Xbar")`는 ordering/data
  위반을 잡는 레퍼런스 메모리 모델 — 모든 sparse config에서 path에 유지한다. 오라우팅을
  잡는 핵심 oracle.
- [ ] **`TLMonitor` assertion을 항상 활성화한다.** edge별 프로토콜 체커로,
  negotiation(Section F) 이후의 파라미터로 파라미터화되어 있어 자동 교차검증 역할을
  겸한다.
- [ ] **`TLDelayer`를 유지한다.** 레퍼런스 하네스는 `TLDelayer(0.1)`을 쓴다 — 랜덤
  딜레이가 back-pressure/arbitration 버그를 드러낸다. 딜레이 확률을 sweep한다.
- [ ] **매트릭스 엔트리별로 명시적인 directed test를 나열한다.** true 엔트리마다:
  경로가 동작함을 증명하는 최소 트랜잭션. false 엔트리마다: 도달 불가능함을 증명하는
  테스트(가능하면 정적/elaboration assertion — tie-off된 포트를 실제로 드라이브할 수
  없으니). 추가로: 단일 도달가능 slave master, 주소 공백 접근, 연결된 모든 master가
  동시에 같은 slave를 경쟁, 모든 master가 서로 다른 slave로(완전 병렬이어야 함 —
  sparsity의 보상이므로 실제로 병렬인지 확인).
- [ ] **커버리지를 매트릭스 기준으로 정의한다.** 5개 매트릭스 각각의 모든 true 엔트리
  exercise, 연결된 경로에서의 모든 (master, slave, opcode) 삼중, 출력별 모든 arbiter
  grant-vector 값, master별 모든 decoder 출력 분기, 출력별 최대 동시성 상태(연결된
  모든 master가 동시에 in-flight).
- [ ] **config 자체도 sweep한다.** 실제 위험은 자극이 아니라 **잘못된 RTL을 만드는
  config**다. nMasters × nSlaves × visibility 패턴(완전 dense, block-diagonal,
  한-master-가-전체-보임, 한-master-가-하나만-보임, 겹치는 band)으로 전체 스위트를
  매 config마다 돌린다. `TestDurationMultiplier`로 장시간 실행 스케일.
- [ ] **config 간 RTL diff를 저렴한 regression으로 쓴다.** config별 생성된 Verilog
  줄 수/arbiter 개수는 pruning 변화를 민감하게 잡아내는 빠른 신호 — 스냅샷해둔다.

## I. Formal/static 체크 (시뮬레이션보다 나은 지점)

- [ ] **connectivity는 정적 속성이다 — 정적으로 체크한다.** (master, slave) 쌍의
  도달가능/불가능은 elaboration 시점에 결정된다. 시뮬레이션 테스트보다 Scala-level
  elaboration assertion을 우선한다 — exhaustive하고 즉시 나온다.
- [ ] **가치 순으로 formal 타겟:** (1) unreachability — pruning된 쌍에 대해 master i의
  어떤 입력 시퀀스도 slave j에 트랜잭션을 만들지 않음, (2) sparse coherence 채널의
  deadlock freedom, (3) 비대칭 fan-in round-robin 하의 no-starvation/eventual grant,
  (4) address-decode exclusivity — 한 master의 widen된 `route_addrs`들이 증명 가능하게
  pairwise disjoint.
- [ ] **`TLMonitor` 속성을 formal assertion으로 재활용한다** — 처음부터 프로토콜
  속성을 새로 쓰지 않는다.
- [ ] **sparse vs dense 등가성 체크.** 두 config가 공통으로 서빙하는 주소 subspace에
  대해, sparse xbar는 dense xbar와 기능적으로 동등해야 한다. 그 subspace에 대한
  bounded equivalence proof가 pruning이 sound하다는 강한 증거다.
- [ ] **생성된 RTL을 tie-off 시그니처로 lint한다.** 상수-false `ready`, 연결 안 된
  net, `DontCare`로부터의 X-source — lint가 저렴하게 잡아내는 것들.

## J. Sign-off 테이블

config마다 채워넣는 표:

| config | M×N | A/B/C/D/E true-count | golden matrix 일치 | directed test | 커버리지 % | deadlock check | formal check | reviewer | date |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

부록: config별 "알려진 don't-care alias" 목록 (Section B에서 이어짐).
