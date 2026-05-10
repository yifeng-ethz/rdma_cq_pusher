# DV Coverage - rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_ERROR.md`, `DV_CROSS.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Status:** established empty at DV bring-up. Tables populate as the
regression runs and `dv_report_gen.py` aggregates per-case UCDBs.

This file is the per-bucket coverage tracking ledger. It carries the
strict per-bucket testcase tables (5 columns per `dv-workflow` rule
4), the running ordered-isolated merged totals, and the separate
continuous-frame `bucket_frame` / `all_buckets_frame` totals, **for
both DEBUG=1 and DEBUG=2 builds** (per the dual-UVM contract in
`DV_PLAN.md` §1 and `DV_HARNESS.md` §1).

---

## Coverage Targets

| Category | Target | Notes |
|----------|-------:|-------|
| Statement | >= 95 % | per `dv-workflow` skill defaults |
| Branch | >= 90 % | |
| Condition | >= 90 % | |
| Expression | >= 90 % | |
| FSM state / transition | 100 % | only 5 states (IDLE, AW, W, B, ADVANCE_TAIL) plus retry edge |
| Toggle | >= 80 % | |
| Functional (per cg_*) | >= 95 % | per covergroup defined in `DV_PLAN.md` §2 |

Coverage is split per debug-level (DEBUG=1 vs DEBUG=2) build and not
merged across levels (per the dual-UVM contract). Both builds must
hit the targets independently. The DEBUG=1 vs DEBUG=0 transparency
trace check (sign-off ladder rung 7 in `DV_PLAN.md`) is not a
coverage metric but a hard byte-identity gate that runs alongside
the DEBUG=1 regression.

---

## Execution-Mode Baselines

Per `dv-workflow` rule 12, coverage evidence is published in three
ordered baselines:

1. **isolated**: every case run with a fresh DUT reset; UCDB per
   case under `tb/uvm/cov_after/<debug_level>/<case_name>.ucdb`.
2. **`bucket_frame`**: per-bucket continuous-frame run; UCDB at
   `tb/uvm/cov_after/<debug_level>/buckets/<bucket>.ucdb`.
3. **`all_buckets_frame`**: full sign-off frame; UCDB at
   `tb/uvm/cov_after/<debug_level>/signoff.ucdb`.

Case ordering for `bucket_frame` is canonical (`B001 -> B128`,
`E001 -> E128`, `P001 -> P128`, `X001 -> X128`).
`all_buckets_frame` order is `BASIC -> EDGE -> PROF -> ERROR`.

---

## Per-Bucket Tables (DEBUG_LEVEL=1)

### BASIC (B001 - B128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated by dv_report_gen.py from per-case UCDBs_ | | | | |

Running ordered-isolated merged total (DEBUG=1 BASIC): _pending_

`bucket_frame_basic` continuous-frame merged total (DEBUG=1): _pending_

### EDGE (E001 - E128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=1 EDGE): _pending_

`bucket_frame_edge` continuous-frame merged total (DEBUG=1): _pending_

### PROF (P001 - P128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=1 PROF): _pending_

`bucket_frame_prof` continuous-frame merged total (DEBUG=1): _pending_

### ERROR (X001 - X128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=1 ERROR): _pending_

`bucket_frame_error` continuous-frame merged total (DEBUG=1): _pending_

---

## Per-Bucket Tables (DEBUG_LEVEL=2)

### BASIC (B001 - B128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 BASIC): _pending_

`bucket_frame_basic` continuous-frame merged total (DEBUG=2): _pending_

### EDGE (E001 - E128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 EDGE): _pending_

`bucket_frame_edge` continuous-frame merged total (DEBUG=2): _pending_

### PROF (P001 - P128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 PROF): _pending_

`bucket_frame_prof` continuous-frame merged total (DEBUG=2): _pending_

### ERROR (X001 - X128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 ERROR): _pending_

`bucket_frame_error` continuous-frame merged total (DEBUG=2): _pending_

---

## Sign-off Summary

| Build | Bucket | isolated merged total | bucket_frame total | all_buckets_frame total |
|-------|--------|-----------------------|--------------------|--------------------------|
| DEBUG=1 | BASIC | _pending_ | _pending_ | _pending_ |
| DEBUG=1 | EDGE | _pending_ | _pending_ | _pending_ |
| DEBUG=1 | PROF | _pending_ | _pending_ | _pending_ |
| DEBUG=1 | ERROR | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | BASIC | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | EDGE | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | PROF | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | ERROR | _pending_ | _pending_ | _pending_ |

---

## Functional Coverage Groups

Per `DV_PLAN.md` §2, the following covergroups are defined:

| Covergroup | Source file | Sample event | Bin notes |
|-----------|-------------|---------------|-----------|
| `cg_cq_depth_bin` | `cov/cov_doorbell.sv` | every `cfg_cq_depth` programming | bins `{2, 4, 16, 256, 4096, 65536}` |
| `cg_doorbell_value` | `cov/cov_doorbell.sv` | every `cq_head_dbl_pulse` | head, head+1, head+depth/2, head+depth-1, equal to tail, masked-overflow |
| `cg_fsm_state` | `cov/cov_axi.sv` | every clock | FSM states visited and transitions; `B->B` waitstate, `AW->AW` and `W->W` waitstates |
| `cg_axi_handshake_lag` | `cov/cov_axi.sv` | every AW/W/B handshake | AW lag, W lag, W-last to B-first lag, bins `{0, 1, 2-7, 8-31, 32+}` |
| `cg_cqe_backpressure` | `cov/cov_axi.sv` | every CQE acceptance | cycles `s_axis_cqe_tvalid` waits before `tready`, bins `{0, 1, 2-7, 8-31, 32+}` |
| `cg_doorbell_race` | `cov/cov_cross.sv` | every `cq_head_dbl_pulse` | doorbell pulse during {IDLE, AW, W, B, ADVANCE_TAIL} |
| `cg_bresp` | `cov/cov_axi.sv` | every B handshake | BRESP value (OKAY, EXOKAY-illegal, SLVERR, DECERR) |
| `cg_full_distance` | `cov/cov_full.sv` | every clock | distance between `cq_tail` and `cq_head`, bins `{0, 1, 2-7, 8-31, 32-127, 128-depth/2, depth/2..depth-1, full}` |
| `cg_enable_toggle` | `cov/cov_doorbell.sv` | every `cfg_enable` change | enable transitions during a push (mid-AW, mid-W, mid-B, mid-ADV) |
| `cg_lineage_match` | `cov/cov_lineage.sv` (DEBUG=2 only) | every B-OKAY retire | per-CQE `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)` lineage bins; every observed host CQ slot must hit one bin |

Functional coverage is reported per-covergroup at sign-off; closure
target >= 95 % across all hit bins. The `cg_lineage_match` group
must hit every observed CQE; unmatched slots are a closure blocker.

---

## Update Protocol

This file is regenerated by `dv_report_gen.py` after every
regression. Hand edits below this line are the only persistent
surface; everything above is generated.

**Hand-edit notes:**

- _none yet_
