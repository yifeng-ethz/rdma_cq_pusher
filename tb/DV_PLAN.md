# DV Plan — rdma_cq_pusher

**Companion docs:** `DV_HARNESS.md`, `DV_BASIC.md`, `DV_EDGE.md`,
`DV_PROF.md`, `DV_ERROR.md`, `DV_COV.md`, `DV_CROSS.md`,
`BUG_HISTORY.md`.

**Parent:** `../RTL_PLAN.md` and supercore
`../../rdma_subsystem/ARCHITECTURE_PLAN.md`.

**Status:** Phase 1 unit cosim. The IP is the CQE pusher of the
`rdma_subsystem` supercore. It owns CQ ring head/tail bookkeeping,
issues a single AXI4 write at `cfg_cq_base + cq_tail*64` per CQE, then
advances `cq_tail`. The host polls `cq_tail` (surfaced by the run
manager as `csr.CQ_TAIL`) and returns credit through `cq_head_dbl_pulse`.

The IP follows the **dual-UVM-env DEBUG_LEVEL contract** mandated by
`~/.codex/skills/dv-workflow/SKILL.md` Harness Construction rule 7
(out-of-order datapath debug ladder). See §1 verification scope and
`DV_HARNESS.md` for the env split, parallel regression, and shared
cross-validating scoreboard.

## 1. Verification scope

The DUT is `rdma_cq_pusher` instantiated at `WQE_BUS_W=512`, Phase 1
default geometry. Both `DEBUG_LEVEL=1` (functional with status taps)
and `DEBUG_LEVEL=2` (sim-only lineage sidecar) are exercised in
parallel under one regression. Verification covers exactly the
contract surface enumerated in `RTL_PLAN.md` and the supercore
architecture plan §4 / §5:

1. **CQ ring state**: FW-owned `cq_tail`, doorbell-owned `cq_head`,
   `cq_full` predicate `((cq_tail+1) & (cq_depth-1)) == cq_head`,
   power-of-2 wrap on `cfg_cq_depth`.
2. **4-state push FSM**: `IDLE -> AW -> W -> B -> ADVANCE_TAIL ->
   IDLE`. One AXI4 write per CQE in Phase 1. `awlen=0` (1 beat),
   `awsize = $clog2(WQE_BUS_W/8) = 6`, `awburst = INCR`,
   `wstrb = all-1s`, `wlast = 1`.
3. **Address arithmetic**: `m_axi_awaddr == cfg_cq_base + cq_tail*64`.
   Each transaction is one beat naturally aligned to a 64 B cacheline,
   so the AXI4 4 KB rule is satisfied trivially.
4. **CQE atomicity**: full 64 B beat with `wstrb` all ones. The host
   either sees the entire previous CQE or the entire new CQE, never a
   torn fragment.
5. **AXI4-Stream sink**: one CQE per beat, `s_axis_cqe_tlast=1`,
   `s_axis_cqe_tuser` carries `sqe_id`. `s_axis_cqe_tready =
   !cq_full && (state == IDLE) && cfg_enable`.
6. **Doorbell semantics**: `cq_head` updates atomically on
   `cq_head_dbl_pulse`; `cq_head_dbl_value` is masked by
   `cfg_cq_depth-1`. The deferred-doorbell case (host frees N slots,
   single doorbell) is the canonical credit-restore scenario.
7. **B-channel response**: `m_axi_bresp == OKAY` retires the push and
   advances `cq_tail`; non-OKAY responses are surfaced (Phase 1: error
   counter increments and the FSM does NOT advance, so the same CQE is
   re-attempted on the next IDLE entry).
8. **Sideband counters**: `cnt_cqe_posted` increments exactly once per
   B-channel OKAY; `cq_tail` mirrors the FSM-owned tail pointer.
9. **MSI-X (Phase 1 stub)**: `msix_req` tied to 0; `msix_vector` is a
   reserved port. Verified to never glitch and to ignore `msix_ack`.
10. **`cfg_enable=0` gating**: doorbell pulses still latch `cq_head`,
    but `s_axis_cqe_tready` stays low and no AW transaction is issued.
11. **Reset**: `reset_n=0` clears `cq_tail`, `cq_head`, the FSM to
    IDLE, the latched CQE buffer, and `cnt_cqe_posted`. AW/W/B
    channels return to idle.
12. **DEBUG_LEVEL=1 status taps** (synthesizable observability):
    `dbg_cur_cq_tail`, `dbg_cur_cq_head_credit`, `dbg_cq_full`,
    `dbg_aw_pending`, `dbg_b_inflight`, `dbg_ring_full_stall_cyc`,
    `dbg_state`, `dbg_cnt_bresp_error` mirror DUT state every cycle.
    Adding these must **not** perturb the AXI4-Stream / AXI4 master
    payload — DEBUG=0 vs DEBUG=1 W/AW/B traces are byte-identical
    cycle-for-cycle.
13. **DEBUG_LEVEL=2 lineage sidecar** (sim-only): the per-CQE meta
    sidecar `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)`
    is carried alongside the AXI4-Stream input via
    `s_axis_cqe_tuser_meta`. The DEBUG-2 monitor proves that for
    every host CQ slot observed by the DEBUG-1 monitor, exactly one
    sidecar tuple matches; conversely every injected sidecar lands
    in a CQ slot or is documented as a known drop (e.g. legal
    overwrite, BRESP-error retry).

Out of scope (deferred to Phase 2 or to subsystem cosim):

- Real MSI-X interrupt assertion and host-side ack flow (Phase 2 in
  `rdma_cq_msix.sv`; Phase 1 stub only).
- AXI4 ID interleaving / outstanding > 1 transactions (Phase 1 keeps
  one push in flight at a time).
- Real PCIe HIP / Avalon-MM bridge (Phase 2 boundary).
- Multiple QPs (`N_QP` parameter exists, default 1, scaled later).

## 2. Coverage intent

Refer to `DV_COV.md` for the strict per-bucket tables. The plan tracks:

- **Code coverage** (statement / branch / condition / expression / FSM
  transition / toggle) per QuestaOne 2026.1 conventions, isolated UCDB
  per case plus ordered isolated merge per bucket. Per `dv-workflow`
  rule 6 the per-test isolated UCDB is mandatory.
- **Functional coverage**:
  - `cg_cq_depth_bin`: depth values exercised
    (`{2, 4, 16, 256, 4096, 65536}`).
  - `cg_doorbell_value`: head value bins (head, head+1, head+depth/2,
    head+depth-1, equal to tail, masked-overflow).
  - `cg_fsm_state`: FSM states visited and transitions, including
    `B->B` waitstate transitions when `m_axi_bvalid` is delayed and
    `AW->AW` and `W->W` waitstates when `m_axi_awready` /
    `m_axi_wready` are delayed.
  - `cg_axi_handshake_lag`: cycles between AW valid and AW ready,
    cycles between W valid and W ready, and cycles between W last and
    B first beat (`{0, 1, 2-7, 8-31, 32+}`).
  - `cg_cqe_backpressure`: cycles `s_axis_cqe_tvalid` waits for
    `s_axis_cqe_tready` before a push (`{0, 1, 2-7, 8-31, 32+}`).
  - `cg_doorbell_race`: doorbell pulse during {IDLE, AW, W, B,
    ADVANCE_TAIL}.
  - `cg_bresp`: BRESP value seen (OKAY, EXOKAY-illegal, SLVERR,
    DECERR).
  - `cg_full_distance`: distance between `cq_tail` and `cq_head` bins
    `{0, 1, 2-7, 8-31, 32-127, 128-depth/2, depth/2..depth-1, full}`.
  - `cg_enable_toggle`: enable transitions during a push.
  - `cg_lineage_match` (DEBUG=2 monitor only): per-CQE
    `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)` lineage
    bins. Every observed host CQ slot must hit one bin; unmatched
    slots are a closure blocker.
- **Cross**: `cg_doorbell_race x cg_fsm_state` and
  `cg_axi_handshake_lag x cg_cqe_backpressure` and
  `cg_full_distance x cg_doorbell_race` and
  `cg_lineage_match x cg_doorbell_race` are the four long-run
  baselines documented in `DV_CROSS.md`.

## 3. Bucket inventory

| Bucket | File | Cases | Frozen ID Range |
|--------|------|------:|-----------------|
| BASIC  | `DV_BASIC.md` | 128 | B001-B128 |
| EDGE   | `DV_EDGE.md`  | 128 | E001-E128 |
| PROF   | `DV_PROF.md`  | 128 | P001-P128 |
| ERROR  | `DV_ERROR.md` | 128 | X001-X128 |

Total: 512 directed and constrained-random cases enumerated against the
`rdma_cq_pusher` contract surface. Every case runs under both
`DEBUG_LEVEL=1` and `DEBUG_LEVEL=2` envs in parallel (one DUT
instance, two scoreboard probes; see `DV_HARNESS.md`).

## 4. Sign-off ladders

1. All 512 cases isolated PASS with their per-case isolated UCDB
   recorded in `DV_COV.md`. Each case's PASS must hold for both the
   DEBUG=1 (functional) and DEBUG=2 (lineage) probes; disagreement
   between the two probes is a hard closure blocker.
2. Ordered isolated merged code coverage per bucket meets the targets
   in `DV_COV.md` (`stmt >= 95%`, `branch >= 90%`, `fsm = 100%`,
   `toggle >= 80%`).
3. `bucket_frame_basic`, `bucket_frame_edge`, `bucket_frame_prof`,
   `bucket_frame_error`, and `all_buckets_frame` continuous-frame
   regressions PASS with their merged coverage published in `DV_COV.md`.
4. Functional coverage closure per `DV_CROSS.md` `>= 95%`. The
   `cg_lineage_match` group must hit every observed CQE.
5. `BUG_HISTORY.md` has zero open RTL bugs and any deferred items have
   a recorded blocking reason.
6. Static screen (`rtl-linter-and-checker`) green: Lint = 0, CDC = 0,
   RDC = 0; formal closure on the `rdma_cq_ring_state` head/tail wrap
   proof (`cq_full` invariant) if formal mode is enabled.
7. **DEBUG=1 vs DEBUG=0 functional equivalence**: the DEBUG=1 probe
   captures the W/AW/B trace; a separate single-DUT no-debug regression
   captures the DEBUG=0 W/AW/B trace; the two traces are byte-identical
   per case. This is the synthesizability contract for the DEBUG=1
   ports.

## 5. Test execution modes

Per the dv-workflow contract every case runs in three views:

- `isolated`: fresh DUT, fresh seed, per-case UCDB.
- `bucket_frame`: every case in the bucket runs back-to-back inside one
  continuous frame without DUT restart, in case-id order.
- `all_buckets_frame`: every bucket runs back-to-back, B then E then P
  then X, in case-id order, no DUT restart.

Continuous-frame runs require the harness `bucket_frame` test class
described in `DV_HARNESS.md`. Cases that legally cannot survive a
no-restart frame (e.g. cases that program `cfg_cq_depth` while the FSM
is mid-AW or that drive the IP into a quiescent disabled state followed
by a soft reset) are explicitly marked in the bucket files and split
into legal continuous-frame variants.

## 6. References

- `../RTL_PLAN.md` — DUT contract source of truth (DEBUG_LEVEL knobs).
- `../../rdma_subsystem/ARCHITECTURE_PLAN.md` §4 (AXI4 buses) and §5
  (64 B WQE wire format, CQE word layout).
- `../../rdma_sq_fetcher/tb/DV_PLAN.md` — sibling IP's DV plan in the
  same supercore family; format anchor.
- `../../packet_scheduler/tb/DV_BASIC.md` — bucket file format
  reference (per `dv-workflow` rule 15b).
- `../../ring-buffer_cam/tb/DV_HARNESS.md` — house monitor pattern
  reference: `hit_monitor.sv` (payload), `out_monitor.sv` (egress),
  `debug_monitor.sv` (DUT-internal taps). The dual env in this IP
  factors that pattern: DEBUG=1 env owns payload/egress monitors,
  DEBUG=2 env owns the lineage / sidecar / debug-tap monitor.
- `../../run-control_mgmt/tb/DV_BASIC.md` — companion-doc header and
  `Pass Criteria` semantics.
- `../../histogram_statistics/tb/DV_BASIC.md` — methodology key and
  per-functional-group structure.
- `~/.codex/skills/dv-workflow/SKILL.md` — hard contract; the
  Harness Construction rule 7 (out-of-order datapath debug ladder)
  is the canonical source for the dual `DEBUG_LEVEL` env pattern.

## 7. Risks specific to DV

- **CQ-full propagation** is the only end-to-end backpressure path the
  pusher owns. If the host stalls the doorbell, the pusher must stall
  the CQE stream cleanly without dropping CQEs, and run_manager must in
  turn stall SQE consumption. The unit harness exercises full-detection
  exhaustively (`E001-E064` enumerate every CQ-full corner) so the
  integration TB does not have to rediscover the contract.
- **AXI4 completer latency** is open until the supercore cosim is built.
  The unit harness `axi4_completer` in `DV_HARNESS.md` pins it to
  programmable bins (`{0,1,4,16,64,256}` cycles for AW-ready, W-ready,
  and B-arrival) so the FSM is exercised across the full latency
  space.
- **Atomicity at the host boundary** is asserted by SVA: every cycle
  `m_axi_wvalid && m_axi_wready` must coincide with `m_axi_wlast=1`
  and `m_axi_wstrb` all-ones. Violating either is a silent data
  corruption that the host would only catch on a CQE field mismatch.
- **Endianness**: scoreboard reads CQE as little-endian 8 x 64-bit
  words per architecture plan §5. Diverging from that order in the
  harness silently masks an RTL bit-swap; pinned in `DV_HARNESS.md`.
- **MSI-X stub correctness**: even though Phase 1 ties `msix_req=0`,
  the harness must still bind a sink agent to that port and assert
  `msix_req` never toggles, so a Phase 2 wire-up does not regress the
  Phase 1 quiescence.
- **Doorbell credit window**: see `doc/QUEUE_MATH.md` for the queueing
  analysis. Cases `P065-P096` exercise the credit window calculated
  there.
- **DEBUG=1 must be functionally transparent.** Adding 8 status taps
  to the FSM and ring-state register file is meant to be flop-only
  (no feedback into the data path). The DV ladder must catch any
  drift via a parallel DEBUG=0 trace check (sign-off ladder rung 7).
- **DEBUG=2 sidecar latency.** The sim-only meta-FIFO must drain
  in lockstep with the AXI4 W beat. If the meta-FIFO depth drifts
  from the W/B inflight depth, lineage maps to the wrong host CQ
  slot. Harness asserts strict 1:1 between W beats and meta-FIFO
  pops at the DEBUG=2 monitor.
