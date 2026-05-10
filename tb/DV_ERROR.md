# DV Error - rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_COV.md`, `DV_CROSS.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** X001-X128
**Total:** 128 cases (0 implemented / 0 waived)

This document collects the reset / fault / illegal / recovery cases
for `rdma_cq_pusher`. Cases are derived from `DV_PLAN.md` §1 (reset,
BRESP error semantics, AXI4 protocol contract, MSI-X stub
quiescence), the AXI4 protocol error contract on the write master,
and the OoO-datapath DEBUG=2 lineage break section of the
dv-workflow skill. Both DEBUG=1 (functional/payload) and DEBUG=2
(sim-only lineage) envs run every X-bucket case in parallel under
one regression. The shared scoreboard cross-validates that the
DEBUG=1 nominal payload trace and the DEBUG=2 lineage tuple track
the same fault and recovery path; disagreement is a hard closure
blocker.

**Methodology key:**
- **D** = Directed (hand-crafted stimulus, single transaction or
  fault injection, deterministic seed)
- **R** = Constrained-random (UVM `rand`/`constraint`; fault
  profile is randomized, multiple transactions per case;
  checkpoint UCDB emitter required for soak cases)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Reset during operation | 14 | X001-X014 | reset_n asserted at every FSM state and every AXI handshake boundary; clean recovery to IDLE; `cq_tail`, `cq_head`, `cnt_cqe_posted`, `dbg_*` taps all clear | 0/14 |
| BRESP error handling | 14 | X015-X028 | non-OKAY BRESP (SLVERR / DECERR) on the write master; `dbg_cnt_bresp_error` increments; Phase 1 retry semantics: `cq_tail` does NOT advance | 0/14 |
| AXI4 master protocol violations on completer input | 12 | X029-X040 | non-compliant inputs from the AXI4 host completer (dropped ready, spurious B, bid mismatch, multiple B per AW); SVA flags; engine does not propagate undefined behavior | 0/12 |
| AXI4-Stream sink illegal sequencing | 8 | X041-X048 | illegal `s_axis_cqe_*` patterns (tlast=0, mid-burst tvalid drop, tuser change while tready=0); SVA flags; engine refuses or latches per spec | 0/8 |
| Doorbell illegal patterns | 8 | X049-X056 | doorbell pulse longer than 1 clk, value above `cfg_cq_depth`, value with high bits set; mask logic clamps cleanly | 0/8 |
| `cfg_enable=0` race conditions | 6 | X057-X062 | enable falling mid-FSM (AW/W/B); pending push completes; new pushes blocked | 0/6 |
| `cfg_*` reprogram in-flight (illegal in Phase 1) | 6 | X063-X068 | reprogramming `cfg_cq_base`/`cfg_cq_depth` while not in IDLE; defined SVA flag; FSM behavior matches spec | 0/6 |
| MSI-X stub poisoning | 6 | X069-X074 | `msix_ack` race vs B-OKAY; sustained `msix_ack=1`; verify Phase 1 `msix_req=0` SVA never trips | 0/6 |
| Recovery sequences | 8 | X075-X082 | engine resumes operation cleanly after BRESP error / reset / illegal stimulus / sustained backpressure release | 0/8 |
| DEBUG=1 fault observability | 6 | X083-X088 | `dbg_*` taps remain consistent during fault scenarios; `dbg_cnt_bresp_error` saturates at 32-bit max | 0/6 |
| DEBUG=2 lineage breaks | 8 | X089-X096 | sim-only meta-FIFO lineage residual under reset, BRESP error, full-stall, sidecar drop / reorder injection | 0/8 |
| Boundary fault timing | 6 | X097-X102 | reset / BRESP error arriving at exact transition cycles (AW handshake, W last, B handshake, ADVANCE_TAIL) | 0/6 |
| Watchdog / hang scenarios | 6 | X103-X108 | engine should not hang silently under stuck completer (awready=0, wready=0, bvalid=0); SVA / scoreboard timeout | 0/6 |
| Multi-step error recovery | 6 | X109-X114 | error chains with multiple recovery hops (BRESP -> reset -> ALIGN-like -> valid; etc.) | 0/6 |
| Random fault soak | 6 | X115-X120 | random fault profile (mixed BRESP, reset, illegal stim, full-stall) over long runs; conservation modulo error semantics | 0/6 |
| Final-closure ERROR cases | 8 | X121-X128 | the final cases that close the ERROR bucket for sign-off; bucket_frame composite at DEBUG=1 and DEBUG=2 | 0/8 |

---

## 2. Reset during operation (X001-X014)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X001 | D | reset_n asserted in IDLE (no in-flight push) | 1 | hold reset_n=0 for 16 clk while DUT is in IDLE | post-deassert `dbg_state==IDLE`, `cq_tail==0`, `cq_head==0`, `cnt_cqe_posted==0`, `dbg_cq_full==0` | FUNC-X001-reset-during-operation-x001-x014-reset-n-asserted-in-idle-no-in-flight |
| X002 | D | reset_n asserted in AW (awvalid pending) | 1 | inject 1 CQE; assert reset_n while awvalid&&!awready | next clk `m_axi_awvalid==0`; FSM back to IDLE; `outstanding_aw_q` cleared in scoreboard | FUNC-X002-reset-during-operation-x001-x014-reset-n-asserted-in-aw-awvalid-pending |
| X003 | D | reset_n asserted in W (wvalid pending) | 1 | inject 1 CQE; force wready=0; assert reset_n in W state | `m_axi_wvalid==0`; FSM back to IDLE | FUNC-X003-reset-during-operation-x001-x014-reset-n-asserted-in-w-wvalid-pending |
| X004 | D | reset_n asserted in B (waiting bvalid) | 1 | inject 1 CQE; force B latency=64 clk; assert reset_n in B | `m_axi_bready==0`; FSM back to IDLE; pending B abandoned | FUNC-X004-reset-during-operation-x001-x014-reset-n-asserted-in-b-waiting-bvalid |
| X005 | D | reset_n asserted in ADVANCE_TAIL | 1 | inject 1 CQE with 0-lag completer; assert reset_n on the ADV state cycle | post-deassert `cq_tail==0` (advance discarded); `cnt_cqe_posted==0` | FUNC-X005-reset-during-operation-x001-x014-reset-n-asserted-in-advance-tail |
| X006 | D | reset_n asserted on the cycle of awvalid && awready | 1 | race: reset on the AW handshake cycle | AW abandoned; B not expected; FSM to IDLE | FUNC-X006-reset-during-operation-x001-x014-reset-n-asserted-on-the-cycle-of-awvalid |
| X007 | D | reset_n asserted on the cycle of wvalid && wready && wlast | 1 | race: reset on the W handshake cycle | B may or may not arrive; FSM to IDLE; scoreboard tolerates either ledger; coverage duplicate of prior merged baseline after X006; retained for functional scenario check | FUNC-X007-reset-during-operation-x001-x014-reset-n-asserted-on-the-cycle-of-wvalid |
| X008 | D | reset_n asserted on the cycle of bvalid && bready | 1 | race: reset on the B handshake cycle | counters cleared; FSM to IDLE; coverage duplicate of prior merged baseline after X007; retained for functional scenario check | FUNC-X008-reset-during-operation-x001-x014-reset-n-asserted-on-the-cycle-of-bvalid |
| X009 | D | reset_n minimum-pulse: 1 clk assertion clears state | 1 | hold reset_n=0 for 1 clk only; release | post-deassert `dbg_state==IDLE`; FSM stable; coverage duplicate of prior merged baseline after X008; retained for functional scenario check | FUNC-X009-reset-during-operation-x001-x014-reset-n-minimum-pulse-1-clk-assertion-clears |
| X010 | D | reset_n long-pulse: 1024 clk assertion does not corrupt state | 1 | hold reset_n=0 for 1024 clk; release | post-deassert all counters at 0; bring-up reaches `tready=1` within 4 clk; coverage duplicate of prior merged baseline after X009; retained for functional scenario check | FUNC-X010-reset-during-operation-x001-x014-reset-n-long-pulse-1024-clk-assertion-does |
| X011 | D | reset_n asserted while ring is full (depth=4 with 3 retired CQEs, no credit) | 1 | fill ring; assert reset_n | post-deassert `dbg_cq_full==0`, `cq_tail==0`, host_cq_shadow ledger cleared; coverage duplicate of prior merged baseline after X010; retained for functional scenario check | FUNC-X011-reset-during-operation-x001-x014-reset-n-asserted-while-ring-is-full-depth |
| X012 | D | reset_n asserted with `dbg_ring_full_stall_cyc` accumulated | 1 | drive ring-full backpressure for 64 clk to accumulate counter; assert reset_n | post-deassert `dbg_ring_full_stall_cyc==0`; coverage duplicate of prior merged baseline after X011; retained for functional scenario check | FUNC-X012-reset-during-operation-x001-x014-reset-n-asserted-with-dbg-ring-full-stall |
| X013 | D | reset_n asserted with `dbg_cnt_bresp_error` accumulated | 1 | inject 1 SLVERR (deferred X-bucket setup), counter==1; assert reset_n | post-deassert `dbg_cnt_bresp_error==0`; coverage duplicate of prior merged baseline after X012; retained for functional scenario check | FUNC-X013-reset-during-operation-x001-x014-reset-n-asserted-with-dbg-cnt-bresp-error |
| X014 | D | back-to-back reset_n pulses (10 in succession) do not produce phantom counters | 1 | toggle reset_n 10 times | post-final-deassert all counters at 0; FSM in IDLE; coverage duplicate of prior merged baseline after X013; retained for functional scenario check | FUNC-X014-reset-during-operation-x001-x014-back-to-back-reset-n-pulses-10-in |

---

## 3. BRESP error handling (X015-X028)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X015 | D | BRESP=SLVERR (2'b10) on a single CQE push | 1 | inject 1 CQE; completer returns SLVERR | `dbg_cnt_bresp_error==1`; `cq_tail==0` (no advance per Phase 1 retry); `cnt_cqe_posted==0` | FUNC-X015-bresp-error-handling-x015-x028-bresp-slverr-2-b10-on-a-single-cqe |
| X016 | D | BRESP=DECERR (2'b11) on a single CQE push | 1 | inject 1 CQE; completer returns DECERR | `dbg_cnt_bresp_error==1`; `cq_tail==0`; `cnt_cqe_posted==0` | FUNC-X016-bresp-error-handling-x015-x028-bresp-decerr-2-b11-on-a-single-cqe |
| X017 | D | BRESP=EXOKAY (2'b01) on a single CQE push (illegal for single-id master) | 1 | completer returns EXOKAY | SVA `sva_axi_b` flags; scoreboard records EXOKAY-illegal as a BRESP error; coverage duplicate of prior merged baseline after X016; retained for functional scenario check | FUNC-X017-bresp-error-handling-x015-x028-bresp-exokay-2-b01-on-a-single-cqe |
| X018 | D | BRESP=SLVERR retry: same CQE re-attempted on next IDLE entry | 1 | inject 1 CQE; first push gets SLVERR; second attempt gets OKAY | first push errored, second push posts; `cnt_cqe_posted==1`; `cq_tail==1`; coverage duplicate of prior merged baseline after X017; retained for functional scenario check | FUNC-X018-bresp-error-handling-x015-x028-bresp-slverr-retry-same-cqe-re-attempted-on |
| X019 | D | BRESP=SLVERR on the first of 4 back-to-back CQEs | 4 | inject 4 CQEs; first B = SLVERR, rest = OKAY | `dbg_cnt_bresp_error==1`; first CQE retries until OKAY; final `cq_tail` consistent | FUNC-X019-bresp-error-handling-x015-x028-bresp-slverr-on-the-first-of-4-back |
| X020 | D | BRESP=SLVERR on the last of 4 back-to-back CQEs | 4 | inject 4 CQEs; last B = SLVERR | error captured on last; first 3 land in slots 0..2; 4th retries; coverage duplicate of prior merged baseline after X019; retained for functional scenario check | FUNC-X020-bresp-error-handling-x015-x028-bresp-slverr-on-the-last-of-4-back |
| X021 | D | BRESP=SLVERR on every B for 10 pushes (sustained error) | 10 | all B = SLVERR | `dbg_cnt_bresp_error==10` (or saturated count); no engine hang; `cq_tail==0` | FUNC-X021-bresp-error-handling-x015-x028-bresp-slverr-on-every-b-for-10-pushes |
| X022 | D | BRESP=DECERR followed by OKAY | 2 | first B = DECERR; second B = OKAY | first errors; second push posts; final state consistent; coverage duplicate of prior merged baseline after X021; retained for functional scenario check | FUNC-X022-bresp-error-handling-x015-x028-bresp-decerr-followed-by-okay |
| X023 | D | BRESP=SLVERR with sustained backpressure: error during full-stall release | 1 | depth=4, full state, doorbell credit released; first push gets SLVERR | error captured; `cq_full` re-asserts because `cq_tail` did not advance; coverage duplicate of prior merged baseline after X022; retained for functional scenario check | FUNC-X023-bresp-error-handling-x015-x028-bresp-slverr-with-sustained-backpressure-error-during-f |
| X024 | D | BRESP=SLVERR while `cfg_enable` falls (race) | 1 | during B state, deassert cfg_enable; B = SLVERR | error captured; FSM exits to IDLE; new pushes blocked by enable; coverage duplicate of prior merged baseline after X023; retained for functional scenario check | FUNC-X024-bresp-error-handling-x015-x028-bresp-slverr-while-cfg-enable-falls-race |
| X025 | D | BRESP=SLVERR while doorbell pulse arrives same clk | 1 | race: doorbell on the SLVERR B cycle | both effects observed: error counted, head credit updated; coverage duplicate of prior merged baseline after X024; retained for functional scenario check | FUNC-X025-bresp-error-handling-x015-x028-bresp-slverr-while-doorbell-pulse-arrives-same-clk |
| X026 | D | `dbg_cnt_bresp_error` 32-bit saturating behavior | 1 | inject many SLVERRs to approach saturation | counter saturates at 32-bit max if RTL spec is saturating; otherwise wraps; document observed behavior; coverage duplicate of prior merged baseline after X025; retained for functional scenario check | FUNC-X026-bresp-error-handling-x015-x028-dbg-cnt-bresp-error-32-bit-saturating-behavior |
| X027 | R | random BRESP injection at 1% rate over 1000 CQEs | 1000 | 1% bursts get SLVERR or DECERR | all errors counted in `dbg_cnt_bresp_error`; final `cnt_cqe_posted == 1000 - errors`; conservation holds | FUNC-X027-bresp-error-handling-x015-x028-random-bresp-injection-at-1-rate-over-1000 |
| X028 | R | random BRESP=SLVERR at 10% rate over 100 CQEs | 100 | 10% errors | conservation modulo error semantics; no engine hang; coverage duplicate of prior merged baseline after X027; retained for functional scenario check | FUNC-X028-bresp-error-handling-x015-x028-random-bresp-slverr-at-10-rate-over-100 |

---

## 4. AXI4 master protocol violations on completer input (X029-X040)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X029 | D | completer drops `awready` after asserting (illegal) | 1 | force awready=1 then awready=0 before AW handshake | SVA flags awready withdrawal; engine retains awvalid stable; scoreboard tolerates the contract violation; coverage duplicate of prior merged baseline after X028; retained for functional scenario check | FUNC-X029-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-drops-awready-a |
| X030 | D | completer drops `wready` after asserting | 1 | force wready=1 then wready=0 before W handshake | SVA flags; engine retains wvalid stable; coverage duplicate of prior merged baseline after X029; retained for functional scenario check | FUNC-X030-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-drops-wready-af |
| X031 | D | completer pulses `bvalid` without preceding wlast | 1 | force spurious bvalid before any W beat | SVA flags spurious B; engine ignores (single-id, no outstanding AW); coverage duplicate of prior merged baseline after X030; retained for functional scenario check | FUNC-X031-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-pulses-bvalid-w |
| X032 | D | completer asserts `bvalid` before `wlast` (race) | 1 | inject 1 CQE; force bvalid one clk before wvalid&&wready&&wlast | SVA may flag race; engine waits for wlast then accepts B; coverage duplicate of prior merged baseline after X031; retained for functional scenario check | FUNC-X032-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-asserts-bvalid |
| X033 | D | completer returns `bid` mismatched with `awid` | 1 | inject 1 CQE with awid=0 (Phase 1); completer returns bid=4'hF | SVA `sva_axi_b` flags; engine accepts (single-id) but scoreboard records mismatch; coverage duplicate of prior merged baseline after X032; retained for functional scenario check | FUNC-X033-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-returns-bid-mis |
| X034 | D | completer asserts two `bvalid` for one AW (illegal) | 1 | inject 1 CQE; completer pulses bvalid twice | SVA flags duplicate B; engine ignores second bvalid (no second outstanding AW); coverage duplicate of prior merged baseline after X033; retained for functional scenario check | FUNC-X034-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-asserts-two-bva |
| X035 | D | completer asserts `bvalid` with no preceding AW (orphan B) | 1 | with FSM in IDLE, force bvalid=1 | SVA flags; engine `bready==0` in IDLE so the orphan B is not consumed; coverage duplicate of prior merged baseline after X034; retained for functional scenario check | FUNC-X035-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-asserts-bvalid |
| X036 | D | completer holds `awready=1` indefinitely with no AW issued | 1 | force awready=1 throughout test; FSM in IDLE | engine does not issue spurious AW; `cnt_cqe_posted==0`; coverage duplicate of prior merged baseline after X035; retained for functional scenario check | FUNC-X036-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-holds-awready-1 |
| X037 | D | completer holds `wready=1` indefinitely | 1 | force wready=1; FSM in IDLE | no spurious wvalid; FSM stays in IDLE; coverage duplicate of prior merged baseline after X036; retained for functional scenario check | FUNC-X037-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-holds-wready-1 |
| X038 | D | completer X-injection on `bresp` (sim X-prop check) | 1 | force bresp = 2'bxx on a B handshake | SVA may flag X; scoreboard records as a BRESP error path; engine does not propagate X to wdata or counters; coverage duplicate of prior merged baseline after X037; retained for functional scenario check | FUNC-X038-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-x-injection-on |
| X039 | D | completer X-injection on `bid` | 1 | force bid = X | SVA may flag; engine ignores bid since it is single-id; coverage duplicate of prior merged baseline after X038; retained for functional scenario check | FUNC-X039-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-x-injection-on |
| X040 | D | completer drops `bvalid` after asserting (illegal handshake) | 1 | force bvalid=1 then bvalid=0 before bready samples | SVA flags; engine waits indefinitely for bvalid stable; coverage duplicate of prior merged baseline after X039; retained for functional scenario check | FUNC-X040-axi4-master-protocol-violations-on-completer-input-x029-x040-completer-drops-bvalid-af |

---

## 5. AXI4-Stream sink illegal sequencing (X041-X048)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X041 | D | source asserts `tvalid && !tlast` (illegal: every CQE is one beat) | 1 | drive tvalid=1, tlast=0 | SVA `sva_cqe_in` flags; engine refuses or accepts per RTL spec; scoreboard records the contract violation | FUNC-X041-axi4-stream-sink-illegal-sequencing-x041-x048-source-asserts-tvalid-and-and-tlast-ille |
| X042 | D | source drops `tvalid` after asserting before tready | 1 | tvalid=1, tready=0; drop tvalid mid-handshake | SVA flags tvalid withdrawal; no CQE consumed; coverage duplicate of prior merged baseline after X041; retained for functional scenario check | FUNC-X042-axi4-stream-sink-illegal-sequencing-x041-x048-source-drops-tvalid-after-asserting-befo |
| X043 | D | source changes `tdata` while `tvalid=1, tready=0` | 1 | hold tvalid=1, tready=0; flip tdata | SVA flags tdata change while held; engine latches first or final value per spec; coverage duplicate of prior merged baseline after X042; retained for functional scenario check | FUNC-X043-axi4-stream-sink-illegal-sequencing-x041-x048-source-changes-tdata-while-tvalid-1-trea |
| X044 | D | source changes `tuser` while `tvalid=1, tready=0` | 1 | hold tvalid=1, tready=0; flip tuser | SVA flags; sqe_id mapping recorded; coverage duplicate of prior merged baseline after X043; retained for functional scenario check | FUNC-X044-axi4-stream-sink-illegal-sequencing-x041-x048-source-changes-tuser-while-tvalid-1-trea |
| X045 | D | source asserts `tvalid` simultaneously with reset_n falling | 1 | race: tvalid=1 on reset cycle | reset wins; CQE not latched; FSM to IDLE; coverage duplicate of prior merged baseline after X044; retained for functional scenario check | FUNC-X045-axi4-stream-sink-illegal-sequencing-x041-x048-source-asserts-tvalid-simultaneously-wit |
| X046 | D | source asserts `tvalid` while `cfg_enable=0` | 1 | cfg_enable=0; tvalid=1 holding | engine `tready=0`; CQE not consumed; doorbell still latches if pulsed | FUNC-X046-axi4-stream-sink-illegal-sequencing-x041-x048-source-asserts-tvalid-while-cfg-enable-0 |
| X047 | D | source asserts `tvalid` while `cq_full=1` | 1 | depth=4 full; tvalid=1 holding | engine `tready=0`; SVA `sva_full` PASS; CQE waits for credit | FUNC-X047-axi4-stream-sink-illegal-sequencing-x041-x048-source-asserts-tvalid-while-cq-full-1 |
| X048 | D | source asserts `tvalid` with X-injected `tdata` (sim X-prop check) | 1 | force tdata = X on a beat | SVA may flag X; engine still functions on `tvalid && tready` predicate; payload corruption surfaces in the host_cq_shadow check; coverage duplicate of prior merged baseline after X047; retained for functional scenario check | FUNC-X048-axi4-stream-sink-illegal-sequencing-x041-x048-source-asserts-tvalid-with-x-injected-td |

---

## 6. Doorbell illegal patterns (X049-X056)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X049 | D | `cq_head_dbl_pulse` held high for 4 clk (illegal: should be 1 clk) | 1 | hold pulse=1 for 4 clk with value=4 | SVA `sva_doorbell` flags; engine samples first or last value per spec | FUNC-X049-doorbell-illegal-patterns-x049-x056-cq-head-dbl-pulse-held-high-for-4 |
| X050 | D | `cq_head_dbl_pulse` toggled at every clk for 16 clk (rapid pulses) | 16 | pulse=1 every other clk with monotonically increasing value | each pulse latches `cq_head` next clk; final value is the last one written; coverage duplicate of prior merged baseline after X049; retained for functional scenario check | FUNC-X050-doorbell-illegal-patterns-x049-x056-cq-head-dbl-pulse-toggled-at-every-clk |
| X051 | D | doorbell value with high bits set above `cfg_cq_depth` (depth=16, value=0x10001) | 1 | pulse value=0x10001, depth=16 | masked: `dbg_cur_cq_head_credit == (0x10001 & 0xF) == 0x1`; coverage duplicate of prior merged baseline after X050; retained for functional scenario check | FUNC-X051-doorbell-illegal-patterns-x049-x056-doorbell-value-with-high-bits-set-above-cfg |
| X052 | D | doorbell value all-1s (16'hFFFF) at depth=16 | 1 | pulse value=0xFFFF, depth=16 | masked: `dbg_cur_cq_head_credit == 0xF` | FUNC-X052-doorbell-illegal-patterns-x049-x056-doorbell-value-all-1s-16-hffff-at-depth |
| X053 | D | doorbell value all-1s (16'hFFFF) at depth=2 | 1 | pulse value=0xFFFF, depth=2 | masked: `dbg_cur_cq_head_credit == 0x1` | FUNC-X053-doorbell-illegal-patterns-x049-x056-doorbell-value-all-1s-16-hffff-at-depth |
| X054 | D | doorbell pulse on the cycle of reset_n (race) | 1 | race: pulse=1 on reset cycle | reset wins; `cq_head==0` post-deassert; coverage duplicate of prior merged baseline after X053; retained for functional scenario check | FUNC-X054-doorbell-illegal-patterns-x049-x056-doorbell-pulse-on-the-cycle-of-reset-n |
| X055 | D | doorbell pulse with `cfg_cq_depth` newly programmed (illegal: cfg should be static) | 1 | reprogram cfg_cq_depth, then pulse | engine masks against latched depth at the time of pulse; SVA flags reprogram; coverage duplicate of prior merged baseline after X054; retained for functional scenario check | FUNC-X055-doorbell-illegal-patterns-x049-x056-doorbell-pulse-with-cfg-cq-depth-newly-programmed |
| X056 | D | doorbell pulse with X-injected value (sim X-prop check) | 1 | force value=X on a pulse | SVA may flag X; `dbg_cur_cq_head_credit` becomes X next clk; recovers on next legal pulse; coverage duplicate of prior merged baseline after X055; retained for functional scenario check | FUNC-X056-doorbell-illegal-patterns-x049-x056-doorbell-pulse-with-x-injected-value-sim-x |

---

## 7. `cfg_enable=0` race conditions (X057-X062)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X057 | D | `cfg_enable` falls during AW state | 1 | inject 1 CQE; deassert cfg_enable in AW | per RTL spec: pending push completes (FSM has latched the CQE) or aborts; scoreboard records; coverage duplicate of prior merged baseline after X056; retained for functional scenario check | FUNC-X057-cfg-enable-0-race-conditions-x057-x062-cfg-enable-falls-during-aw-state |
| X058 | D | `cfg_enable` falls during W state | 1 | inject 1 CQE; deassert cfg_enable in W | pending W-burst completes; B accepted; FSM returns to IDLE; new pushes blocked; coverage duplicate of prior merged baseline after X057; retained for functional scenario check | FUNC-X058-cfg-enable-0-race-conditions-x057-x062-cfg-enable-falls-during-w-state |
| X059 | D | `cfg_enable` falls during B state | 1 | inject 1 CQE; deassert cfg_enable in B | B handshake completes; FSM returns to IDLE; `cnt_cqe_posted==1`; coverage duplicate of prior merged baseline after X058; retained for functional scenario check | FUNC-X059-cfg-enable-0-race-conditions-x057-x062-cfg-enable-falls-during-b-state |
| X060 | D | `cfg_enable` rises while ring is full | 1 | depth=4 full; deassert/reassert cfg_enable | `tready` gated by full + enable; once enable rises and credit released, push resumes | FUNC-X060-cfg-enable-0-race-conditions-x057-x062-cfg-enable-rises-while-ring-is-full |
| X061 | D | `cfg_enable` toggling at every clk for 16 clk (rapid) | 16 | toggle | engine state machine settles; scoreboard verifies no spurious AW or extra retire; coverage duplicate of prior merged baseline after X060; retained for functional scenario check | FUNC-X061-cfg-enable-0-race-conditions-x057-x062-cfg-enable-toggling-at-every-clk-for-16 |
| X062 | D | `cfg_enable=0` for 1024 clk with sustained `tvalid=1` | 1 | cfg_enable=0 for 1024 clk; source asserts tvalid throughout | `tready==0` for the entire window; no AW issued; counters unchanged; coverage duplicate of prior merged baseline after X061; retained for functional scenario check | FUNC-X062-cfg-enable-0-race-conditions-x057-x062-cfg-enable-0-for-1024-clk-with-sustained |

---

## 8. `cfg_*` reprogram in-flight (illegal in Phase 1) (X063-X068)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X063 | D | `cfg_cq_base` flipped while in AW state (illegal) | 1 | inject 1 CQE; flip cfg_cq_base mid-AW | SVA `sva_axi_aw` may flag; engine uses the originally latched base for that AW; scoreboard records the violation; coverage duplicate of prior merged baseline after X062; retained for functional scenario check | FUNC-X063-cfg-reprogram-in-flight-illegal-in-phase-1-x063-x068-cfg-cq-base-flipped-while-in-aw-s |
| X064 | D | `cfg_cq_depth` flipped while in W state (illegal) | 1 | flip depth mid-W | doorbell mask logic uses latched depth; SVA may flag the change; coverage duplicate of prior merged baseline after X063; retained for functional scenario check | FUNC-X064-cfg-reprogram-in-flight-illegal-in-phase-1-x063-x068-cfg-cq-depth-flipped-while-in-w-s |
| X065 | D | `cfg_cq_base` flipped on the cycle of `cq_head_dbl_pulse` | 1 | race: flip base + pulse same clk | base latches per RTL spec; doorbell value masks against the depth in effect that clk; coverage duplicate of prior merged baseline after X064; retained for functional scenario check | FUNC-X065-cfg-reprogram-in-flight-illegal-in-phase-1-x063-x068-cfg-cq-base-flipped-on-the-cycle |
| X066 | D | `cfg_cq_depth` flipped to a non-power-of-2 value (illegal) | 1 | depth=12 (not power of 2) | SVA flags non-power-of-2; mask logic still operates on the bits but `cq_full` predicate may misbehave; scoreboard records | FUNC-X066-cfg-reprogram-in-flight-illegal-in-phase-1-x063-x068-cfg-cq-depth-flipped-to-a-non-pow |
| X067 | D | `cfg_cq_depth` flipped to 0 (illegal) | 1 | depth=0 | SVA flags; engine masks all bits to 0; `cq_full` always asserted; engine refuses pushes; coverage duplicate of prior merged baseline after X066; retained for functional scenario check | FUNC-X067-cfg-reprogram-in-flight-illegal-in-phase-1-x063-x068-cfg-cq-depth-flipped-to-0-illegal |
| X068 | D | `cfg_cq_depth` flipped to 1 (illegal: must be >=2) | 1 | depth=1 | SVA flags; mask=0; `cq_full` always asserted; coverage duplicate of prior merged baseline after X067; retained for functional scenario check | FUNC-X068-cfg-reprogram-in-flight-illegal-in-phase-1-x063-x068-cfg-cq-depth-flipped-to-1-illegal |

---

## 9. MSI-X stub poisoning (X069-X074)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X069 | D | `msix_ack=1` pulsed during a B-OKAY retire (race) | 1 | inject 1 CQE; pulse msix_ack on the B handshake cycle | SVA `sva_msix_quiet` PASS: `msix_req===0`; FSM unchanged | FUNC-X069-msi-x-stub-poisoning-x069-x074-msix-ack-1-pulsed-during-a-b-okay |
| X070 | D | `msix_ack=1` held high for 1024 clk during 16 sustained pushes | 16 | inject 16 CQEs; msix_ack held high entire run | `msix_req` stays 0; all 16 CQEs post correctly; coverage duplicate of prior merged baseline after X069; retained for functional scenario check | FUNC-X070-msi-x-stub-poisoning-x069-x074-msix-ack-1-held-high-for-1024-clk |
| X071 | D | `msix_ack` toggling at every clk during a sustained 100-CQE run | 100 | inject 100 CQEs; toggle msix_ack | `msix_req===0` at every clk; SVA PASS; coverage duplicate of prior merged baseline after X070; retained for functional scenario check | FUNC-X071-msi-x-stub-poisoning-x069-x074-msix-ack-toggling-at-every-clk-during-a |
| X072 | D | `msix_ack` X-injection (sim X-prop check) | 1 | force msix_ack=X | SVA may flag X; `msix_req` remains a stable constant 0 (Phase 1 stub ties it); coverage duplicate of prior merged baseline after X071; retained for functional scenario check | FUNC-X072-msi-x-stub-poisoning-x069-x074-msix-ack-x-injection-sim-x-prop-check |
| X073 | D | `msix_ack` race with reset_n falling | 1 | race: msix_ack=1 on reset cycle | reset wins; both ports settle to 0; coverage duplicate of prior merged baseline after X072; retained for functional scenario check | FUNC-X073-msi-x-stub-poisoning-x069-x074-msix-ack-race-with-reset-n-falling |
| X074 | D | `msix_ack` race with `cfg_enable` falling | 1 | race: msix_ack=1 on enable falling | `msix_req===0`; FSM behavior unchanged from non-MSI cases; coverage duplicate of prior merged baseline after X073; retained for functional scenario check | FUNC-X074-msi-x-stub-poisoning-x069-x074-msix-ack-race-with-cfg-enable-falling |

---

## 10. Recovery sequences (X075-X082)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X075 | D | recover from BRESP=SLVERR: re-attempt same CQE (Phase 1 retry) | 2 | first push SLVERR; second push OKAY | retry posts; `cnt_cqe_posted==1`; `cq_tail==1`; coverage duplicate of prior merged baseline after X074; retained for functional scenario check | FUNC-X075-recovery-sequences-x075-x082-recover-from-bresp-slverr-re-attempt-same-cqe |
| X076 | D | recover from reset mid-push: fresh CQE after reset | 2 | inject 1 CQE; reset mid-W; release; inject fresh CQE | fresh CQE posts at slot 0; counters consistent post-reset; coverage duplicate of prior merged baseline after X075; retained for functional scenario check | FUNC-X076-recovery-sequences-x075-x082-recover-from-reset-mid-push-fresh-cqe-after |
| X077 | D | recover from full-stall release: 16 CQEs queued, credit released in chunks | 16 | depth=4 full; release credit in pulses of 1 | every CQE posts in order; `cnt_cqe_posted==16`; lineage closure; coverage duplicate of prior merged baseline after X076; retained for functional scenario check | FUNC-X077-recovery-sequences-x075-x082-recover-from-full-stall-release-16-cqes-queued |
| X078 | D | recover from sustained `cfg_enable=0` window | 16 | cfg_enable=0 for 256 clk while source is held; reassert; inject 16 CQEs | all 16 CQEs post after enable rises; coverage duplicate of prior merged baseline after X077; retained for functional scenario check | FUNC-X078-recovery-sequences-x075-x082-recover-from-sustained-cfg-enable-0-window |
| X079 | D | recover from illegal AXI4-Stream beat (tlast=0): subsequent legal beats post | 4 | one illegal beat; then 4 legal CQEs | scoreboard recovers ledger; 4 legal CQEs post; coverage duplicate of prior merged baseline after X078; retained for functional scenario check | FUNC-X079-recovery-sequences-x075-x082-recover-from-illegal-axi4-stream-beat-tlast-0 |
| X080 | D | recover from illegal doorbell value: subsequent legal pulses work | 4 | pulse value=0xFFFF (illegal); pulse value=4 (legal); inject 4 CQEs | masked illegal value clamps to depth-1; subsequent push completes; coverage duplicate of prior merged baseline after X079; retained for functional scenario check | FUNC-X080-recovery-sequences-x075-x082-recover-from-illegal-doorbell-value-subsequent-legal-puls |
| X081 | D | recover from BRESP-error sustained burst: clean run after error window | 32 | 16 SLVERR errors then 16 clean; `dbg_cnt_bresp_error==16` | clean window posts 16 CQEs; final `cnt_cqe_posted==16`; coverage duplicate of prior merged baseline after X080; retained for functional scenario check | FUNC-X081-recovery-sequences-x075-x082-recover-from-bresp-error-sustained-burst-clean-run |
| X082 | D | recover from MSI-X poison (X073/X074 chain) followed by clean run | 8 | run X073 + X074 sequence; then inject 8 CQEs | clean run posts 8 CQEs; SVA `sva_msix_quiet` PASS; coverage duplicate of prior merged baseline after X081; retained for functional scenario check | FUNC-X082-recovery-sequences-x075-x082-recover-from-msi-x-poison-x073-x074-chain |

---

## 11. DEBUG=1 fault observability (X083-X088)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X083 | D | `dbg_*` taps during BRESP=SLVERR | 1 | 1 SLVERR | `dbg_state` walks IDLE -> AW -> W -> B -> IDLE (no ADV); `dbg_cnt_bresp_error==1`; `dbg_aw_pending` returns to 0; coverage duplicate of prior merged baseline after X082; retained for functional scenario check | FUNC-X083-debug-1-fault-observability-x083-x088-dbg-taps-during-bresp-slverr |
| X084 | D | `dbg_*` taps during reset mid-burst | 1 | reset in W | all `dbg_*` taps return to default after reset deassert; `dbg_state==IDLE`; coverage duplicate of prior merged baseline after X083; retained for functional scenario check | FUNC-X084-debug-1-fault-observability-x083-x088-dbg-taps-during-reset-mid-burst |
| X085 | D | `dbg_aw_pending` and `dbg_b_inflight` consistent under sustained backpressure | 1 | force B latency=64 clk | both counters track the in-flight burst; never exceed 1 in Phase 1; coverage duplicate of prior merged baseline after X084; retained for functional scenario check | FUNC-X085-debug-1-fault-observability-x083-x088-dbg-aw-pending-and-dbg-b-inflight-consistent |
| X086 | D | `dbg_ring_full_stall_cyc` saturating semantics | 1 | drive sustained ring-full backpressure | counter saturates at 32-bit max under prolonged stall (or wraps per RTL spec; document observed); coverage duplicate of prior merged baseline after X085; retained for functional scenario check | FUNC-X086-debug-1-fault-observability-x083-x088-dbg-ring-full-stall-cyc-saturating-semantics |
| X087 | D | `dbg_cnt_bresp_error` saturating semantics | 1 | inject many SLVERRs (~2^32 over a soak; surrogate: force RTL counter to near-max) | counter behavior matches RTL spec (saturating or wrapping); coverage duplicate of prior merged baseline after X086; retained for functional scenario check | FUNC-X087-debug-1-fault-observability-x083-x088-dbg-cnt-bresp-error-saturating-semantics |
| X088 | D | `dbg_*` cross-validate against scoreboard predictor under fault | 1 | inject 1 SLVERR | per-clk `dbg_cur_cq_tail == expected_cq_tail`, `dbg_cnt_bresp_error == expected_cnt_bresp_error`; SVA `sva_dbg1_transparency` PASS; coverage duplicate of prior merged baseline after X087; retained for functional scenario check | FUNC-X088-debug-1-fault-observability-x083-x088-dbg-cross-validate-against-scoreboard-predictor |

---

## 12. DEBUG=2 lineage breaks (X089-X096)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X089 | D | force lineage drop (corrupt 1 sidecar entry by TB injection) | 1 | DEBUG=2; corrupt one beat's `s_axis_cqe_tuser_meta` so it does not match the paired CQE | shared scoreboard reports lineage mismatch as expected-anomaly; cross-check failure flagged; coverage duplicate of prior merged baseline after X088; retained for functional scenario check | FUNC-X089-debug-2-lineage-breaks-x089-x096-force-lineage-drop-corrupt-1-sidecar-entry-by |
| X090 | D | force lineage reorder (swap two beats' meta) | 1 | DEBUG=2; swap meta on two consecutive beats | shared scoreboard reports out-of-order lineage; flagged; coverage duplicate of prior merged baseline after X089; retained for functional scenario check | FUNC-X090-debug-2-lineage-breaks-x089-x096-force-lineage-reorder-swap-two-beats-meta |
| X091 | D | force lineage duplicate (resubmit a meta tuple) | 1 | DEBUG=2; replay meta on two beats with the same tuple | shared scoreboard reports duplicate sqe_id at distinct host CQ slots; flagged; coverage duplicate of prior merged baseline after X090; retained for functional scenario check | FUNC-X091-debug-2-lineage-breaks-x089-x096-force-lineage-duplicate-resubmit-a-meta-tuple |
| X092 | D | lineage residual under reset (mid-push) | 1 | DEBUG=2; reset in W with sidecar in flight | meta-FIFO state cleared on reset; shared scoreboard reports lineage residual = un-emitted ingress entries; matcher restarts cleanly; coverage duplicate of prior merged baseline after X091; retained for functional scenario check | FUNC-X092-debug-2-lineage-breaks-x089-x096-lineage-residual-under-reset-mid-push |
| X093 | D | lineage residual under BRESP=SLVERR | 1 | DEBUG=2; 1 SLVERR | meta-FIFO retains the entry (Phase 1 retry); next attempt pops it on B-OKAY; lineage closure; coverage duplicate of prior merged baseline after X092; retained for functional scenario check | FUNC-X093-debug-2-lineage-breaks-x089-x096-lineage-residual-under-bresp-slverr |
| X094 | D | lineage residual under sustained full-stall | 1 | DEBUG=2; depth=4 full with 16 queued upstream | meta-FIFO entries match in-flight CQEs (Phase 1: at most 1); residual tracks the queued upstream; coverage duplicate of prior merged baseline after X093; retained for functional scenario check | FUNC-X094-debug-2-lineage-breaks-x089-x096-lineage-residual-under-sustained-full-stall |
| X095 | D | lineage closure across reset boundary | 1 | DEBUG=2; inject 4 CQEs; reset mid-flow; inject 4 fresh | first batch lineage discarded on reset; second batch lineage closes cleanly; coverage duplicate of prior merged baseline after X094; retained for functional scenario check | FUNC-X095-debug-2-lineage-breaks-x089-x096-lineage-closure-across-reset-boundary |
| X096 | D | meta-FIFO push/pop strict 1:1 with W beats / B-OKAY (SVA `sva_dbg2_lineage`) | 16 | DEBUG=2; sustained 16 CQEs at zero-lag | `sva_dbg2_lineage` PASS: every wvalid&&wready pushes 1; every bvalid&&bready&&bresp==OKAY pops 1; meta-FIFO depth never exceeds inflight AW (Phase 1: <= 1); coverage duplicate of prior merged baseline after X095; retained for functional scenario check | FUNC-X096-debug-2-lineage-breaks-x089-x096-meta-fifo-push-pop-strict-1-1-with |

---

## 13. Boundary fault timing (X097-X102)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X097 | D | reset_n on the cycle of awvalid && awready | 1 | race: reset on AW handshake | AW abandoned; B not expected; FSM to IDLE; meta-FIFO state cleared; coverage duplicate of prior merged baseline after X096; retained for functional scenario check | FUNC-X097-boundary-fault-timing-x097-x102-reset-n-on-the-cycle-of-awvalid-and |
| X098 | D | reset_n on the cycle of wvalid && wready && wlast | 1 | race: reset on W handshake | B may or may not arrive; FSM to IDLE; scoreboard tolerates either ledger; coverage duplicate of prior merged baseline after X097; retained for functional scenario check | FUNC-X098-boundary-fault-timing-x097-x102-reset-n-on-the-cycle-of-wvalid-and |
| X099 | D | reset_n on the cycle of bvalid && bready | 1 | race: reset on B handshake | counters cleared; FSM to IDLE; lineage closes if BRESP==OKAY before reset; otherwise discards; coverage duplicate of prior merged baseline after X098; retained for functional scenario check | FUNC-X099-boundary-fault-timing-x097-x102-reset-n-on-the-cycle-of-bvalid-and |
| X100 | D | BRESP=SLVERR arriving on the cycle of reset_n falling | 1 | race | reset wins; SLVERR is discarded; `dbg_cnt_bresp_error==0` post-deassert; coverage duplicate of prior merged baseline after X099; retained for functional scenario check | FUNC-X100-boundary-fault-timing-x097-x102-bresp-slverr-arriving-on-the-cycle-of-reset |
| X101 | D | doorbell pulse on the cycle of bvalid && bready | 1 | race: pulse on B handshake | both effects observed: `cq_head` updates next clk; `cq_tail` advances on B-OKAY; coverage duplicate of prior merged baseline after X100; retained for functional scenario check | FUNC-X101-boundary-fault-timing-x097-x102-doorbell-pulse-on-the-cycle-of-bvalid-and |
| X102 | D | `cfg_enable` falling on the cycle of awvalid handshake | 1 | race | enable falls; pending push behaviors per RTL spec; new pushes blocked; coverage duplicate of prior merged baseline after X101; retained for functional scenario check | FUNC-X102-boundary-fault-timing-x097-x102-cfg-enable-falling-on-the-cycle-of-awvalid |

---

## 14. Watchdog / hang scenarios (X103-X108)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X103 | D | completer holds `awready=0` indefinitely with one pending CQE | 1 | inject 1 CQE; force awready=0 for 1024 clk | engine waits in AW (legal pause); SVA optional watchdog; coverage duplicate of prior merged baseline after X102; retained for functional scenario check | FUNC-X103-watchdog-hang-scenarios-x103-x108-completer-holds-awready-0-indefinitely-with-one-pend |
| X104 | D | completer holds `wready=0` indefinitely after AW handshake | 1 | inject 1 CQE; AW completes; force wready=0 for 1024 clk | engine waits in W (legal pause); FSM does not advance; coverage duplicate of prior merged baseline after X103; retained for functional scenario check | FUNC-X104-watchdog-hang-scenarios-x103-x108-completer-holds-wready-0-indefinitely-after-aw-hands |
| X105 | D | completer holds `bvalid=0` indefinitely after wlast | 1 | inject 1 CQE; W completes; force bvalid=0 for 1024 clk | engine waits in B (legal pause); FSM does not advance; coverage duplicate of prior merged baseline after X104; retained for functional scenario check | FUNC-X105-watchdog-hang-scenarios-x103-x108-completer-holds-bvalid-0-indefinitely-after-wlast |
| X106 | D | source holds `tvalid=0` indefinitely (no CQE traffic) | 1 | no source traffic for 1M clk | engine remains in IDLE; no spurious AW; counters at 0; coverage duplicate of prior merged baseline after X105; retained for functional scenario check | FUNC-X106-watchdog-hang-scenarios-x103-x108-source-holds-tvalid-0-indefinitely-no-cqe-traffic |
| X107 | D | sustained ring-full with no doorbell credit (engine waits forever) | 1 | depth=4 full; no doorbell pulse for 1024 clk | engine waits in IDLE with `tready=0`; `dbg_cq_full=1` throughout; `dbg_ring_full_stall_cyc` increments while tvalid asserted; coverage duplicate of prior merged baseline after X106; retained for functional scenario check | FUNC-X107-watchdog-hang-scenarios-x103-x108-sustained-ring-full-with-no-doorbell-credit-engine |
| X108 | D | sustained `cfg_enable=0` with source asserting `tvalid` (no progress) | 1 | cfg_enable=0; source tvalid=1 holding for 1024 clk | engine `tready=0`; no AW; counters at 0; coverage duplicate of prior merged baseline after X107; retained for functional scenario check | FUNC-X108-watchdog-hang-scenarios-x103-x108-sustained-cfg-enable-0-with-source-asserting-tvalid |

---

## 15. Multi-step error recovery (X109-X114)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X109 | D | BRESP=SLVERR -> reset -> illegal beat -> valid CQE | 1 | chain | each step cleanly handled; final CQE posts; coverage duplicate of prior merged baseline after X108; retained for functional scenario check | FUNC-X109-multi-step-error-recovery-x109-x114-bresp-slverr-reset-illegal-beat-valid-cqe |
| X110 | D | reset -> reset -> reset -> valid CQE | 1 | triple reset | final CQE posts at slot 0; counters at 1; coverage duplicate of prior merged baseline after X109; retained for functional scenario check | FUNC-X110-multi-step-error-recovery-x109-x114-reset-reset-reset-valid-cqe |
| X111 | D | full-stall -> doorbell credit -> SLVERR -> retry | 1 | full window, credit released, push gets SLVERR, retry posts | retry posts; `cnt_cqe_posted==1`; lineage closes; coverage duplicate of prior merged baseline after X110; retained for functional scenario check | FUNC-X111-multi-step-error-recovery-x109-x114-full-stall-doorbell-credit-slverr-retry |
| X112 | D | cfg_enable=0 mid-push -> reassert -> retry -> SLVERR -> retry | 1 | chain | each step handled; final retry posts; coverage duplicate of prior merged baseline after X111; retained for functional scenario check | FUNC-X112-multi-step-error-recovery-x109-x114-cfg-enable-0-mid-push-reassert-retry-slverr |
| X113 | D | reset -> illegal doorbell value -> valid doorbell -> CQE | 1 | chain | masked illegal value resolves; subsequent push posts; coverage duplicate of prior merged baseline after X112; retained for functional scenario check | FUNC-X113-multi-step-error-recovery-x109-x114-reset-illegal-doorbell-value-valid-doorbell-cqe |
| X114 | D | sustained 100 CQEs with 1% SLVERR + 1 reset mid-run + 1 enable toggle | 100 | mixed | conservation modulo errors; engine recovers each event; `cnt_cqe_posted == 100 - errors`; coverage duplicate of prior merged baseline after X113; retained for functional scenario check | FUNC-X114-multi-step-error-recovery-x109-x114-sustained-100-cqes-with-1-slverr-1-reset |

---

## 16. Random fault soak (X115-X120)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X115 | R | random BRESP injection at 5% rate over 1000 CQEs | 1000 | random | all errors counted; conservation; no engine hang; checkpoint UCDB at log-spaced milestones; coverage duplicate of prior merged baseline after X114; retained for functional scenario check | FUNC-X115-random-fault-soak-x115-x120-random-bresp-injection-at-5-rate-over-1000 |
| X116 | R | random reset every N CQEs (N rand 50..200) over 1000 CQEs | 1000 | random reset | each reset clean; subsequent CQEs post; checkpoint UCDB; coverage duplicate of prior merged baseline after X115; retained for functional scenario check | FUNC-X116-random-fault-soak-x115-x120-random-reset-every-n-cqes-n-rand-50 |
| X117 | R | random cfg_enable toggle at PRNG-shaped rate over 1000 CQEs | 1000 | random toggle | engine state machine settles each window; CQEs post when enabled; coverage duplicate of prior merged baseline after X116; retained for functional scenario check | FUNC-X117-random-fault-soak-x115-x120-random-cfg-enable-toggle-at-prng-shaped-rate |
| X118 | R | random doorbell value (legal + illegal mix) over 500 pushes | 500 | random | masked values clamp; legal values latch; engine progresses; coverage duplicate of prior merged baseline after X117; retained for functional scenario check | FUNC-X118-random-fault-soak-x115-x120-random-doorbell-value-legal-illegal-mix-over-500 |
| X119 | R | random combined fault profile (BRESP + reset + enable + doorbell) over 1000 CQEs | 1000 | mixed | conservation modulo errors; final state consistent; checkpoint UCDB at 1, 2, 4, 8, ..., 1024; coverage duplicate of prior merged baseline after X118; retained for functional scenario check | FUNC-X119-random-fault-soak-x115-x120-random-combined-fault-profile-bresp-reset-enable-doorbell |
| X120 | R | extra-long random combined fault soak: 4096 CQEs | 4096 | as X119, longer | scoreboard PASS; per-txn coverage growth recorded | FUNC-X120-random-fault-soak-x115-x120-extra-long-random-combined-fault-soak-4096-cqes |

---

## 17. Final-closure ERROR cases (X121-X128)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X121 | D | final-closure ERROR composite at DEBUG=1 | 1 | run all error scenarios in one frame at DEBUG=1 | all cases pass; closure; coverage duplicate of prior merged baseline after X120; retained for functional scenario check | FUNC-X121-final-closure-error-cases-x121-x128-final-closure-error-composite-at-debug-1 |
| X122 | D | final-closure ERROR composite at DEBUG=2 | 1 | same composite at DEBUG=2 | lineage closure; cross-build residual report PASS; coverage duplicate of prior merged baseline after X121; retained for functional scenario check | FUNC-X122-final-closure-error-cases-x121-x128-final-closure-error-composite-at-debug-2 |
| X123 | D | DEBUG=1 vs DEBUG=2 cross-variant equivalence on the entire ERROR bucket | 1 | rerun X115 / X119 / X120 on both variants | byte-equivalent payload trace; lineage closure; coverage duplicate of prior merged baseline after X122; retained for functional scenario check | FUNC-X123-final-closure-error-cases-x121-x128-debug-1-vs-debug-2-cross-variant-equivalence |
| X124 | D | ERROR bucket continuous-frame baseline (`bucket_frame_error`) | 1 | run X001 -> X128 in one continuous frame, no DUT restart between cases | every case PASS at its case-boundary check; merged code coverage published; cross-validation PASS; coverage duplicate of prior merged baseline after X123; retained for functional scenario check | FUNC-X124-final-closure-error-cases-x121-x128-error-bucket-continuous-frame-baseline-bucket-fram |
| X125 | D | ERROR bucket reset-injection composite | 1 | every reset-related case (X001-X014, X076, X100, X110) chained back-to-back | engine recovers each time; final state consistent; coverage duplicate of prior merged baseline after X124; retained for functional scenario check | FUNC-X125-final-closure-error-cases-x121-x128-error-bucket-reset-injection-composite |
| X126 | D | ERROR bucket BRESP composite | 1 | every BRESP-related case (X015-X028, X081, X083, X087, X093) chained | error counter stable; conservation; lineage closure under BRESP; coverage duplicate of prior merged baseline after X125; retained for functional scenario check | FUNC-X126-final-closure-error-cases-x121-x128-error-bucket-bresp-composite |
| X127 | D | ERROR bucket protocol-violation composite | 1 | every protocol-violation case (X029-X048, X063-X068) chained | every SVA flag observed at least once; engine recovers; clean post-window run posts; coverage duplicate of prior merged baseline after X126; retained for functional scenario check | FUNC-X127-final-closure-error-cases-x121-x128-error-bucket-protocol-violation-composite |
| X128 | D | final ERROR bucket sign-off seal | 1 | composite of X124 + X125 + X126 + X127 | merged code coverage targets met (`stmt >= 95%`, `branch >= 90%`, `fsm = 100%`, `toggle >= 80%`); functional coverage closure on `cg_bresp`, `cg_doorbell_race x cg_fsm_state`, `cg_lineage_match x cg_doorbell_race`; coverage duplicate of prior merged baseline after X127; retained for functional scenario check | FUNC-X128-final-closure-error-cases-x121-x128-final-error-bucket-sign-off-seal |

---
