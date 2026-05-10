# DV Performance / Profile — rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_ERROR.md`, `DV_COV.md`, `DV_CROSS.md`, `BUG_HISTORY.md`

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** P001-P128
**Total:** 128 cases (128 implemented / 0 waived)

This document covers throughput, soak, and credit-window behavior on
the `rdma_cq_pusher`. Every case here is multi-transaction: many
CQEs run through the dual-env harness so that long-run merged code
coverage and the queue-math credit window analysis in
`../doc/QUEUE_MATH.md` can be validated. Random cases here MUST emit
checkpoint UCDBs at log-spaced txn boundaries (`1, 2, 4, 8, 16, 32,
...`) per `~/.codex/skills/dv-workflow/SKILL.md` Report Layout.

**Methodology key:**
- **D** = Directed (deterministic profile, fixed seed, parameterised iter)
- **R** = Constrained-random (SystemVerilog `rand`/`constraint`,
  per-case seed, checkpoint UCDB emitter required)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Sustained throughput | 16 | P001-P016 | sustained CQE rate at zero-lag completer reaches 1 CQE per 5 clk; bin steady-state | 16/16 |
| Throughput vs B-channel latency | 16 | P017-P032 | per-CQE round trip = 5 + B_lat clk; effective CQE rate scales | 16/16 |
| Throughput vs AW/W stall | 16 | P033-P048 | combined stall scales latency; saturation curve | 16/16 |
| Doorbell-rate sweep | 16 | P049-P064 | doorbell pacing vs sustainable CQE rate; back-pressure onset at low credit rate | 16/16 |
| Credit-window proof | 32 | P065-P096 | `../doc/QUEUE_MATH.md` minimum host-credit window formula validated empirically | 32/32 |
| Soak runs | 16 | P097-P112 | 1 k - 100 k CQE soaks; coverage saturation curves; lineage closure | 16/16 |
| Mixed-pattern soak | 16 | P113-P128 | mixed depth + mixed pacing + mixed B latency soaks | 16/16 |

---

## 2. Sustained throughput (P001-P016)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P001 | D | sustained throughput at depth=256, B-lat=0, no stall, no doorbell limit | 1000 | inject 1000 CQEs back-to-back; cq_head pre-credited beyond depth | average per-CQE latency == 5 clk; sustained CQE rate == 1/5 = 0.2 per clk | TBD |
| P002 | D | sustained throughput at depth=4096 | 1000 | same as P001 with depth=4096 | sustained 0.2 CQE/clk | TBD |
| P003 | D | sustained throughput at depth=65536 | 1000 | same with depth=65536 | sustained 0.2 CQE/clk | TBD |
| P004 | D | sustained at depth=4 with sustained 1-clk doorbell pacing per push | 100 | depth=4; doorbell value=cq_tail+1 each clk | rate limited by doorbell pacing | TBD |
| P005 | D | sustained burst: 16 CQEs, gap 32 clk, repeat 100 | 1600 | bursty inject | each burst sustains 0.2 CQE/clk during the burst | TBD |
| P006 | D | sustained 50% duty (16 CQE on, 16 idle, repeat) | 800 | duty cycle | sustained rate 0.1 CQE/clk overall | TBD |
| P007 | D | sustained 25% duty | 400 | 25% duty | sustained rate 0.05 CQE/clk | TBD |
| P008 | D | sustained 75% duty | 1200 | 75% duty | sustained rate 0.15 CQE/clk | TBD |
| P009 | D | depth=256, sustained 1000-CQE run, B-lat 0, with checkpoint UCDB | 1000 | as P001 with checkpoint UCDB at txn 1,2,4,8,...,1024 | coverage curve recorded; PASS | TBD |
| P010 | D | depth=256, sustained 2000-CQE run | 2000 | as P001 with longer run | scoreboard PASS; lineage closed | TBD |
| P011 | D | depth=256, sustained 5000-CQE run | 5000 | as P001 with longer run | PASS | TBD |
| P012 | D | depth=256, sustained 10000-CQE run | 10000 | as P001 longer | PASS; coverage saturation knee identified | TBD |
| P013 | R | random sustained 1000-CQE with random B-lat in [0,8] | 1000 | random B-lat | PASS | TBD |
| P014 | R | random sustained 1000-CQE with random AW stall in [0,4] | 1000 | random AW stall | PASS | TBD |
| P015 | R | random sustained 1000-CQE with random W stall in [0,4] | 1000 | random W stall | PASS | TBD |
| P016 | R | random sustained 1000-CQE with random everything | 1000 | full random handshake lag | PASS; cg_axi_handshake_lag covered | TBD |

---

## 3. Throughput vs B-channel latency (P017-P032)

Per-CQE round-trip latency `T = T_aw + T_w + T_b + T_adv`. With
zero-lag completer `T_aw = T_w = T_adv = 1 clk` and `T_b = 1 + B_lat`,
so `T = 4 + B_lat`. Sustained rate = 1/T CQE per clk.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P017 | D | B-lat=0 | 100 | 100 CQEs at B-lat=0 | per-CQE T=4 clk; rate=0.25 CQE/clk | TBD |
| P018 | D | B-lat=1 | 100 | B-lat=1 | T=5; rate=0.20 | TBD |
| P019 | D | B-lat=2 | 100 | B-lat=2 | T=6; rate~0.167 | TBD |
| P020 | D | B-lat=4 | 100 | B-lat=4 | T=8; rate=0.125 | TBD |
| P021 | D | B-lat=8 | 100 | B-lat=8 | T=12; rate~0.083 | TBD |
| P022 | D | B-lat=16 | 100 | B-lat=16 | T=20; rate=0.05 | TBD |
| P023 | D | B-lat=32 | 100 | B-lat=32 | T=36; rate~0.028 | TBD |
| P024 | D | B-lat=64 | 100 | B-lat=64 | T=68; rate~0.0147 | TBD |
| P025 | D | B-lat=128 | 100 | B-lat=128 | T=132; rate~0.0076 | TBD |
| P026 | D | B-lat=256 | 100 | B-lat=256 | T=260; rate~0.0038 | TBD |
| P027 | D | B-lat=500 (PCIe Gen3 worst-case write completion budget) | 100 | B-lat=500 | T=504; rate~0.002 CQE/clk == 400 K CQE/s @ 200 MHz | TBD |
| P028 | D | B-lat=1000 (very pessimistic) | 50 | B-lat=1000 | T=1004; rate~0.001 | TBD |
| P029 | R | random B-lat in {0,1,2,4,8,16,32,64,128,256} per push | 1000 | random B-lat | rate matches harmonic mean prediction | TBD |
| P030 | R | random B-lat geometric mean=8 | 1000 | random | PASS | TBD |
| P031 | R | random B-lat uniform [0,256] | 1000 | random | PASS; checkpoint UCDB recorded | TBD |
| P032 | R | random B-lat burst (long stall every 16th push) | 1000 | burst | PASS | TBD |

---

## 4. Throughput vs AW/W stall (P033-P048)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P033 | D | aw_stall=4, others=0 | 100 | 100 CQEs at aw_stall=4 | T=4+4=8 clk | TBD |
| P034 | D | aw_stall=16 | 100 | aw_stall=16 | T=20 | TBD |
| P035 | D | aw_stall=64 | 100 | aw_stall=64 | T=68 | TBD |
| P036 | D | w_stall=4 | 100 | w_stall=4 | T=8 | TBD |
| P037 | D | w_stall=16 | 100 | w_stall=16 | T=20 | TBD |
| P038 | D | w_stall=64 | 100 | w_stall=64 | T=68 | TBD |
| P039 | D | aw_stall=4 + w_stall=4 | 100 | both | T=12 | TBD |
| P040 | D | aw_stall=16 + w_stall=16 | 100 | both | T=36 | TBD |
| P041 | D | aw_stall=4 + w_stall=4 + B-lat=4 | 100 | all three | T=16 | TBD |
| P042 | D | aw_stall=64 + w_stall=64 + B-lat=64 | 100 | all 64 | T=196 | TBD |
| P043 | D | aw_stall=256 + w_stall=256 + B-lat=256 | 50 | all 256 | T=772 | TBD |
| P044 | R | random AW + W + B stalls (geometric, mean=4) | 1000 | random | PASS | TBD |
| P045 | R | random AW + W + B stalls (uniform [0,8]) | 1000 | random | PASS | TBD |
| P046 | R | random AW + W + B stalls (uniform [0,32]) | 1000 | random | PASS | TBD |
| P047 | R | random burst stall every 8th push | 1000 | burst | PASS | TBD |
| P048 | R | full random AW/W/B + random doorbell + random depth | 1000 | full random | PASS; coverage saturation knee identified | TBD |

---

## 5. Doorbell-rate sweep (P049-P064)

Doorbell pacing controls how fast credit returns. If doorbell rate <
push rate, the ring fills and back-pressure starts. Cases here
sweep doorbell pacing and verify the `dbg_ring_full_stall_cyc`
counter and `dbg_cq_full` predicate.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P049 | D | doorbell rate == push rate (no back-pressure expected) | 100 | doorbell every 5 clk; push every 5 clk; depth=4 | dbg_cq_full=0 throughout | TBD |
| P050 | D | doorbell rate < push rate (back-pressure expected) | 100 | doorbell every 10 clk; push every 5 clk; depth=4 | dbg_cq_full toggles; dbg_ring_full_stall_cyc grows | TBD |
| P051 | D | doorbell rate >> push rate (always credit) | 100 | doorbell every 1 clk; push every 5 clk; depth=4 | no back-pressure | TBD |
| P052 | D | doorbell single bulk credit (depth-1 in one pulse) | 1 | depth=4; pulse credit=3 | 3 slots released; tready high | TBD |
| P053 | D | doorbell drip-feed (1 credit at a time, every 100 clk) | 100 | depth=16; doorbell value=cq_tail+1 every 100 clk | rate limited to 1 CQE per 100 clk | TBD |
| P054 | D | doorbell coalesced (4 pushes worth of credit in one pulse) | 4 | depth=8; pulse credit=4 | 4 slots released; 4 pushes flow back-to-back | TBD |
| P055 | D | doorbell rate==push rate at depth=2 (corner) | 50 | depth=2; doorbell every 5 clk; push every 5 clk | no back-pressure | TBD |
| P056 | D | doorbell rate==push rate at depth=65536 (max) | 100 | depth=65536; same pacing | no back-pressure | TBD |
| P057 | D | doorbell every 16 clk; push every 5 clk; depth=4 (back-pressure onset) | 100 | mismatched pacing | dbg_ring_full_stall_cyc grows monotonically | TBD |
| P058 | D | doorbell every 32 clk; push every 5 clk; depth=4 (heavy back-pressure) | 100 | mismatched | dbg_ring_full_stall_cyc grows fast | TBD |
| P059 | D | doorbell every 64 clk; push every 5 clk; depth=16 (depth absorbs jitter) | 100 | mismatched | depth absorbs initially; back-pressure later | TBD |
| P060 | D | doorbell every 128 clk; push every 5 clk; depth=256 (large depth) | 100 | mismatched | back-pressure delayed; depth absorbs many | TBD |
| P061 | R | random doorbell pacing (geometric, mean=10 clk) | 1000 | random | PASS | TBD |
| P062 | R | random doorbell pacing (uniform [0,32] clk) | 1000 | random | PASS | TBD |
| P063 | R | random doorbell value with random pacing | 1000 | random both | PASS | TBD |
| P064 | R | random doorbell + random push spacing | 1000 | full random | PASS; cg_doorbell_value covered | TBD |

---

## 6. Credit-window proof (P065-P096)

The queueing analysis in `../doc/QUEUE_MATH.md` derives the minimum
credit window the host must provide to never block FW. These cases
empirically validate the formula across the parameter space.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P065 | D | min credit window: depth=4, B-lat=0, no stall (formula: depth-1=3 needed) | 4 | depth=4; pre-credit cq_head=3; inject 4 | all 4 retire; no back-pressure | TBD |
| P066 | D | min credit window: depth=4, B-lat=4 | 4 | depth=4; B-lat=4; pre-credit=3 | all 4 retire | TBD |
| P067 | D | min credit window: depth=4, B-lat=16 | 4 | depth=4; B-lat=16; pre-credit=3 | all 4 retire | TBD |
| P068 | D | min credit window: depth=4, B-lat=64 | 4 | depth=4; B-lat=64; pre-credit=3 | all 4 retire | TBD |
| P069 | D | min credit window: depth=16, B-lat=0 (pre-credit=15) | 16 | depth=16; pre-credit=15 | all 16 retire | TBD |
| P070 | D | min credit window: depth=16, B-lat=64 | 16 | depth=16; B-lat=64; pre-credit=15 | all 16 retire | TBD |
| P071 | D | min credit window: depth=256, B-lat=0 | 256 | depth=256; pre-credit=255 | all 256 retire | TBD |
| P072 | D | min credit window: depth=256, B-lat=256 | 256 | depth=256; B-lat=256; pre-credit=255 | all 256 retire | TBD |
| P073 | D | host doorbell once per depth-1 retires; queueing formula | 100 | depth=4; doorbell every 3 retires | sustained throughput == push rate (no back-pressure) | TBD |
| P074 | D | host doorbell every depth retires (last possible) | 100 | depth=4; doorbell every 4 retires | sustained throughput slightly below push rate | TBD |
| P075 | D | host doorbell every depth+1 retires (back-pressure expected) | 100 | depth=4; doorbell every 5 retires | back-pressure observed | TBD |
| P076 | D | depth=16, doorbell every 15 retires | 100 | depth=16 | no back-pressure | TBD |
| P077 | D | depth=16, doorbell every 16 retires | 100 | depth=16 | borderline | TBD |
| P078 | D | depth=16, doorbell every 17 retires | 100 | depth=16 | back-pressure | TBD |
| P079 | D | depth=256, doorbell every 255 retires | 1000 | depth=256 | no back-pressure | TBD |
| P080 | D | depth=256, doorbell every 256 retires | 1000 | depth=256 | borderline | TBD |
| P081 | D | depth=256, doorbell every 257 retires | 1000 | depth=256 | back-pressure | TBD |
| P082 | D | host stalls 1 ms (200 K clk @ 200 MHz) before doorbell | 1 | depth=256; B-lat=0; host stall = 200 K clk | back-pressure window ~ ring_full_stall_cyc grows | TBD |
| P083 | D | depth + B-lat budget: depth must absorb B-lat round trips | 100 | depth=16, B-lat=80 (16*5) | depth absorbs the round-trip budget; no back-pressure | TBD |
| P084 | D | depth + B-lat budget: depth=16, B-lat=160 (over budget) | 100 | depth=16, B-lat=160 | back-pressure as predicted | TBD |
| P085 | D | depth=256, B-lat=1280 (256*5; over budget) | 200 | depth=256, B-lat=1280 | back-pressure | TBD |
| P086 | D | host CPU latency model: doorbell every (depth/2)*round-trip clk | 200 | depth=16; doorbell every 40 clk | sustained throughput | TBD |
| P087 | D | host CPU latency model: doorbell every depth*round-trip clk | 200 | depth=16; doorbell every 80 clk | borderline | TBD |
| P088 | R | random credit window with random depth | 1000 | random depth in {4,16,256}; random doorbell pacing | scoreboard PASS; back-pressure hit when formula predicts | TBD |
| P089 | R | random credit window with random B-lat | 1000 | random | PASS | TBD |
| P090 | R | random credit window with mixed pacing | 1000 | random | PASS | TBD |
| P091 | D | extreme: depth=2 with B-lat=0 | 100 | depth=2 | sustained at borderline | TBD |
| P092 | D | extreme: depth=2 with B-lat=64 | 100 | depth=2; B-lat=64; sustained inject | back-pressure as predicted | TBD |
| P093 | D | extreme: depth=65536 with B-lat=64 | 5000 | huge depth absorbs everything | no back-pressure | TBD |
| P094 | D | extreme: depth=65536 with B-lat=10000 | 5000 | depth=65536; B-lat=10000 | depth still absorbs; check formula | TBD |
| P095 | R | random scenario validating QUEUE_MATH.md eq.4 (host-credit-window) | 1000 | random across full range | empirical rate matches formula within 5% | TBD |
| P096 | R | random scenario validating QUEUE_MATH.md eq.5 (back-pressure onset) | 1000 | random | empirical onset matches formula | TBD |

---

## 7. Soak runs (P097-P112)

Each case must emit checkpoint UCDBs at txn boundaries
`{1, 2, 4, 8, 16, ..., final}`.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P097 | R | 1000-CQE random soak, depth=256 | 1000 | random pacing/handshake lag | PASS; checkpoint UCDB recorded | TBD |
| P098 | R | 5000-CQE random soak, depth=256 | 5000 | random | PASS; saturation knee identified | TBD |
| P099 | R | 10000-CQE random soak, depth=256 | 10000 | random | PASS | TBD |
| P100 | R | 50000-CQE random soak, depth=256 | 50000 | random | PASS; ~17 checkpoint UCDBs | TBD |
| P101 | R | 100000-CQE random soak, depth=256 (max recommended for unit DV) | 100000 | random | PASS; coverage saturation curve published | TBD |
| P102 | R | soak with depth=4 | 5000 | random pacing/lag at small depth | PASS | TBD |
| P103 | R | soak with depth=16 | 5000 | random at medium depth | PASS | TBD |
| P104 | R | soak with depth=4096 | 5000 | random at large depth | PASS | TBD |
| P105 | R | soak with depth=65536 | 5000 | random at max depth | PASS | TBD |
| P106 | R | soak with random doorbell value | 5000 | random | PASS | TBD |
| P107 | R | soak with bursty inject pattern | 5000 | bursts | PASS | TBD |
| P108 | R | soak with quiescent gaps (mostly idle) | 5000 | sparse inject | PASS | TBD |
| P109 | R | soak with high B-lat (mean=64 clk) | 5000 | random | PASS | TBD |
| P110 | R | soak with high AW/W stall (mean=32 clk) | 5000 | random | PASS | TBD |
| P111 | R | soak with combined high stalls | 5000 | random | PASS | TBD |
| P112 | R | soak with `cfg_enable` random toggle (1% per clk) | 5000 | random toggle | PASS; tready follows enable | TBD |

---

## 8. Mixed-pattern soak (P113-P128)

Mixed-pattern cases combine the dimensions above to stress real-world
host behavior.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P113 | R | mixed depth + mixed pacing | 5000 | random | PASS | TBD |
| P114 | R | mixed depth + mixed B-lat | 5000 | random | PASS | TBD |
| P115 | R | mixed depth + mixed doorbell | 5000 | random | PASS | TBD |
| P116 | R | mixed pacing + mixed B-lat + mixed doorbell | 5000 | random | PASS | TBD |
| P117 | R | host doorbell coalescing (mostly bulk credit) | 5000 | bulk | PASS | TBD |
| P118 | R | host doorbell drip (mostly 1-credit) | 5000 | drip | PASS | TBD |
| P119 | R | host doorbell-stall windows (1ms idle every 10 ms) | 5000 | windowed | PASS | TBD |
| P120 | R | sustained 50% link load | 5000 | 50% duty | PASS | TBD |
| P121 | R | sustained 90% link load | 5000 | 90% duty | PASS | TBD |
| P122 | R | sustained 99% link load | 5000 | 99% duty | back-pressure observed; PASS | TBD |
| P123 | R | random `cfg_*` reprogram windows | 5000 | random reprogram between bursts | PASS | TBD |
| P124 | R | mixed sqe_id pattern (random) | 5000 | random sqe_id | PASS; lineage closed | TBD |
| P125 | R | mixed lineage tuple values (random sidecar) | 5000 | random lineage | PASS; cg_lineage_match closed | TBD |
| P126 | R | full random everything (depth/lag/doorbell/sidecar/enable) | 10000 | full random | PASS; coverage knee identified | TBD |
| P127 | R | bucket_frame stress: random concatenation of 5 cases inside one frame | 5000 | bucket_frame mode | PASS | TBD |
| P128 | R | all_buckets_frame stress: random run across all 4 buckets | 10000 | all_buckets_frame mode | PASS; long-run merged coverage published | TBD |
