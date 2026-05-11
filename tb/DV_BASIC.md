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
| AXI4-Stream sink | 12 | B061-B072 | `s_axis_cqe_tready` gating, `tlast`, `tuser` (rqe_id) propagation | 12/12 |
| AXI4 master shape | 12 | B073-B084 | AW/W/B handshake invariants, `bid==awid`, single-beat full-cacheline write | 12/12 |
| DEBUG=1 taps | 12 | B085-B096 | every `dbg_*` synthesizable port mirrors DUT state, no functional perturbation | 12/12 |
| DEBUG=2 lineage | 12 | B097-B108 | sim-only sidecar drives `(rqe_id, retire_seq, origin_dma_done_seq, push_seq)`, lineage observed at retire | 12/12 |
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
| B001 | D | async reset clears `cq_tail`, `cq_head`, FSM=IDLE, `cnt_cqe_posted=0`, `cq_full=0` | 1 | hold reset_n=0 for 16 clk, release with `cfg_*` programmed and idle stimulus | post-deassert `cq_tail==0`, `cnt_cqe_posted==0`, `dbg_state==IDLE`, `dbg_cq_full==0`, `s_axis_cqe_tready==1` | B001: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B002 | D | reset deassert observed clean on every clk edge | 1 | release reset_n synchronous to clk; sample on every edge for 8 clk | no glitches on `m_axi_aw/w/b_valid` and `s_axis_cqe_tready` follows protocol immediately; coverage duplicate of prior merged baseline after B001; retained for functional scenario check | B002: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B001 |
| B003 | D | reset asserted mid-AW returns master signals to idle | 1 | start one push, assert reset_n in AW state | `m_axi_awvalid==0` next clk; FSM back to IDLE; outstanding AW dropped from harness queue | B003: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B004 | D | reset asserted mid-W returns master signals to idle | 1 | start one push, assert reset_n in W state | `m_axi_wvalid==0` next clk; FSM back to IDLE | B004: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B005 | D | reset asserted mid-B returns master signals to idle | 1 | start one push, hold B latency, assert reset_n in B state | `m_axi_bready==0` after deassert; ledger cleared in scoreboard | B005: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B006 | D | back-to-back resets do not produce phantom counters | 1 | release reset_n, hold 4 clk idle, assert reset_n again | `cnt_cqe_posted==0` after second deassert | B006: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B007 | D | reset clears `cq_full` even after CQ ring filled | 1 | fill ring at depth=4, assert reset_n | `dbg_cq_full==0` and `cq_tail==0` post-deassert; coverage duplicate of prior merged baseline after B006; retained for functional scenario check | B007: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B006 |
| B008 | D | reset propagates through env_dbg2 sidecar without leaking lineage | 1 | drive sidecar lineage on a stuck push, assert reset | `dbg_last_pushed_meta==0` after deassert; coverage duplicate of prior merged baseline after B007; retained for functional scenario check | B008: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B007 |
| B009 | D | reset must not glitch `cq_tail` -> `csr.CQ_TAIL` shadow | 1 | observe `cq_tail` over 16 clk reset window | `cq_tail==0` for entire reset window; coverage duplicate of prior merged baseline after B008; retained for functional scenario check | B009: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B008 |
| B010 | D | bring-up reaches IDLE within 4 clk after deassert | 1 | release reset_n, sample `dbg_state` and `s_axis_cqe_tready` | both stable at IDLE / 1 within 4 clk; coverage duplicate of prior merged baseline after B009; retained for functional scenario check | B010: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B009 |
| B011 | D | reset clears `dbg_ring_full_stall_cyc` saturating counter | 1 | drive ring-full backpressure to accumulate counter, then reset | `dbg_ring_full_stall_cyc==0` post-deassert; coverage duplicate of prior merged baseline after B010; retained for functional scenario check | B011: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B010 |
| B012 | D | reset clears `dbg_cnt_bresp_error` | 1 | inject one SLVERR (deferred to X bucket details), then reset | `dbg_cnt_bresp_error==0` post-deassert; coverage duplicate of prior merged baseline after B011; retained for functional scenario check | B012: rtl/rdma_cq_axi_writer.sv:146 WAITING_B bresp retry/error path; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.slverr; dup=after B011 |

---

## 3. Single-CQE push (B013-B024)

One CQE drives the full 4-state FSM round trip with all
hand-shake bins at zero latency. Verifies the basic dataflow path
end-to-end before stress.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B013 | D | single CQE, depth=256, all-zero hand-shake lag | 1 | inject 1 CQE with deterministic 8x64-bit payload | host_cq_shadow[0]==CQE; `cq_tail==1`; `cnt_cqe_posted==1`; B-OKAY observed once | B013: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B014 | D | FSM walks IDLE -> AW -> W -> B -> ADVANCE -> IDLE | 1 | same as B013 with `dbg_state` capture | `dbg_state` sequence matches the canonical 5-tick round trip; coverage duplicate of prior merged baseline after B013; retained for functional scenario check | B014: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B013 |
| B015 | D | `m_axi_awvalid` only high in AW state | 1 | single push | `awvalid` window aligned with `dbg_state==AW` (SVA `sva_axi_aw`); coverage duplicate of prior merged baseline after B014; retained for functional scenario check | B015: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B014 |
| B016 | D | `m_axi_wvalid` only high in W state | 1 | single push | `wvalid` window aligned with `dbg_state==W`; coverage duplicate of prior merged baseline after B015; retained for functional scenario check | B016: rtl/rdma_cq_axi_writer.sv:106 W channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.w; dup=after B015 |
| B017 | D | `m_axi_bready` only high in B state | 1 | single push | `bready` window aligned with `dbg_state==B`; coverage duplicate of prior merged baseline after B016; retained for functional scenario check | B017: rtl/rdma_cq_axi_writer.sv:111 B channel ready and rtl/rdma_cq_axi_writer.sv:146 WAITING_B; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.b; dup=after B016 |
| B018 | D | one B-OKAY per AW (1:1 retire) | 1 | single push | exactly one `b_observed_e` event with `bresp==OKAY` per `aw_observed_e`; coverage duplicate of prior merged baseline after B017; retained for functional scenario check | B018: rtl/rdma_cq_axi_writer.sv:146 WAITING_B bresp retry/error path; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B017 |
| B019 | D | CQE byte-perfect: each of 8 x 64-bit words preserved | 1 | inject CQE with distinct word values | host_cq_shadow word-i equals injected word-i for i in 0..7; coverage duplicate of prior merged baseline after B018; retained for functional scenario check | B019: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B018 |
| B020 | D | rqe_id propagated via `s_axis_cqe_tuser` to host word2[31:16] | 1 | inject CQE with rqe_id=0xCAFE in tuser AND CQE word2[31:16] | host shadow word2[31:16]==0xCAFE; coverage duplicate of prior merged baseline after B019; retained for functional scenario check | B020: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B019 |
| B021 | D | `cnt_cqe_posted` increments exactly once | 1 | single push | counter delta == 1 after B-OKAY; coverage duplicate of prior merged baseline after B020; retained for functional scenario check | B021: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B020 |
| B022 | D | `cq_tail` advances exactly once | 1 | single push | `cq_tail` 0 -> 1; SVA `sva_full` consistent; coverage duplicate of prior merged baseline after B021; retained for functional scenario check | B022: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B021 |
| B023 | D | `awaddr` exactly equals `cfg_cq_base` for first push | 1 | single push, cfg_cq_base=0x1000_0000_0000_0000 | observed `m_axi_awaddr == cfg_cq_base`; coverage duplicate of prior merged baseline after B022; retained for functional scenario check | B023: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B022 |
| B024 | D | scoreboard lineage tuple matched by env_dbg2 | 1 | single push, env_dbg2 drives sidecar | `meta_retired_e` carries injected `(rqe_id, retire_seq, origin_dma_done_seq, push_seq)`; coverage duplicate of prior merged baseline after B023; retained for functional scenario check | B024: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B023 |

---

## 4. Back-to-back pushes (B025-B036)

Sustained CQE stream while doorbell credit is plentiful. No
backpressure stalls expected.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B025 | D | 2 CQEs back-to-back, depth=256 | 2 | inject 2 CQEs with no inter-beat gap | host_cq_shadow[0..1] match injected order; cq_tail==2 | B025: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B026 | D | 4 CQEs back-to-back, depth=256 | 4 | inject 4 CQEs | host_cq_shadow[0..3] match; cq_tail==4 | B026: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B027 | D | 8 CQEs back-to-back, depth=256 | 8 | inject 8 CQEs | host_cq_shadow[0..7] match; cq_tail==8 | B027: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B028 | D | 16 CQEs back-to-back, depth=256 | 16 | inject 16 CQEs | host_cq_shadow[0..15] match; cnt_cqe_posted==16 | B028: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B029 | D | 64 CQEs back-to-back, depth=256 | 64 | inject 64 CQEs | host_cq_shadow[0..63] match | B029: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B030 | D | 128 CQEs back-to-back, depth=256 | 128 | inject 128 CQEs | cq_tail==128; counters consistent | B030: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256 |
| B031 | D | 4 CQEs with 1-cycle gap each | 4 | inject 4 CQEs; gap_cycles=1 | each CQE retires before next AW; ordering preserved; coverage duplicate of prior merged baseline after B030; retained for functional scenario check | B031: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B030 |
| B032 | D | 4 CQEs with 4-cycle gap each | 4 | inject 4 CQEs; gap_cycles=4 | same as B031 with longer idle; coverage duplicate of prior merged baseline after B031; retained for functional scenario check | B032: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B031 |
| B033 | D | back-to-back ordering is FIFO (no reordering) | 8 | inject 8 CQEs with rqe_id=0..7 | host_cq_shadow word2[31:16] == 0..7 in order; coverage duplicate of prior merged baseline after B032; retained for functional scenario check | B033: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B032 |
| B034 | D | sustained `dbg_aw_pending` <= 1 in Phase 1 (one push in flight) | 8 | inject 8 CQEs | `dbg_aw_pending` never exceeds 1 during the run; coverage duplicate of prior merged baseline after B033; retained for functional scenario check | B034: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B033 |
| B035 | D | sustained `dbg_b_inflight` <= 1 in Phase 1 | 8 | inject 8 CQEs | `dbg_b_inflight` never exceeds 1; coverage duplicate of prior merged baseline after B034; retained for functional scenario check | B035: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B034 |
| B036 | D | each round-trip latency equals 5 clk under zero hand-shake lag | 8 | inject 8 CQEs at 0-lag completer | per-CQE wall-clock latency == 5 clk (1 per FSM state); coverage duplicate of prior merged baseline after B035; retained for functional scenario check | B036: rtl/rdma_cq_axi_writer.sv:111 B channel ready and rtl/rdma_cq_axi_writer.sv:146 WAITING_B; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.b; dup=after B035 |

---

## 5. Address arithmetic (B037-B048)

`awaddr` formula and AXI4 invariants: `awsize`, `awlen`, `awburst`,
`wstrb`, `wlast`, alignment.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B037 | D | `awaddr` formula: `cfg_cq_base + cq_tail*64` for cq_tail=0..7 | 8 | inject 8 CQEs | for each AW i, `awaddr == cfg_cq_base + i*64`; coverage duplicate of prior merged baseline after B036; retained for functional scenario check | B037: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B036 |
| B038 | D | `cfg_cq_base` 4 KB-aligned (typical Linux page) | 8 | cfg_cq_base=0x0000_1000_0000_0000 | every awaddr 64 B aligned within the page; coverage duplicate of prior merged baseline after B037; retained for functional scenario check | B038: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B037 |
| B039 | D | `cfg_cq_base` 64 B-aligned (cacheline-aligned) | 8 | cfg_cq_base=0x0000_0000_0000_2040 | every awaddr 64 B aligned; coverage duplicate of prior merged baseline after B038; retained for functional scenario check | B039: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B038 |
| B040 | D | `cfg_cq_base` very high address (AXI 64-bit address space) | 4 | cfg_cq_base=0xFFFF_FFFF_FFFF_FF00 | awaddr arithmetic correct, no overflow on cq_tail*64; coverage duplicate of prior merged baseline after B039; retained for functional scenario check | B040: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B039 |
| B041 | D | `awsize == $clog2(WQE_BUS_W/8) == 6` (64 B beat) | 1 | single push | observed awsize == 3'd6 every push; coverage duplicate of prior merged baseline after B040; retained for functional scenario check | B041: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B040 |
| B042 | D | `awlen == 0` (single-beat burst) | 1 | single push | observed awlen == 8'd0 every push; coverage duplicate of prior merged baseline after B041; retained for functional scenario check | B042: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B041 |
| B043 | D | `awburst == INCR (2'b01)` | 1 | single push | observed awburst == 2'b01 every push; coverage duplicate of prior merged baseline after B042; retained for functional scenario check | B043: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B042 |
| B044 | D | `wstrb == all-1s` for full cacheline write | 1 | single push | observed wstrb == 64'hFFFF_FFFF_FFFF_FFFF every push; coverage duplicate of prior merged baseline after B043; retained for functional scenario check | B044: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B043 |
| B045 | D | `wlast == 1` on the single beat | 1 | single push | observed wlast==1 coincident with `wvalid&&wready`; coverage duplicate of prior merged baseline after B044; retained for functional scenario check | B045: rtl/rdma_cq_axi_writer.sv:106 W channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.w; dup=after B044 |
| B046 | D | `awid` consistent (Phase 1: fixed value or 0) | 4 | inject 4 CQEs | awid stable across pushes; bid==awid for each; coverage duplicate of prior merged baseline after B045; retained for functional scenario check | B046: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B045 |
| B047 | D | `awaddr` never wanders outside `[cfg_cq_base, cfg_cq_base+cfg_cq_depth*64)` | 32 | inject 32 CQEs at depth=16 (forces wraparound) | every awaddr in range; SVA `sva_axi_aw` PASS | B047: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d16 |
| B048 | D | wraparound: cq_tail=depth-1 -> next push lands at `cfg_cq_base` | 4 | inject `depth+1` CQEs at depth=4 with doorbell credit released | host_cq_shadow[0] overwritten with second pass's CQE; coverage duplicate of prior merged baseline after B047; retained for functional scenario check | B048: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4; dup=after B047 |

---

## 6. Doorbell credit (B049-B060)

`cq_head_dbl_pulse` updates internal `cq_head`; `cq_full` predicate
holds across credit windows.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B049 | D | doorbell pulse updates `dbg_cur_cq_head_credit` next clk | 1 | pulse `cq_head_dbl_pulse=1` for 1 clk with value=4 | next clk `dbg_cur_cq_head_credit==4`; coverage duplicate of prior merged baseline after B048; retained for functional scenario check | B049: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B048 |
| B050 | D | doorbell value masked by `cfg_cq_depth-1` (depth=16, value=0x18) | 1 | pulse value=0x18, depth=16 | next clk `dbg_cur_cq_head_credit==(0x18 & 0xF)==0x8`; coverage duplicate of prior merged baseline after B049; retained for functional scenario check | B050: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d16; dup=after B049 |
| B051 | D | doorbell value at boundary (value==depth-1) | 1 | pulse value=15, depth=16 | `dbg_cur_cq_head_credit==15`; coverage duplicate of prior merged baseline after B050; retained for functional scenario check | B051: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d16; dup=after B050 |
| B052 | D | doorbell value at boundary (value==depth) wraps to 0 | 1 | pulse value=16, depth=16 | `dbg_cur_cq_head_credit==0`; coverage duplicate of prior merged baseline after B051; retained for functional scenario check | B052: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d16; dup=after B051 |
| B053 | D | doorbell value 0 (no credit) | 1 | pulse value=0 | `dbg_cur_cq_head_credit==0`; if `cq_tail==1`, ring is one-slot full; coverage duplicate of prior merged baseline after B052; retained for functional scenario check | B053: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B052 |
| B054 | D | bulk credit: doorbell jumps from 0 to 8 | 1 | pulse value=8, depth=16 | credit shadow updated atomically; coverage duplicate of prior merged baseline after B053; retained for functional scenario check | B054: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d16; dup=after B053 |
| B055 | D | doorbell while DUT is idle | 1 | no CQE traffic; pulse value=4 | only `dbg_cur_cq_head_credit` changes; FSM remains IDLE; coverage duplicate of prior merged baseline after B054; retained for functional scenario check | B055: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B054 |
| B056 | D | two doorbells back-to-back coalesce or apply in order | 2 | pulse value=2, then pulse value=4 | final `dbg_cur_cq_head_credit==4` (last write wins per spec); coverage duplicate of prior merged baseline after B055; retained for functional scenario check | B056: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B055 |
| B057 | D | `cq_full` predicate: depth=4, push 3 CQEs without credit | 3 | inject 3 CQEs at depth=4, no doorbell | `dbg_cq_full==1` after 3rd retire (cq_tail+1 == cq_head==0); coverage duplicate of prior merged baseline after B056; retained for functional scenario check | B057: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4; dup=after B056 |
| B058 | D | `cq_full` predicate clears on doorbell | 1 | continue from B057, pulse value=1 | `dbg_cq_full==0` next clk; coverage duplicate of prior merged baseline after B057; retained for functional scenario check | B058: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B057 |
| B059 | D | doorbell pulse exactly 1 clk wide | 1 | pulse value=4 | DUT samples value on the asserted clk; level=0 next clk; coverage duplicate of prior merged baseline after B058; retained for functional scenario check | B059: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B058 |
| B060 | D | doorbell during `cfg_enable=0` still latches | 1 | cfg_enable=0; pulse value=4 | `dbg_cur_cq_head_credit==4` even though no AW issued; coverage duplicate of prior merged baseline after B059; retained for functional scenario check | B060: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B059 |

---

## 7. AXI4-Stream sink (B061-B072)

`s_axis_cqe_*` handshake, `tlast`, `tuser` propagation.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B061 | D | `tready` only high in IDLE && cfg_enable && !cq_full | 1 | single push | observed `tready` window matches the predicate (SVA `sva_cqe_in`); coverage duplicate of prior merged baseline after B060; retained for functional scenario check | B061: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B060 |
| B062 | D | `tlast` always 1 on a valid beat (1 CQE = 1 beat) | 8 | inject 8 CQEs | every `tvalid&&tready` cycle has `tlast==1`; coverage duplicate of prior merged baseline after B061; retained for functional scenario check | B062: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B061 |
| B063 | D | `tuser` (rqe_id) propagates to host CQE word2[31:16] | 8 | rqe_id varies 0..7 | host_cq_shadow[i].word2[31:16] == i; coverage duplicate of prior merged baseline after B062; retained for functional scenario check | B063: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B062 |
| B064 | D | `tdata` byte-perfect to host_cq_shadow | 8 | random 512-bit payloads | host shadow == injected for each CQE; coverage duplicate of prior merged baseline after B063; retained for functional scenario check | B064: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B063 |
| B065 | D | `tvalid` low while DUT is in AW/W/B (no second push accepted) | 1 | inject 1 CQE, force AW completer to stall | `tvalid&&tready` does not fire again until B retires; coverage duplicate of prior merged baseline after B064; retained for functional scenario check | B065: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B064 |
| B066 | D | sink stalls cleanly when `cq_full=1` | 4 | depth=4, push 4 with no credit | `tready` low after 3rd retire; new CQE waits; coverage duplicate of prior merged baseline after B065; retained for functional scenario check | B066: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4; dup=after B065 |
| B067 | D | sink resumes cleanly after credit released | 4 | continue from B066, pulse 1 credit | next CQE flows; `tready` rises within 1 clk; coverage duplicate of prior merged baseline after B066; retained for functional scenario check | B067: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B066 |
| B068 | D | `tready` does not glitch high during AW state | 1 | single push, sample tready every clk in AW | `tready==0` in AW window; coverage duplicate of prior merged baseline after B067; retained for functional scenario check | B068: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B067 |
| B069 | D | `tready` does not glitch high during W state | 1 | single push, sample tready in W | `tready==0` in W; coverage duplicate of prior merged baseline after B068; retained for functional scenario check | B069: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B068 |
| B070 | D | `tready` does not glitch high during B state | 1 | single push, sample tready in B | `tready==0` in B; coverage duplicate of prior merged baseline after B069; retained for functional scenario check | B070: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B069 |
| B071 | D | `tready` does not glitch high during ADVANCE_TAIL | 1 | single push, sample tready in ADVANCE | `tready==0` in ADVANCE; rises in IDLE next clk; coverage duplicate of prior merged baseline after B070; retained for functional scenario check | B071: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B070 |
| B072 | D | sink rejects CQE with `tlast=0` (illegal in Phase 1) | 1 | drive `tvalid=1, tlast=0` | env_dbg1 driver records this as protocol violation; SVA fires | B072: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |

---

## 8. AXI4 master shape (B073-B084)

AW/W/B handshake invariants, completer compatibility, single-beat
single-cacheline write.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B073 | D | `awvalid` stable until `awready` (no withdrawal) | 1 | force awready to wait 4 clk | awvalid stays high across the wait window; coverage duplicate of prior merged baseline after B072; retained for functional scenario check | B073: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B072 |
| B074 | D | `wvalid` stable until `wready` | 1 | force wready to wait 4 clk | wvalid stays high across the wait window; coverage duplicate of prior merged baseline after B073; retained for functional scenario check | B074: rtl/rdma_cq_axi_writer.sv:106 W channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.w; dup=after B073 |
| B075 | D | `awvalid` does not appear before W or B issued | 1 | single push, observe order | awvalid -> wvalid -> bvalid in that order; coverage duplicate of prior merged baseline after B074; retained for functional scenario check | B075: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B074 |
| B076 | D | `wvalid` does not appear before AW handshake completes | 1 | force AW wait | wvalid only rises after awvalid&&awready; coverage duplicate of prior merged baseline after B075; retained for functional scenario check | B076: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B075 |
| B077 | D | `bready` rises before bvalid (Phase 1: bready always high in B state) | 1 | single push, force B latency | bready==1 throughout B state regardless of bvalid; coverage duplicate of prior merged baseline after B076; retained for functional scenario check | B077: rtl/rdma_cq_axi_writer.sv:111 B channel ready and rtl/rdma_cq_axi_writer.sv:146 WAITING_B; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.b; dup=after B076 |
| B078 | D | one B per AW (no orphan B accepted) | 8 | inject 8 CQEs | scoreboard `outstanding_aw_q` stays balanced; coverage duplicate of prior merged baseline after B077; retained for functional scenario check | B078: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B077 |
| B079 | D | `bid==awid` for each transaction | 4 | inject 4 CQEs with awid varying (Phase 1: awid fixed) | bid matches awid; SVA `sva_axi_b` PASS; coverage duplicate of prior merged baseline after B078; retained for functional scenario check | B079: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B078 |
| B080 | D | AW/W issue order may be parallel (Phase 1: serial) | 1 | single push, observe AW->W timing | AW handshake completes before W; matches FSM; coverage duplicate of prior merged baseline after B079; retained for functional scenario check | B080: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B079 |
| B081 | D | full-cacheline write: 64 B = 8 x 64-bit words atomically observable on host | 1 | single push with distinct 8 words | host shadow snapshot atomic; never partial; coverage duplicate of prior merged baseline after B080; retained for functional scenario check | B081: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B080 |
| B082 | D | `awsize=6` (64 B) is hard-coded for Phase 1 (no other size accepted by RTL) | 1 | single push | static observation; SVA `sva_axi_aw` PASS; coverage duplicate of prior merged baseline after B081; retained for functional scenario check | B082: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B081 |
| B083 | D | AXI4 4 KB rule trivially satisfied (single beat, naturally aligned) | 8 | inject 8 CQEs | each transaction within a 64 B cacheline; never crosses 4 KB; coverage duplicate of prior merged baseline after B082; retained for functional scenario check | B083: rtl/rdma_cq_axi_writer.sv:106 W channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.w; dup=after B082 |
| B084 | D | exclusive access (`awlock`, `arlock`) not used in Phase 1 | 1 | single push | awlock=0; arlock not driven (write-only master); coverage duplicate of prior merged baseline after B083; retained for functional scenario check | B084: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B083 |

---

## 9. DEBUG=1 taps (B085-B096)

Synthesizable observability ports mirror DUT state with no functional
perturbation.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B085 | D | `dbg_cur_cq_tail` mirrors FSM `cq_tail` every clk | 8 | inject 8 CQEs | per-clk `dbg_cur_cq_tail == cq_tail` (predicted by scoreboard); coverage duplicate of prior merged baseline after B084; retained for functional scenario check | B085: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B084 |
| B086 | D | `dbg_cur_cq_head_credit` mirrors `cq_head` every clk | 4 | inject doorbell sequence | `dbg_cur_cq_head_credit == cq_head` per clk; coverage duplicate of prior merged baseline after B085; retained for functional scenario check | B086: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B085 |
| B087 | D | `dbg_cq_full` matches `((cq_tail+1)&(cq_depth-1))==cq_head` | 8 | depth=4, push to fill | `dbg_cq_full==1` exactly when ring full | B087: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4 |
| B088 | D | `dbg_aw_pending` counts AW issued but B not retired | 4 | force B latency=4 clk | counter rises to 1 during W/B, returns to 0 at retire; coverage duplicate of prior merged baseline after B087; retained for functional scenario check | B088: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B087 |
| B089 | D | `dbg_b_inflight` counts B-channel beats in flight | 4 | force B latency=4 | counter rises to 1 during B wait, returns to 0; coverage duplicate of prior merged baseline after B088; retained for functional scenario check | B089: rtl/rdma_cq_axi_writer.sv:111 B channel ready and rtl/rdma_cq_axi_writer.sv:146 WAITING_B; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.b; dup=after B088 |
| B090 | D | `dbg_ring_full_stall_cyc` is saturating, increments only when `cq_full=1 && cqe_tvalid=1` | 4 | depth=4, push 5 with no credit | counter increments per stall clk; saturates at 32-bit max; coverage duplicate of prior merged baseline after B089; retained for functional scenario check | B090: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4; dup=after B089 |
| B091 | D | `dbg_state` 4-bit encoding stable: IDLE=0, AW=1, W=2, B=3, ADV=4 (or per RTL) | 1 | single push | observed sequence matches the 5-state walk; coverage duplicate of prior merged baseline after B090; retained for functional scenario check | B091: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B090 |
| B092 | D | `dbg_cnt_bresp_error` increments on non-OKAY BRESP | 1 | inject 1 SLVERR (env_dbg1 completer in error mode) | counter==1; cq_tail does not advance (Phase 1 retry) | B092: rtl/rdma_cq_axi_writer.sv:146 WAITING_B bresp retry/error path; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.slverr |
| B093 | D | DEBUG=1 ports tied to 0 at `DEBUG_LEVEL=0` | 1 | DEBUG_PARITY build A | all dbg_* outputs stuck at 0 in build A; coverage duplicate of prior merged baseline after B092; retained for functional scenario check | B093: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B092 |
| B094 | D | DEBUG=1 ports do not perturb m_axi_w/aw/b trace | 1 | DEBUG_PARITY test | byte-identical trace between DEBUG=0 and DEBUG=2 builds; coverage duplicate of prior merged baseline after B093; retained for functional scenario check | B094: rtl/rdma_cq_axi_writer.sv:99 AW channel shape and rtl/rdma_cq_axi_writer.sv:121 axi_write_engine; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.aw; dup=after B093 |
| B095 | D | `dbg_*` are flopped (no combinational glitch from internal state) | 8 | inject 8 CQEs | dbg taps stable on each clk edge; no zero-clk glitches; coverage duplicate of prior merged baseline after B094; retained for functional scenario check | B095: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B094 |
| B096 | D | `dbg_state` matches SVA cover bins for FSM transitions | 4 | inject 4 CQEs | every observed FSM transition recorded by `cg_fsm_state`; coverage duplicate of prior merged baseline after B095; retained for functional scenario check | B096: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B095 |

---

## 10. DEBUG=2 lineage (B097-B108)

Sim-only sidecar drives `(rqe_id, retire_seq, origin_dma_done_seq,
push_seq)`; lineage observed at retire matches.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B097 | D | env_dbg2 drives `s_axis_cqe_tuser_meta` synchronously with cqe_tdata | 1 | single push, sidecar=0xCAFE_BABE_DEAD_BEEF | meta_observed_e captured matches injected; coverage duplicate of prior merged baseline after B096; retained for functional scenario check | B097: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B096 |
| B098 | D | `dbg_last_pushed_meta` updates exactly on B-OKAY retire | 1 | single push | meta_retired_e fires once per B-OKAY; coverage duplicate of prior merged baseline after B097; retained for functional scenario check | B098: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B097 |
| B099 | D | lineage tuple's `rqe_id` equals CQE word2[31:16] (host slot) | 4 | inject 4 CQEs with matching rqe_ids | shared scoreboard cross-validates per CQE; coverage duplicate of prior merged baseline after B098; retained for functional scenario check | B099: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B098 |
| B100 | D | `push_seq` strictly monotonic across regression (env_dbg2 sequencer) | 8 | inject 8 CQEs | observed push_seq increments by 1 per CQE; coverage duplicate of prior merged baseline after B099; retained for functional scenario check | B100: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B099 |
| B101 | D | `retire_seq` matches injected order at host slot | 8 | inject 8 CQEs with retire_seq=0..7 | meta_retired_e carries 0..7 in order; coverage duplicate of prior merged baseline after B100; retained for functional scenario check | B101: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B100 |
| B102 | D | `origin_dma_done_seq` carried unchanged through pipeline | 4 | inject 4 CQEs with distinct origin_dma_done_seq | meta_retired_e carries injected origin_dma_done_seq; coverage duplicate of prior merged baseline after B101; retained for functional scenario check | B102: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B101 |
| B103 | D | sidecar tied to 0 at DEBUG_LEVEL=0 (no driver in env_dbg2) | 1 | DEBUG_PARITY build A | sidecar wires statically 0 in build A; coverage duplicate of prior merged baseline after B102; retained for functional scenario check | B103: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B102 |
| B104 | D | sidecar does not appear in synthesizable W payload | 1 | inject 1 CQE with sidecar=0xFFFF... | host_cq_shadow word contents do NOT contain sidecar bits; coverage duplicate of prior merged baseline after B103; retained for functional scenario check | B104: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B103 |
| B105 | D | meta-FIFO depth bounded (Phase 1: depth >= 1) | 4 | inject 4 CQEs back-to-back | sidecar FIFO never overflows; lineage observed in order; coverage duplicate of prior merged baseline after B104; retained for functional scenario check | B105: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B104 |
| B106 | D | sidecar mismatch (env_dbg2 corrupts on inject) is caught by scoreboard | 1 | inject 1 CQE with mismatched rqe_id between cqe_tuser and meta | scoreboard flags lineage mismatch as FAIL (negative test wired in env_dbg2); coverage duplicate of prior merged baseline after B105; retained for functional scenario check | B106: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B105 |
| B107 | D | env_dbg2's `meta_observed_e` and env_dbg1's `cqe_observed_e` arrive same clk | 4 | inject 4 CQEs | both ports fire on the same `tvalid&&tready` clk; coverage duplicate of prior merged baseline after B106; retained for functional scenario check | B107: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B106 |
| B108 | D | shared scoreboard cross-validates 100% lineage closure for B097-B107 | 1 | replay batch of B097-B107 sequences | zero unmatched lineage at end-of-test; coverage duplicate of prior merged baseline after B107; retained for functional scenario check | B108: rtl/rdma_cq_axi_writer.sv:170 g_debug2_meta.write_meta/dbg_last_pushed_meta; cov=tb/uvm/coverage.sv:47 cg_lineage_match.cp_match.matched; dup=after B107 |

---

## 11. MSI-X stub quiescence (B109-B116)

Phase 1: `msix_req` tied 0; `msix_ack` ignored. Verified to never
toggle.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B109 | D | `msix_req==0` at reset deassert | 1 | reset, sample msix_req | msix_req==0; coverage duplicate of prior merged baseline after B108; retained for functional scenario check | B109: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B108 |
| B110 | D | `msix_req==0` after a single CQE push | 1 | single push | msix_req remains 0 (SVA `sva_msix_quiet`); coverage duplicate of prior merged baseline after B109; retained for functional scenario check | B110: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B109 |
| B111 | D | `msix_req==0` after 16 back-to-back pushes | 16 | inject 16 CQEs | msix_req never asserts; coverage duplicate of prior merged baseline after B110; retained for functional scenario check | B111: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B110 |
| B112 | D | `msix_vector` reserved (Phase 1: tied or undriven) | 1 | observe msix_vector | static value across run; coverage duplicate of prior merged baseline after B111; retained for functional scenario check | B112: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B111 |
| B113 | D | `msix_ack` pulse ignored (no FSM reaction) | 1 | pulse msix_ack=1 for 1 clk | DUT FSM unchanged; msix_req stays 0 | B113: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B114 | D | `msix_ack` held high ignored | 1 | hold msix_ack=1 for 16 clk | no msix_req transition; coverage duplicate of prior merged baseline after B113; retained for functional scenario check | B114: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B113 |
| B115 | D | `msix_ack` race with B-OKAY ignored | 4 | inject 4 CQEs, pulse msix_ack at each B | no msix_req transition; coverage duplicate of prior merged baseline after B114; retained for functional scenario check | B115: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B114 |
| B116 | D | Phase 2 wire-up will replace this section; Phase 1 stub contract is hard | 1 | regression-locked SVA gate | `sva_msix_quiet` PASS for entire bucket regression; coverage duplicate of prior merged baseline after B115; retained for functional scenario check | B116: rtl/rdma_cq_msix.sv:25 msix_req phase1_quiet_req tieoff; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B115 |

---

## 12. Sideband counters (B117-B124)

`cnt_cqe_posted` increments per B-OKAY; `cq_tail` mirrors FSM tail.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B117 | D | `cnt_cqe_posted==0` at reset | 1 | reset | counter==0; coverage duplicate of prior merged baseline after B116; retained for functional scenario check | B117: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle; dup=after B116 |
| B118 | D | `cnt_cqe_posted` increments by 1 per B-OKAY | 8 | inject 8 CQEs | counter==8 at end; coverage duplicate of prior merged baseline after B117; retained for functional scenario check | B118: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B117 |
| B119 | D | `cnt_cqe_posted` does NOT increment on non-OKAY BRESP | 1 | inject 1 SLVERR | counter unchanged; coverage duplicate of prior merged baseline after B118; retained for functional scenario check | B119: rtl/rdma_cq_axi_writer.sv:146 WAITING_B bresp retry/error path; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.slverr; dup=after B118 |
| B120 | D | `cnt_cqe_posted` saturating? (Phase 1: 32-bit, plenty of headroom) | 1 | observe over 64 pushes | counter reads 64; no rollover; coverage duplicate of prior merged baseline after B119; retained for functional scenario check | B120: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B119 |
| B121 | D | `cq_tail` shadow always equals predictor | 8 | inject 8 CQEs | per-clk `cq_tail == expected_cq_tail`; coverage duplicate of prior merged baseline after B120; retained for functional scenario check | B121: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B120 |
| B122 | D | `cq_tail` at depth boundary wraps to 0 | 4 | depth=4, push 4 with credit | observed `cq_tail` 0,1,2,3,0 | B122: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4 |
| B123 | D | `cq_tail` and `cnt_cqe_posted` agree mod cfg_cq_depth | 16 | depth=4, push 16 with credit released continuously | `cq_tail == cnt_cqe_posted % depth` at each retire; coverage duplicate of prior merged baseline after B122; retained for functional scenario check | B123: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d4; dup=after B122 |
| B124 | D | both counters survive bucket_frame transitions | 8 | inject 8 CQEs across two case boundaries | counters monotonic across bucket boundaries; coverage duplicate of prior merged baseline after B123; retained for functional scenario check | B124: rtl/rdma_cq_pusher.sv:106 writer_addr = cfg_cq_base + cq_tail*64; cov=tb/uvm/coverage.sv:37 cg_bresp.cp_resp.okay; dup=after B123 |

---

## 13. `cfg_enable=0` gating (B125-B128)

Disabled holds `tready` low and produces no AW; doorbell still latches.

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B125 | D | `cfg_enable=0` at reset deassert | 1 | reset with cfg_enable=0 | `s_axis_cqe_tready==0`; no AW issued | B125: rtl/rdma_cq_pusher.sv:177 pusher_counters reset and rdma_cq_ring_state.sv:51 ring_bookkeeper reset; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B126 | D | `cfg_enable=1->0` transition between pushes | 1 | inject 1 CQE, deassert enable, attempt second push | second push waits on tready | B126: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
| B127 | D | doorbell still latches `cq_head` while `cfg_enable=0` | 1 | cfg_enable=0; pulse value=4 | `dbg_cur_cq_head_credit==4` next clk; coverage duplicate of prior merged baseline after B126; retained for functional scenario check | B127: rtl/rdma_cq_ring_state.sv:43 ring_depth_mask/ring_next_tail/cq_full; cov=tb/uvm/coverage.sv:14 cg_cq_depth_bin.cp_depth.d256; dup=after B126 |
| B128 | D | `cfg_enable=0->1` transition unblocks `tready` | 2 | continue from B126, assert enable | second push completes within 1 clk after enable rises | B128: rtl/rdma_cq_pusher.sv:101 s_axis_cqe_tready/cqe_stream_well_formed; cov=tb/uvm/coverage.sv:26 cg_fsm_state.cp_state.idle |
