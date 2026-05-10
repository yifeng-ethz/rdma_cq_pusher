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
| B001 | D | async reset clears `cq_tail`, `cq_head`, FSM=IDLE, `cnt_cqe_posted=0`, `cq_full=0` | 1 | hold reset_n=0 for 16 clk, release with `cfg_*` programmed and idle stimulus | post-deassert `cq_tail==0`, `cnt_cqe_posted==0`, `dbg_state==IDLE`, `dbg_cq_full==0`, `s_axis_cqe_tready==1` | TBD |
| B002 | D | reset deassert observed clean on every clk edge | 1 | release reset_n synchronous to clk; sample on every edge for 8 clk | no glitches on `m_axi_aw/w/b_valid` and `s_axis_cqe_tready` follows protocol immediately | TBD |
| B003 | D | reset asserted mid-AW returns master signals to idle | 1 | start one push, assert reset_n in AW state | `m_axi_awvalid==0` next clk; FSM back to IDLE; outstanding AW dropped from harness queue | TBD |
| B004 | D | reset asserted mid-W returns master signals to idle | 1 | start one push, assert reset_n in W state | `m_axi_wvalid==0` next clk; FSM back to IDLE | TBD |
| B005 | D | reset asserted mid-B returns master signals to idle | 1 | start one push, hold B latency, assert reset_n in B state | `m_axi_bready==0` after deassert; ledger cleared in scoreboard | TBD |
| B006 | D | back-to-back resets do not produce phantom counters | 1 | release reset_n, hold 4 clk idle, assert reset_n again | `cnt_cqe_posted==0` after second deassert | TBD |
| B007 | D | reset clears `cq_full` even after CQ ring filled | 1 | fill ring at depth=4, assert reset_n | `dbg_cq_full==0` and `cq_tail==0` post-deassert | TBD |
| B008 | D | reset propagates through env_dbg2 sidecar without leaking lineage | 1 | drive sidecar lineage on a stuck push, assert reset | `dbg_last_pushed_meta==0` after deassert | TBD |
| B009 | D | reset must not glitch `cq_tail` -> `csr.CQ_TAIL` shadow | 1 | observe `cq_tail` over 16 clk reset window | `cq_tail==0` for entire reset window | TBD |
| B010 | D | bring-up reaches IDLE within 4 clk after deassert | 1 | release reset_n, sample `dbg_state` and `s_axis_cqe_tready` | both stable at IDLE / 1 within 4 clk | TBD |
| B011 | D | reset clears `dbg_ring_full_stall_cyc` saturating counter | 1 | drive ring-full backpressure to accumulate counter, then reset | `dbg_ring_full_stall_cyc==0` post-deassert | TBD |
| B012 | D | reset clears `dbg_cnt_bresp_error` | 1 | inject one SLVERR (deferred to X bucket details), then reset | `dbg_cnt_bresp_error==0` post-deassert | TBD |

---

## 3. Single-CQE push (B013-B024)

One CQE drives the full 4-state FSM round trip with all
hand-shake bins at zero latency. Verifies the basic dataflow path
end-to-end before stress.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B013 | D | single CQE, depth=256, all-zero hand-shake lag | 1 | inject 1 CQE with deterministic 8x64-bit payload | host_cq_shadow[0]==CQE; `cq_tail==1`; `cnt_cqe_posted==1`; B-OKAY observed once | TBD |
| B014 | D | FSM walks IDLE -> AW -> W -> B -> ADVANCE -> IDLE | 1 | same as B013 with `dbg_state` capture | `dbg_state` sequence matches the canonical 5-tick round trip | TBD |
| B015 | D | `m_axi_awvalid` only high in AW state | 1 | single push | `awvalid` window aligned with `dbg_state==AW` (SVA `sva_axi_aw`) | TBD |
| B016 | D | `m_axi_wvalid` only high in W state | 1 | single push | `wvalid` window aligned with `dbg_state==W` | TBD |
| B017 | D | `m_axi_bready` only high in B state | 1 | single push | `bready` window aligned with `dbg_state==B` | TBD |
| B018 | D | one B-OKAY per AW (1:1 retire) | 1 | single push | exactly one `b_observed_e` event with `bresp==OKAY` per `aw_observed_e` | TBD |
| B019 | D | CQE byte-perfect: each of 8 x 64-bit words preserved | 1 | inject CQE with distinct word values | host_cq_shadow word-i equals injected word-i for i in 0..7 | TBD |
| B020 | D | sqe_id propagated via `s_axis_cqe_tuser` to host word2[31:16] | 1 | inject CQE with sqe_id=0xCAFE in tuser AND CQE word2[31:16] | host shadow word2[31:16]==0xCAFE | TBD |
| B021 | D | `cnt_cqe_posted` increments exactly once | 1 | single push | counter delta == 1 after B-OKAY | TBD |
| B022 | D | `cq_tail` advances exactly once | 1 | single push | `cq_tail` 0 -> 1; SVA `sva_full` consistent | TBD |
| B023 | D | `awaddr` exactly equals `cfg_cq_base` for first push | 1 | single push, cfg_cq_base=0x1000_0000_0000_0000 | observed `m_axi_awaddr == cfg_cq_base` | TBD |
| B024 | D | scoreboard lineage tuple matched by env_dbg2 | 1 | single push, env_dbg2 drives sidecar | `meta_retired_e` carries injected `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)` | TBD |

---

## 4. Back-to-back pushes (B025-B036)

Sustained CQE stream while doorbell credit is plentiful. No
backpressure stalls expected.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B025 | D | 2 CQEs back-to-back, depth=256 | 2 | inject 2 CQEs with no inter-beat gap | host_cq_shadow[0..1] match injected order; cq_tail==2 | TBD |
| B026 | D | 4 CQEs back-to-back, depth=256 | 4 | inject 4 CQEs | host_cq_shadow[0..3] match; cq_tail==4 | TBD |
| B027 | D | 8 CQEs back-to-back, depth=256 | 8 | inject 8 CQEs | host_cq_shadow[0..7] match; cq_tail==8 | TBD |
| B028 | D | 16 CQEs back-to-back, depth=256 | 16 | inject 16 CQEs | host_cq_shadow[0..15] match; cnt_cqe_posted==16 | TBD |
| B029 | D | 64 CQEs back-to-back, depth=256 | 64 | inject 64 CQEs | host_cq_shadow[0..63] match | TBD |
| B030 | D | 128 CQEs back-to-back, depth=256 | 128 | inject 128 CQEs | cq_tail==128; counters consistent | TBD |
| B031 | D | 4 CQEs with 1-cycle gap each | 4 | inject 4 CQEs; gap_cycles=1 | each CQE retires before next AW; ordering preserved | TBD |
| B032 | D | 4 CQEs with 4-cycle gap each | 4 | inject 4 CQEs; gap_cycles=4 | same as B031 with longer idle | TBD |
| B033 | D | back-to-back ordering is FIFO (no reordering) | 8 | inject 8 CQEs with sqe_id=0..7 | host_cq_shadow word2[31:16] == 0..7 in order | TBD |
| B034 | D | sustained `dbg_aw_pending` <= 1 in Phase 1 (one push in flight) | 8 | inject 8 CQEs | `dbg_aw_pending` never exceeds 1 during the run | TBD |
| B035 | D | sustained `dbg_b_inflight` <= 1 in Phase 1 | 8 | inject 8 CQEs | `dbg_b_inflight` never exceeds 1 | TBD |
| B036 | D | each round-trip latency equals 5 clk under zero hand-shake lag | 8 | inject 8 CQEs at 0-lag completer | per-CQE wall-clock latency == 5 clk (1 per FSM state) | TBD |

---

## 5. Address arithmetic (B037-B048)

`awaddr` formula and AXI4 invariants: `awsize`, `awlen`, `awburst`,
`wstrb`, `wlast`, alignment.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B037 | D | `awaddr` formula: `cfg_cq_base + cq_tail*64` for cq_tail=0..7 | 8 | inject 8 CQEs | for each AW i, `awaddr == cfg_cq_base + i*64` | TBD |
| B038 | D | `cfg_cq_base` 4 KB-aligned (typical Linux page) | 8 | cfg_cq_base=0x0000_1000_0000_0000 | every awaddr 64 B aligned within the page | TBD |
| B039 | D | `cfg_cq_base` 64 B-aligned (cacheline-aligned) | 8 | cfg_cq_base=0x0000_0000_0000_2040 | every awaddr 64 B aligned | TBD |
| B040 | D | `cfg_cq_base` very high address (AXI 64-bit address space) | 4 | cfg_cq_base=0xFFFF_FFFF_FFFF_FF00 | awaddr arithmetic correct, no overflow on cq_tail*64 | TBD |
| B041 | D | `awsize == $clog2(WQE_BUS_W/8) == 6` (64 B beat) | 1 | single push | observed awsize == 3'd6 every push | TBD |
| B042 | D | `awlen == 0` (single-beat burst) | 1 | single push | observed awlen == 8'd0 every push | TBD |
| B043 | D | `awburst == INCR (2'b01)` | 1 | single push | observed awburst == 2'b01 every push | TBD |
| B044 | D | `wstrb == all-1s` for full cacheline write | 1 | single push | observed wstrb == 64'hFFFF_FFFF_FFFF_FFFF every push | TBD |
| B045 | D | `wlast == 1` on the single beat | 1 | single push | observed wlast==1 coincident with `wvalid&&wready` | TBD |
| B046 | D | `awid` consistent (Phase 1: fixed value or 0) | 4 | inject 4 CQEs | awid stable across pushes; bid==awid for each | TBD |
| B047 | D | `awaddr` never wanders outside `[cfg_cq_base, cfg_cq_base+cfg_cq_depth*64)` | 32 | inject 32 CQEs at depth=16 (forces wraparound) | every awaddr in range; SVA `sva_axi_aw` PASS | TBD |
| B048 | D | wraparound: cq_tail=depth-1 -> next push lands at `cfg_cq_base` | 4 | inject `depth+1` CQEs at depth=4 with doorbell credit released | host_cq_shadow[0] overwritten with second pass's CQE | TBD |

---

## 6. Doorbell credit (B049-B060)

`cq_head_dbl_pulse` updates internal `cq_head`; `cq_full` predicate
holds across credit windows.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B049 | D | doorbell pulse updates `dbg_cur_cq_head_credit` next clk | 1 | pulse `cq_head_dbl_pulse=1` for 1 clk with value=4 | next clk `dbg_cur_cq_head_credit==4` | TBD |
| B050 | D | doorbell value masked by `cfg_cq_depth-1` (depth=16, value=0x18) | 1 | pulse value=0x18, depth=16 | next clk `dbg_cur_cq_head_credit==(0x18 & 0xF)==0x8` | TBD |
| B051 | D | doorbell value at boundary (value==depth-1) | 1 | pulse value=15, depth=16 | `dbg_cur_cq_head_credit==15` | TBD |
| B052 | D | doorbell value at boundary (value==depth) wraps to 0 | 1 | pulse value=16, depth=16 | `dbg_cur_cq_head_credit==0` | TBD |
| B053 | D | doorbell value 0 (no credit) | 1 | pulse value=0 | `dbg_cur_cq_head_credit==0`; if `cq_tail==1`, ring is one-slot full | TBD |
| B054 | D | bulk credit: doorbell jumps from 0 to 8 | 1 | pulse value=8, depth=16 | credit shadow updated atomically | TBD |
| B055 | D | doorbell while DUT is idle | 1 | no CQE traffic; pulse value=4 | only `dbg_cur_cq_head_credit` changes; FSM remains IDLE | TBD |
| B056 | D | two doorbells back-to-back coalesce or apply in order | 2 | pulse value=2, then pulse value=4 | final `dbg_cur_cq_head_credit==4` (last write wins per spec) | TBD |
| B057 | D | `cq_full` predicate: depth=4, push 3 CQEs without credit | 3 | inject 3 CQEs at depth=4, no doorbell | `dbg_cq_full==1` after 3rd retire (cq_tail+1 == cq_head==0) | TBD |
| B058 | D | `cq_full` predicate clears on doorbell | 1 | continue from B057, pulse value=1 | `dbg_cq_full==0` next clk | TBD |
| B059 | D | doorbell pulse exactly 1 clk wide | 1 | pulse value=4 | DUT samples value on the asserted clk; level=0 next clk | TBD |
| B060 | D | doorbell during `cfg_enable=0` still latches | 1 | cfg_enable=0; pulse value=4 | `dbg_cur_cq_head_credit==4` even though no AW issued | TBD |

---

## 7. AXI4-Stream sink (B061-B072)

`s_axis_cqe_*` handshake, `tlast`, `tuser` propagation.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B061 | D | `tready` only high in IDLE && cfg_enable && !cq_full | 1 | single push | observed `tready` window matches the predicate (SVA `sva_cqe_in`) | TBD |
| B062 | D | `tlast` always 1 on a valid beat (1 CQE = 1 beat) | 8 | inject 8 CQEs | every `tvalid&&tready` cycle has `tlast==1` | TBD |
| B063 | D | `tuser` (sqe_id) propagates to host CQE word2[31:16] | 8 | sqe_id varies 0..7 | host_cq_shadow[i].word2[31:16] == i | TBD |
| B064 | D | `tdata` byte-perfect to host_cq_shadow | 8 | random 512-bit payloads | host shadow == injected for each CQE | TBD |
| B065 | D | `tvalid` low while DUT is in AW/W/B (no second push accepted) | 1 | inject 1 CQE, force AW completer to stall | `tvalid&&tready` does not fire again until B retires | TBD |
| B066 | D | sink stalls cleanly when `cq_full=1` | 4 | depth=4, push 4 with no credit | `tready` low after 3rd retire; new CQE waits | TBD |
| B067 | D | sink resumes cleanly after credit released | 4 | continue from B066, pulse 1 credit | next CQE flows; `tready` rises within 1 clk | TBD |
| B068 | D | `tready` does not glitch high during AW state | 1 | single push, sample tready every clk in AW | `tready==0` in AW window | TBD |
| B069 | D | `tready` does not glitch high during W state | 1 | single push, sample tready in W | `tready==0` in W | TBD |
| B070 | D | `tready` does not glitch high during B state | 1 | single push, sample tready in B | `tready==0` in B | TBD |
| B071 | D | `tready` does not glitch high during ADVANCE_TAIL | 1 | single push, sample tready in ADVANCE | `tready==0` in ADVANCE; rises in IDLE next clk | TBD |
| B072 | D | sink rejects CQE with `tlast=0` (illegal in Phase 1) | 1 | drive `tvalid=1, tlast=0` | env_dbg1 driver records this as protocol violation; SVA fires | TBD |

---

## 8. AXI4 master shape (B073-B084)

AW/W/B handshake invariants, completer compatibility, single-beat
single-cacheline write.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B073 | D | `awvalid` stable until `awready` (no withdrawal) | 1 | force awready to wait 4 clk | awvalid stays high across the wait window | TBD |
| B074 | D | `wvalid` stable until `wready` | 1 | force wready to wait 4 clk | wvalid stays high across the wait window | TBD |
| B075 | D | `awvalid` does not appear before W or B issued | 1 | single push, observe order | awvalid -> wvalid -> bvalid in that order | TBD |
| B076 | D | `wvalid` does not appear before AW handshake completes | 1 | force AW wait | wvalid only rises after awvalid&&awready | TBD |
| B077 | D | `bready` rises before bvalid (Phase 1: bready always high in B state) | 1 | single push, force B latency | bready==1 throughout B state regardless of bvalid | TBD |
| B078 | D | one B per AW (no orphan B accepted) | 8 | inject 8 CQEs | scoreboard `outstanding_aw_q` stays balanced | TBD |
| B079 | D | `bid==awid` for each transaction | 4 | inject 4 CQEs with awid varying (Phase 1: awid fixed) | bid matches awid; SVA `sva_axi_b` PASS | TBD |
| B080 | D | AW/W issue order may be parallel (Phase 1: serial) | 1 | single push, observe AW->W timing | AW handshake completes before W; matches FSM | TBD |
| B081 | D | full-cacheline write: 64 B = 8 x 64-bit words atomically observable on host | 1 | single push with distinct 8 words | host shadow snapshot atomic; never partial | TBD |
| B082 | D | `awsize=6` (64 B) is hard-coded for Phase 1 (no other size accepted by RTL) | 1 | single push | static observation; SVA `sva_axi_aw` PASS | TBD |
| B083 | D | AXI4 4 KB rule trivially satisfied (single beat, naturally aligned) | 8 | inject 8 CQEs | each transaction within a 64 B cacheline; never crosses 4 KB | TBD |
| B084 | D | exclusive access (`awlock`, `arlock`) not used in Phase 1 | 1 | single push | awlock=0; arlock not driven (write-only master) | TBD |

---

## 9. DEBUG=1 taps (B085-B096)

Synthesizable observability ports mirror DUT state with no functional
perturbation.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B085 | D | `dbg_cur_cq_tail` mirrors FSM `cq_tail` every clk | 8 | inject 8 CQEs | per-clk `dbg_cur_cq_tail == cq_tail` (predicted by scoreboard) | TBD |
| B086 | D | `dbg_cur_cq_head_credit` mirrors `cq_head` every clk | 4 | inject doorbell sequence | `dbg_cur_cq_head_credit == cq_head` per clk | TBD |
| B087 | D | `dbg_cq_full` matches `((cq_tail+1)&(cq_depth-1))==cq_head` | 8 | depth=4, push to fill | `dbg_cq_full==1` exactly when ring full | TBD |
| B088 | D | `dbg_aw_pending` counts AW issued but B not retired | 4 | force B latency=4 clk | counter rises to 1 during W/B, returns to 0 at retire | TBD |
| B089 | D | `dbg_b_inflight` counts B-channel beats in flight | 4 | force B latency=4 | counter rises to 1 during B wait, returns to 0 | TBD |
| B090 | D | `dbg_ring_full_stall_cyc` is saturating, increments only when `cq_full=1 && cqe_tvalid=1` | 4 | depth=4, push 5 with no credit | counter increments per stall clk; saturates at 32-bit max | TBD |
| B091 | D | `dbg_state` 4-bit encoding stable: IDLE=0, AW=1, W=2, B=3, ADV=4 (or per RTL) | 1 | single push | observed sequence matches the 5-state walk | TBD |
| B092 | D | `dbg_cnt_bresp_error` increments on non-OKAY BRESP | 1 | inject 1 SLVERR (env_dbg1 completer in error mode) | counter==1; cq_tail does not advance (Phase 1 retry) | TBD |
| B093 | D | DEBUG=1 ports tied to 0 at `DEBUG_LEVEL=0` | 1 | DEBUG_PARITY build A | all dbg_* outputs stuck at 0 in build A | TBD |
| B094 | D | DEBUG=1 ports do not perturb m_axi_w/aw/b trace | 1 | DEBUG_PARITY test | byte-identical trace between DEBUG=0 and DEBUG=2 builds | TBD |
| B095 | D | `dbg_*` are flopped (no combinational glitch from internal state) | 8 | inject 8 CQEs | dbg taps stable on each clk edge; no zero-clk glitches | TBD |
| B096 | D | `dbg_state` matches SVA cover bins for FSM transitions | 4 | inject 4 CQEs | every observed FSM transition recorded by `cg_fsm_state` | TBD |

---

## 10. DEBUG=2 lineage (B097-B108)

Sim-only sidecar drives `(sqe_id, retire_seq, origin_dma_done_seq,
push_seq)`; lineage observed at retire matches.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B097 | D | env_dbg2 drives `s_axis_cqe_tuser_meta` synchronously with cqe_tdata | 1 | single push, sidecar=0xCAFE_BABE_DEAD_BEEF | meta_observed_e captured matches injected | TBD |
| B098 | D | `dbg_last_pushed_meta` updates exactly on B-OKAY retire | 1 | single push | meta_retired_e fires once per B-OKAY | TBD |
| B099 | D | lineage tuple's `sqe_id` equals CQE word2[31:16] (host slot) | 4 | inject 4 CQEs with matching sqe_ids | shared scoreboard cross-validates per CQE | TBD |
| B100 | D | `push_seq` strictly monotonic across regression (env_dbg2 sequencer) | 8 | inject 8 CQEs | observed push_seq increments by 1 per CQE | TBD |
| B101 | D | `retire_seq` matches injected order at host slot | 8 | inject 8 CQEs with retire_seq=0..7 | meta_retired_e carries 0..7 in order | TBD |
| B102 | D | `origin_dma_done_seq` carried unchanged through pipeline | 4 | inject 4 CQEs with distinct origin_dma_done_seq | meta_retired_e carries injected origin_dma_done_seq | TBD |
| B103 | D | sidecar tied to 0 at DEBUG_LEVEL=0 (no driver in env_dbg2) | 1 | DEBUG_PARITY build A | sidecar wires statically 0 in build A | TBD |
| B104 | D | sidecar does not appear in synthesizable W payload | 1 | inject 1 CQE with sidecar=0xFFFF... | host_cq_shadow word contents do NOT contain sidecar bits | TBD |
| B105 | D | meta-FIFO depth bounded (Phase 1: depth >= 1) | 4 | inject 4 CQEs back-to-back | sidecar FIFO never overflows; lineage observed in order | TBD |
| B106 | D | sidecar mismatch (env_dbg2 corrupts on inject) is caught by scoreboard | 1 | inject 1 CQE with mismatched sqe_id between cqe_tuser and meta | scoreboard flags lineage mismatch as FAIL (negative test wired in env_dbg2) | TBD |
| B107 | D | env_dbg2's `meta_observed_e` and env_dbg1's `cqe_observed_e` arrive same clk | 4 | inject 4 CQEs | both ports fire on the same `tvalid&&tready` clk | TBD |
| B108 | D | shared scoreboard cross-validates 100% lineage closure for B097-B107 | 1 | replay batch of B097-B107 sequences | zero unmatched lineage at end-of-test | TBD |

---

## 11. MSI-X stub quiescence (B109-B116)

Phase 1: `msix_req` tied 0; `msix_ack` ignored. Verified to never
toggle.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B109 | D | `msix_req==0` at reset deassert | 1 | reset, sample msix_req | msix_req==0 | TBD |
| B110 | D | `msix_req==0` after a single CQE push | 1 | single push | msix_req remains 0 (SVA `sva_msix_quiet`) | TBD |
| B111 | D | `msix_req==0` after 16 back-to-back pushes | 16 | inject 16 CQEs | msix_req never asserts | TBD |
| B112 | D | `msix_vector` reserved (Phase 1: tied or undriven) | 1 | observe msix_vector | static value across run | TBD |
| B113 | D | `msix_ack` pulse ignored (no FSM reaction) | 1 | pulse msix_ack=1 for 1 clk | DUT FSM unchanged; msix_req stays 0 | TBD |
| B114 | D | `msix_ack` held high ignored | 1 | hold msix_ack=1 for 16 clk | no msix_req transition | TBD |
| B115 | D | `msix_ack` race with B-OKAY ignored | 4 | inject 4 CQEs, pulse msix_ack at each B | no msix_req transition | TBD |
| B116 | D | Phase 2 wire-up will replace this section; Phase 1 stub contract is hard | 1 | regression-locked SVA gate | `sva_msix_quiet` PASS for entire bucket regression | TBD |

---

## 12. Sideband counters (B117-B124)

`cnt_cqe_posted` increments per B-OKAY; `cq_tail` mirrors FSM tail.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B117 | D | `cnt_cqe_posted==0` at reset | 1 | reset | counter==0 | TBD |
| B118 | D | `cnt_cqe_posted` increments by 1 per B-OKAY | 8 | inject 8 CQEs | counter==8 at end | TBD |
| B119 | D | `cnt_cqe_posted` does NOT increment on non-OKAY BRESP | 1 | inject 1 SLVERR | counter unchanged | TBD |
| B120 | D | `cnt_cqe_posted` saturating? (Phase 1: 32-bit, plenty of headroom) | 1 | observe over 64 pushes | counter reads 64; no rollover | TBD |
| B121 | D | `cq_tail` shadow always equals predictor | 8 | inject 8 CQEs | per-clk `cq_tail == expected_cq_tail` | TBD |
| B122 | D | `cq_tail` at depth boundary wraps to 0 | 4 | depth=4, push 4 with credit | observed `cq_tail` 0,1,2,3,0 | TBD |
| B123 | D | `cq_tail` and `cnt_cqe_posted` agree mod cfg_cq_depth | 16 | depth=4, push 16 with credit released continuously | `cq_tail == cnt_cqe_posted % depth` at each retire | TBD |
| B124 | D | both counters survive bucket_frame transitions | 8 | inject 8 CQEs across two case boundaries | counters monotonic across bucket boundaries | TBD |

---

## 13. `cfg_enable=0` gating (B125-B128)

Disabled holds `tready` low and produces no AW; doorbell still latches.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B125 | D | `cfg_enable=0` at reset deassert | 1 | reset with cfg_enable=0 | `s_axis_cqe_tready==0`; no AW issued | TBD |
| B126 | D | `cfg_enable=1->0` transition between pushes | 1 | inject 1 CQE, deassert enable, attempt second push | second push waits on tready | TBD |
| B127 | D | doorbell still latches `cq_head` while `cfg_enable=0` | 1 | cfg_enable=0; pulse value=4 | `dbg_cur_cq_head_credit==4` next clk | TBD |
| B128 | D | `cfg_enable=0->1` transition unblocks `tready` | 2 | continue from B126, assert enable | second push completes within 1 clk after enable rises | TBD |
