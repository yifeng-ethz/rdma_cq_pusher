# DV Basic — rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_EDGE.md`,
`DV_PROF.md`, `DV_ERROR.md`, `DV_COV.md`, `DV_CROSS.md`, `BUG_HISTORY.md`

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** B001-B128
**Total:** 128 cases (128 implemented / 0 waived)

This document expands every B-bucket entry from `DV_PLAN.md` §1
into a deterministic functional case. Each row pins one specific
contract surface anchored in `../RTL_PLAN.md` §3 / §4 (top interface,
4-state push FSM, DEBUG=1 taps, DEBUG=2 lineage). The dual env
(`env_dbg1` payload + `env_dbg2` lineage) runs joint in every case;
the shared scoreboard is the pass/fail arbiter.

**Methodology key:**
- **D** = Directed (hand-crafted stimulus, deterministic seed,
  one canonical CQE-stream per case)
- **R** = Constrained-random (SystemVerilog `rand`/`constraint`,
  per-case seed, randomized cfg / doorbell / handshake-lag bins;
  must implement the checkpoint UCDB emitter)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Reset and bring-up | 12 | B001-B012 | reset clears state; bring-up sequence reaches IDLE with `s_axis_cqe_tready=1` | 12/12 |
| Single-CQE push | 12 | B013-B024 | one CQE flows IDLE -> AW -> W -> B -> ADVANCE; payload arrives at host slot 0; counters move | 12/12 |
| Back-to-back pushes | 12 | B025-B036 | sustained CQE stream with no doorbell stall; ordering preserved across the 4-state FSM | 12/12 |
| Address arithmetic | 12 | B037-B048 | `awaddr == cfg_cq_base + cq_tail*64`; awsize/awlen/awburst/wstrb/wlast invariants | 12/12 |
| Doorbell credit | 12 | B049-B060 | `cq_head_dbl_pulse` updates internal `cq_head` masked by `cfg_cq_depth-1`; cq_full predicate | 12/12 |
| AXI4-Stream sink | 12 | B061-B072 | `s_axis_cqe_tready` gating, `tlast`, `tuser` (sqe_id) propagation | 12/12 |
| AXI4 master shape | 12 | B073-B084 | AW/W/B handshake invariants, `bid==awid`, single-beat full-cacheline write | 12/12 |
| DEBUG=1 taps | 12 | B085-B096 | every `dbg_*` synthesizable port mirrors DUT state, no functional perturbation | 12/12 |
| DEBUG=2 lineage | 12 | B097-B108 | sim-only sidecar drives `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)`, lineage observed at retire | 12/12 |
| MSI-X stub quiescence | 8 | B109-B116 | `msix_req=0` always in Phase 1; `msix_ack` ignored | 8/8 |
| Sideband counters | 8 | B117-B124 | `cnt_cqe_posted` and `cq_tail` track each B-OKAY exactly | 8/8 |
| `cfg_enable=0` gating | 4 | B125-B128 | disabled holds `tready` low and produces no AW; doorbell still latches | 4/4 |

---

## 2. Reset and bring-up (B001-B012)

Reset behavior, default state at deassertion, and the proof that the
DUT reaches IDLE with `s_axis_cqe_tready` ready to accept the first
CQE before any test stimulus is launched.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B001 | D | async reset clears `cq_tail`, `cq_head`, FSM=IDLE, `cnt_cqe_posted=0`, `cq_full=0` | 1 | hold reset_n=0 for 16 clk, release with `cfg_*` programmed and idle stimulus | post-deassert `cq_tail==0`, `cnt_cqe_posted==0`, `dbg_state==IDLE`, `dbg_cq_full==0`, `s_axis_cqe_tready==1` | FUNC-B001-reset-and-bring-up-b001-b012-async-reset-clears-cq-tail-cq-head-fsm |
| B002 | D | reset deassert observed clean on every clk edge | 1 | release reset_n synchronous to clk; sample on every edge for 8 clk | no glitches on `m_axi_aw/w/b_valid` and `s_axis_cqe_tready` follows protocol immediately; coverage duplicate of prior merged baseline after B001; retained for functional scenario check | FUNC-B002-reset-and-bring-up-b001-b012-reset-deassert-observed-clean-on-every-clk-edge |
| B003 | D | reset asserted mid-AW returns master signals to idle | 1 | start one push, assert reset_n in AW state | `m_axi_awvalid==0` next clk; FSM back to IDLE; outstanding AW dropped from harness queue | FUNC-B003-reset-and-bring-up-b001-b012-reset-asserted-mid-aw-returns-master-signals-to |
| B004 | D | reset asserted mid-W returns master signals to idle | 1 | start one push, assert reset_n in W state | `m_axi_wvalid==0` next clk; FSM back to IDLE | FUNC-B004-reset-and-bring-up-b001-b012-reset-asserted-mid-w-returns-master-signals-to |
| B005 | D | reset asserted mid-B returns master signals to idle | 1 | start one push, hold B latency, assert reset_n in B state | `m_axi_bready==0` after deassert; ledger cleared in scoreboard | FUNC-B005-reset-and-bring-up-b001-b012-reset-asserted-mid-b-returns-master-signals-to |
| B006 | D | back-to-back resets do not produce phantom counters | 1 | release reset_n, hold 4 clk idle, assert reset_n again | `cnt_cqe_posted==0` after second deassert | FUNC-B006-reset-and-bring-up-b001-b012-back-to-back-resets-do-not-produce-phantom |
| B007 | D | reset clears `cq_full` even after CQ ring filled | 1 | fill ring at depth=4, assert reset_n | `dbg_cq_full==0` and `cq_tail==0` post-deassert; coverage duplicate of prior merged baseline after B006; retained for functional scenario check | FUNC-B007-reset-and-bring-up-b001-b012-reset-clears-cq-full-even-after-cq-ring |
| B008 | D | reset propagates through env_dbg2 sidecar without leaking lineage | 1 | drive sidecar lineage on a stuck push, assert reset | `dbg_last_pushed_meta==0` after deassert; coverage duplicate of prior merged baseline after B007; retained for functional scenario check | FUNC-B008-reset-and-bring-up-b001-b012-reset-propagates-through-env-dbg2-sidecar-without-leaking |
| B009 | D | reset must not glitch `cq_tail` -> `csr.CQ_TAIL` shadow | 1 | observe `cq_tail` over 16 clk reset window | `cq_tail==0` for entire reset window; coverage duplicate of prior merged baseline after B008; retained for functional scenario check | FUNC-B009-reset-and-bring-up-b001-b012-reset-must-not-glitch-cq-tail-csr-cq |
| B010 | D | bring-up reaches IDLE within 4 clk after deassert | 1 | release reset_n, sample `dbg_state` and `s_axis_cqe_tready` | both stable at IDLE / 1 within 4 clk; coverage duplicate of prior merged baseline after B009; retained for functional scenario check | FUNC-B010-reset-and-bring-up-b001-b012-bring-up-reaches-idle-within-4-clk-after |
| B011 | D | reset clears `dbg_ring_full_stall_cyc` saturating counter | 1 | drive ring-full backpressure to accumulate counter, then reset | `dbg_ring_full_stall_cyc==0` post-deassert; coverage duplicate of prior merged baseline after B010; retained for functional scenario check | FUNC-B011-reset-and-bring-up-b001-b012-reset-clears-dbg-ring-full-stall-cyc-saturating |
| B012 | D | reset clears `dbg_cnt_bresp_error` | 1 | inject one SLVERR (deferred to X bucket details), then reset | `dbg_cnt_bresp_error==0` post-deassert; coverage duplicate of prior merged baseline after B011; retained for functional scenario check | FUNC-B012-reset-and-bring-up-b001-b012-reset-clears-dbg-cnt-bresp-error |

---

## 3. Single-CQE push (B013-B024)

One CQE drives the full 4-state FSM round trip with all
hand-shake bins at zero latency. Verifies the basic dataflow path
end-to-end before stress.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B013 | D | single CQE, depth=256, all-zero hand-shake lag | 1 | inject 1 CQE with deterministic 8x64-bit payload | host_cq_shadow[0]==CQE; `cq_tail==1`; `cnt_cqe_posted==1`; B-OKAY observed once | FUNC-B013-single-cqe-push-b013-b024-single-cqe-depth-256-all-zero-hand-shake |
| B014 | D | FSM walks IDLE -> AW -> W -> B -> ADVANCE -> IDLE | 1 | same as B013 with `dbg_state` capture | `dbg_state` sequence matches the canonical 5-tick round trip; coverage duplicate of prior merged baseline after B013; retained for functional scenario check | FUNC-B014-single-cqe-push-b013-b024-fsm-walks-idle-aw-w-b-advance-idle |
| B015 | D | `m_axi_awvalid` only high in AW state | 1 | single push | `awvalid` window aligned with `dbg_state==AW` (SVA `sva_axi_aw`); coverage duplicate of prior merged baseline after B014; retained for functional scenario check | FUNC-B015-single-cqe-push-b013-b024-m-axi-awvalid-only-high-in-aw-state |
| B016 | D | `m_axi_wvalid` only high in W state | 1 | single push | `wvalid` window aligned with `dbg_state==W`; coverage duplicate of prior merged baseline after B015; retained for functional scenario check | FUNC-B016-single-cqe-push-b013-b024-m-axi-wvalid-only-high-in-w-state |
| B017 | D | `m_axi_bready` only high in B state | 1 | single push | `bready` window aligned with `dbg_state==B`; coverage duplicate of prior merged baseline after B016; retained for functional scenario check | FUNC-B017-single-cqe-push-b013-b024-m-axi-bready-only-high-in-b-state |
| B018 | D | one B-OKAY per AW (1:1 retire) | 1 | single push | exactly one `b_observed_e` event with `bresp==OKAY` per `aw_observed_e`; coverage duplicate of prior merged baseline after B017; retained for functional scenario check | FUNC-B018-single-cqe-push-b013-b024-one-b-okay-per-aw-1-1-retire |
| B019 | D | CQE byte-perfect: each of 8 x 64-bit words preserved | 1 | inject CQE with distinct word values | host_cq_shadow word-i equals injected word-i for i in 0..7; coverage duplicate of prior merged baseline after B018; retained for functional scenario check | FUNC-B019-single-cqe-push-b013-b024-cqe-byte-perfect-each-of-8-x-64 |
| B020 | D | sqe_id propagated via `s_axis_cqe_tuser` to host word2[31:16] | 1 | inject CQE with sqe_id=0xCAFE in tuser AND CQE word2[31:16] | host shadow word2[31:16]==0xCAFE; coverage duplicate of prior merged baseline after B019; retained for functional scenario check | FUNC-B020-single-cqe-push-b013-b024-sqe-id-propagated-via-s-axis-cqe-tuser |
| B021 | D | `cnt_cqe_posted` increments exactly once | 1 | single push | counter delta == 1 after B-OKAY; coverage duplicate of prior merged baseline after B020; retained for functional scenario check | FUNC-B021-single-cqe-push-b013-b024-cnt-cqe-posted-increments-exactly-once |
| B022 | D | `cq_tail` advances exactly once | 1 | single push | `cq_tail` 0 -> 1; SVA `sva_full` consistent; coverage duplicate of prior merged baseline after B021; retained for functional scenario check | FUNC-B022-single-cqe-push-b013-b024-cq-tail-advances-exactly-once |
| B023 | D | `awaddr` exactly equals `cfg_cq_base` for first push | 1 | single push, cfg_cq_base=0x1000_0000_0000_0000 | observed `m_axi_awaddr == cfg_cq_base`; coverage duplicate of prior merged baseline after B022; retained for functional scenario check | FUNC-B023-single-cqe-push-b013-b024-awaddr-exactly-equals-cfg-cq-base-for-first |
| B024 | D | scoreboard lineage tuple matched by env_dbg2 | 1 | single push, env_dbg2 drives sidecar | `meta_retired_e` carries injected `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)`; coverage duplicate of prior merged baseline after B023; retained for functional scenario check | FUNC-B024-single-cqe-push-b013-b024-scoreboard-lineage-tuple-matched-by-env-dbg2 |

---

## 4. Back-to-back pushes (B025-B036)

Sustained CQE stream while doorbell credit is plentiful. No
backpressure stalls expected.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B025 | D | 2 CQEs back-to-back, depth=256 | 2 | inject 2 CQEs with no inter-beat gap | host_cq_shadow[0..1] match injected order; cq_tail==2 | FUNC-B025-back-to-back-pushes-b025-b036-2-cqes-back-to-back-depth-256 |
| B026 | D | 4 CQEs back-to-back, depth=256 | 4 | inject 4 CQEs | host_cq_shadow[0..3] match; cq_tail==4 | FUNC-B026-back-to-back-pushes-b025-b036-4-cqes-back-to-back-depth-256 |
| B027 | D | 8 CQEs back-to-back, depth=256 | 8 | inject 8 CQEs | host_cq_shadow[0..7] match; cq_tail==8 | FUNC-B027-back-to-back-pushes-b025-b036-8-cqes-back-to-back-depth-256 |
| B028 | D | 16 CQEs back-to-back, depth=256 | 16 | inject 16 CQEs | host_cq_shadow[0..15] match; cnt_cqe_posted==16 | FUNC-B028-back-to-back-pushes-b025-b036-16-cqes-back-to-back-depth-256 |
| B029 | D | 64 CQEs back-to-back, depth=256 | 64 | inject 64 CQEs | host_cq_shadow[0..63] match | FUNC-B029-back-to-back-pushes-b025-b036-64-cqes-back-to-back-depth-256 |
| B030 | D | 128 CQEs back-to-back, depth=256 | 128 | inject 128 CQEs | cq_tail==128; counters consistent | FUNC-B030-back-to-back-pushes-b025-b036-128-cqes-back-to-back-depth-256 |
| B031 | D | 4 CQEs with 1-cycle gap each | 4 | inject 4 CQEs; gap_cycles=1 | each CQE retires before next AW; ordering preserved; coverage duplicate of prior merged baseline after B030; retained for functional scenario check | FUNC-B031-back-to-back-pushes-b025-b036-4-cqes-with-1-cycle-gap-each |
| B032 | D | 4 CQEs with 4-cycle gap each | 4 | inject 4 CQEs; gap_cycles=4 | same as B031 with longer idle; coverage duplicate of prior merged baseline after B031; retained for functional scenario check | FUNC-B032-back-to-back-pushes-b025-b036-4-cqes-with-4-cycle-gap-each |
| B033 | D | back-to-back ordering is FIFO (no reordering) | 8 | inject 8 CQEs with sqe_id=0..7 | host_cq_shadow word2[31:16] == 0..7 in order; coverage duplicate of prior merged baseline after B032; retained for functional scenario check | FUNC-B033-back-to-back-pushes-b025-b036-back-to-back-ordering-is-fifo-no-reordering |
| B034 | D | sustained `dbg_aw_pending` <= 1 in Phase 1 (one push in flight) | 8 | inject 8 CQEs | `dbg_aw_pending` never exceeds 1 during the run; coverage duplicate of prior merged baseline after B033; retained for functional scenario check | FUNC-B034-back-to-back-pushes-b025-b036-sustained-dbg-aw-pending-1-in-phase-1 |
| B035 | D | sustained `dbg_b_inflight` <= 1 in Phase 1 | 8 | inject 8 CQEs | `dbg_b_inflight` never exceeds 1; coverage duplicate of prior merged baseline after B034; retained for functional scenario check | FUNC-B035-back-to-back-pushes-b025-b036-sustained-dbg-b-inflight-1-in-phase-1 |
| B036 | D | each round-trip latency equals 5 clk under zero hand-shake lag | 8 | inject 8 CQEs at 0-lag completer | per-CQE wall-clock latency == 5 clk (1 per FSM state); coverage duplicate of prior merged baseline after B035; retained for functional scenario check | FUNC-B036-back-to-back-pushes-b025-b036-each-round-trip-latency-equals-5-clk-under |

---

## 5. Address arithmetic (B037-B048)

`awaddr` formula and AXI4 invariants: `awsize`, `awlen`, `awburst`,
`wstrb`, `wlast`, alignment.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B037 | D | `awaddr` formula: `cfg_cq_base + cq_tail*64` for cq_tail=0..7 | 8 | inject 8 CQEs | for each AW i, `awaddr == cfg_cq_base + i*64`; coverage duplicate of prior merged baseline after B036; retained for functional scenario check | FUNC-B037-address-arithmetic-b037-b048-awaddr-formula-cfg-cq-base-cq-tail-64 |
| B038 | D | `cfg_cq_base` 4 KB-aligned (typical Linux page) | 8 | cfg_cq_base=0x0000_1000_0000_0000 | every awaddr 64 B aligned within the page; coverage duplicate of prior merged baseline after B037; retained for functional scenario check | FUNC-B038-address-arithmetic-b037-b048-cfg-cq-base-4-kb-aligned-typical-linux |
| B039 | D | `cfg_cq_base` 64 B-aligned (cacheline-aligned) | 8 | cfg_cq_base=0x0000_0000_0000_2040 | every awaddr 64 B aligned; coverage duplicate of prior merged baseline after B038; retained for functional scenario check | FUNC-B039-address-arithmetic-b037-b048-cfg-cq-base-64-b-aligned-cacheline-aligned |
| B040 | D | `cfg_cq_base` very high address (AXI 64-bit address space) | 4 | cfg_cq_base=0xFFFF_FFFF_FFFF_FF00 | awaddr arithmetic correct, no overflow on cq_tail*64; coverage duplicate of prior merged baseline after B039; retained for functional scenario check | FUNC-B040-address-arithmetic-b037-b048-cfg-cq-base-very-high-address-axi-64 |
| B041 | D | `awsize == $clog2(WQE_BUS_W/8) == 6` (64 B beat) | 1 | single push | observed awsize == 3'd6 every push; coverage duplicate of prior merged baseline after B040; retained for functional scenario check | FUNC-B041-address-arithmetic-b037-b048-awsize-clog2-wqe-bus-w-8-6-64 |
| B042 | D | `awlen == 0` (single-beat burst) | 1 | single push | observed awlen == 8'd0 every push; coverage duplicate of prior merged baseline after B041; retained for functional scenario check | FUNC-B042-address-arithmetic-b037-b048-awlen-0-single-beat-burst |
| B043 | D | `awburst == INCR (2'b01)` | 1 | single push | observed awburst == 2'b01 every push; coverage duplicate of prior merged baseline after B042; retained for functional scenario check | FUNC-B043-address-arithmetic-b037-b048-awburst-incr-2-b01 |
| B044 | D | `wstrb == all-1s` for full cacheline write | 1 | single push | observed wstrb == 64'hFFFF_FFFF_FFFF_FFFF every push; coverage duplicate of prior merged baseline after B043; retained for functional scenario check | FUNC-B044-address-arithmetic-b037-b048-wstrb-all-1s-for-full-cacheline-write |
| B045 | D | `wlast == 1` on the single beat | 1 | single push | observed wlast==1 coincident with `wvalid&&wready`; coverage duplicate of prior merged baseline after B044; retained for functional scenario check | FUNC-B045-address-arithmetic-b037-b048-wlast-1-on-the-single-beat |
| B046 | D | `awid` consistent (Phase 1: fixed value or 0) | 4 | inject 4 CQEs | awid stable across pushes; bid==awid for each; coverage duplicate of prior merged baseline after B045; retained for functional scenario check | FUNC-B046-address-arithmetic-b037-b048-awid-consistent-phase-1-fixed-value-or-0 |
| B047 | D | `awaddr` never wanders outside `[cfg_cq_base, cfg_cq_base+cfg_cq_depth*64)` | 32 | inject 32 CQEs at depth=16 (forces wraparound) | every awaddr in range; SVA `sva_axi_aw` PASS | FUNC-B047-address-arithmetic-b037-b048-awaddr-never-wanders-outside-cfg-cq-base-cfg |
| B048 | D | wraparound: cq_tail=depth-1 -> next push lands at `cfg_cq_base` | 4 | inject `depth+1` CQEs at depth=4 with doorbell credit released | host_cq_shadow[0] overwritten with second pass's CQE; coverage duplicate of prior merged baseline after B047; retained for functional scenario check | FUNC-B048-address-arithmetic-b037-b048-wraparound-cq-tail-depth-1-next-push-lands |

---

## 6. Doorbell credit (B049-B060)

`cq_head_dbl_pulse` updates internal `cq_head`; `cq_full` predicate
holds across credit windows.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B049 | D | doorbell pulse updates `dbg_cur_cq_head_credit` next clk | 1 | pulse `cq_head_dbl_pulse=1` for 1 clk with value=4 | next clk `dbg_cur_cq_head_credit==4`; coverage duplicate of prior merged baseline after B048; retained for functional scenario check | FUNC-B049-doorbell-credit-b049-b060-doorbell-pulse-updates-dbg-cur-cq-head-credit |
| B050 | D | doorbell value masked by `cfg_cq_depth-1` (depth=16, value=0x18) | 1 | pulse value=0x18, depth=16 | next clk `dbg_cur_cq_head_credit==(0x18 & 0xF)==0x8`; coverage duplicate of prior merged baseline after B049; retained for functional scenario check | FUNC-B050-doorbell-credit-b049-b060-doorbell-value-masked-by-cfg-cq-depth-1 |
| B051 | D | doorbell value at boundary (value==depth-1) | 1 | pulse value=15, depth=16 | `dbg_cur_cq_head_credit==15`; coverage duplicate of prior merged baseline after B050; retained for functional scenario check | FUNC-B051-doorbell-credit-b049-b060-doorbell-value-at-boundary-value-depth-1 |
| B052 | D | doorbell value at boundary (value==depth) wraps to 0 | 1 | pulse value=16, depth=16 | `dbg_cur_cq_head_credit==0`; coverage duplicate of prior merged baseline after B051; retained for functional scenario check | FUNC-B052-doorbell-credit-b049-b060-doorbell-value-at-boundary-value-depth-wraps-to |
| B053 | D | doorbell value 0 (no credit) | 1 | pulse value=0 | `dbg_cur_cq_head_credit==0`; if `cq_tail==1`, ring is one-slot full; coverage duplicate of prior merged baseline after B052; retained for functional scenario check | FUNC-B053-doorbell-credit-b049-b060-doorbell-value-0-no-credit |
| B054 | D | bulk credit: doorbell jumps from 0 to 8 | 1 | pulse value=8, depth=16 | credit shadow updated atomically; coverage duplicate of prior merged baseline after B053; retained for functional scenario check | FUNC-B054-doorbell-credit-b049-b060-bulk-credit-doorbell-jumps-from-0-to-8 |
| B055 | D | doorbell while DUT is idle | 1 | no CQE traffic; pulse value=4 | only `dbg_cur_cq_head_credit` changes; FSM remains IDLE; coverage duplicate of prior merged baseline after B054; retained for functional scenario check | FUNC-B055-doorbell-credit-b049-b060-doorbell-while-dut-is-idle |
| B056 | D | two doorbells back-to-back coalesce or apply in order | 2 | pulse value=2, then pulse value=4 | final `dbg_cur_cq_head_credit==4` (last write wins per spec); coverage duplicate of prior merged baseline after B055; retained for functional scenario check | FUNC-B056-doorbell-credit-b049-b060-two-doorbells-back-to-back-coalesce-or-apply |
| B057 | D | `cq_full` predicate: depth=4, push 3 CQEs without credit | 3 | inject 3 CQEs at depth=4, no doorbell | `dbg_cq_full==1` after 3rd retire (cq_tail+1 == cq_head==0); coverage duplicate of prior merged baseline after B056; retained for functional scenario check | FUNC-B057-doorbell-credit-b049-b060-cq-full-predicate-depth-4-push-3-cqes |
| B058 | D | `cq_full` predicate clears on doorbell | 1 | continue from B057, pulse value=1 | `dbg_cq_full==0` next clk; coverage duplicate of prior merged baseline after B057; retained for functional scenario check | FUNC-B058-doorbell-credit-b049-b060-cq-full-predicate-clears-on-doorbell |
| B059 | D | doorbell pulse exactly 1 clk wide | 1 | pulse value=4 | DUT samples value on the asserted clk; level=0 next clk; coverage duplicate of prior merged baseline after B058; retained for functional scenario check | FUNC-B059-doorbell-credit-b049-b060-doorbell-pulse-exactly-1-clk-wide |
| B060 | D | doorbell during `cfg_enable=0` still latches | 1 | cfg_enable=0; pulse value=4 | `dbg_cur_cq_head_credit==4` even though no AW issued; coverage duplicate of prior merged baseline after B059; retained for functional scenario check | FUNC-B060-doorbell-credit-b049-b060-doorbell-during-cfg-enable-0-still-latches |

---

## 7. AXI4-Stream sink (B061-B072)

`s_axis_cqe_*` handshake, `tlast`, `tuser` propagation.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B061 | D | `tready` only high in IDLE && cfg_enable && !cq_full | 1 | single push | observed `tready` window matches the predicate (SVA `sva_cqe_in`); coverage duplicate of prior merged baseline after B060; retained for functional scenario check | FUNC-B061-axi4-stream-sink-b061-b072-tready-only-high-in-idle-and-and-cfg |
| B062 | D | `tlast` always 1 on a valid beat (1 CQE = 1 beat) | 8 | inject 8 CQEs | every `tvalid&&tready` cycle has `tlast==1`; coverage duplicate of prior merged baseline after B061; retained for functional scenario check | FUNC-B062-axi4-stream-sink-b061-b072-tlast-always-1-on-a-valid-beat-1 |
| B063 | D | `tuser` (sqe_id) propagates to host CQE word2[31:16] | 8 | sqe_id varies 0..7 | host_cq_shadow[i].word2[31:16] == i; coverage duplicate of prior merged baseline after B062; retained for functional scenario check | FUNC-B063-axi4-stream-sink-b061-b072-tuser-sqe-id-propagates-to-host-cqe-word2 |
| B064 | D | `tdata` byte-perfect to host_cq_shadow | 8 | random 512-bit payloads | host shadow == injected for each CQE; coverage duplicate of prior merged baseline after B063; retained for functional scenario check | FUNC-B064-axi4-stream-sink-b061-b072-tdata-byte-perfect-to-host-cq-shadow |
| B065 | D | `tvalid` low while DUT is in AW/W/B (no second push accepted) | 1 | inject 1 CQE, force AW completer to stall | `tvalid&&tready` does not fire again until B retires; coverage duplicate of prior merged baseline after B064; retained for functional scenario check | FUNC-B065-axi4-stream-sink-b061-b072-tvalid-low-while-dut-is-in-aw-w |
| B066 | D | sink stalls cleanly when `cq_full=1` | 4 | depth=4, push 4 with no credit | `tready` low after 3rd retire; new CQE waits; coverage duplicate of prior merged baseline after B065; retained for functional scenario check | FUNC-B066-axi4-stream-sink-b061-b072-sink-stalls-cleanly-when-cq-full-1 |
| B067 | D | sink resumes cleanly after credit released | 4 | continue from B066, pulse 1 credit | next CQE flows; `tready` rises within 1 clk; coverage duplicate of prior merged baseline after B066; retained for functional scenario check | FUNC-B067-axi4-stream-sink-b061-b072-sink-resumes-cleanly-after-credit-released |
| B068 | D | `tready` does not glitch high during AW state | 1 | single push, sample tready every clk in AW | `tready==0` in AW window; coverage duplicate of prior merged baseline after B067; retained for functional scenario check | FUNC-B068-axi4-stream-sink-b061-b072-tready-does-not-glitch-high-during-aw-state |
| B069 | D | `tready` does not glitch high during W state | 1 | single push, sample tready in W | `tready==0` in W; coverage duplicate of prior merged baseline after B068; retained for functional scenario check | FUNC-B069-axi4-stream-sink-b061-b072-tready-does-not-glitch-high-during-w-state |
| B070 | D | `tready` does not glitch high during B state | 1 | single push, sample tready in B | `tready==0` in B; coverage duplicate of prior merged baseline after B069; retained for functional scenario check | FUNC-B070-axi4-stream-sink-b061-b072-tready-does-not-glitch-high-during-b-state |
| B071 | D | `tready` does not glitch high during ADVANCE_TAIL | 1 | single push, sample tready in ADVANCE | `tready==0` in ADVANCE; rises in IDLE next clk; coverage duplicate of prior merged baseline after B070; retained for functional scenario check | FUNC-B071-axi4-stream-sink-b061-b072-tready-does-not-glitch-high-during-advance-tail |
| B072 | D | sink rejects CQE with `tlast=0` (illegal in Phase 1) | 1 | drive `tvalid=1, tlast=0` | env_dbg1 driver records this as protocol violation; SVA fires | FUNC-B072-axi4-stream-sink-b061-b072-sink-rejects-cqe-with-tlast-0-illegal-in |

---

## 8. AXI4 master shape (B073-B084)

AW/W/B handshake invariants, completer compatibility, single-beat
single-cacheline write.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B073 | D | `awvalid` stable until `awready` (no withdrawal) | 1 | force awready to wait 4 clk | awvalid stays high across the wait window; coverage duplicate of prior merged baseline after B072; retained for functional scenario check | FUNC-B073-axi4-master-shape-b073-b084-awvalid-stable-until-awready-no-withdrawal |
| B074 | D | `wvalid` stable until `wready` | 1 | force wready to wait 4 clk | wvalid stays high across the wait window; coverage duplicate of prior merged baseline after B073; retained for functional scenario check | FUNC-B074-axi4-master-shape-b073-b084-wvalid-stable-until-wready |
| B075 | D | `awvalid` does not appear before W or B issued | 1 | single push, observe order | awvalid -> wvalid -> bvalid in that order; coverage duplicate of prior merged baseline after B074; retained for functional scenario check | FUNC-B075-axi4-master-shape-b073-b084-awvalid-does-not-appear-before-w-or-b |
| B076 | D | `wvalid` does not appear before AW handshake completes | 1 | force AW wait | wvalid only rises after awvalid&&awready; coverage duplicate of prior merged baseline after B075; retained for functional scenario check | FUNC-B076-axi4-master-shape-b073-b084-wvalid-does-not-appear-before-aw-handshake-completes |
| B077 | D | `bready` rises before bvalid (Phase 1: bready always high in B state) | 1 | single push, force B latency | bready==1 throughout B state regardless of bvalid; coverage duplicate of prior merged baseline after B076; retained for functional scenario check | FUNC-B077-axi4-master-shape-b073-b084-bready-rises-before-bvalid-phase-1-bready-always |
| B078 | D | one B per AW (no orphan B accepted) | 8 | inject 8 CQEs | scoreboard `outstanding_aw_q` stays balanced; coverage duplicate of prior merged baseline after B077; retained for functional scenario check | FUNC-B078-axi4-master-shape-b073-b084-one-b-per-aw-no-orphan-b-accepted |
| B079 | D | `bid==awid` for each transaction | 4 | inject 4 CQEs with awid varying (Phase 1: awid fixed) | bid matches awid; SVA `sva_axi_b` PASS; coverage duplicate of prior merged baseline after B078; retained for functional scenario check | FUNC-B079-axi4-master-shape-b073-b084-bid-awid-for-each-transaction |
| B080 | D | AW/W issue order may be parallel (Phase 1: serial) | 1 | single push, observe AW->W timing | AW handshake completes before W; matches FSM; coverage duplicate of prior merged baseline after B079; retained for functional scenario check | FUNC-B080-axi4-master-shape-b073-b084-aw-w-issue-order-may-be-parallel-phase |
| B081 | D | full-cacheline write: 64 B = 8 x 64-bit words atomically observable on host | 1 | single push with distinct 8 words | host shadow snapshot atomic; never partial; coverage duplicate of prior merged baseline after B080; retained for functional scenario check | FUNC-B081-axi4-master-shape-b073-b084-full-cacheline-write-64-b-8-x-64 |
| B082 | D | `awsize=6` (64 B) is hard-coded for Phase 1 (no other size accepted by RTL) | 1 | single push | static observation; SVA `sva_axi_aw` PASS; coverage duplicate of prior merged baseline after B081; retained for functional scenario check | FUNC-B082-axi4-master-shape-b073-b084-awsize-6-64-b-is-hard-coded-for |
| B083 | D | AXI4 4 KB rule trivially satisfied (single beat, naturally aligned) | 8 | inject 8 CQEs | each transaction within a 64 B cacheline; never crosses 4 KB; coverage duplicate of prior merged baseline after B082; retained for functional scenario check | FUNC-B083-axi4-master-shape-b073-b084-axi4-4-kb-rule-trivially-satisfied-single-beat |
| B084 | D | exclusive access (`awlock`, `arlock`) not used in Phase 1 | 1 | single push | awlock=0; arlock not driven (write-only master); coverage duplicate of prior merged baseline after B083; retained for functional scenario check | FUNC-B084-axi4-master-shape-b073-b084-exclusive-access-awlock-arlock-not-used-in-phase |

---

## 9. DEBUG=1 taps (B085-B096)

Synthesizable observability ports mirror DUT state with no functional
perturbation.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B085 | D | `dbg_cur_cq_tail` mirrors FSM `cq_tail` every clk | 8 | inject 8 CQEs | per-clk `dbg_cur_cq_tail == cq_tail` (predicted by scoreboard); coverage duplicate of prior merged baseline after B084; retained for functional scenario check | FUNC-B085-debug-1-taps-b085-b096-dbg-cur-cq-tail-mirrors-fsm-cq-tail |
| B086 | D | `dbg_cur_cq_head_credit` mirrors `cq_head` every clk | 4 | inject doorbell sequence | `dbg_cur_cq_head_credit == cq_head` per clk; coverage duplicate of prior merged baseline after B085; retained for functional scenario check | FUNC-B086-debug-1-taps-b085-b096-dbg-cur-cq-head-credit-mirrors-cq-head |
| B087 | D | `dbg_cq_full` matches `((cq_tail+1)&(cq_depth-1))==cq_head` | 8 | depth=4, push to fill | `dbg_cq_full==1` exactly when ring full | FUNC-B087-debug-1-taps-b085-b096-dbg-cq-full-matches-cq-tail-1-and |
| B088 | D | `dbg_aw_pending` counts AW issued but B not retired | 4 | force B latency=4 clk | counter rises to 1 during W/B, returns to 0 at retire; coverage duplicate of prior merged baseline after B087; retained for functional scenario check | FUNC-B088-debug-1-taps-b085-b096-dbg-aw-pending-counts-aw-issued-but-b |
| B089 | D | `dbg_b_inflight` counts B-channel beats in flight | 4 | force B latency=4 | counter rises to 1 during B wait, returns to 0; coverage duplicate of prior merged baseline after B088; retained for functional scenario check | FUNC-B089-debug-1-taps-b085-b096-dbg-b-inflight-counts-b-channel-beats-in |
| B090 | D | `dbg_ring_full_stall_cyc` is saturating, increments only when `cq_full=1 && cqe_tvalid=1` | 4 | depth=4, push 5 with no credit | counter increments per stall clk; saturates at 32-bit max; coverage duplicate of prior merged baseline after B089; retained for functional scenario check | FUNC-B090-debug-1-taps-b085-b096-dbg-ring-full-stall-cyc-is-saturating-increments |
| B091 | D | `dbg_state` 4-bit encoding stable: IDLE=0, AW=1, W=2, B=3, ADV=4 (or per RTL) | 1 | single push | observed sequence matches the 5-state walk; coverage duplicate of prior merged baseline after B090; retained for functional scenario check | FUNC-B091-debug-1-taps-b085-b096-dbg-state-4-bit-encoding-stable-idle-0 |
| B092 | D | `dbg_cnt_bresp_error` increments on non-OKAY BRESP | 1 | inject 1 SLVERR (env_dbg1 completer in error mode) | counter==1; cq_tail does not advance (Phase 1 retry) | FUNC-B092-debug-1-taps-b085-b096-dbg-cnt-bresp-error-increments-on-non-okay |
| B093 | D | DEBUG=1 ports tied to 0 at `DEBUG_LEVEL=0` | 1 | DEBUG_PARITY build A | all dbg_* outputs stuck at 0 in build A; coverage duplicate of prior merged baseline after B092; retained for functional scenario check | FUNC-B093-debug-1-taps-b085-b096-debug-1-ports-tied-to-0-at-debug |
| B094 | D | DEBUG=1 ports do not perturb m_axi_w/aw/b trace | 1 | DEBUG_PARITY test | byte-identical trace between DEBUG=0 and DEBUG=2 builds; coverage duplicate of prior merged baseline after B093; retained for functional scenario check | FUNC-B094-debug-1-taps-b085-b096-debug-1-ports-do-not-perturb-m-axi |
| B095 | D | `dbg_*` are flopped (no combinational glitch from internal state) | 8 | inject 8 CQEs | dbg taps stable on each clk edge; no zero-clk glitches; coverage duplicate of prior merged baseline after B094; retained for functional scenario check | FUNC-B095-debug-1-taps-b085-b096-dbg-are-flopped-no-combinational-glitch-from-internal |
| B096 | D | `dbg_state` matches SVA cover bins for FSM transitions | 4 | inject 4 CQEs | every observed FSM transition recorded by `cg_fsm_state`; coverage duplicate of prior merged baseline after B095; retained for functional scenario check | FUNC-B096-debug-1-taps-b085-b096-dbg-state-matches-sva-cover-bins-for-fsm |

---

## 10. DEBUG=2 lineage (B097-B108)

Sim-only sidecar drives `(sqe_id, retire_seq, origin_dma_done_seq,
push_seq)`; lineage observed at retire matches.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B097 | D | env_dbg2 drives `s_axis_cqe_tuser_meta` synchronously with cqe_tdata | 1 | single push, sidecar=0xCAFE_BABE_DEAD_BEEF | meta_observed_e captured matches injected; coverage duplicate of prior merged baseline after B096; retained for functional scenario check | FUNC-B097-debug-2-lineage-b097-b108-env-dbg2-drives-s-axis-cqe-tuser-meta |
| B098 | D | `dbg_last_pushed_meta` updates exactly on B-OKAY retire | 1 | single push | meta_retired_e fires once per B-OKAY; coverage duplicate of prior merged baseline after B097; retained for functional scenario check | FUNC-B098-debug-2-lineage-b097-b108-dbg-last-pushed-meta-updates-exactly-on-b |
| B099 | D | lineage tuple's `sqe_id` equals CQE word2[31:16] (host slot) | 4 | inject 4 CQEs with matching sqe_ids | shared scoreboard cross-validates per CQE; coverage duplicate of prior merged baseline after B098; retained for functional scenario check | FUNC-B099-debug-2-lineage-b097-b108-lineage-tuple-s-sqe-id-equals-cqe-word2 |
| B100 | D | `push_seq` strictly monotonic across regression (env_dbg2 sequencer) | 8 | inject 8 CQEs | observed push_seq increments by 1 per CQE; coverage duplicate of prior merged baseline after B099; retained for functional scenario check | FUNC-B100-debug-2-lineage-b097-b108-push-seq-strictly-monotonic-across-regression-env-dbg2 |
| B101 | D | `retire_seq` matches injected order at host slot | 8 | inject 8 CQEs with retire_seq=0..7 | meta_retired_e carries 0..7 in order; coverage duplicate of prior merged baseline after B100; retained for functional scenario check | FUNC-B101-debug-2-lineage-b097-b108-retire-seq-matches-injected-order-at-host-slot |
| B102 | D | `origin_dma_done_seq` carried unchanged through pipeline | 4 | inject 4 CQEs with distinct origin_dma_done_seq | meta_retired_e carries injected origin_dma_done_seq; coverage duplicate of prior merged baseline after B101; retained for functional scenario check | FUNC-B102-debug-2-lineage-b097-b108-origin-dma-done-seq-carried-unchanged-through-pipeline |
| B103 | D | sidecar tied to 0 at DEBUG_LEVEL=0 (no driver in env_dbg2) | 1 | DEBUG_PARITY build A | sidecar wires statically 0 in build A; coverage duplicate of prior merged baseline after B102; retained for functional scenario check | FUNC-B103-debug-2-lineage-b097-b108-sidecar-tied-to-0-at-debug-level-0 |
| B104 | D | sidecar does not appear in synthesizable W payload | 1 | inject 1 CQE with sidecar=0xFFFF... | host_cq_shadow word contents do NOT contain sidecar bits; coverage duplicate of prior merged baseline after B103; retained for functional scenario check | FUNC-B104-debug-2-lineage-b097-b108-sidecar-does-not-appear-in-synthesizable-w-payload |
| B105 | D | meta-FIFO depth bounded (Phase 1: depth >= 1) | 4 | inject 4 CQEs back-to-back | sidecar FIFO never overflows; lineage observed in order; coverage duplicate of prior merged baseline after B104; retained for functional scenario check | FUNC-B105-debug-2-lineage-b097-b108-meta-fifo-depth-bounded-phase-1-depth-1 |
| B106 | D | sidecar mismatch (env_dbg2 corrupts on inject) is caught by scoreboard | 1 | inject 1 CQE with mismatched sqe_id between cqe_tuser and meta | scoreboard flags lineage mismatch as FAIL (negative test wired in env_dbg2); coverage duplicate of prior merged baseline after B105; retained for functional scenario check | FUNC-B106-debug-2-lineage-b097-b108-sidecar-mismatch-env-dbg2-corrupts-on-inject-is |
| B107 | D | env_dbg2's `meta_observed_e` and env_dbg1's `cqe_observed_e` arrive same clk | 4 | inject 4 CQEs | both ports fire on the same `tvalid&&tready` clk; coverage duplicate of prior merged baseline after B106; retained for functional scenario check | FUNC-B107-debug-2-lineage-b097-b108-env-dbg2-s-meta-observed-e-and-env |
| B108 | D | shared scoreboard cross-validates 100% lineage closure for B097-B107 | 1 | replay batch of B097-B107 sequences | zero unmatched lineage at end-of-test; coverage duplicate of prior merged baseline after B107; retained for functional scenario check | FUNC-B108-debug-2-lineage-b097-b108-shared-scoreboard-cross-validates-100-lineage-closure-for |

---

## 11. MSI-X stub quiescence (B109-B116)

Phase 1: `msix_req` tied 0; `msix_ack` ignored. Verified to never
toggle.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B109 | D | `msix_req==0` at reset deassert | 1 | reset, sample msix_req | msix_req==0; coverage duplicate of prior merged baseline after B108; retained for functional scenario check | FUNC-B109-msi-x-stub-quiescence-b109-b116-msix-req-0-at-reset-deassert |
| B110 | D | `msix_req==0` after a single CQE push | 1 | single push | msix_req remains 0 (SVA `sva_msix_quiet`); coverage duplicate of prior merged baseline after B109; retained for functional scenario check | FUNC-B110-msi-x-stub-quiescence-b109-b116-msix-req-0-after-a-single-cqe-push |
| B111 | D | `msix_req==0` after 16 back-to-back pushes | 16 | inject 16 CQEs | msix_req never asserts; coverage duplicate of prior merged baseline after B110; retained for functional scenario check | FUNC-B111-msi-x-stub-quiescence-b109-b116-msix-req-0-after-16-back-to-back |
| B112 | D | `msix_vector` reserved (Phase 1: tied or undriven) | 1 | observe msix_vector | static value across run; coverage duplicate of prior merged baseline after B111; retained for functional scenario check | FUNC-B112-msi-x-stub-quiescence-b109-b116-msix-vector-reserved-phase-1-tied-or-undriven |
| B113 | D | `msix_ack` pulse ignored (no FSM reaction) | 1 | pulse msix_ack=1 for 1 clk | DUT FSM unchanged; msix_req stays 0 | FUNC-B113-msi-x-stub-quiescence-b109-b116-msix-ack-pulse-ignored-no-fsm-reaction |
| B114 | D | `msix_ack` held high ignored | 1 | hold msix_ack=1 for 16 clk | no msix_req transition; coverage duplicate of prior merged baseline after B113; retained for functional scenario check | FUNC-B114-msi-x-stub-quiescence-b109-b116-msix-ack-held-high-ignored |
| B115 | D | `msix_ack` race with B-OKAY ignored | 4 | inject 4 CQEs, pulse msix_ack at each B | no msix_req transition; coverage duplicate of prior merged baseline after B114; retained for functional scenario check | FUNC-B115-msi-x-stub-quiescence-b109-b116-msix-ack-race-with-b-okay-ignored |
| B116 | D | Phase 2 wire-up will replace this section; Phase 1 stub contract is hard | 1 | regression-locked SVA gate | `sva_msix_quiet` PASS for entire bucket regression; coverage duplicate of prior merged baseline after B115; retained for functional scenario check | FUNC-B116-msi-x-stub-quiescence-b109-b116-phase-2-wire-up-will-replace-this-section |

---

## 12. Sideband counters (B117-B124)

`cnt_cqe_posted` increments per B-OKAY; `cq_tail` mirrors FSM tail.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B117 | D | `cnt_cqe_posted==0` at reset | 1 | reset | counter==0; coverage duplicate of prior merged baseline after B116; retained for functional scenario check | FUNC-B117-sideband-counters-b117-b124-cnt-cqe-posted-0-at-reset |
| B118 | D | `cnt_cqe_posted` increments by 1 per B-OKAY | 8 | inject 8 CQEs | counter==8 at end; coverage duplicate of prior merged baseline after B117; retained for functional scenario check | FUNC-B118-sideband-counters-b117-b124-cnt-cqe-posted-increments-by-1-per-b |
| B119 | D | `cnt_cqe_posted` does NOT increment on non-OKAY BRESP | 1 | inject 1 SLVERR | counter unchanged; coverage duplicate of prior merged baseline after B118; retained for functional scenario check | FUNC-B119-sideband-counters-b117-b124-cnt-cqe-posted-does-not-increment-on-non |
| B120 | D | `cnt_cqe_posted` saturating? (Phase 1: 32-bit, plenty of headroom) | 1 | observe over 64 pushes | counter reads 64; no rollover; coverage duplicate of prior merged baseline after B119; retained for functional scenario check | FUNC-B120-sideband-counters-b117-b124-cnt-cqe-posted-saturating-phase-1-32-bit |
| B121 | D | `cq_tail` shadow always equals predictor | 8 | inject 8 CQEs | per-clk `cq_tail == expected_cq_tail`; coverage duplicate of prior merged baseline after B120; retained for functional scenario check | FUNC-B121-sideband-counters-b117-b124-cq-tail-shadow-always-equals-predictor |
| B122 | D | `cq_tail` at depth boundary wraps to 0 | 4 | depth=4, push 4 with credit | observed `cq_tail` 0,1,2,3,0 | FUNC-B122-sideband-counters-b117-b124-cq-tail-at-depth-boundary-wraps-to-0 |
| B123 | D | `cq_tail` and `cnt_cqe_posted` agree mod cfg_cq_depth | 16 | depth=4, push 16 with credit released continuously | `cq_tail == cnt_cqe_posted % depth` at each retire; coverage duplicate of prior merged baseline after B122; retained for functional scenario check | FUNC-B123-sideband-counters-b117-b124-cq-tail-and-cnt-cqe-posted-agree-mod |
| B124 | D | both counters survive bucket_frame transitions | 8 | inject 8 CQEs across two case boundaries | counters monotonic across bucket boundaries; coverage duplicate of prior merged baseline after B123; retained for functional scenario check | FUNC-B124-sideband-counters-b117-b124-both-counters-survive-bucket-frame-transitions |

---

## 13. `cfg_enable=0` gating (B125-B128)

Disabled holds `tready` low and produces no AW; doorbell still latches.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B125 | D | `cfg_enable=0` at reset deassert | 1 | reset with cfg_enable=0 | `s_axis_cqe_tready==0`; no AW issued | FUNC-B125-cfg-enable-0-gating-b125-b128-cfg-enable-0-at-reset-deassert |
| B126 | D | `cfg_enable=1->0` transition between pushes | 1 | inject 1 CQE, deassert enable, attempt second push | second push waits on tready | FUNC-B126-cfg-enable-0-gating-b125-b128-cfg-enable-1-0-transition-between-pushes |
| B127 | D | doorbell still latches `cq_head` while `cfg_enable=0` | 1 | cfg_enable=0; pulse value=4 | `dbg_cur_cq_head_credit==4` next clk; coverage duplicate of prior merged baseline after B126; retained for functional scenario check | FUNC-B127-cfg-enable-0-gating-b125-b128-doorbell-still-latches-cq-head-while-cfg-enable |
| B128 | D | `cfg_enable=0->1` transition unblocks `tready` | 2 | continue from B126, assert enable | second push completes within 1 clk after enable rises | FUNC-B128-cfg-enable-0-gating-b125-b128-cfg-enable-0-1-transition-unblocks-tready |
