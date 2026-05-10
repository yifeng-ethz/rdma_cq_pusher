# rdma_cq_pusher Phase B — REPORT index

**DUT:** `rdma_cq_pusher` &nbsp; **Date:** `2026-05-10` &nbsp;
**RTL variant:** `rdma_cq_pusher_phase_b_smoke` &nbsp; **Seed:** `1`

## Legend

✅ pass / closed / target met &middot; ⚠️ partial / below target / known limitation &middot; ❌ failed / missing evidence &middot; ❓ pending &middot; ℹ️ informational

## Buckets

<!-- click a bucket row to open its ordered-merge trace and linked per-case pages. -->

| status | bucket | planned | evidenced | merged (stmt/branch/cond/expr/fsm_state/fsm_trans/toggle) |
|:---:|---|---:|---:|---|
| ⚠️ | [`BASIC`](buckets/BASIC.md) | 128 | 3 | stmt=61.36, branch=30.40, cond=14.01, expr=65.38, fsm_state=100.00, fsm_trans=44.44, toggle=6.93 |
| ⚠️ | [`EDGE`](buckets/EDGE.md) | 128 | 0 | stmt=n/a, branch=n/a, cond=n/a, expr=n/a, fsm_state=n/a, fsm_trans=n/a, toggle=n/a |
| ⚠️ | [`PROF`](buckets/PROF.md) | 128 | 0 | stmt=n/a, branch=n/a, cond=n/a, expr=n/a, fsm_state=n/a, fsm_trans=n/a, toggle=n/a |
| ⚠️ | [`ERROR`](buckets/ERROR.md) | 128 | 0 | stmt=n/a, branch=n/a, cond=n/a, expr=n/a, fsm_state=n/a, fsm_trans=n/a, toggle=n/a |

## Cross / continuous-frame runs

| status | run_id | kind | build | bucket | seq | txns | cross_pct |
|:---:|---|---|---|---|---|---:|---:|
| ✅ | [`phase_b_smoke_b001_b002_b003`](cross/phase_b_smoke_b001_b002_b003.md) | smoke_triplet | rdma_cq_pusher_phase_b_smoke | BASIC | regress (B001 + B002 + B003 + cross_validate + merge_ucdb) | 2 | 100.0 |

## Random long-run cases

<!-- each random case has a txn_growth page; pages are pending until checkpoint UCDBs exist. -->

| status | case_id | bucket | observed_txn | growth_page |
|:---:|---|---|---:|---|

## Totals

<!-- merged_total_code_coverage is the merge across all evidenced cases in all buckets. -->

- planned_cases = `512`
- evidenced_cases = `3`
- excluded_cases = `?`
- merged total code coverage: `stmt=61.36, branch=30.40, cond=14.01, expr=65.38, fsm_state=100.00, fsm_trans=44.44, toggle=6.93`
- functional coverage: `0.59% (3/512)`

---
_[Dashboard](../DV_REPORT.md) &middot; [Coverage](../DV_COV.md)_
