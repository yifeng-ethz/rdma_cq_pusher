# DV Coverage Summary — `rdma_cq_pusher Phase B`

This page is the coverage summary only. Per-case incremental coverage lives under
[`REPORT/cases/`](REPORT/cases/); per-bucket ordered-merge traces live under
[`REPORT/buckets/`](REPORT/buckets/).

## Legend

✅ pass / closed &middot; ⚠️ partial / below target &middot; ❌ failed / missing evidence &middot; ❓ pending &middot; ℹ️ informational

## Targets vs merged totals

<!-- merged_pct = merge across all evidenced isolated-mode UCDBs across all buckets. -->

| status | metric | merged_pct | target |
|:---:|---|---|---|
| ✅ | stmt | 98.07 | 95.0 |
| ✅ | branch | 94.44 | 90.0 |
| ℹ️ | cond | 63.63 | - |
| ℹ️ | expr | 100.00 | - |
| ✅ | fsm_state | 100.00 | 95.0 |
| ✅ | fsm_trans | 100.00 | 90.0 |
| ✅ | toggle | 100.00 | 80.0 |

## Per-bucket merged totals

| status | bucket | stmt | branch | cond | expr | fsm_state | fsm_trans | toggle |
|:---:|---|---|---|---|---|---|---|---|
| ✅ | [`BASIC`](REPORT/buckets/BASIC.md) | 98.07 | 94.44 | 63.63 | 100.00 | 100.00 | 100.00 | 100.00 |
| ✅ | [`EDGE`](REPORT/buckets/EDGE.md) | 100.00 | 100.00 | 63.63 | 79.16 | 100.00 | 100.00 | 100.00 |
| ✅ | [`PROF`](REPORT/buckets/PROF.md) | 100.00 | 100.00 | 45.45 | 79.16 | 100.00 | 100.00 | 100.00 |
| ✅ | [`ERROR`](REPORT/buckets/ERROR.md) | 98.07 | 94.44 | 63.63 | 100.00 | 100.00 | 100.00 | 100.00 |

## Continuous-frame baselines by build

<!-- one row per bucket_frame / all_buckets_frame signoff run (see REPORT/cross/ for curves). -->

| status | run_id | kind | build | bucket | case_count | stmt | branch | toggle | functional_cross_pct | txns |
|:---:|---|---|---|---|---:|---|---|---|---:|---:|
| ✅ | [`phase_b_all_cases`](REPORT/cross/phase_b_all_cases.md) | isolated_full_regression | phase_b_all_cases | all_buckets | 512 | 98.07 | 94.44 | 100.00 | 100.0 | 530874 |
| ✅ | [`phase_b_basic_bucket`](REPORT/cross/phase_b_basic_bucket.md) | isolated_bucket_merge | phase_b_all_cases | BASIC | 128 | 98.07 | 94.44 | 100.00 | 100.0 | 754 |
| ✅ | [`phase_b_edge_bucket`](REPORT/cross/phase_b_edge_bucket.md) | isolated_bucket_merge | phase_b_all_cases | EDGE | 128 | 100.00 | 100.00 | 100.00 | 100.0 | 143455 |
| ✅ | [`phase_b_prof_bucket`](REPORT/cross/phase_b_prof_bucket.md) | isolated_bucket_merge | phase_b_all_cases | PROF | 128 | 100.00 | 100.00 | 100.00 | 100.0 | 376416 |
| ✅ | [`phase_b_error_bucket`](REPORT/cross/phase_b_error_bucket.md) | isolated_bucket_merge | phase_b_all_cases | ERROR | 128 | 98.07 | 94.44 | 100.00 | 100.0 | 10249 |
| ✅ | [`phase_b_smoke_b001_b002_b003`](REPORT/cross/phase_b_smoke_b001_b002_b003.md) | smoke_triplet_retained | phase_b_all_cases | BASIC | 3 | 98.07 | 94.44 | 100.00 | 100.0 | 0 |

_Regenerate with `python3 ~/.codex/skills/dv-workflow/scripts/dv_report_gen.py <tb>`._
