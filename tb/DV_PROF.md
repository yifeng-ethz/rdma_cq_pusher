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
| P001 | D | sustained throughput at depth=256, B-lat=0, no stall, no doorbell limit | 1000 | inject 1000 CQEs back-to-back; cq_head pre-credited beyond depth | average per-CQE latency == 5 clk; sustained CQE rate == 1/5 = 0.2 per clk | FUNC-P001-sustained-throughput-p001-p016-sustained-throughput-at-depth-256-b-lat-0 |
| P002 | D | sustained throughput at depth=4096 | 1000 | same as P001 with depth=4096 | sustained 0.2 CQE/clk | FUNC-P002-sustained-throughput-p001-p016-sustained-throughput-at-depth-4096 |
| P003 | D | sustained throughput at depth=65536 | 1000 | same with depth=65536 | sustained 0.2 CQE/clk | FUNC-P003-sustained-throughput-p001-p016-sustained-throughput-at-depth-65536 |
| P004 | D | sustained at depth=4 with sustained 1-clk doorbell pacing per push | 100 | depth=4; doorbell value=cq_tail+1 each clk | rate limited by doorbell pacing | FUNC-P004-sustained-throughput-p001-p016-sustained-at-depth-4-with-sustained-1-clk |
| P005 | D | sustained burst: 16 CQEs, gap 32 clk, repeat 100 | 1600 | bursty inject | each burst sustains 0.2 CQE/clk during the burst | FUNC-P005-sustained-throughput-p001-p016-sustained-burst-16-cqes-gap-32-clk-repeat |
| P006 | D | sustained 50% duty (16 CQE on, 16 idle, repeat) | 800 | duty cycle | sustained rate 0.1 CQE/clk overall; coverage duplicate of prior merged baseline after P005; retained for functional scenario check | FUNC-P006-sustained-throughput-p001-p016-sustained-50-duty-16-cqe-on-16-idle |
| P007 | D | sustained 25% duty | 400 | 25% duty | sustained rate 0.05 CQE/clk; coverage duplicate of prior merged baseline after P006; retained for functional scenario check | FUNC-P007-sustained-throughput-p001-p016-sustained-25-duty |
| P008 | D | sustained 75% duty | 1200 | 75% duty | sustained rate 0.15 CQE/clk; coverage duplicate of prior merged baseline after P007; retained for functional scenario check | FUNC-P008-sustained-throughput-p001-p016-sustained-75-duty |
| P009 | D | depth=256, sustained 1000-CQE run, B-lat 0, with checkpoint UCDB | 1000 | as P001 with checkpoint UCDB at txn 1,2,4,8,...,1024 | coverage curve recorded; PASS; coverage duplicate of prior merged baseline after P008; retained for functional scenario check | FUNC-P009-sustained-throughput-p001-p016-depth-256-sustained-1000-cqe-run-b-lat |
| P010 | D | depth=256, sustained 2000-CQE run | 2000 | as P001 with longer run | scoreboard PASS; lineage closed | FUNC-P010-sustained-throughput-p001-p016-depth-256-sustained-2000-cqe-run |
| P011 | D | depth=256, sustained 5000-CQE run | 5000 | as P001 with longer run | PASS | FUNC-P011-sustained-throughput-p001-p016-depth-256-sustained-5000-cqe-run |
| P012 | D | depth=256, sustained 10000-CQE run | 10000 | as P001 longer | PASS; coverage saturation knee identified | FUNC-P012-sustained-throughput-p001-p016-depth-256-sustained-10000-cqe-run |
| P013 | R | random sustained 1000-CQE with random B-lat in [0,8] | 1000 | random B-lat | PASS; coverage duplicate of prior merged baseline after P012; retained for functional scenario check | FUNC-P013-sustained-throughput-p001-p016-random-sustained-1000-cqe-with-random-b-lat |
| P014 | R | random sustained 1000-CQE with random AW stall in [0,4] | 1000 | random AW stall | PASS; coverage duplicate of prior merged baseline after P013; retained for functional scenario check | FUNC-P014-sustained-throughput-p001-p016-random-sustained-1000-cqe-with-random-aw-stall |
| P015 | R | random sustained 1000-CQE with random W stall in [0,4] | 1000 | random W stall | PASS; coverage duplicate of prior merged baseline after P014; retained for functional scenario check | FUNC-P015-sustained-throughput-p001-p016-random-sustained-1000-cqe-with-random-w-stall |
| P016 | R | random sustained 1000-CQE with random everything | 1000 | full random handshake lag | PASS; cg_axi_handshake_lag covered; coverage duplicate of prior merged baseline after P015; retained for functional scenario check | FUNC-P016-sustained-throughput-p001-p016-random-sustained-1000-cqe-with-random-everything |

---

## 3. Throughput vs B-channel latency (P017-P032)

Per-CQE round-trip latency `T = T_aw + T_w + T_b + T_adv`. With
zero-lag completer `T_aw = T_w = T_adv = 1 clk` and `T_b = 1 + B_lat`,
so `T = 4 + B_lat`. Sustained rate = 1/T CQE per clk.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P017 | D | B-lat=0 | 100 | 100 CQEs at B-lat=0 | per-CQE T=4 clk; rate=0.25 CQE/clk; coverage duplicate of prior merged baseline after P016; retained for functional scenario check | FUNC-P017-throughput-vs-b-channel-latency-p017-p032-b-lat-0 |
| P018 | D | B-lat=1 | 100 | B-lat=1 | T=5; rate=0.20; coverage duplicate of prior merged baseline after P017; retained for functional scenario check | FUNC-P018-throughput-vs-b-channel-latency-p017-p032-b-lat-1 |
| P019 | D | B-lat=2 | 100 | B-lat=2 | T=6; rate~0.167; coverage duplicate of prior merged baseline after P018; retained for functional scenario check | FUNC-P019-throughput-vs-b-channel-latency-p017-p032-b-lat-2 |
| P020 | D | B-lat=4 | 100 | B-lat=4 | T=8; rate=0.125; coverage duplicate of prior merged baseline after P019; retained for functional scenario check | FUNC-P020-throughput-vs-b-channel-latency-p017-p032-b-lat-4 |
| P021 | D | B-lat=8 | 100 | B-lat=8 | T=12; rate~0.083; coverage duplicate of prior merged baseline after P020; retained for functional scenario check | FUNC-P021-throughput-vs-b-channel-latency-p017-p032-b-lat-8 |
| P022 | D | B-lat=16 | 100 | B-lat=16 | T=20; rate=0.05; coverage duplicate of prior merged baseline after P021; retained for functional scenario check | FUNC-P022-throughput-vs-b-channel-latency-p017-p032-b-lat-16 |
| P023 | D | B-lat=32 | 100 | B-lat=32 | T=36; rate~0.028; coverage duplicate of prior merged baseline after P022; retained for functional scenario check | FUNC-P023-throughput-vs-b-channel-latency-p017-p032-b-lat-32 |
| P024 | D | B-lat=64 | 100 | B-lat=64 | T=68; rate~0.0147; coverage duplicate of prior merged baseline after P023; retained for functional scenario check | FUNC-P024-throughput-vs-b-channel-latency-p017-p032-b-lat-64 |
| P025 | D | B-lat=128 | 100 | B-lat=128 | T=132; rate~0.0076; coverage duplicate of prior merged baseline after P024; retained for functional scenario check | FUNC-P025-throughput-vs-b-channel-latency-p017-p032-b-lat-128 |
| P026 | D | B-lat=256 | 100 | B-lat=256 | T=260; rate~0.0038; coverage duplicate of prior merged baseline after P025; retained for functional scenario check | FUNC-P026-throughput-vs-b-channel-latency-p017-p032-b-lat-256 |
| P027 | D | B-lat=500 (PCIe Gen3 worst-case write completion budget) | 100 | B-lat=500 | T=504; rate~0.002 CQE/clk == 400 K CQE/s @ 200 MHz; coverage duplicate of prior merged baseline after P026; retained for functional scenario check | FUNC-P027-throughput-vs-b-channel-latency-p017-p032-b-lat-500-pcie-gen3-worst-case-write |
| P028 | D | B-lat=1000 (very pessimistic) | 50 | B-lat=1000 | T=1004; rate~0.001; coverage duplicate of prior merged baseline after P027; retained for functional scenario check | FUNC-P028-throughput-vs-b-channel-latency-p017-p032-b-lat-1000-very-pessimistic |
| P029 | R | random B-lat in {0,1,2,4,8,16,32,64,128,256} per push | 1000 | random B-lat | rate matches harmonic mean prediction; coverage duplicate of prior merged baseline after P028; retained for functional scenario check | FUNC-P029-throughput-vs-b-channel-latency-p017-p032-random-b-lat-in-0-1-2-4 |
| P030 | R | random B-lat geometric mean=8 | 1000 | random | PASS; coverage duplicate of prior merged baseline after P029; retained for functional scenario check | FUNC-P030-throughput-vs-b-channel-latency-p017-p032-random-b-lat-geometric-mean-8 |
| P031 | R | random B-lat uniform [0,256] | 1000 | random | PASS; checkpoint UCDB recorded; coverage duplicate of prior merged baseline after P030; retained for functional scenario check | FUNC-P031-throughput-vs-b-channel-latency-p017-p032-random-b-lat-uniform-0-256 |
| P032 | R | random B-lat burst (long stall every 16th push) | 1000 | burst | PASS; coverage duplicate of prior merged baseline after P031; retained for functional scenario check | FUNC-P032-throughput-vs-b-channel-latency-p017-p032-random-b-lat-burst-long-stall-every-16th |

---

## 4. Throughput vs AW/W stall (P033-P048)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P033 | D | aw_stall=4, others=0 | 100 | 100 CQEs at aw_stall=4 | T=4+4=8 clk; coverage duplicate of prior merged baseline after P032; retained for functional scenario check | FUNC-P033-throughput-vs-aw-w-stall-p033-p048-aw-stall-4-others-0 |
| P034 | D | aw_stall=16 | 100 | aw_stall=16 | T=20; coverage duplicate of prior merged baseline after P033; retained for functional scenario check | FUNC-P034-throughput-vs-aw-w-stall-p033-p048-aw-stall-16 |
| P035 | D | aw_stall=64 | 100 | aw_stall=64 | T=68; coverage duplicate of prior merged baseline after P034; retained for functional scenario check | FUNC-P035-throughput-vs-aw-w-stall-p033-p048-aw-stall-64 |
| P036 | D | w_stall=4 | 100 | w_stall=4 | T=8; coverage duplicate of prior merged baseline after P035; retained for functional scenario check | FUNC-P036-throughput-vs-aw-w-stall-p033-p048-w-stall-4 |
| P037 | D | w_stall=16 | 100 | w_stall=16 | T=20; coverage duplicate of prior merged baseline after P036; retained for functional scenario check | FUNC-P037-throughput-vs-aw-w-stall-p033-p048-w-stall-16 |
| P038 | D | w_stall=64 | 100 | w_stall=64 | T=68; coverage duplicate of prior merged baseline after P037; retained for functional scenario check | FUNC-P038-throughput-vs-aw-w-stall-p033-p048-w-stall-64 |
| P039 | D | aw_stall=4 + w_stall=4 | 100 | both | T=12; coverage duplicate of prior merged baseline after P038; retained for functional scenario check | FUNC-P039-throughput-vs-aw-w-stall-p033-p048-aw-stall-4-w-stall-4 |
| P040 | D | aw_stall=16 + w_stall=16 | 100 | both | T=36; coverage duplicate of prior merged baseline after P039; retained for functional scenario check | FUNC-P040-throughput-vs-aw-w-stall-p033-p048-aw-stall-16-w-stall-16 |
| P041 | D | aw_stall=4 + w_stall=4 + B-lat=4 | 100 | all three | T=16; coverage duplicate of prior merged baseline after P040; retained for functional scenario check | FUNC-P041-throughput-vs-aw-w-stall-p033-p048-aw-stall-4-w-stall-4-b-lat |
| P042 | D | aw_stall=64 + w_stall=64 + B-lat=64 | 100 | all 64 | T=196; coverage duplicate of prior merged baseline after P041; retained for functional scenario check | FUNC-P042-throughput-vs-aw-w-stall-p033-p048-aw-stall-64-w-stall-64-b-lat |
| P043 | D | aw_stall=256 + w_stall=256 + B-lat=256 | 50 | all 256 | T=772; coverage duplicate of prior merged baseline after P042; retained for functional scenario check | FUNC-P043-throughput-vs-aw-w-stall-p033-p048-aw-stall-256-w-stall-256-b-lat |
| P044 | R | random AW + W + B stalls (geometric, mean=4) | 1000 | random | PASS; coverage duplicate of prior merged baseline after P043; retained for functional scenario check | FUNC-P044-throughput-vs-aw-w-stall-p033-p048-random-aw-w-b-stalls-geometric-mean-4 |
| P045 | R | random AW + W + B stalls (uniform [0,8]) | 1000 | random | PASS; coverage duplicate of prior merged baseline after P044; retained for functional scenario check | FUNC-P045-throughput-vs-aw-w-stall-p033-p048-random-aw-w-b-stalls-uniform-0-8 |
| P046 | R | random AW + W + B stalls (uniform [0,32]) | 1000 | random | PASS; coverage duplicate of prior merged baseline after P045; retained for functional scenario check | FUNC-P046-throughput-vs-aw-w-stall-p033-p048-random-aw-w-b-stalls-uniform-0-32 |
| P047 | R | random burst stall every 8th push | 1000 | burst | PASS; coverage duplicate of prior merged baseline after P046; retained for functional scenario check | FUNC-P047-throughput-vs-aw-w-stall-p033-p048-random-burst-stall-every-8th-push |
| P048 | R | full random AW/W/B + random doorbell + random depth | 1000 | full random | PASS; coverage saturation knee identified; coverage duplicate of prior merged baseline after P047; retained for functional scenario check | FUNC-P048-throughput-vs-aw-w-stall-p033-p048-full-random-aw-w-b-random-doorbell-random |

---

## 5. Doorbell-rate sweep (P049-P064)

Doorbell pacing controls how fast credit returns. If doorbell rate <
push rate, the ring fills and back-pressure starts. Cases here
sweep doorbell pacing and verify the `dbg_ring_full_stall_cyc`
counter and `dbg_cq_full` predicate.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P049 | D | doorbell rate == push rate (no back-pressure expected) | 100 | doorbell every 5 clk; push every 5 clk; depth=4 | dbg_cq_full=0 throughout; coverage duplicate of prior merged baseline after P048; retained for functional scenario check | FUNC-P049-doorbell-rate-sweep-p049-p064-doorbell-rate-push-rate-no-back-pressure-expected |
| P050 | D | doorbell rate < push rate (back-pressure expected) | 100 | doorbell every 10 clk; push every 5 clk; depth=4 | dbg_cq_full toggles; dbg_ring_full_stall_cyc grows; coverage duplicate of prior merged baseline after P049; retained for functional scenario check | FUNC-P050-doorbell-rate-sweep-p049-p064-doorbell-rate-push-rate-back-pressure-expected |
| P051 | D | doorbell rate >> push rate (always credit) | 100 | doorbell every 1 clk; push every 5 clk; depth=4 | no back-pressure; coverage duplicate of prior merged baseline after P050; retained for functional scenario check | FUNC-P051-doorbell-rate-sweep-p049-p064-doorbell-rate-push-rate-always-credit |
| P052 | D | doorbell single bulk credit (depth-1 in one pulse) | 1 | depth=4; pulse credit=3 | 3 slots released; tready high; coverage duplicate of prior merged baseline after P051; retained for functional scenario check | FUNC-P052-doorbell-rate-sweep-p049-p064-doorbell-single-bulk-credit-depth-1-in-one |
| P053 | D | doorbell drip-feed (1 credit at a time, every 100 clk) | 100 | depth=16; doorbell value=cq_tail+1 every 100 clk | rate limited to 1 CQE per 100 clk; coverage duplicate of prior merged baseline after P052; retained for functional scenario check | FUNC-P053-doorbell-rate-sweep-p049-p064-doorbell-drip-feed-1-credit-at-a-time |
| P054 | D | doorbell coalesced (4 pushes worth of credit in one pulse) | 4 | depth=8; pulse credit=4 | 4 slots released; 4 pushes flow back-to-back; coverage duplicate of prior merged baseline after P053; retained for functional scenario check | FUNC-P054-doorbell-rate-sweep-p049-p064-doorbell-coalesced-4-pushes-worth-of-credit-in |
| P055 | D | doorbell rate==push rate at depth=2 (corner) | 50 | depth=2; doorbell every 5 clk; push every 5 clk | no back-pressure | FUNC-P055-doorbell-rate-sweep-p049-p064-doorbell-rate-push-rate-at-depth-2-corner |
| P056 | D | doorbell rate==push rate at depth=65536 (max) | 100 | depth=65536; same pacing | no back-pressure; coverage duplicate of prior merged baseline after P055; retained for functional scenario check | FUNC-P056-doorbell-rate-sweep-p049-p064-doorbell-rate-push-rate-at-depth-65536-max |
| P057 | D | doorbell every 16 clk; push every 5 clk; depth=4 (back-pressure onset) | 100 | mismatched pacing | dbg_ring_full_stall_cyc grows monotonically; coverage duplicate of prior merged baseline after P056; retained for functional scenario check | FUNC-P057-doorbell-rate-sweep-p049-p064-doorbell-every-16-clk-push-every-5-clk |
| P058 | D | doorbell every 32 clk; push every 5 clk; depth=4 (heavy back-pressure) | 100 | mismatched | dbg_ring_full_stall_cyc grows fast; coverage duplicate of prior merged baseline after P057; retained for functional scenario check | FUNC-P058-doorbell-rate-sweep-p049-p064-doorbell-every-32-clk-push-every-5-clk |
| P059 | D | doorbell every 64 clk; push every 5 clk; depth=16 (depth absorbs jitter) | 100 | mismatched | depth absorbs initially; back-pressure later; coverage duplicate of prior merged baseline after P058; retained for functional scenario check | FUNC-P059-doorbell-rate-sweep-p049-p064-doorbell-every-64-clk-push-every-5-clk |
| P060 | D | doorbell every 128 clk; push every 5 clk; depth=256 (large depth) | 100 | mismatched | back-pressure delayed; depth absorbs many; coverage duplicate of prior merged baseline after P059; retained for functional scenario check | FUNC-P060-doorbell-rate-sweep-p049-p064-doorbell-every-128-clk-push-every-5-clk |
| P061 | R | random doorbell pacing (geometric, mean=10 clk) | 1000 | random | PASS; coverage duplicate of prior merged baseline after P060; retained for functional scenario check | FUNC-P061-doorbell-rate-sweep-p049-p064-random-doorbell-pacing-geometric-mean-10-clk |
| P062 | R | random doorbell pacing (uniform [0,32] clk) | 1000 | random | PASS; coverage duplicate of prior merged baseline after P061; retained for functional scenario check | FUNC-P062-doorbell-rate-sweep-p049-p064-random-doorbell-pacing-uniform-0-32-clk |
| P063 | R | random doorbell value with random pacing | 1000 | random both | PASS; coverage duplicate of prior merged baseline after P062; retained for functional scenario check | FUNC-P063-doorbell-rate-sweep-p049-p064-random-doorbell-value-with-random-pacing |
| P064 | R | random doorbell + random push spacing | 1000 | full random | PASS; cg_doorbell_value covered; coverage duplicate of prior merged baseline after P063; retained for functional scenario check | FUNC-P064-doorbell-rate-sweep-p049-p064-random-doorbell-random-push-spacing |

---

## 6. Credit-window proof (P065-P096)

The queueing analysis in `../doc/QUEUE_MATH.md` derives the minimum
credit window the host must provide to never block FW. These cases
empirically validate the formula across the parameter space.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P065 | D | min credit window: depth=4, B-lat=0, no stall (formula: depth-1=3 needed) | 4 | depth=4; pre-credit cq_head=3; inject 4 | all 4 retire; no back-pressure; coverage duplicate of prior merged baseline after P064; retained for functional scenario check | FUNC-P065-credit-window-proof-p065-p096-min-credit-window-depth-4-b-lat-0 |
| P066 | D | min credit window: depth=4, B-lat=4 | 4 | depth=4; B-lat=4; pre-credit=3 | all 4 retire; coverage duplicate of prior merged baseline after P065; retained for functional scenario check | FUNC-P066-credit-window-proof-p065-p096-min-credit-window-depth-4-b-lat-4 |
| P067 | D | min credit window: depth=4, B-lat=16 | 4 | depth=4; B-lat=16; pre-credit=3 | all 4 retire; coverage duplicate of prior merged baseline after P066; retained for functional scenario check | FUNC-P067-credit-window-proof-p065-p096-min-credit-window-depth-4-b-lat-16 |
| P068 | D | min credit window: depth=4, B-lat=64 | 4 | depth=4; B-lat=64; pre-credit=3 | all 4 retire; coverage duplicate of prior merged baseline after P067; retained for functional scenario check | FUNC-P068-credit-window-proof-p065-p096-min-credit-window-depth-4-b-lat-64 |
| P069 | D | min credit window: depth=16, B-lat=0 (pre-credit=15) | 16 | depth=16; pre-credit=15 | all 16 retire | FUNC-P069-credit-window-proof-p065-p096-min-credit-window-depth-16-b-lat-0 |
| P070 | D | min credit window: depth=16, B-lat=64 | 16 | depth=16; B-lat=64; pre-credit=15 | all 16 retire; coverage duplicate of prior merged baseline after P069; retained for functional scenario check | FUNC-P070-credit-window-proof-p065-p096-min-credit-window-depth-16-b-lat-64 |
| P071 | D | min credit window: depth=256, B-lat=0 | 256 | depth=256; pre-credit=255 | all 256 retire; coverage duplicate of prior merged baseline after P070; retained for functional scenario check | FUNC-P071-credit-window-proof-p065-p096-min-credit-window-depth-256-b-lat-0 |
| P072 | D | min credit window: depth=256, B-lat=256 | 256 | depth=256; B-lat=256; pre-credit=255 | all 256 retire; coverage duplicate of prior merged baseline after P071; retained for functional scenario check | FUNC-P072-credit-window-proof-p065-p096-min-credit-window-depth-256-b-lat-256 |
| P073 | D | host doorbell once per depth-1 retires; queueing formula | 100 | depth=4; doorbell every 3 retires | sustained throughput == push rate (no back-pressure); coverage duplicate of prior merged baseline after P072; retained for functional scenario check | FUNC-P073-credit-window-proof-p065-p096-host-doorbell-once-per-depth-1-retires-queueing |
| P074 | D | host doorbell every depth retires (last possible) | 100 | depth=4; doorbell every 4 retires | sustained throughput slightly below push rate; coverage duplicate of prior merged baseline after P073; retained for functional scenario check | FUNC-P074-credit-window-proof-p065-p096-host-doorbell-every-depth-retires-last-possible |
| P075 | D | host doorbell every depth+1 retires (back-pressure expected) | 100 | depth=4; doorbell every 5 retires | back-pressure observed; coverage duplicate of prior merged baseline after P074; retained for functional scenario check | FUNC-P075-credit-window-proof-p065-p096-host-doorbell-every-depth-1-retires-back-pressure |
| P076 | D | depth=16, doorbell every 15 retires | 100 | depth=16 | no back-pressure; coverage duplicate of prior merged baseline after P075; retained for functional scenario check | FUNC-P076-credit-window-proof-p065-p096-depth-16-doorbell-every-15-retires |
| P077 | D | depth=16, doorbell every 16 retires | 100 | depth=16 | borderline; coverage duplicate of prior merged baseline after P076; retained for functional scenario check | FUNC-P077-credit-window-proof-p065-p096-depth-16-doorbell-every-16-retires |
| P078 | D | depth=16, doorbell every 17 retires | 100 | depth=16 | back-pressure; coverage duplicate of prior merged baseline after P077; retained for functional scenario check | FUNC-P078-credit-window-proof-p065-p096-depth-16-doorbell-every-17-retires |
| P079 | D | depth=256, doorbell every 255 retires | 1000 | depth=256 | no back-pressure; coverage duplicate of prior merged baseline after P078; retained for functional scenario check | FUNC-P079-credit-window-proof-p065-p096-depth-256-doorbell-every-255-retires |
| P080 | D | depth=256, doorbell every 256 retires | 1000 | depth=256 | borderline; coverage duplicate of prior merged baseline after P079; retained for functional scenario check | FUNC-P080-credit-window-proof-p065-p096-depth-256-doorbell-every-256-retires |
| P081 | D | depth=256, doorbell every 257 retires | 1000 | depth=256 | back-pressure; coverage duplicate of prior merged baseline after P080; retained for functional scenario check | FUNC-P081-credit-window-proof-p065-p096-depth-256-doorbell-every-257-retires |
| P082 | D | host stalls 1 ms (200 K clk @ 200 MHz) before doorbell | 1 | depth=256; B-lat=0; host stall = 200 K clk | back-pressure window ~ ring_full_stall_cyc grows; coverage duplicate of prior merged baseline after P081; retained for functional scenario check | FUNC-P082-credit-window-proof-p065-p096-host-stalls-1-ms-200-k-clk-200 |
| P083 | D | depth + B-lat budget: depth must absorb B-lat round trips | 100 | depth=16, B-lat=80 (16*5) | depth absorbs the round-trip budget; no back-pressure; coverage duplicate of prior merged baseline after P082; retained for functional scenario check | FUNC-P083-credit-window-proof-p065-p096-depth-b-lat-budget-depth-must-absorb-b |
| P084 | D | depth + B-lat budget: depth=16, B-lat=160 (over budget) | 100 | depth=16, B-lat=160 | back-pressure as predicted; coverage duplicate of prior merged baseline after P083; retained for functional scenario check | FUNC-P084-credit-window-proof-p065-p096-depth-b-lat-budget-depth-16-b-lat |
| P085 | D | depth=256, B-lat=1280 (256*5; over budget) | 200 | depth=256, B-lat=1280 | back-pressure; coverage duplicate of prior merged baseline after P084; retained for functional scenario check | FUNC-P085-credit-window-proof-p065-p096-depth-256-b-lat-1280-256-5-over |
| P086 | D | host CPU latency model: doorbell every (depth/2)*round-trip clk | 200 | depth=16; doorbell every 40 clk | sustained throughput; coverage duplicate of prior merged baseline after P085; retained for functional scenario check | FUNC-P086-credit-window-proof-p065-p096-host-cpu-latency-model-doorbell-every-depth-2 |
| P087 | D | host CPU latency model: doorbell every depth*round-trip clk | 200 | depth=16; doorbell every 80 clk | borderline; coverage duplicate of prior merged baseline after P086; retained for functional scenario check | FUNC-P087-credit-window-proof-p065-p096-host-cpu-latency-model-doorbell-every-depth-round |
| P088 | R | random credit window with random depth | 1000 | random depth in {4,16,256}; random doorbell pacing | scoreboard PASS; back-pressure hit when formula predicts; coverage duplicate of prior merged baseline after P087; retained for functional scenario check | FUNC-P088-credit-window-proof-p065-p096-random-credit-window-with-random-depth |
| P089 | R | random credit window with random B-lat | 1000 | random | PASS; coverage duplicate of prior merged baseline after P088; retained for functional scenario check | FUNC-P089-credit-window-proof-p065-p096-random-credit-window-with-random-b-lat |
| P090 | R | random credit window with mixed pacing | 1000 | random | PASS; coverage duplicate of prior merged baseline after P089; retained for functional scenario check | FUNC-P090-credit-window-proof-p065-p096-random-credit-window-with-mixed-pacing |
| P091 | D | extreme: depth=2 with B-lat=0 | 100 | depth=2 | sustained at borderline; coverage duplicate of prior merged baseline after P090; retained for functional scenario check | FUNC-P091-credit-window-proof-p065-p096-extreme-depth-2-with-b-lat-0 |
| P092 | D | extreme: depth=2 with B-lat=64 | 100 | depth=2; B-lat=64; sustained inject | back-pressure as predicted; coverage duplicate of prior merged baseline after P091; retained for functional scenario check | FUNC-P092-credit-window-proof-p065-p096-extreme-depth-2-with-b-lat-64 |
| P093 | D | extreme: depth=65536 with B-lat=64 | 5000 | huge depth absorbs everything | no back-pressure | FUNC-P093-credit-window-proof-p065-p096-extreme-depth-65536-with-b-lat-64 |
| P094 | D | extreme: depth=65536 with B-lat=10000 | 5000 | depth=65536; B-lat=10000 | depth still absorbs; check formula; coverage duplicate of prior merged baseline after P093; retained for functional scenario check | FUNC-P094-credit-window-proof-p065-p096-extreme-depth-65536-with-b-lat-10000 |
| P095 | R | random scenario validating QUEUE_MATH.md eq.4 (host-credit-window) | 1000 | random across full range | empirical rate matches formula within 5%; coverage duplicate of prior merged baseline after P094; retained for functional scenario check | FUNC-P095-credit-window-proof-p065-p096-random-scenario-validating-queue-math-md-eq-4 |
| P096 | R | random scenario validating QUEUE_MATH.md eq.5 (back-pressure onset) | 1000 | random | empirical onset matches formula; coverage duplicate of prior merged baseline after P095; retained for functional scenario check | FUNC-P096-credit-window-proof-p065-p096-random-scenario-validating-queue-math-md-eq-5 |

---

## 7. Soak runs (P097-P112)

Each case must emit checkpoint UCDBs at txn boundaries
`{1, 2, 4, 8, 16, ..., final}`.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P097 | R | 1000-CQE random soak, depth=256 | 1000 | random pacing/handshake lag | PASS; checkpoint UCDB recorded; coverage duplicate of prior merged baseline after P096; retained for functional scenario check | FUNC-P097-soak-runs-p097-p112-1000-cqe-random-soak-depth-256 |
| P098 | R | 5000-CQE random soak, depth=256 | 5000 | random | PASS; saturation knee identified; coverage duplicate of prior merged baseline after P097; retained for functional scenario check | FUNC-P098-soak-runs-p097-p112-5000-cqe-random-soak-depth-256 |
| P099 | R | 10000-CQE random soak, depth=256 | 10000 | random | PASS; coverage duplicate of prior merged baseline after P098; retained for functional scenario check | FUNC-P099-soak-runs-p097-p112-10000-cqe-random-soak-depth-256 |
| P100 | R | 50000-CQE random soak, depth=256 | 50000 | random | PASS; ~17 checkpoint UCDBs | FUNC-P100-soak-runs-p097-p112-50000-cqe-random-soak-depth-256 |
| P101 | R | 100000-CQE random soak, depth=256 (max recommended for unit DV) | 100000 | random | PASS; coverage saturation curve published | FUNC-P101-soak-runs-p097-p112-100000-cqe-random-soak-depth-256-max-recommended |
| P102 | R | soak with depth=4 | 5000 | random pacing/lag at small depth | PASS; coverage duplicate of prior merged baseline after P101; retained for functional scenario check | FUNC-P102-soak-runs-p097-p112-soak-with-depth-4 |
| P103 | R | soak with depth=16 | 5000 | random at medium depth | PASS; coverage duplicate of prior merged baseline after P102; retained for functional scenario check | FUNC-P103-soak-runs-p097-p112-soak-with-depth-16 |
| P104 | R | soak with depth=4096 | 5000 | random at large depth | PASS; coverage duplicate of prior merged baseline after P103; retained for functional scenario check | FUNC-P104-soak-runs-p097-p112-soak-with-depth-4096 |
| P105 | R | soak with depth=65536 | 5000 | random at max depth | PASS; coverage duplicate of prior merged baseline after P104; retained for functional scenario check | FUNC-P105-soak-runs-p097-p112-soak-with-depth-65536 |
| P106 | R | soak with random doorbell value | 5000 | random | PASS; coverage duplicate of prior merged baseline after P105; retained for functional scenario check | FUNC-P106-soak-runs-p097-p112-soak-with-random-doorbell-value |
| P107 | R | soak with bursty inject pattern | 5000 | bursts | PASS; coverage duplicate of prior merged baseline after P106; retained for functional scenario check | FUNC-P107-soak-runs-p097-p112-soak-with-bursty-inject-pattern |
| P108 | R | soak with quiescent gaps (mostly idle) | 5000 | sparse inject | PASS; coverage duplicate of prior merged baseline after P107; retained for functional scenario check | FUNC-P108-soak-runs-p097-p112-soak-with-quiescent-gaps-mostly-idle |
| P109 | R | soak with high B-lat (mean=64 clk) | 5000 | random | PASS; coverage duplicate of prior merged baseline after P108; retained for functional scenario check | FUNC-P109-soak-runs-p097-p112-soak-with-high-b-lat-mean-64-clk |
| P110 | R | soak with high AW/W stall (mean=32 clk) | 5000 | random | PASS; coverage duplicate of prior merged baseline after P109; retained for functional scenario check | FUNC-P110-soak-runs-p097-p112-soak-with-high-aw-w-stall-mean-32 |
| P111 | R | soak with combined high stalls | 5000 | random | PASS; coverage duplicate of prior merged baseline after P110; retained for functional scenario check | FUNC-P111-soak-runs-p097-p112-soak-with-combined-high-stalls |
| P112 | R | soak with `cfg_enable` random toggle (1% per clk) | 5000 | random toggle | PASS; tready follows enable; coverage duplicate of prior merged baseline after P111; retained for functional scenario check | FUNC-P112-soak-runs-p097-p112-soak-with-cfg-enable-random-toggle-1-per |

---

## 8. Mixed-pattern soak (P113-P128)

Mixed-pattern cases combine the dimensions above to stress real-world
host behavior.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P113 | R | mixed depth + mixed pacing | 5000 | random | PASS; coverage duplicate of prior merged baseline after P112; retained for functional scenario check | FUNC-P113-mixed-pattern-soak-p113-p128-mixed-depth-mixed-pacing |
| P114 | R | mixed depth + mixed B-lat | 5000 | random | PASS; coverage duplicate of prior merged baseline after P113; retained for functional scenario check | FUNC-P114-mixed-pattern-soak-p113-p128-mixed-depth-mixed-b-lat |
| P115 | R | mixed depth + mixed doorbell | 5000 | random | PASS; coverage duplicate of prior merged baseline after P114; retained for functional scenario check | FUNC-P115-mixed-pattern-soak-p113-p128-mixed-depth-mixed-doorbell |
| P116 | R | mixed pacing + mixed B-lat + mixed doorbell | 5000 | random | PASS; coverage duplicate of prior merged baseline after P115; retained for functional scenario check | FUNC-P116-mixed-pattern-soak-p113-p128-mixed-pacing-mixed-b-lat-mixed-doorbell |
| P117 | R | host doorbell coalescing (mostly bulk credit) | 5000 | bulk | PASS; coverage duplicate of prior merged baseline after P116; retained for functional scenario check | FUNC-P117-mixed-pattern-soak-p113-p128-host-doorbell-coalescing-mostly-bulk-credit |
| P118 | R | host doorbell drip (mostly 1-credit) | 5000 | drip | PASS; coverage duplicate of prior merged baseline after P117; retained for functional scenario check | FUNC-P118-mixed-pattern-soak-p113-p128-host-doorbell-drip-mostly-1-credit |
| P119 | R | host doorbell-stall windows (1ms idle every 10 ms) | 5000 | windowed | PASS; coverage duplicate of prior merged baseline after P118; retained for functional scenario check | FUNC-P119-mixed-pattern-soak-p113-p128-host-doorbell-stall-windows-1ms-idle-every-10 |
| P120 | R | sustained 50% link load | 5000 | 50% duty | PASS; coverage duplicate of prior merged baseline after P119; retained for functional scenario check | FUNC-P120-mixed-pattern-soak-p113-p128-sustained-50-link-load |
| P121 | R | sustained 90% link load | 5000 | 90% duty | PASS; coverage duplicate of prior merged baseline after P120; retained for functional scenario check | FUNC-P121-mixed-pattern-soak-p113-p128-sustained-90-link-load |
| P122 | R | sustained 99% link load | 5000 | 99% duty | back-pressure observed; PASS; coverage duplicate of prior merged baseline after P121; retained for functional scenario check | FUNC-P122-mixed-pattern-soak-p113-p128-sustained-99-link-load |
| P123 | R | random `cfg_*` reprogram windows | 5000 | random reprogram between bursts | PASS; coverage duplicate of prior merged baseline after P122; retained for functional scenario check | FUNC-P123-mixed-pattern-soak-p113-p128-random-cfg-reprogram-windows |
| P124 | R | mixed sqe_id pattern (random) | 5000 | random sqe_id | PASS; lineage closed; coverage duplicate of prior merged baseline after P123; retained for functional scenario check | FUNC-P124-mixed-pattern-soak-p113-p128-mixed-sqe-id-pattern-random |
| P125 | R | mixed lineage tuple values (random sidecar) | 5000 | random lineage | PASS; cg_lineage_match closed; coverage duplicate of prior merged baseline after P124; retained for functional scenario check | FUNC-P125-mixed-pattern-soak-p113-p128-mixed-lineage-tuple-values-random-sidecar |
| P126 | R | full random everything (depth/lag/doorbell/sidecar/enable) | 10000 | full random | PASS; coverage knee identified; coverage duplicate of prior merged baseline after P125; retained for functional scenario check | FUNC-P126-mixed-pattern-soak-p113-p128-full-random-everything-depth-lag-doorbell-sidecar-enable |
| P127 | R | bucket_frame stress: random concatenation of 5 cases inside one frame | 5000 | bucket_frame mode | PASS; coverage duplicate of prior merged baseline after P126; retained for functional scenario check | FUNC-P127-mixed-pattern-soak-p113-p128-bucket-frame-stress-random-concatenation-of-5-cases |
| P128 | R | all_buckets_frame stress: random run across all 4 buckets | 10000 | all_buckets_frame mode | PASS; long-run merged coverage published; coverage duplicate of prior merged baseline after P127; retained for functional scenario check | FUNC-P128-mixed-pattern-soak-p113-p128-all-buckets-frame-stress-random-run-across-all |
