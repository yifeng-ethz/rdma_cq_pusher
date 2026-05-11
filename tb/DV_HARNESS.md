# DV Harness — rdma_cq_pusher

**Companion docs:** `DV_PLAN.md`, `DV_BASIC.md`, `DV_EDGE.md`,
`DV_PROF.md`, `DV_ERROR.md`, `DV_COV.md`, `DV_CROSS.md`,
`BUG_HISTORY.md`.

**Parent:** `DV_PLAN.md`.

**Status:** Phase 1 unit cosim. Authoritative description of the UVM
1.2 environment that realizes the test catalog in
`DV_BASIC.md` / `DV_EDGE.md` / `DV_PROF.md` / `DV_ERROR.md` against
`rdma_cq_pusher` on QuestaOne 2026.1.

The DUT contract is the source of truth (see `../RTL_PLAN.md`). This
document only describes the harness; CSR / register layout for the
supercore is owned by the run manager's `ip-packaging` artifacts.

This harness implements the **dual-UVM-env DEBUG_LEVEL contract**
mandated by `~/.codex/skills/dv-workflow/SKILL.md` Harness
Construction rule 7 (out-of-order datapath debug ladder):

- `DEBUG_LEVEL=1` env: synthesizable build with debug-only ports for
  CQ-ring fill-level / status observability (no functional change;
  tied off in synthesis at `DEBUG_LEVEL=0`, exposed for sim/SignalTap
  at `DEBUG_LEVEL=1`). Carries the **functional payload** monitor and
  **CQE/AXI ledger** scoreboard probe.
- `DEBUG_LEVEL=2` env: simulation-only widened datapath. Carries
  per-CQE meta sidecar `(rqe_id, retire_seq, origin_dma_done_seq,
  push_seq)` alongside the AXI4-Stream CQE input. The DEBUG=2 monitor
  proves per-CQE lineage from `rdma_run_manager` retire to host CQ
  slot. Widening is **sim-only** (`generate-if (DEBUG_LEVEL >= 2)`
  plus `// synthesis translate_off`).

Both DEBUG=1 and DEBUG=2 envs run in **parallel under one regression**,
each producing its own UCDB. They share **one scoreboard**:

- DEBUG=1 probe: ledger of `(host_cq_slot, wdata_payload)` events
- DEBUG=2 probe: ledger of `(rqe_id, retire_seq, origin_dma_done_seq,
  push_seq)` events
- Shared scoreboard cross-validates the two ledgers per case:
  - every CQE in a host CQ slot must map back to a known sidecar
  - every sidecar must land in a CQ slot or be classified as a
    documented drop (legal overwrite, BRESP-error retry, full-stall
    pending)
  - disagreement is a hard closure blocker

## 1. Overview

```
+-----------------------------------------------------------------------+
|                     rdma_cq_pusher_env_top (uvm_env)                   |
|                                                                       |
|  +-----------------+    +-----------------+    +----------------+    |
|  | env_dbg1        |    | env_dbg2        |    | shared SB      |    |
|  | (functional/    |    | (lineage /      |    | (cross-val:    |    |
|  |  payload env)   |    |  sidecar env)   |    |  payload x     |    |
|  |                 |    |                 |    |  lineage)      |    |
|  | - cqe_src_agt   |    | - cqe_meta_agt  |    |                |    |
|  | - axi4_host_agt |    | - lineage_mon   |    |                |    |
|  | - dbg1_tap_mon  |    | - meta_fifo_mon |    |                |    |
|  | - cfg_agt       |    | - dbg2_tap_mon  |    |                |    |
|  | - doorbell_drv  |    |                 |    |                |    |
|  | - msix_sink     |    |                 |    |                |    |
|  +--------+--------+    +--------+--------+    +-------+--------+    |
|           |                      |                     ^             |
|           v                      v                     |             |
|     payload ledger          lineage ledger             |             |
|           |                      |                     |             |
|           +--------- analysis ports ---->--------------+             |
|                                                                       |
|                  +------------------------------+                    |
|                  |     DUT (single instance)    |                    |
|                  |  rdma_cq_pusher              |                    |
|                  |  #(.WQE_BUS_W(512),          |                    |
|                  |    .DEBUG_LEVEL(2))          |                    |
|                  |                              |                    |
|                  |  - functional ports drive    |                    |
|                  |    env_dbg1 monitor          |                    |
|                  |  - dbg_* ports (DEBUG>=1)    |                    |
|                  |    drive env_dbg1 tap_mon    |                    |
|                  |  - s_axis_cqe_tuser_meta     |                    |
|                  |    sidecar (DEBUG>=2) is     |                    |
|                  |    fed by env_dbg2 cqe_meta  |                    |
|                  |  - dbg_last_pushed_meta      |                    |
|                  |    drives env_dbg2 lineage   |                    |
|                  +------------------------------+                    |
+-----------------------------------------------------------------------+
                                ^
                                |
                       clk (200 MHz default)
                       reset_n (async assert / sync deassert)
```

The single DUT is built at the highest active `DEBUG_LEVEL=2` so both
envs see live taps. Synthesis builds compile the same RTL at
`DEBUG_LEVEL=1` (or `0` for production) to confirm the sim-only
sidecar disappears.

`tb_top.sv` owns the clock generator, the reset generator, the DUT
instance, and the `bind` statements for SVA modules. Both envs are
instantiated under `rdma_cq_pusher_env_top` and connect to the DUT
through `virtual interface` handles passed via `uvm_config_db`.

### 1.1 House monitor pattern (rbcam reference)

The dual-env split factors the house monitor pattern from
`ring-buffer_cam/tb/uvm/`:

| rbcam monitor | this harness placement |
|---|---|
| `hit_monitor.sv` (input payload) | `env_dbg1.cqe_src_agent.monitor` |
| `out_monitor.sv` (egress payload) | `env_dbg1.axi4_host_agent.monitor` (AW/W/B + host CQ slot writes) |
| `debug_monitor.sv` (DUT-side observer) | `env_dbg1.dbg1_tap_monitor` (debug-1 status taps) AND `env_dbg2.dbg2_tap_monitor` (sim-only dbg_last_pushed_meta tap) |

The lineage / sidecar tracking is new and lives only in `env_dbg2`;
the rbcam reference does not have an OoO datapath but the monitor
factoring (payload monitor + egress monitor + DUT-side debug monitor)
is the model.

## 2. Directory layout

All paths are relative to the IP root (`rdma_cq_pusher/`).

```
tb/
  DV_PLAN.md
  DV_HARNESS.md                      (this document)
  DV_BASIC.md / DV_EDGE.md / DV_PROF.md / DV_ERROR.md
  DV_COV.md / DV_CROSS.md / BUG_HISTORY.md
  uvm/
    Makefile                         (vsim QuestaOne 2026.1; builds DUT once at DEBUG_LEVEL=2)
    tb_top.sv                        (DUT, clock, reset, SVA binds, both env handles)
    rdma_cq_pusher_pkg.sv            (env_top, both envs, scoreboard, sequences)
    rdma_cq_pusher_addr_map.sv       (CFG word layout, ring helpers)
    rdma_cq_pusher_ref_model.sv      (golden CQE ring + tail predictor)
    env_dbg1/                        (DEBUG=1 functional/payload env)
      env_pkg.sv
      env.sv
      cqe_src_agent_pkg.sv           (AXI4-Stream source: drv, mon, seqr)
      axi4_host_agent_pkg.sv         (AXI4 master completer; AW/W/B mon, host CQ shadow)
      doorbell_drv_agent_pkg.sv      (cq_head doorbell pulse + value)
      cfg_agent_pkg.sv               (cfg_cq_base, cfg_cq_depth, cfg_enable)
      msix_sink_agent_pkg.sv         (Phase 1: passive sink, asserts msix_req stays 0)
      dbg1_tap_monitor.sv            (samples dbg_* ports every cycle)
      dbg1_payload_ledger.sv         (analysis port -> shared SB)
    env_dbg2/                        (DEBUG=2 sim-only lineage env)
      env_pkg.sv
      env.sv
      cqe_meta_agent_pkg.sv          (drives s_axis_cqe_tuser_meta sidecar; aligned with env_dbg1.cqe_src)
      meta_fifo_monitor.sv           (samples internal sim-only dbg_meta_fifo)
      dbg2_tap_monitor.sv            (samples dbg_last_pushed_meta on every B-channel retire)
      dbg2_lineage_ledger.sv         (analysis port -> shared SB)
    shared_scoreboard.sv             (cross-validates payload x lineage)
    sequences/
      basic/                         (B001-B128 sequence library)
      edge/                          (E001-E128 sequence library)
      prof/                          (P001-P128 sequence library)
      error/                         (X001-X128 sequence library)
    sva/
      sva_cqe_in.sv
      sva_axi_aw.sv
      sva_axi_w.sv
      sva_axi_b.sv
      sva_atomicity.sv
      sva_doorbell.sv
      sva_msix_quiet.sv
      sva_full.sv
      sva_dbg1_transparency.sv       (DEBUG=1: dbg_* must be flop-only mirrors of FSM state)
      sva_dbg2_lineage.sv            (DEBUG=2: meta-FIFO drains 1:1 with B-channel retire)
    cov/
      cov_axi.sv
      cov_doorbell.sv
      cov_full.sv
      cov_cross.sv
      cov_lineage.sv                 (DEBUG=2 only)
    tests/
      rdma_cq_pusher_base_test.sv
      rdma_cq_pusher_basic_<id>_test.sv ...
      rdma_cq_pusher_edge_<id>_test.sv ...
      rdma_cq_pusher_prof_<id>_test.sv ...
      rdma_cq_pusher_error_<id>_test.sv ...
      rdma_cq_pusher_bucket_frame_basic_test.sv
      rdma_cq_pusher_bucket_frame_edge_test.sv
      rdma_cq_pusher_bucket_frame_prof_test.sv
      rdma_cq_pusher_bucket_frame_error_test.sv
      rdma_cq_pusher_all_buckets_frame_test.sv
    cov_after/
      txn_growth/                    (per-random-case checkpoint UCDBs)
```

The two envs (`env_dbg1` and `env_dbg2`) live under one
`rdma_cq_pusher_env_top` (`rdma_cq_pusher_pkg.sv`). Both attach to
the same DUT; they do not race on driving inputs because the
`env_dbg2.cqe_meta_agent` only drives the sim-only sidecar ports,
while `env_dbg1.cqe_src_agent` drives the functional CQE stream.
Sequence coordination (one CQE injection = one sidecar injection)
is owned by the virtual sequencer in `env_top`.

## 3. Agents

### 3.1 cqe_src_agent (env_dbg1, AXI4-Stream source — functional payload)

Drives `s_axis_cqe_*` into the DUT.

- One transaction = one 64 B CQE = one 512-bit beat with `tlast=1`.
- Transaction class: `cqe_txn_t` carries the eight 64-bit words named
  in architecture plan §5 (`bytes_written_total`, `seg0/1_bytes_written`,
  `status_id`, `event_count`, `first_event_ts`, `last_event_ts`,
  `opq_drop_snapshot`, `retire_seq`) plus an `rqe_id` sideband.
- Driver options (controllable per case): `inter_beat_gap_cycles`
  (deterministic), `gap_distribution` (uniform / geometric / burst),
  `force_no_backpressure_wait` (cap on time waiting for ready).
- Monitor publishes `cqe_observed_e` events (input observations).

### 3.2 axi4_host_agent (env_dbg1, AXI4 master completer + host CQ memory)

Acts as the host-side memory and AXI4 completer for the DUT's
write master.

- Backing store: `bit [511:0] host_cq_mem [0:MAX_CQ_DEPTH-1]` indexed
  by `(awaddr - cfg_cq_base) >> 6`. Default `MAX_CQ_DEPTH = 65536`.
- AW completer: configurable wait-states for `m_axi_awready` per case
  (`{0, 1, 4, 16, 64, 256}` cycles, plus uniform-random and
  burst-stall profiles).
- W completer: configurable wait-states for `m_axi_wready`.
- B responder: configurable latency for `m_axi_bvalid` after `wlast`,
  configurable `bresp` (default OKAY; SLVERR / DECERR for X-bucket
  cases). The completer asserts `bid` equal to the corresponding `awid`.
- Monitor publishes `aw_observed_e`, `w_observed_e`, `b_observed_e`,
  `cq_slot_written_e` events.
- Sanity assertions: `awlen=0`, `awsize=6`, `awburst=INCR`, `wstrb`
  all-ones, `wlast=1`, `awaddr` 64 B aligned, `awaddr` within
  `[cfg_cq_base, cfg_cq_base + cfg_cq_depth*64)`.

### 3.3 doorbell_drv_agent (env_dbg1)

Drives `cq_head_dbl_pulse` and `cq_head_dbl_value`.

- One transaction = one single-cycle pulse with a value.
- Sequencer offers parameterised modes:
  - `single_step`: increment by 1.
  - `bulk_credit`: jump to a target value (multiple slots in one
    pulse).
  - `wraparound`: target straddles the power-of-2 boundary.
  - `racing`: pulse aligned to a specific FSM state (IDLE / AW / W / B
    / ADVANCE_TAIL) for race-window coverage.
  - `disabled_window`: pulse during `cfg_enable=0` to verify silent
    latch.
- Monitor publishes `doorbell_observed_e` events.

### 3.4 cfg_agent (env_dbg1)

Drives static configuration `cfg_cq_base`, `cfg_cq_depth`,
`cfg_enable` once per test (and on legal in-flight reprogram cases).

- `cfg_cq_depth` is constrained to powers of two in
  `{2, 4, 16, 256, 4096, 65536}`.
- `cfg_cq_base` is constrained to 64 B alignment by default; X-bucket
  cases inject misalignment to verify the SVA fires (input contract,
  not a recovery requirement).
- `cfg_enable` is asserted before the first CQE; X-bucket cases
  toggle it mid-flight.

### 3.5 msix_sink_agent (env_dbg1, Phase 1: passive)

- Holds `msix_ack=0` by default; some Edge cases pulse `msix_ack` to
  verify the Phase 1 stub never reacts.
- Monitor asserts `msix_req` never goes to 1 in Phase 1 (Phase 1 stub
  contract). The same agent is reused in Phase 2 with the assertion
  removed.

### 3.6 dbg1_tap_monitor (env_dbg1, DEBUG_LEVEL >= 1)

Background observer running in parallel with the active sequence:

- Samples `dbg_cur_cq_tail`, `dbg_cur_cq_head_credit`, `dbg_cq_full`,
  `dbg_aw_pending`, `dbg_b_inflight`, `dbg_ring_full_stall_cyc`,
  `dbg_state`, `dbg_cnt_bresp_error` every clock.
- Publishes `dbg1_tap_observed_e` events to the shared scoreboard.
- Used to cross-check the scoreboard's predicted cq_tail / cq_head /
  inflight without relying on the AXI4 master FSM mirror alone (catches
  the case where the dbg_* taps drift from the actual functional FSM).

### 3.7 cqe_meta_agent (env_dbg2, sim-only sidecar driver)

- Drives `s_axis_cqe_tuser_meta` =
  `{push_seq[15:0], origin_dma_done_seq[15:0], retire_seq[15:0],
    rqe_id[15:0]}` aligned with every CQE injected by
  `env_dbg1.cqe_src_agent`. The virtual sequencer in `env_top`
  generates a paired `(cqe_txn_t, meta_t)` per beat so the two
  agents stay in lockstep.
- Monitor: `cqe_meta_observed_e` events publish the sidecar payload
  on each `s_axis_cqe_tvalid && s_axis_cqe_tready`.

### 3.8 meta_fifo_monitor (env_dbg2)

- Background observer of the sim-only meta-FIFO inside the DUT
  (`rdma_cq_pusher.g_dbg2.dbg_meta_fifo.*`). Samples the FIFO level
  and pop pointer every clock and publishes
  `meta_fifo_state_e` events to the shared scoreboard.
- Asserts strict 1:1 between `m_axi_wvalid && m_axi_wready` (push
  retire-meta into the FIFO) and `m_axi_bvalid && m_axi_bready`
  (pop retire-meta out of the FIFO into `dbg_last_pushed_meta`).
  Drift is a hard scoreboard failure (the lineage map would otherwise
  point at the wrong host CQ slot).

### 3.9 dbg2_tap_monitor (env_dbg2)

- Samples `dbg_last_pushed_meta` on every B-channel retire
  (`m_axi_bvalid && m_axi_bready && m_axi_bresp == OKAY`) and
  publishes `lineage_observed_e` events to the shared scoreboard.
  The event carries `(host_cq_slot, rqe_id, retire_seq,
  origin_dma_done_seq, push_seq)` so the scoreboard can fuse it
  with the env_dbg1 payload event for the same slot.

## 4. Shared scoreboard

The shared scoreboard is the single arbiter of pass/fail per case for
**both** envs. It is owned by `env_top`; both envs publish into its
analysis ports.

Inputs from env_dbg1:

- `cqe_observed_e` from cqe_src_agent (CQEs injected into the DUT).
- `aw_observed_e`, `w_observed_e`, `b_observed_e` from axi4_host_agent.
- `cq_slot_written_e` from axi4_host_agent (host-side memory write).
- `doorbell_observed_e` from doorbell_drv_agent.
- `dbg1_tap_observed_e` from dbg1_tap_monitor (synthesizable status
  taps).

Inputs from env_dbg2:

- `cqe_meta_observed_e` from cqe_meta_agent.
- `meta_fifo_state_e` from meta_fifo_monitor.
- `lineage_observed_e` from dbg2_tap_monitor.

State:

- `injected_cqe_q` — FIFO of `(cqe_txn_t, meta_t)` pairs injected.
- `host_cq_shadow [0:cfg_cq_depth-1]` — shadow of the host memory ring.
- `lineage_map[host_cq_slot] = meta_t` — per-slot lineage tuple.
- `expected_cq_tail` — predictor mirroring DUT FSM advancement.
- `expected_cq_head` — driven by doorbell agent.
- `expected_cnt_cqe_posted`.
- `outstanding_aw_q` — AW transactions waiting for B response, used to
  catch out-of-order or duplicate B retirement.

Per-event predictions:

1. On `cqe_observed_e` + `cqe_meta_observed_e` (paired): push the pair
   into `injected_cqe_q`; record `rqe_id` and lineage tuple for
   end-to-end matching. Both events must arrive on the same clock or
   the env sequencer is broken; the scoreboard asserts this.
2. On `aw_observed_e`: assert
   `awaddr == cfg_cq_base + expected_cq_tail*64`;
   assert `awlen=0`, `awsize=6`, `awburst=INCR`;
   push into `outstanding_aw_q`.
3. On `w_observed_e`: assert `wstrb` is all-ones, `wlast=1`;
   assert `wdata` matches the CQE at the head of `injected_cqe_q`.
4. On `cq_slot_written_e` (host model wrote a CQE slot):
   update `host_cq_shadow[expected_cq_tail] = wdata`.
5. On `b_observed_e` with `bresp == OKAY`:
   pop `outstanding_aw_q` and `injected_cqe_q`;
   increment `expected_cnt_cqe_posted`;
   increment `expected_cq_tail` modulo `cfg_cq_depth`.
6. On `b_observed_e` with `bresp != OKAY`:
   leave queues untouched (Phase 1 retry semantics);
   increment `expected_cnt_bresp_error`;
   assert `expected_cq_tail` does NOT advance.
7. On `doorbell_observed_e`: update `expected_cq_head` to the masked
   value.
8. On `dbg1_tap_observed_e`: assert
   `dbg_cur_cq_tail == expected_cq_tail` AND
   `dbg_cur_cq_head_credit == expected_cq_head` AND
   `dbg_cq_full == ((expected_cq_tail+1) & mask) == expected_cq_head`
   AND `dbg_state` matches the predicted FSM state.
9. On `lineage_observed_e` (DEBUG=2): record
   `lineage_map[host_cq_slot] = meta_t`. Assert the meta_t at the
   B-channel retire equals the meta_t at the head of the
   `injected_cqe_q` (sim-only meta-FIFO must not reorder).
10. **Cross-validation** (DEBUG=1 x DEBUG=2), end of test:
    For each `host_cq_slot` written:
    - find the env_dbg1 payload at `host_cq_shadow[slot]`;
    - find the env_dbg2 lineage at `lineage_map[slot]`;
    - assert the lineage tuple's `(rqe_id, retire_seq)` matches the
      payload's `status_id[31:16]` (rqe_id) and `retire_seq` field.
    - For each injected `(cqe, meta)` pair:
      - either it lands in a `host_cq_shadow` slot (success), or
      - it is documented as a known drop (legal overwrite, BRESP-error
        retry pending, full-stall pending). Any unmatched pair is a
        hard failure.

End-of-test ledger:

- `injected_cqe_q.size() == 0` once the test has drained credit
  (otherwise the case must explicitly mark some CQEs as in-flight,
  e.g. backpressure-stuck cases).
- `expected_cq_tail == dut_cq_tail` (and `dut_cq_tail ==
  dbg_cur_cq_tail`).
- For every `rqe_id` injected, the host shadow contains exactly one
  CQE with that `rqe_id` in word 2 bits `[31:16]`.
- For every `host_cq_slot` written, `lineage_map[slot]` exists.
- `cnt_cqe_posted == #(injected_cqe_q drained with bresp==OKAY)`.
- `msix_req` never asserted (Phase 1 contract).

## 5. SVA bind modules

| Module | Targets | Key properties |
|--------|---------|----------------|
| `sva_cqe_in` | `s_axis_cqe_*` | tlast always 1 on a valid beat; `tready` only high in IDLE with `cfg_enable=1` and `!cq_full`; no `tvalid&&tready&&!tlast` |
| `sva_axi_aw` | `m_axi_aw*` | `awvalid` only in AW state; `awvalid` stable until `awready`; `awlen=0`, `awsize=6`, `awburst=INCR`, `awaddr` 64 B aligned; `awaddr` within ring |
| `sva_axi_w` | `m_axi_w*` | `wvalid` only in W state; `wvalid` stable until `wready`; `wstrb` all-ones; `wlast=1` |
| `sva_axi_b` | `m_axi_b*` | `bready` always high in B state; one B per AW; `bid==awid` |
| `sva_atomicity` | `m_axi_w*`, `cnt_cqe_posted` | exactly one (wvalid && wready && wlast) per CQE accepted; the W payload equals the CQE that drove the AW |
| `sva_doorbell` | `cq_head_dbl_*`, internal `cq_head` | `cq_head` updates one cycle after a pulse; value masked by `cfg_cq_depth-1` |
| `sva_msix_quiet` | `msix_req`, `msix_vector` | Phase 1: `msix_req===1'b0` always; Phase 2: removed |
| `sva_full` | internal `cq_full`, `cq_tail`, `cq_head` | `cq_full <-> ((cq_tail+1)&(cfg_cq_depth-1))==cq_head`; `s_axis_cqe_tready` low when `cq_full`; `cq_tail` cannot advance when `cq_full` |
| `sva_dbg1_transparency` | `dbg_*` ports vs internal FSM | every cycle `dbg_cur_cq_tail == cq_tail`, `dbg_cur_cq_head_credit == cq_head`, `dbg_cq_full == cq_full`, `dbg_state == fsm_state`; the dbg_* ports must be flop-only mirrors and never feed back into the data path |
| `sva_dbg2_lineage` | sim-only meta-FIFO | every `m_axi_wvalid && m_axi_wready` pushes the head meta_t into the FIFO; every `m_axi_bvalid && m_axi_bready && bresp==OKAY` pops one meta_t; FIFO depth never exceeds inflight AW depth |

All SVA modules expose `cover_*` clauses in addition to their assertion
clauses so the harness can produce property coverage at sign-off.

## 6. Sequences and tests

### 6.1 Base test

`rdma_cq_pusher_base_test`:

- Builds the `env_top` (which builds both envs and the shared SB),
  applies a default cfg `(cfg_cq_base = 64'h1000_0000_0000_0000,
  cfg_cq_depth = 256, cfg_enable = 1)`.
- Holds reset for 16 clocks, releases.
- Waits for `s_axis_cqe_tready` to assert high (proves the IP is in
  IDLE with no full and enabled).
- Hands off to the case-specific virtual sequence on the env_top
  virtual sequencer (which coordinates env_dbg1 and env_dbg2 paired
  injections).

### 6.2 Per-case test classes

One test class per ID. Each test sets a unique `seed`, declares its
case-specific cfg overrides, and runs one virtual sequence from the
matching `sequences/<bucket>/` library. Random tests must implement
the checkpoint UCDB emitter described in
`~/.codex/skills/dv-workflow/SKILL.md` Report Layout > Checkpoint
UCDBs.

### 6.3 Continuous-frame tests

`rdma_cq_pusher_bucket_frame_<bucket>_test` runs every case in the
named bucket back-to-back inside one continuous frame, in case-id
order, without DUT reset between cases. The shared scoreboard is held
active across cases; per-case end-of-test ledgers are checked at each
case boundary.

`rdma_cq_pusher_all_buckets_frame_test` does the same across all four
buckets in the order BASIC -> EDGE -> PROF -> ERROR.

## 7. Build, run, regression

### 7.1 Compile and elaborate

```
make -C tb/uvm clean
make -C tb/uvm compile
```

Uses the QuestaOne 2026.1 Makefile pattern from CLAUDE.md (full UVM
1.2, native `rand`/`covergroup`, DPI enabled). The DUT compiles once
at `+define+RDMA_CQ_PUSHER_DEBUG_LEVEL=2` so both envs can attach.

### 7.2 Run a single test

```
make -C tb/uvm run UVM_TESTNAME=rdma_cq_pusher_basic_b001_test SEED=42
```

Per-case UCDB lands in `tb/uvm/cov_after/<test>_s<seed>.ucdb`. The
UCDB carries coverage from both envs (one merged code-coverage view
per case; functional coverage groups are env-distinguishable via
their package prefix).

### 7.3 Run a bucket

```
make -C tb/uvm regress BUCKET=basic
```

Runs every case in the bucket isolated, then runs the
`bucket_frame_basic` continuous-frame variant once.

### 7.4 Run sign-off

```
make -C tb/uvm signoff
```

Runs every isolated case, every `bucket_frame_*` continuous-frame
test, and `all_buckets_frame`, merges per-bucket UCDBs into ordered
isolated baselines, generates `DV_REPORT.json` from the run logs, and
invokes `dv_report_gen.py` to refresh `tb/REPORT/`.

### 7.5 DEBUG=0 vs DEBUG=1 transparency check

```
make -C tb/uvm transparency_check
```

Recompiles the DUT at `DEBUG_LEVEL=0` (no dbg_* ports), reruns a
fixed signature test set, captures the AXI4 master AW/W/B trace, and
compares byte-for-byte against the DEBUG=1 trace from the same seed.
Disagreement is a hard failure (DEBUG=1 ports must be functionally
transparent — sign-off ladder rung 7 in `DV_PLAN.md`).

## 8. Coverage collectors

Code coverage is collected by QuestaOne 2026.1 at compile time
(`+cover=bcestf` plus toggle on the DUT pins).

Functional coverage is implemented as native SystemVerilog covergroups
in `cov/cov_*.sv` per the `DV_COV.md` plan. Every covergroup is
sampled by the matching agent monitor; the shared scoreboard does not
sample covergroups directly so coverage stays decoupled from pass/fail
verdicts.

`cov_lineage.sv` (DEBUG=2 only) tracks
`(rqe_id, retire_seq, origin_dma_done_seq, push_seq)` bins. Every
host CQ slot must hit one bin; unmatched slots are a closure blocker.

## 9. Debug observability

The harness exposes the following debug signals to the waveform window
(`tb_top.dbg_*`):

- DUT internal `state` (FSM register, 4-state).
- DUT internal `cq_tail`, `cq_head`, `cq_full`.
- DUT internal `cqe_buf` (latched CQE in flight).
- DEBUG_LEVEL >= 1 ports: `dbg_cur_cq_tail`,
  `dbg_cur_cq_head_credit`, `dbg_cq_full`, `dbg_aw_pending`,
  `dbg_b_inflight`, `dbg_ring_full_stall_cyc`, `dbg_state`,
  `dbg_cnt_bresp_error`.
- DEBUG_LEVEL >= 2 ports: `dbg_last_pushed_meta`.
- AXI4-Stream sink handshake (valid/ready/last) + sim-only sidecar.
- AXI4 master AW/W/B handshake.
- Doorbell pulse.
- `cnt_cqe_posted` counter.
- `msix_req` (verified to stay 0 in Phase 1).
- Sim-only `dbg_meta_fifo` level / pop pointer (DEBUG=2 only).

A `.gtkw` save file template ships at `tb/uvm/wave/cq_pusher.gtkw` and
groups signals as `[CQE_IN]`, `[CQE_META_IN]`, `[AXI_AW]`,
`[AXI_W]`, `[AXI_B]`, `[FSM]`, `[RING]`, `[DBG1_TAPS]`,
`[DBG2_LINEAGE]`, `[DOORBELL]`, `[MSIX]`, `[CTRS]`.

## 10. References

- `../RTL_PLAN.md` — DUT contract (DEBUG_LEVEL parameter,
  dbg_* ports, sim-only sidecar).
- `../../rdma_subsystem/ARCHITECTURE_PLAN.md` §4, §5.
- `../../rdma_rq_fetcher/tb/DV_PLAN.md` — sibling format anchor.
- `../../packet_scheduler/tb/DV_HARNESS.md` — house env style anchor
  (build-knob sweeps, DRR cover intent, scoreboard contract).
- `../../ring-buffer_cam/tb/DV_HARNESS.md` — house monitor pattern
  anchor: `hit_monitor.sv` (input payload), `out_monitor.sv`
  (egress), `debug_monitor.sv` (DUT-side taps). The dual env factors
  this pattern (env_dbg1 = payload+egress, env_dbg2 = lineage taps).
- `../../ring-buffer_cam/tb/BUG_HISTORY.md` — bug-ledger style anchor.
- `~/.codex/skills/dv-workflow/SKILL.md` — hard contract; Harness
  Construction rule 7 (out-of-order datapath debug ladder) is the
  source for the dual `DEBUG_LEVEL` env pattern realized here.
- `~/.codex/skills/verification-tools/SKILL.md` — QuestaOne runtime.
