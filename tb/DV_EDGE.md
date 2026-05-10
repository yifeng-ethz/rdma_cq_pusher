# DV Edge — rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_PROF.md`, `DV_ERROR.md`, `DV_COV.md`, `DV_CROSS.md`, `BUG_HISTORY.md`

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** E001-E128
**Total:** 128 cases (128 implemented / 0 waived)

This document covers boundary and corner conditions on the
`rdma_cq_pusher` contract: ring wraparound, CQ-full backpressure,
doorbell credit corners, AXI4 hand-shake-lag corners, and FSM race
windows. Cases here exercise transitions and predicates that the
basic bucket only touched at zero latency.

**Methodology key:**
- **D** = Directed (hand-crafted, deterministic)
- **R** = Constrained-random (SystemVerilog `rand`/`constraint`,
  per-case seed; checkpoint UCDB emitter required)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Wraparound | 16 | E001-E016 | `cq_tail` wraps at `cfg_cq_depth-1` -> 0; multi-pass wraparound preserves ordering | 16/16 |
| CQ-full backpressure | 16 | E017-E032 | `dbg_cq_full=1` -> `tready=0`; resumes on doorbell credit | 16/16 |
| Doorbell credit corners | 16 | E033-E048 | `cq_head_dbl_pulse` racing AW/W/B/ADV; bulk credit + masked overflow | 16/16 |
| Depth corner values | 16 | E049-E064 | every supported depth in `{2,4,16,256,4096,65536}` works | 16/16 |
| AXI4 AW-ready stall | 12 | E065-E076 | `awready` stalled `{0,1,4,16,64,256}` clk; FSM holds awvalid stable | 12/12 |
| AXI4 W-ready stall | 12 | E077-E088 | `wready` stalled in W; `wvalid` stable | 12/12 |
| AXI4 B-channel latency | 12 | E089-E100 | `bvalid` arrives `{0,1,4,16,64,256}` clk after wlast | 12/12 |
| FSM-state doorbell race | 16 | E101-E116 | doorbell pulse aligned with each FSM state (IDLE/AW/W/B/ADV) | 16/16 |
| Reprogram in flight | 8 | E117-E124 | reprogramming `cfg_*` mid-flight has defined semantics (Phase 1: legal only on idle) | 8/8 |
| DEBUG sidecar corners | 4 | E125-E128 | sidecar all-1s vs all-0s; meta_fifo at depth boundary | 4/4 |

---

## 2. Wraparound (E001-E016)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E001 | D | depth=2 wraparound: cq_tail walks 0,1,0,1 with credit | 4 | depth=2; pulse credit=2 each retire; inject 4 CQEs | host_cq_shadow[0..1] overwritten in second pass; cq_tail trace 0,1,0,1 | FUNC-E001-wraparound-e001-e016-depth-2-wraparound-cq-tail-walks-0-1 |
| E002 | D | depth=4 wraparound: cq_tail walks 0..3,0..3 | 8 | depth=4; pulse credit per retire; inject 8 CQEs | host_cq_shadow[0..3] overwritten with second pass | FUNC-E002-wraparound-e001-e016-depth-4-wraparound-cq-tail-walks-0-3 |
| E003 | D | depth=16 wraparound: 32 CQEs | 32 | depth=16; sustained credit; inject 32 CQEs | first pass and second pass both visible at host slots | FUNC-E003-wraparound-e001-e016-depth-16-wraparound-32-cqes |
| E004 | D | depth=256 wraparound: 257 CQEs (1-slot wrap) | 257 | depth=256; sustained credit | host_cq_shadow[0] holds 257th CQE | FUNC-E004-wraparound-e001-e016-depth-256-wraparound-257-cqes-1-slot-wrap |
| E005 | D | depth=4096 wraparound: 4097 CQEs | 4097 | depth=4096; sustained credit | wraparound observed at slot 0 | FUNC-E005-wraparound-e001-e016-depth-4096-wraparound-4097-cqes |
| E006 | D | depth=65536 wraparound: 65537 CQEs | 65537 | depth=65536; sustained credit | wraparound observed at slot 0 | FUNC-E006-wraparound-e001-e016-depth-65536-wraparound-65537-cqes |
| E007 | D | wraparound preserves sqe_id ordering across the boundary | 8 | depth=4; inject 8 CQEs sqe_id=0..7 | host shadow shows last-write-wins per slot; sqe_id chain monotonic; coverage duplicate of prior merged baseline after E006; retained for functional scenario check | FUNC-E007-wraparound-e001-e016-wraparound-preserves-sqe-id-ordering-across-the-boundary |
| E008 | D | wraparound preserves DEBUG=2 lineage chain | 8 | depth=4; inject 8 CQEs with monotonic push_seq | meta_retired_e per CQE; push_seq strictly monotonic across wrap; coverage duplicate of prior merged baseline after E007; retained for functional scenario check | FUNC-E008-wraparound-e001-e016-wraparound-preserves-debug-2-lineage-chain |
| E009 | D | doorbell tracking through wraparound (head also wraps) | 16 | depth=4; sustained credit at each retire (pulse value=cq_tail+1) | `dbg_cur_cq_head_credit` follows wraparound pattern 0..3,0..3; coverage duplicate of prior merged baseline after E008; retained for functional scenario check | FUNC-E009-wraparound-e001-e016-doorbell-tracking-through-wraparound-head-also-wraps |
| E010 | D | `awaddr` wraps to `cfg_cq_base` at depth boundary | 4 | depth=4; inject 5 CQEs | 5th awaddr == cfg_cq_base (first slot); coverage duplicate of prior merged baseline after E009; retained for functional scenario check | FUNC-E010-wraparound-e001-e016-awaddr-wraps-to-cfg-cq-base-at-depth |
| E011 | D | wraparound under bursty inject (4 in then 4 out) | 8 | depth=4; inject 4, drain via doorbell, inject 4 more | each burst lands in correct slots; second burst overwrites first; coverage duplicate of prior merged baseline after E010; retained for functional scenario check | FUNC-E011-wraparound-e001-e016-wraparound-under-bursty-inject-4-in-then-4 |
| E012 | D | wraparound at exact wrap point (cq_tail==depth-1, cq_head==0) | 1 | depth=4; cq_tail=3, push 1 more with cq_head pre-credited to 1 | next push lands at slot 0; host shadow updated; coverage duplicate of prior merged baseline after E011; retained for functional scenario check | FUNC-E012-wraparound-e001-e016-wraparound-at-exact-wrap-point-cq-tail-depth |
| E013 | D | wraparound holds `dbg_cq_full` correctly across the boundary | 4 | depth=4; vary cq_head to test predicate | `dbg_cq_full` matches `((cq_tail+1)&3)==cq_head` invariant; coverage duplicate of prior merged baseline after E012; retained for functional scenario check | FUNC-E013-wraparound-e001-e016-wraparound-holds-dbg-cq-full-correctly-across-the |
| E014 | D | wraparound across reset boundary (reset clears cq_tail to 0) | 8 | inject 4 CQEs, reset, inject 4 more | second batch starts at slot 0; counters reset; coverage duplicate of prior merged baseline after E013; retained for functional scenario check | FUNC-E014-wraparound-e001-e016-wraparound-across-reset-boundary-reset-clears-cq-tail |
| E015 | R | random multi-pass wraparound (R-test, 100 CQEs at depth=8) | 100 | random sqe_ids, sustained credit, depth=8 | scoreboard reports zero unmatched lineage and zero payload mismatch; coverage duplicate of prior merged baseline after E014; retained for functional scenario check | FUNC-E015-wraparound-e001-e016-random-multi-pass-wraparound-r-test-100-cqes |
| E016 | R | random wraparound with random doorbell pacing | 100 | random doorbell value bins; depth=16; 100 CQEs | scoreboard PASS; per-txn coverage growth recorded; coverage duplicate of prior merged baseline after E015; retained for functional scenario check | FUNC-E016-wraparound-e001-e016-random-wraparound-with-random-doorbell-pacing |

---

## 3. CQ-full backpressure (E017-E032)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E017 | D | depth=2: push 1, no credit, push next stalls | 1 | depth=2; inject 2 CQEs (cq_full after 1st retire) | `dbg_cq_full==1` after 1st; `tready==0` for 2nd | FUNC-E017-cq-full-backpressure-e017-e032-depth-2-push-1-no-credit-push-next |
| E018 | D | depth=4: push 3, no credit, push next stalls | 3 | depth=4; no credit | `dbg_cq_full==1` after 3rd retire (cq_tail+1 == cq_head==0); coverage duplicate of prior merged baseline after E017; retained for functional scenario check | FUNC-E018-cq-full-backpressure-e017-e032-depth-4-push-3-no-credit-push-next |
| E019 | D | depth=16: push 15, no credit, push next stalls | 15 | depth=16 | `dbg_cq_full==1` after 15th retire; coverage duplicate of prior merged baseline after E018; retained for functional scenario check | FUNC-E019-cq-full-backpressure-e017-e032-depth-16-push-15-no-credit-push-next |
| E020 | D | depth=256: push 255, no credit, stall | 255 | depth=256 | `dbg_cq_full==1` after 255th retire; coverage duplicate of prior merged baseline after E019; retained for functional scenario check | FUNC-E020-cq-full-backpressure-e017-e032-depth-256-push-255-no-credit-stall |
| E021 | D | full clears on doorbell credit==1 | 1 | continue from E017, pulse credit=1 | `dbg_cq_full==0` next clk; next CQE flows; coverage duplicate of prior merged baseline after E020; retained for functional scenario check | FUNC-E021-cq-full-backpressure-e017-e032-full-clears-on-doorbell-credit-1 |
| E022 | D | full clears on doorbell credit==depth/2 | 1 | continue from E018, pulse credit=2 | `dbg_cq_full==0`; multiple CQEs can flow; coverage duplicate of prior merged baseline after E021; retained for functional scenario check | FUNC-E022-cq-full-backpressure-e017-e032-full-clears-on-doorbell-credit-depth-2 |
| E023 | D | sustained backpressure: 100 CQEs queued upstream waiting on tready | 100 | depth=4; no credit; inject 100 with backpressure handling | `tready` low until credit; first 3 land, remaining 97 wait; coverage duplicate of prior merged baseline after E022; retained for functional scenario check | FUNC-E023-cq-full-backpressure-e017-e032-sustained-backpressure-100-cqes-queued-upstream-waiting |
| E024 | D | `dbg_ring_full_stall_cyc` increments only when stall present | 16 | depth=4; cqe_tvalid=1 with no credit | counter increments per stall clk while tvalid&&cq_full; coverage duplicate of prior merged baseline after E023; retained for functional scenario check | FUNC-E024-cq-full-backpressure-e017-e032-dbg-ring-full-stall-cyc-increments-only-when |
| E025 | D | `dbg_ring_full_stall_cyc` does NOT increment when no upstream pressure | 16 | depth=4; quiescent stream; no tvalid | counter stable; coverage duplicate of prior merged baseline after E024; retained for functional scenario check | FUNC-E025-cq-full-backpressure-e017-e032-dbg-ring-full-stall-cyc-does-not-increment |
| E026 | D | full propagates clean back-edge (no glitch on `tready`) | 4 | depth=4; oscillate cq_head | tready falls/rises only at full-edge; coverage duplicate of prior merged baseline after E025; retained for functional scenario check | FUNC-E026-cq-full-backpressure-e017-e032-full-propagates-clean-back-edge-no-glitch-on |
| E027 | D | full and `cfg_enable=0` interaction: tready stays low (either gate) | 1 | depth=4 full + cfg_enable=0 | tready=0 regardless of full-state; coverage duplicate of prior merged baseline after E026; retained for functional scenario check | FUNC-E027-cq-full-backpressure-e017-e032-full-and-cfg-enable-0-interaction-tready-stays |
| E028 | D | doorbell during stall releases minimum credit | 1 | depth=4 full; pulse credit=cq_tail+1 (1 slot) | exactly 1 push releases; coverage duplicate of prior merged baseline after E027; retained for functional scenario check | FUNC-E028-cq-full-backpressure-e017-e032-doorbell-during-stall-releases-minimum-credit |
| E029 | D | doorbell during stall releases full credit (drain ring) | 1 | depth=4 full; pulse credit=cq_tail (full drain) | 4 pushes release back-to-back; coverage duplicate of prior merged baseline after E028; retained for functional scenario check | FUNC-E029-cq-full-backpressure-e017-e032-doorbell-during-stall-releases-full-credit-drain-ring |
| E030 | D | back-pressure during AW state holds awvalid stable | 1 | depth=4 full while DUT in AW | awvalid stable until `cq_head` advances; coverage duplicate of prior merged baseline after E029; retained for functional scenario check | FUNC-E030-cq-full-backpressure-e017-e032-back-pressure-during-aw-state-holds-awvalid-stable |
| E031 | R | random fill/drain cycle (100 CQEs, depth=8, random doorbell pacing) | 100 | random pacing | per-txn growth curve recorded; PASS | FUNC-E031-cq-full-backpressure-e017-e032-random-fill-drain-cycle-100-cqes-depth-8 |
| E032 | R | random fill/drain with mixed depth values | 100 | random depth in {4,16,256}; random doorbell | scoreboard PASS; coverage duplicate of prior merged baseline after E031; retained for functional scenario check | FUNC-E032-cq-full-backpressure-e017-e032-random-fill-drain-with-mixed-depth-values |

---

## 4. Doorbell credit corners (E033-E048)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E033 | D | doorbell value 0 (no-op) | 1 | pulse value=0 | `cq_head` unchanged; coverage duplicate of prior merged baseline after E032; retained for functional scenario check | FUNC-E033-doorbell-credit-corners-e033-e048-doorbell-value-0-no-op |
| E034 | D | doorbell value at depth boundary (depth=16, value=15) | 1 | pulse value=15, depth=16 | `cq_head==15`; coverage duplicate of prior merged baseline after E033; retained for functional scenario check | FUNC-E034-doorbell-credit-corners-e033-e048-doorbell-value-at-depth-boundary-depth-16-value |
| E035 | D | doorbell value at depth boundary (depth=16, value=16) wraps to 0 | 1 | pulse value=16, depth=16 | `cq_head==0`; coverage duplicate of prior merged baseline after E034; retained for functional scenario check | FUNC-E035-doorbell-credit-corners-e033-e048-doorbell-value-at-depth-boundary-depth-16-value |
| E036 | D | doorbell value at masked overflow (value=0x18, depth=16) | 1 | pulse value=0x18, depth=16 | `cq_head==(0x18 & 0xF)==0x8`; coverage duplicate of prior merged baseline after E035; retained for functional scenario check | FUNC-E036-doorbell-credit-corners-e033-e048-doorbell-value-at-masked-overflow-value-0x18-depth |
| E037 | D | doorbell pulse aligned to `cq_tail` (head==tail==0, no full) | 1 | depth=4, cq_tail=0, pulse value=0 | `dbg_cq_full==0`; ring not declared full; coverage duplicate of prior merged baseline after E036; retained for functional scenario check | FUNC-E037-doorbell-credit-corners-e033-e048-doorbell-pulse-aligned-to-cq-tail-head-tail |
| E038 | D | doorbell pulse equal to `cq_tail+1` (just-released-1) | 1 | cq_tail=2, pulse value=3 | one slot of credit available; coverage duplicate of prior merged baseline after E037; retained for functional scenario check | FUNC-E038-doorbell-credit-corners-e033-e048-doorbell-pulse-equal-to-cq-tail-1-just |
| E039 | D | doorbell two pulses same clk window (last-write-wins) | 2 | pulse value=2 then value=4 within 2 clk | final `cq_head==4`; coverage duplicate of prior merged baseline after E038; retained for functional scenario check | FUNC-E039-doorbell-credit-corners-e033-e048-doorbell-two-pulses-same-clk-window-last-write |
| E040 | D | doorbell during cqe-tvalid going high (race) | 1 | pulse and tvalid same clk | tready evaluation uses post-doorbell `cq_head`; FSM advances correctly; coverage duplicate of prior merged baseline after E039; retained for functional scenario check | FUNC-E040-doorbell-credit-corners-e033-e048-doorbell-during-cqe-tvalid-going-high-race |
| E041 | D | doorbell during AW state | 1 | inject 1 CQE, pulse credit during AW | doorbell latches; FSM continues to W; coverage duplicate of prior merged baseline after E040; retained for functional scenario check | FUNC-E041-doorbell-credit-corners-e033-e048-doorbell-during-aw-state |
| E042 | D | doorbell during W state | 1 | inject 1 CQE, pulse during W | latches; FSM continues to B; coverage duplicate of prior merged baseline after E041; retained for functional scenario check | FUNC-E042-doorbell-credit-corners-e033-e048-doorbell-during-w-state |
| E043 | D | doorbell during B state | 1 | inject 1 CQE, pulse during B | latches; FSM retires normally; coverage duplicate of prior merged baseline after E042; retained for functional scenario check | FUNC-E043-doorbell-credit-corners-e033-e048-doorbell-during-b-state |
| E044 | D | doorbell during ADVANCE_TAIL state | 1 | inject 1 CQE, pulse during ADV | latches; FSM returns to IDLE; coverage duplicate of prior merged baseline after E043; retained for functional scenario check | FUNC-E044-doorbell-credit-corners-e033-e048-doorbell-during-advance-tail-state |
| E045 | D | doorbell at exact reset deassert | 1 | release reset, pulse credit on first clk after deassert | latches `cq_head=value`; coverage duplicate of prior merged baseline after E044; retained for functional scenario check | FUNC-E045-doorbell-credit-corners-e033-e048-doorbell-at-exact-reset-deassert |
| E046 | D | doorbell pulse 2 clk wide (illegal: pulse must be 1 clk per spec) | 1 | drive pulse high 2 clk | DUT samples once on each rising edge of pulse; SVA `sva_doorbell` should detect; coverage duplicate of prior merged baseline after E045; retained for functional scenario check | FUNC-E046-doorbell-credit-corners-e033-e048-doorbell-pulse-2-clk-wide-illegal-pulse-must |
| E047 | R | random doorbell value (100 pulses, full bin coverage) | 100 | random value in [0, 2*depth) | `cq_head` updates match `value & (depth-1)` invariant; coverage duplicate of prior merged baseline after E046; retained for functional scenario check | FUNC-E047-doorbell-credit-corners-e033-e048-random-doorbell-value-100-pulses-full-bin-coverage |
| E048 | R | random doorbell pacing (geometric distribution, 100 events) | 100 | doorbell every k clk where k~Geometric | scoreboard PASS; cg_doorbell_value covered; coverage duplicate of prior merged baseline after E047; retained for functional scenario check | FUNC-E048-doorbell-credit-corners-e033-e048-random-doorbell-pacing-geometric-distribution-100-ev |

---

## 5. Depth corner values (E049-E064)

Every supported `cfg_cq_depth` in `{2,4,16,256,4096,65536}` exercised
with a small directed scenario.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E049 | D | depth=2: 2 CQEs with 2 credits | 2 | inject 2 with sustained credit | both retire; cq_tail wraps to 0; coverage duplicate of prior merged baseline after E048; retained for functional scenario check | FUNC-E049-depth-corner-values-e049-e064-depth-2-2-cqes-with-2-credits |
| E050 | D | depth=2: ring full after 1 push (depth-1=1 slot) | 1 | inject 1, no credit | dbg_cq_full=1 after 1st retire; coverage duplicate of prior merged baseline after E049; retained for functional scenario check | FUNC-E050-depth-corner-values-e049-e064-depth-2-ring-full-after-1-push-depth |
| E051 | D | depth=4 (smoke); already covered by basic; corner sweep adds full+drain | 4 | inject 4, drain via 1 doorbell | scoreboard PASS; coverage duplicate of prior merged baseline after E050; retained for functional scenario check | FUNC-E051-depth-corner-values-e049-e064-depth-4-smoke-already-covered-by-basic-corner |
| E052 | D | depth=4: doorbell 0->3 in one pulse (drain entire ring) | 4 | inject 4 with no credit, then pulse credit=3 | all 4 retire; cq_tail wraps to 0; coverage duplicate of prior merged baseline after E051; retained for functional scenario check | FUNC-E052-depth-corner-values-e049-e064-depth-4-doorbell-0-3-in-one-pulse |
| E053 | D | depth=16: small smoke + single wrap | 17 | inject 17 with sustained credit | wraparound at slot 0; coverage duplicate of prior merged baseline after E052; retained for functional scenario check | FUNC-E053-depth-corner-values-e049-e064-depth-16-small-smoke-single-wrap |
| E054 | D | depth=16: ring full at 15 pushes | 15 | inject 15, no credit | dbg_cq_full=1; coverage duplicate of prior merged baseline after E053; retained for functional scenario check | FUNC-E054-depth-corner-values-e049-e064-depth-16-ring-full-at-15-pushes |
| E055 | D | depth=256: typical default geometry, 50-CQE smoke | 50 | inject 50 with sustained credit | scoreboard PASS; coverage duplicate of prior merged baseline after E054; retained for functional scenario check | FUNC-E055-depth-corner-values-e049-e064-depth-256-typical-default-geometry-50-cqe-smoke |
| E056 | D | depth=256: full at 255 pushes | 255 | inject 255 with no credit | dbg_cq_full=1; tready=0; coverage duplicate of prior merged baseline after E055; retained for functional scenario check | FUNC-E056-depth-corner-values-e049-e064-depth-256-full-at-255-pushes |
| E057 | D | depth=4096: 100-CQE smoke | 100 | inject 100 with sustained credit | PASS; coverage duplicate of prior merged baseline after E056; retained for functional scenario check | FUNC-E057-depth-corner-values-e049-e064-depth-4096-100-cqe-smoke |
| E058 | D | depth=4096: full at 4095 pushes | 4095 | inject 4095 with no credit | dbg_cq_full=1; coverage duplicate of prior merged baseline after E057; retained for functional scenario check | FUNC-E058-depth-corner-values-e049-e064-depth-4096-full-at-4095-pushes |
| E059 | D | depth=65536 (max): 1000-CQE smoke | 1000 | inject 1000 with sustained credit | PASS; coverage duplicate of prior merged baseline after E058; retained for functional scenario check | FUNC-E059-depth-corner-values-e049-e064-depth-65536-max-1000-cqe-smoke |
| E060 | D | depth=65536: full at 65535 pushes | 65535 | inject 65535 with no credit (very long run) | dbg_cq_full=1 (legal but long); coverage duplicate of prior merged baseline after E059; retained for functional scenario check | FUNC-E060-depth-corner-values-e049-e064-depth-65536-full-at-65535-pushes |
| E061 | D | depth=8 (non-standard but power-of-2): 8 CQEs | 8 | inject 8 with sustained credit | wraparound; coverage duplicate of prior merged baseline after E060; retained for functional scenario check | FUNC-E061-depth-corner-values-e049-e064-depth-8-non-standard-but-power-of-2 |
| E062 | D | depth=32: 32 CQEs | 32 | inject 32 | wraparound | FUNC-E062-depth-corner-values-e049-e064-depth-32-32-cqes |
| E063 | D | depth=128: 128 CQEs | 128 | inject 128 | wraparound | FUNC-E063-depth-corner-values-e049-e064-depth-128-128-cqes |
| E064 | D | depth=1024: 1024 CQEs | 1024 | inject 1024 | wraparound | FUNC-E064-depth-corner-values-e049-e064-depth-1024-1024-cqes |

---

## 6. AXI4 AW-ready stall (E065-E076)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E065 | D | awready stalled 0 clk (zero-lag baseline) | 1 | inject 1 CQE; awready always=1 | round-trip 5 clk; coverage duplicate of prior merged baseline after E064; retained for functional scenario check | FUNC-E065-axi4-aw-ready-stall-e065-e076-awready-stalled-0-clk-zero-lag-baseline |
| E066 | D | awready stalled 1 clk | 1 | hold awready=0 for 1 clk after awvalid | awvalid stable; round-trip 6 clk; coverage duplicate of prior merged baseline after E065; retained for functional scenario check | FUNC-E066-axi4-aw-ready-stall-e065-e076-awready-stalled-1-clk |
| E067 | D | awready stalled 4 clk | 1 | hold 4 clk | round-trip 9 clk; coverage duplicate of prior merged baseline after E066; retained for functional scenario check | FUNC-E067-axi4-aw-ready-stall-e065-e076-awready-stalled-4-clk |
| E068 | D | awready stalled 16 clk | 1 | hold 16 clk | round-trip 21 clk; coverage duplicate of prior merged baseline after E067; retained for functional scenario check | FUNC-E068-axi4-aw-ready-stall-e065-e076-awready-stalled-16-clk |
| E069 | D | awready stalled 64 clk | 1 | hold 64 clk | round-trip 69 clk; coverage duplicate of prior merged baseline after E068; retained for functional scenario check | FUNC-E069-axi4-aw-ready-stall-e065-e076-awready-stalled-64-clk |
| E070 | D | awready stalled 256 clk | 1 | hold 256 clk | round-trip 261 clk; SVA `sva_axi_aw` PASS; coverage duplicate of prior merged baseline after E069; retained for functional scenario check | FUNC-E070-axi4-aw-ready-stall-e065-e076-awready-stalled-256-clk |
| E071 | D | awready glitches 0/1/0 (no stall, just transient) | 1 | toggle awready=0 for 1 clk pre-handshake | DUT samples on awready=1; no double-issue; coverage duplicate of prior merged baseline after E070; retained for functional scenario check | FUNC-E071-axi4-aw-ready-stall-e065-e076-awready-glitches-0-1-0-no-stall-just |
| E072 | D | awready stalled cumulative across multiple pushes (4 CQEs each at 4 clk) | 4 | inject 4 CQEs; awready=0 4 clk per push | each retires correctly; coverage duplicate of prior merged baseline after E071; retained for functional scenario check | FUNC-E072-axi4-aw-ready-stall-e065-e076-awready-stalled-cumulative-across-multiple-pushes-4-cqes |
| E073 | D | random awready stall geometric (mean 8 clk) | 16 | mean=8 clk per push | scoreboard PASS; cg_axi_handshake_lag covered; coverage duplicate of prior merged baseline after E072; retained for functional scenario check | FUNC-E073-axi4-aw-ready-stall-e065-e076-random-awready-stall-geometric-mean-8-clk |
| E074 | R | random awready stall uniform (range 0..32) | 50 | range [0,32] | PASS; coverage duplicate of prior merged baseline after E073; retained for functional scenario check | FUNC-E074-axi4-aw-ready-stall-e065-e076-random-awready-stall-uniform-range-0-32 |
| E075 | R | random awready stall burst (long stall every Nth) | 50 | burst pattern | PASS; coverage duplicate of prior merged baseline after E074; retained for functional scenario check | FUNC-E075-axi4-aw-ready-stall-e065-e076-random-awready-stall-burst-long-stall-every-nth |
| E076 | D | awready stalled while `tready` lowered upstream (idle waiting) | 1 | hold awready=0 indefinite, no upstream traffic | DUT idles; no protocol violation; coverage duplicate of prior merged baseline after E075; retained for functional scenario check | FUNC-E076-axi4-aw-ready-stall-e065-e076-awready-stalled-while-tready-lowered-upstream-idle-waiti |

---

## 7. AXI4 W-ready stall (E077-E088)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E077 | D | wready stalled 0 clk | 1 | wready always=1 | round-trip 5 clk; coverage duplicate of prior merged baseline after E076; retained for functional scenario check | FUNC-E077-axi4-w-ready-stall-e077-e088-wready-stalled-0-clk |
| E078 | D | wready stalled 1 clk | 1 | hold wready=0 for 1 clk | wvalid stable; round-trip 6 clk; coverage duplicate of prior merged baseline after E077; retained for functional scenario check | FUNC-E078-axi4-w-ready-stall-e077-e088-wready-stalled-1-clk |
| E079 | D | wready stalled 4 clk | 1 | hold 4 clk | round-trip 9 clk; coverage duplicate of prior merged baseline after E078; retained for functional scenario check | FUNC-E079-axi4-w-ready-stall-e077-e088-wready-stalled-4-clk |
| E080 | D | wready stalled 16 clk | 1 | hold 16 clk | round-trip 21 clk; coverage duplicate of prior merged baseline after E079; retained for functional scenario check | FUNC-E080-axi4-w-ready-stall-e077-e088-wready-stalled-16-clk |
| E081 | D | wready stalled 64 clk | 1 | hold 64 clk | round-trip 69 clk; coverage duplicate of prior merged baseline after E080; retained for functional scenario check | FUNC-E081-axi4-w-ready-stall-e077-e088-wready-stalled-64-clk |
| E082 | D | wready stalled 256 clk | 1 | hold 256 clk | round-trip 261 clk; coverage duplicate of prior merged baseline after E081; retained for functional scenario check | FUNC-E082-axi4-w-ready-stall-e077-e088-wready-stalled-256-clk |
| E083 | D | wready glitch (0/1/0) before W handshake | 1 | toggle | no double-issue; coverage duplicate of prior merged baseline after E082; retained for functional scenario check | FUNC-E083-axi4-w-ready-stall-e077-e088-wready-glitch-0-1-0-before-w-handshake |
| E084 | D | wready stall across 4 CQEs cumulative | 4 | wready=0 4 clk per push | all retire; coverage duplicate of prior merged baseline after E083; retained for functional scenario check | FUNC-E084-axi4-w-ready-stall-e077-e088-wready-stall-across-4-cqes-cumulative |
| E085 | R | random wready stall geometric | 16 | mean=8 clk | PASS; coverage duplicate of prior merged baseline after E084; retained for functional scenario check | FUNC-E085-axi4-w-ready-stall-e077-e088-random-wready-stall-geometric |
| E086 | R | random wready stall uniform | 50 | range [0,32] | PASS; coverage duplicate of prior merged baseline after E085; retained for functional scenario check | FUNC-E086-axi4-w-ready-stall-e077-e088-random-wready-stall-uniform |
| E087 | R | random wready stall burst | 50 | burst | PASS; coverage duplicate of prior merged baseline after E086; retained for functional scenario check | FUNC-E087-axi4-w-ready-stall-e077-e088-random-wready-stall-burst |
| E088 | D | wready stall combined with awready stall (both 16 clk) | 1 | both hold 16 clk | round-trip ~37 clk; FSM ordering preserved; coverage duplicate of prior merged baseline after E087; retained for functional scenario check | FUNC-E088-axi4-w-ready-stall-e077-e088-wready-stall-combined-with-awready-stall-both-16 |

---

## 8. AXI4 B-channel latency (E089-E100)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E089 | D | bvalid arrives 0 clk after wlast (back-pressure-free) | 1 | bvalid=1 same clk as wlast | round-trip 4 clk (no B wait); coverage duplicate of prior merged baseline after E088; retained for functional scenario check | FUNC-E089-axi4-b-channel-latency-e089-e100-bvalid-arrives-0-clk-after-wlast-back-pressure |
| E090 | D | bvalid arrives 1 clk after wlast | 1 | bvalid 1 clk after | round-trip 5 clk; coverage duplicate of prior merged baseline after E089; retained for functional scenario check | FUNC-E090-axi4-b-channel-latency-e089-e100-bvalid-arrives-1-clk-after-wlast |
| E091 | D | bvalid arrives 4 clk after wlast | 1 | bvalid 4 clk after | round-trip 8 clk; coverage duplicate of prior merged baseline after E090; retained for functional scenario check | FUNC-E091-axi4-b-channel-latency-e089-e100-bvalid-arrives-4-clk-after-wlast |
| E092 | D | bvalid arrives 16 clk after wlast | 1 | 16 clk B latency | round-trip 20 clk; coverage duplicate of prior merged baseline after E091; retained for functional scenario check | FUNC-E092-axi4-b-channel-latency-e089-e100-bvalid-arrives-16-clk-after-wlast |
| E093 | D | bvalid arrives 64 clk after wlast | 1 | 64 clk B latency | round-trip 68 clk; coverage duplicate of prior merged baseline after E092; retained for functional scenario check | FUNC-E093-axi4-b-channel-latency-e089-e100-bvalid-arrives-64-clk-after-wlast |
| E094 | D | bvalid arrives 256 clk after wlast | 1 | 256 clk B latency | round-trip 260 clk; coverage duplicate of prior merged baseline after E093; retained for functional scenario check | FUNC-E094-axi4-b-channel-latency-e089-e100-bvalid-arrives-256-clk-after-wlast |
| E095 | D | B latency cumulative across 4 CQEs (each 16 clk) | 4 | 16 clk B latency per push | all retire in order; coverage duplicate of prior merged baseline after E094; retained for functional scenario check | FUNC-E095-axi4-b-channel-latency-e089-e100-b-latency-cumulative-across-4-cqes-each-16 |
| E096 | D | bvalid arrives concurrent with next push start (back-to-back) | 4 | zero gap, B at 1 clk | Phase 1: serial, no overlap; coverage duplicate of prior merged baseline after E095; retained for functional scenario check | FUNC-E096-axi4-b-channel-latency-e089-e100-bvalid-arrives-concurrent-with-next-push-start-back |
| E097 | R | random B latency geometric | 16 | mean=8 clk | cg_axi_handshake_lag covered; coverage duplicate of prior merged baseline after E096; retained for functional scenario check | FUNC-E097-axi4-b-channel-latency-e089-e100-random-b-latency-geometric |
| E098 | R | random B latency uniform | 50 | range [0,32] | PASS; coverage duplicate of prior merged baseline after E097; retained for functional scenario check | FUNC-E098-axi4-b-channel-latency-e089-e100-random-b-latency-uniform |
| E099 | R | random B latency burst | 50 | burst | PASS; coverage duplicate of prior merged baseline after E098; retained for functional scenario check | FUNC-E099-axi4-b-channel-latency-e089-e100-random-b-latency-burst |
| E100 | D | B latency combined with W stall (worst-case latency) | 1 | wready stall 64 + B latency 64 | round-trip ~133 clk; SVA all PASS; coverage duplicate of prior merged baseline after E099; retained for functional scenario check | FUNC-E100-axi4-b-channel-latency-e089-e100-b-latency-combined-with-w-stall-worst-case |

---

## 9. FSM-state doorbell race (E101-E116)

Doorbell pulse aligned with each FSM state, repeated for full
coverage of `cg_doorbell_race x cg_fsm_state`.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E101 | D | doorbell at IDLE -> AW transition clk | 1 | aim doorbell pulse at FSM transition | latches; FSM proceeds; coverage duplicate of prior merged baseline after E100; retained for functional scenario check | FUNC-E101-fsm-state-doorbell-race-e101-e116-doorbell-at-idle-aw-transition-clk |
| E102 | D | doorbell mid-AW (long awready stall) | 1 | force awready stall 16 clk; doorbell at clk 8 | latches mid-stall; AW completes; coverage duplicate of prior merged baseline after E101; retained for functional scenario check | FUNC-E102-fsm-state-doorbell-race-e101-e116-doorbell-mid-aw-long-awready-stall |
| E103 | D | doorbell at AW -> W transition | 1 | doorbell at handshake clk | latches; W proceeds; coverage duplicate of prior merged baseline after E102; retained for functional scenario check | FUNC-E103-fsm-state-doorbell-race-e101-e116-doorbell-at-aw-w-transition |
| E104 | D | doorbell mid-W (wready stall) | 1 | wready stall 16; doorbell at clk 8 | latches; W completes; coverage duplicate of prior merged baseline after E103; retained for functional scenario check | FUNC-E104-fsm-state-doorbell-race-e101-e116-doorbell-mid-w-wready-stall |
| E105 | D | doorbell at W -> B transition | 1 | doorbell at wvalid&&wready clk | latches; B proceeds; coverage duplicate of prior merged baseline after E104; retained for functional scenario check | FUNC-E105-fsm-state-doorbell-race-e101-e116-doorbell-at-w-b-transition |
| E106 | D | doorbell mid-B (B latency 16) | 1 | B latency 16; doorbell at clk 8 | latches; B retires; coverage duplicate of prior merged baseline after E105; retained for functional scenario check | FUNC-E106-fsm-state-doorbell-race-e101-e116-doorbell-mid-b-b-latency-16 |
| E107 | D | doorbell at B -> ADVANCE transition | 1 | doorbell at bvalid clk | latches; ADV proceeds; coverage duplicate of prior merged baseline after E106; retained for functional scenario check | FUNC-E107-fsm-state-doorbell-race-e101-e116-doorbell-at-b-advance-transition |
| E108 | D | doorbell at ADVANCE -> IDLE transition | 1 | doorbell at the ADV clk | latches; IDLE entered; coverage duplicate of prior merged baseline after E107; retained for functional scenario check | FUNC-E108-fsm-state-doorbell-race-e101-e116-doorbell-at-advance-idle-transition |
| E109 | D | doorbell at the same clk as `s_axis_cqe_tvalid&&tready` | 1 | doorbell on same clk | both latch independently; coverage duplicate of prior merged baseline after E108; retained for functional scenario check | FUNC-E109-fsm-state-doorbell-race-e101-e116-doorbell-at-the-same-clk-as-s-axis |
| E110 | D | doorbell at the same clk as `m_axi_bvalid` | 1 | doorbell at bvalid clk | both latch; coverage duplicate of prior merged baseline after E109; retained for functional scenario check | FUNC-E110-fsm-state-doorbell-race-e101-e116-doorbell-at-the-same-clk-as-m-axi |
| E111 | D | doorbell during quiescent FSM (IDLE for long) | 1 | no traffic for 64 clk; doorbell at random clk | only `cq_head` shadow updates; coverage duplicate of prior merged baseline after E110; retained for functional scenario check | FUNC-E111-fsm-state-doorbell-race-e101-e116-doorbell-during-quiescent-fsm-idle-for-long |
| E112 | D | two doorbells across one push lifecycle | 2 | doorbell at IDLE then at B | both latch in order; coverage duplicate of prior merged baseline after E111; retained for functional scenario check | FUNC-E112-fsm-state-doorbell-race-e101-e116-two-doorbells-across-one-push-lifecycle |
| E113 | D | doorbell race with reset deassert | 1 | reset deasserts on the same clk as doorbell pulse | reset wins (per Phase 1 spec); coverage duplicate of prior merged baseline after E112; retained for functional scenario check | FUNC-E113-fsm-state-doorbell-race-e101-e116-doorbell-race-with-reset-deassert |
| E114 | R | random doorbell timing across 100 push lifecycles | 100 | random offsets within each lifecycle | scoreboard PASS; cg_doorbell_race x cg_fsm_state covered; coverage duplicate of prior merged baseline after E113; retained for functional scenario check | FUNC-E114-fsm-state-doorbell-race-e101-e116-random-doorbell-timing-across-100-push-lifecycles |
| E115 | R | random doorbell pacing with random AW/W/B stall | 100 | full random | PASS; coverage duplicate of prior merged baseline after E114; retained for functional scenario check | FUNC-E115-fsm-state-doorbell-race-e101-e116-random-doorbell-pacing-with-random-aw-w-b |
| E116 | R | random doorbell with random depth | 100 | depth random in {4,16,256} | PASS; coverage duplicate of prior merged baseline after E115; retained for functional scenario check | FUNC-E116-fsm-state-doorbell-race-e101-e116-random-doorbell-with-random-depth |

---

## 10. Reprogram in flight (E117-E124)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E117 | D | `cfg_cq_base` change while idle | 1 | no traffic; reprogram base | next push uses new base; coverage duplicate of prior merged baseline after E116; retained for functional scenario check | FUNC-E117-reprogram-in-flight-e117-e124-cfg-cq-base-change-while-idle |
| E118 | D | `cfg_cq_depth` change while idle | 1 | no traffic; reprogram depth | next push uses new depth wrap; coverage duplicate of prior merged baseline after E117; retained for functional scenario check | FUNC-E118-reprogram-in-flight-e117-e124-cfg-cq-depth-change-while-idle |
| E119 | D | `cfg_enable=1->0->1` while idle | 1 | toggle enable | tready follows enable; no AW issued during disable; coverage duplicate of prior merged baseline after E118; retained for functional scenario check | FUNC-E119-reprogram-in-flight-e117-e124-cfg-enable-1-0-1-while-idle |
| E120 | D | `cfg_cq_base` change mid-AW (Phase 1: undefined; harness logs warning) | 1 | reprogram during AW state | RTL behavior captured; SVA does not fire (cfg is not strobed in flight); coverage duplicate of prior merged baseline after E119; retained for functional scenario check | FUNC-E120-reprogram-in-flight-e117-e124-cfg-cq-base-change-mid-aw-phase-1 |
| E121 | D | `cfg_cq_depth` change mid-flight (Phase 1: undefined) | 1 | reprogram during W state | observed behavior captured; coverage duplicate of prior merged baseline after E120; retained for functional scenario check | FUNC-E121-reprogram-in-flight-e117-e124-cfg-cq-depth-change-mid-flight-phase-1 |
| E122 | D | `cfg_enable=0` during AW state stalls FSM | 1 | inject 1, deassert enable mid-AW | AW completes; no second push accepted; coverage duplicate of prior merged baseline after E121; retained for functional scenario check | FUNC-E122-reprogram-in-flight-e117-e124-cfg-enable-0-during-aw-state-stalls-fsm |
| E123 | D | reprogram base across reset boundary | 1 | program base, reset, reprogram new base | new base used post-reset; coverage duplicate of prior merged baseline after E122; retained for functional scenario check | FUNC-E123-reprogram-in-flight-e117-e124-reprogram-base-across-reset-boundary |
| E124 | D | reprogram depth across reset boundary | 1 | program depth, reset, reprogram new depth | new depth used post-reset; coverage duplicate of prior merged baseline after E123; retained for functional scenario check | FUNC-E124-reprogram-in-flight-e117-e124-reprogram-depth-across-reset-boundary |

---

## 11. DEBUG sidecar corners (E125-E128)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E125 | D | sidecar all-1s (`s_axis_cqe_tuser_meta = 64'hFFFF...`) | 1 | inject 1 CQE with all-1s sidecar | meta_retired_e carries all-1s; payload unaffected; coverage duplicate of prior merged baseline after E124; retained for functional scenario check | FUNC-E125-debug-sidecar-corners-e125-e128-sidecar-all-1s-s-axis-cqe-tuser-meta |
| E126 | D | sidecar all-0s | 1 | inject 1 CQE with all-0s sidecar | meta_retired_e carries 0; payload unaffected; coverage duplicate of prior merged baseline after E125; retained for functional scenario check | FUNC-E126-debug-sidecar-corners-e125-e128-sidecar-all-0s |
| E127 | D | meta_fifo at depth boundary (Phase 1 depth >= 1; back-to-back inject) | 8 | inject 8 CQEs back-to-back with sidecar | sidecar FIFO never overflows; lineage in order; coverage duplicate of prior merged baseline after E126; retained for functional scenario check | FUNC-E127-debug-sidecar-corners-e125-e128-meta-fifo-at-depth-boundary-phase-1-depth |
| E128 | D | sidecar drives matching `sqe_id` field with payload word2[31:16] | 4 | inject 4 CQEs with matching sqe_ids | shared scoreboard cross-validates 4/4; coverage duplicate of prior merged baseline after E127; retained for functional scenario check | FUNC-E128-debug-sidecar-corners-e125-e128-sidecar-drives-matching-sqe-id-field-with-payload |
