# ✅ phase_b_smoke_b001_b002_b003

**Kind:** `smoke_triplet` &nbsp; **Build:** `rdma_cq_pusher_phase_b_smoke` &nbsp; **Bucket:** `BASIC` &nbsp; **Sequence:** `regress (B001 + B002 + B003 + cross_validate + merge_ucdb)`

## Summary

<!-- field legend:
  case_count              = number of plan cases composed into this run
  effort                  = practical (capped per case) or extensive (full planned stress)
  iter_cap, payload_cap   = practical-mode budget caps
  txns                    = total transactions driven through the DUT in this run
  functional_cross_pct    = functional coverage against DV_CROSS.md (percent)
  queued_overlap          = transactions enqueued before the previous drained
  counter_checks_failed   = scoreboard counter mismatches observed (0 is required for pass)
  unexpected_outputs      = outputs the scoreboard did not predict
-->

| status | field | value |
|:---:|---|---|
| ℹ️ | case_count | `3` |
| ℹ️ | effort | `smoke` |
| ℹ️ | iter_cap | `1` |
| ℹ️ | payload_cap | `1` |
| ℹ️ | txns | `2` |
| ✅ | functional_cross_pct | `100.0` |
| ℹ️ | queued_overlap | `0` |
| ✅ | counter_checks_failed | `0` |
| ✅ | unexpected_outputs | `0` |

## Code coverage

<!-- merged code coverage produced by this single run (not ordered-merged into any bucket). -->

| metric | pct |
|---|---|
| stmt | 61.36 |
| branch | 30.40 |
| cond | 14.01 |
| expr | 65.38 |
| fsm_state | 100.00 |
| fsm_trans | 44.44 |
| toggle | 6.93 |

## Transaction growth curve

<!-- each row is one transaction step: which planned case fired, current functional-cross percent, -->
<!-- delta_bins = number of new cross bins hit at this step; reason = scoreboard checkpoint trigger. -->

❓ no curve data available for this run.

---
_Back to [dashboard](../../DV_REPORT.md)_
