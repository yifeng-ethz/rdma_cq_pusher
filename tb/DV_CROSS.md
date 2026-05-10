# DV Cross - rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_ERROR.md`, `DV_COV.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Status:** establishes the `bucket_frame` and `all_buckets_frame`
continuous-frame baseline runs that serve as the long-run
functional-coverage anchors. Per `dv-workflow` rule 8 these are
mandatory baselines.

This document does **NOT** restate the per-case bucket tables;
those live in `DV_BASIC.md` / `DV_EDGE.md` / `DV_PROF.md` /
`DV_ERROR.md`. This document defines the continuous-frame run
names, the order they execute their constituent cases in, the
harness shape they require, and the closure expectation at the end
of each frame.

---

## 1. Continuous-Frame Baselines

Per `dv-workflow` rule 9, both `bucket_frame` and
`all_buckets_frame` are mandatory baselines. They run all sign-off
bucket cases inside one continuous timeframe with no DUT restart
between cases. Each is run twice -- once at DEBUG_LEVEL=1 and once
at DEBUG_LEVEL=2 -- for the dual-UVM contract (per `DV_HARNESS.md`
§1).

### 1.1 `bucket_frame_basic`

- **Bucket:** BASIC (B001 - B128)
- **Order:** canonical numeric (B001 -> B128)
- **Build matrix:** DEBUG=1 and DEBUG=2 sibling runs
- **Reset profile:** asserted at the start; no reset between cases
- **Random cases:** execute their declared `Iter` count from
  `DV_BASIC.md`
- **Closure expectation:**
  - All directed cases pass; all random cases conserve.
  - Per-bucket merged code coverage published in `DV_COV.md`.
  - DEBUG=2 lineage residual == 0 across the full frame (the
    sim-only meta-FIFO must drain fully because no Phase 1 CQE is
    legally dropped in BASIC; outstanding entries at end-of-frame
    are a hard scoreboard failure).

### 1.2 `bucket_frame_edge`

- **Bucket:** EDGE (E001 - E128)
- **Order:** canonical numeric (E001 -> E128)
- Same dual-build, dual-reset semantics as 1.1.
- EDGE cases include depth-corner runs (`{2, 4, 16, 256, 4096,
  65536}`) and full-stall release sequences. Each case sets its
  own `cfg_cq_depth` and `cfg_cq_base` programmatically because the
  continuous frame does not reset the DUT between cases; cases that
  legally need a fresh `cfg_*` programming embed `seq_pulse_reset`
  themselves rather than depending on the harness.

### 1.3 `bucket_frame_prof`

- **Bucket:** PROF (P001 - P128)
- **Order:** canonical numeric (P001 -> P128)
- Same dual-build, dual-reset semantics. PROF cases include long
  random runs that emit checkpoint UCDBs at log-spaced txn
  boundaries per the dv-workflow checkpoint rule. Total bucket-frame
  txn count is on the order of 50 k -- 200 k CQEs, dominated by the
  P065-P096 credit-window proof and the P097-P128 soak block.

### 1.4 `bucket_frame_error`

- **Bucket:** ERROR (X001 - X128)
- **Order:** canonical numeric (X001 -> X128)
- ERROR cases that depend on a clean reset (e.g. X001-X014 reset
  cases, X100 BRESP-on-reset race) embed `seq_pulse_reset` themselves
  rather than depending on the harness. This lets them participate
  in the continuous-frame baseline without breaking the no-restart
  contract. The X121-X128 final-closure cases are explicit composites
  that finish each major fault subsystem (reset, BRESP, protocol
  violation) inside the continuous frame.

### 1.5 `all_buckets_frame`

- **Order:** `BASIC -> EDGE -> PROF -> ERROR`, each in canonical
  case-id order.
- **Build matrix:** DEBUG=1 and DEBUG=2 sibling runs
- **Closure expectation:**
  - Full sign-off coverage published in `DV_COV.md` `Sign-off Summary`.
  - Cross-build residual reporter (per `DV_HARNESS.md` §4.7) reports
    DEBUG=1 vs DEBUG=2 nominal residuals identical at every CQE
    boundary.
  - DEBUG=2 lineage matcher residual == 0 at end-of-frame; unmatched
    sidecar entries either land in a host CQ slot or are documented
    as known drops (BRESP-error retry, full-stall pending).

---

## 2. Cross-Bucket / Long-Run Coverage Crosses

In addition to the per-bucket continuous frames, the regression
maintains the following cross-coverage points (sampled by the
covergroups in `cov/`):

| Cross | Covergroup | Sample event | What it Proves |
|-------|-----------|---------------|----------------|
| `cg_doorbell_race x cg_fsm_state` | `cov/cov_cross.sv` | every `cq_head_dbl_pulse` | doorbell pulse aligned with each FSM state (IDLE / AW / W / B / ADVANCE_TAIL) at least once |
| `cg_axi_handshake_lag x cg_cqe_backpressure` | `cov/cov_cross.sv` | every CQE retire | every legal AW/W/B-lag bin combined with every legal CQE-stream backpressure bin |
| `cg_full_distance x cg_doorbell_race` | `cov/cov_cross.sv` | every clock | full vs near-full vs empty distance for every doorbell race window |
| `cg_lineage_match x cg_doorbell_race` (DEBUG=2 only) | `cov/cov_lineage.sv` | every B-OKAY retire | sidecar lineage closes for every doorbell race window so reorder / drop / duplicate corner cases are evidence-backed |
| `cg_bresp x cg_fsm_state` | `cov/cov_cross.sv` | every B handshake | each BRESP value (OKAY / SLVERR / DECERR / EXOKAY-illegal) observed in at least one FSM state path |
| `cg_cq_depth_bin x cg_full_distance` | `cov/cov_cross.sv` | every clock | every legal depth value spans the full distance bin range during sign-off |
| `cg_enable_toggle x cg_fsm_state` | `cov/cov_cross.sv` | every `cfg_enable` change | enable falling/rising at every FSM state at least once |

Per `dv-workflow` rule 8, the `bucket_frame` runs collect these
crosses naturally because the long-run continuous frame visits
every covergroup repeatedly; the per-cross totals are reported
alongside the bucket totals in `DV_COV.md`. The four explicit
crosses called out in `DV_PLAN.md` §2 are
`cg_doorbell_race x cg_fsm_state`,
`cg_axi_handshake_lag x cg_cqe_backpressure`,
`cg_full_distance x cg_doorbell_race`, and
`cg_lineage_match x cg_doorbell_race`; the remaining three above are
the supplementary coverage rounds that close the BASIC and EDGE
spaces.

---

## 3. Dual-Build Residual Cross-Check

Per `DV_HARNESS.md` §4.7, the shared scoreboard publishes a
side-by-side residual report after every CQE retire and at the end
of every continuous frame:

| residual | DEBUG=1 build | DEBUG=2 build |
|---|---|---|
| CQEs accepted at AXI4-Stream sink | sum over `cqe_observed_e` | sum over `cqe_observed_e` |
| CQEs posted to host (B-OKAY observed) | sum over `b_observed_e` with `bresp==OKAY` | same |
| BRESP errors counted | `dbg_cnt_bresp_error` | same |
| ingress sidecar entries | n/a | sum over `cqe_meta_observed_e` |
| host-CQ-slot lineage entries | n/a | sum over `lineage_observed_e` |
| meta-FIFO inflight at end-of-frame | n/a | meta-FIFO depth |
| lineage residual | n/a | ingress - emit (must == 0 at end-of-frame except for documented drops: BRESP-error retry, full-stall pending) |
| nominal residual | accepted - posted - bresp_error (must == 0 at end-of-frame except for full-stall pending) | same |

Closure:

- Any non-zero "must == 0" cell at the end of `bucket_frame` or
  `all_buckets_frame` is a closure blocker (with the documented
  exceptions for explicitly-pending cases).
- Any disagreement between the DEBUG=1 nominal residual and the
  DEBUG=2 nominal residual is a closure blocker.
- Any disagreement between the DEBUG=0 trace (transparency check)
  and the DEBUG=1 trace on AW/W/B byte content is a closure blocker
  (sign-off ladder rung 7 in `DV_PLAN.md`).

These checks are sampled at every B-OKAY retire boundary (including
inside continuous frames) so that a regression introducing a coupled
behavior between the dbg_* ports and the synthesizable payload is
caught at the case granularity.

---

## 4. Continuous-Frame Run Logs

Run logs land at `tb/uvm/logs/<debug_level>/<frame_name>.log`. UCDBs
land at `tb/uvm/cov_after/<debug_level>/buckets/<bucket>.ucdb` for
bucket frames and at `tb/uvm/cov_after/<debug_level>/signoff.ucdb`
for the all-buckets frame.

`dv_report_gen.py` aggregates these into the `REPORT/` tree:

- `REPORT/cross/bucket_frame_basic_dbg1.md`
- `REPORT/cross/bucket_frame_basic_dbg2.md`
- ... etc per bucket
- `REPORT/cross/all_buckets_frame_dbg1.md`
- `REPORT/cross/all_buckets_frame_dbg2.md`
- `REPORT/cross/transparency_check_dbg0_vs_dbg1.md` (transparency
  trace check, see `DV_PLAN.md` sign-off ladder rung 7)

Each cross-frame report carries: code coverage, functional cross
percentage, per-txn growth curve (for random cases that emit
checkpoint UCDBs), counter-check summary, and the dual-build
residual table.

---

## 5. Update Protocol

This file is hand-maintained at DV bring-up to define the baselines.
Once the harness and `dv_report_gen.py` aggregator emit the
cross-frame reports, the per-bucket and per-frame totals appear
under `REPORT/` rather than here.
