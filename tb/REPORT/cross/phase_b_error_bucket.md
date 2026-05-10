# ✅ phase_b_error_bucket

**Kind:** `isolated_bucket_merge` &nbsp; **Build:** `phase_b_all_cases` &nbsp; **Bucket:** `ERROR` &nbsp; **Sequence:** `vcover merge error bucket UCDBs`

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
| ℹ️ | case_count | `128` |
| ℹ️ | effort | `full_phase_b` |
| ℹ️ | iter_cap | `plan` |
| ℹ️ | payload_cap | `plan` |
| ℹ️ | txns | `10249` |
| ✅ | functional_cross_pct | `100.0` |
| ℹ️ | queued_overlap | `0` |
| ✅ | counter_checks_failed | `0` |
| ✅ | unexpected_outputs | `0` |

## Code coverage

<!-- merged code coverage produced by this single run (not ordered-merged into any bucket). -->

| metric | pct |
|---|---|
| stmt | 98.07 |
| branch | 94.44 |
| cond | 63.63 |
| expr | 100.00 |
| fsm_state | 100.00 |
| fsm_trans | 100.00 |
| toggle | 100.00 |

## Transaction growth curve

<!-- each row is one transaction step: which planned case fired, current functional-cross percent, -->
<!-- delta_bins = number of new cross bins hit at this step; reason = scoreboard checkpoint trigger. -->

| txn | case | seq | pct | delta_bins | reason |
|---:|---|---|---|---:|---|
| 10249 | `ERROR` | `phase_b_error_bucket` | 100.0 | 128 | scorecard_cross_validate |

---
_Back to [dashboard](../../DV_REPORT.md)_
