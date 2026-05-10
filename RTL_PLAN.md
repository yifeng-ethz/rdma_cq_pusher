# `rdma_cq_pusher` — RTL Plan

Status: **PLAN — pending review.** Sibling IP of the `rdma_subsystem`
supercore (`mu3e-ip-cores/rdma_subsystem/ARCHITECTURE_PLAN.md`).

## 1. Role within the subsystem

Pushes Completion Queue Entries (CQEs) into the host CQ ring in host DRAM.
Accepts an Avalon-ST CQE stream from `rdma_run_manager` and turns each
beat into one AVMM write at the next CQ ring slot, then atomically updates
the FW-owned `cq_tail` pointer (which the host polls from `csr.CQ_TAIL`).

In Phase 2, this is also where MSI-X interrupt generation lives.

The IP is fully **stateless to the data plane** — it only handles control
plane CQE bookkeeping.

## 2. Module hierarchy

```
rdma_cq_pusher.sv               (top)
├── rdma_cq_ring_state.sv       (head/tail/depth state)
├── rdma_cq_avmm_writer.sv      (AXI4 master that issues 64 B writes)
├── rdma_cq_msix.sv             (Phase 2 — interrupt generator; Phase 1 stub)
└── rdma_cq_pusher_dbg_meta_fifo.sv  (DEBUG_LEVEL >= 2, sim-only sidecar FIFO)
```

The trailing `*_dbg_meta_fifo.sv` is wrapped in
`generate-if (DEBUG_LEVEL >= 2)` and `// synthesis translate_off` /
`_on` pragmas, so synthesis at `DEBUG_LEVEL <= 1` never instantiates it.

## 3. Top-level interface

CQE = 64 B (one cacheline). AXI4 master uses `WQE_BUS_W = 512` so one CQE
write = one AXI4 beat = one host cacheline atomic update. Inter-IP CQE bus
is **AXI4-Stream**.

The IP exposes a cumulative `DEBUG_LEVEL` parameter (default `0`),
defined per `~/.codex/skills/dv-workflow/SKILL.md` Harness Construction
rule 7 (out-of-order datapath debug ladder):

| `DEBUG_LEVEL` | Effect | Synthesizable? |
|--:|---|---|
| `0` | Functional payload only. All `dbg_*` debug-1 outputs tie off (constant 0). The DEBUG-2 sidecar input `s_axis_cqe_tuser_meta` is ignored. | Yes (production default). |
| `1` | Adds CQ-ring-state and AXI4-channel observability via `dbg_*` output ports for SignalTap and TB monitors. **No functional change** to the AXI4-Stream / AXI4 master payload. The sidecar input is still ignored. | Yes (debug-1 outputs are SignalTap-friendly and tied off if not consumed). |
| `2` | **Simulation-only.** Activates a sim-only widened sidecar field on the CQE input stream that carries per-CQE lineage `(sqe_id, retire_seq, originating_dma_done_seq, push_seq)`. The DEBUG-2 monitor proves end-to-end CQE lineage from `rdma_run_manager` retire to host CQ slot. | **No.** Synthesis must hold `DEBUG_LEVEL <= 1`. The sim-only sidecar wires are guarded with `// synthesis translate_off` / `_on` and a `generate-if (DEBUG_LEVEL >= 2)` block. |

`DEBUG_LEVEL` is cumulative: `>= 1` enables debug-1 taps, `>= 2`
additionally enables the sim-only sidecar.

```systemverilog
module rdma_cq_pusher #(
    parameter int unsigned WQE_BUS_W   = 512,  // 64 B CQE = one beat
    parameter int unsigned DEBUG_LEVEL = 0,    // 0=prod, 1=tap, 2=sim-only sidecar
    // SIM-ONLY (DEBUG_LEVEL >= 2): width of the per-CQE lineage sidecar
    parameter int unsigned DBG_META_W  = 64    // {push_seq[15:0], origin_dma_done_seq[15:0],
                                               //  retire_seq[15:0], sqe_id[15:0]}
) (
    input  logic                 clk,
    input  logic                 reset_n,

    // Configuration from run_manager (CSR-backed)
    input  logic [63:0]          cfg_cq_base,
    input  logic [15:0]          cfg_cq_depth,        // power of 2
    input  logic                 cfg_enable,

    // Doorbell from CSR
    input  logic                 cq_head_dbl_pulse,
    input  logic [15:0]          cq_head_dbl_value,

    // CQE stream in from run_manager (AXI4-Stream sink, 1 beat = 1 CQE)
    input  logic [WQE_BUS_W-1:0] s_axis_cqe_tdata,
    input  logic                 s_axis_cqe_tvalid,
    output logic                 s_axis_cqe_tready,
    input  logic                 s_axis_cqe_tlast,    // always 1
    input  logic [15:0]          s_axis_cqe_tuser,    // sqe_id

    // CQ tail (FW producer pointer, sampled by run_manager into csr.CQ_TAIL)
    output logic [15:0]          cq_tail,

    // AXI4 (full) write-only master
    output logic [3:0]           m_axi_awid,
    output logic [63:0]          m_axi_awaddr,
    output logic [7:0]           m_axi_awlen,         // = 0 (one beat)
    output logic [2:0]           m_axi_awsize,        // = $clog2(WQE_BUS_W/8)
    output logic [1:0]           m_axi_awburst,       // INCR
    output logic                 m_axi_awvalid,
    input  logic                 m_axi_awready,
    output logic [WQE_BUS_W-1:0] m_axi_wdata,
    output logic [WQE_BUS_W/8-1:0] m_axi_wstrb,       // all-1s (full cacheline)
    output logic                 m_axi_wlast,         // 1 on the single beat
    output logic                 m_axi_wvalid,
    input  logic                 m_axi_wready,
    input  logic [3:0]           m_axi_bid,
    input  logic [1:0]           m_axi_bresp,
    input  logic                 m_axi_bvalid,
    output logic                 m_axi_bready,

    // MSI-X (Phase 2 — tied off in Phase 1)
    output logic                 msix_req,
    output logic [4:0]           msix_vector,
    input  logic                 msix_ack,

    // Sideband counter
    output logic [31:0]          cnt_cqe_posted,

    // ----------------------------------------------------------------
    // DEBUG_LEVEL >= 1 observability ports (synthesizable; tied off
    // when DEBUG_LEVEL == 0). Drive SignalTap and TB monitors. Adding
    // these does not change the functional path.
    // ----------------------------------------------------------------
    output logic [15:0]          dbg_cur_cq_tail,         // mirror of FSM-owned tail
    output logic [15:0]          dbg_cur_cq_head_credit,  // mirror of host doorbell
    output logic                 dbg_cq_full,             // ring-full predicate
    output logic [3:0]           dbg_aw_pending,          // # AW issued, B not yet retired
    output logic [3:0]           dbg_b_inflight,          // # B-channel in flight
    output logic [31:0]          dbg_ring_full_stall_cyc, // saturating cyc count of cq_full backpressure
    output logic [3:0]           dbg_state,               // FSM state {IDLE,AW,W,B,ADV}
    output logic [31:0]          dbg_cnt_bresp_error      // non-OKAY BRESP counter

    // ----------------------------------------------------------------
    // DEBUG_LEVEL >= 2 SIM-ONLY sidecar input (lineage meta).
    // Carried alongside s_axis_cqe_tdata; widening guarded by
    // `generate-if (DEBUG_LEVEL >= 2)` and `synthesis translate_off`
    // pragmas so synthesis only ever sees a tied-off zero.
    // ----------------------------------------------------------------
    // synthesis translate_off
    , input  logic [DBG_META_W-1:0] s_axis_cqe_tuser_meta  // {push_seq, origin_dma_done_seq, retire_seq, sqe_id}
    , output logic [DBG_META_W-1:0] dbg_last_pushed_meta   // meta of most recent retired CQE
    // synthesis translate_on
);
```

The 512-bit AXI4 wdata + all-1s wstrb means the host sees a **single
atomic cacheline write** for each CQE. No torn read: the host either
sees the entire previous CQE or the entire new one.

The DEBUG-2 sidecar **does not** flow into AXI4 wdata. It propagates
through a sim-only meta-FIFO (`rdma_cq_pusher_dbg_meta_fifo.sv` —
gated by `generate-if (DEBUG_LEVEL >= 2)`) parallel to the W/B path so
the DEBUG-2 monitor can map every host CQ slot back to a
`(sqe_id, retire_seq, origin_dma_done_seq, push_seq)` tuple. The
functional path is bit-identical regardless of `DEBUG_LEVEL`.

## 4. Behavior

### 4.1 CQ ring state

Maintains:
- `cq_tail` (FW's producer pointer; FW-owned, host reads via CSR)
- `cq_head` (host's consumer pointer; updated on `cq_head_dbl_pulse`)

`cq_full = ((cq_tail + 1) & (cq_depth-1)) == cq_head`. Push stalls when
full.

### 4.2 Push FSM (4 states, AXI4)

```
IDLE
  | s_axis_cqe_tvalid && !cq_full && cfg_enable
  v
AW                            ← m_axi_awaddr  = cfg_cq_base + cq_tail*64
                                 m_axi_awlen   = 0       (1 beat)
                                 m_axi_awsize  = $clog2(WQE_BUS_W/8)
                                 m_axi_awburst = INCR
                                 m_axi_awvalid = 1
  | awvalid && awready
  v
W                             ← m_axi_wdata  = s_axis_cqe_tdata
                                 m_axi_wstrb  = all-1s
                                 m_axi_wlast  = 1
                                 m_axi_wvalid = 1
  | wvalid && wready
  v
B                             ← await m_axi_bvalid; check bresp == OKAY
  | bvalid && bready
  v
ADVANCE_TAIL: cq_tail <- (cq_tail + 1) & (cfg_cq_depth-1)
              cnt_cqe_posted++
              [Phase 2: msix_req <= 1 for one cycle]
  v
IDLE
```

### 4.3 Backpressure

`s_axis_cqe_tready = !cq_full && (state == IDLE) && cfg_enable`.

If host doesn't drain CQ (no doorbell credit), pusher stalls. Run manager
in turn stalls SQE consumption — this propagates the right way.

## 5. Validation plan (unit-level cosim)

Lives at `tb/uvm/rdma_cq_pusher_tb_top.sv`. Detailed contract surface
is the bucket files `tb/DV_BASIC.md`, `tb/DV_EDGE.md`, `tb/DV_PROF.md`,
`tb/DV_ERROR.md` (per `dv-workflow` rule 15b). The high-level coverage
intent is below; the harness contract for the **dual UVM env**
(DEBUG=1 functional / DEBUG=2 lineage) plus the cross-validating
shared scoreboard is in `tb/DV_HARNESS.md` (per `dv-workflow` rule 7).

| # | Test                                | Pass criterion |
|---|-------------------------------------|----------------|
| 1 | Single CQE push                     | host memory CQ slot 0 has the CQE; cq_tail == 1 |
| 2 | 4 CQEs back-to-back (depth=8)       | 4 CQEs in slots 0..3, in order; cq_tail == 4 |
| 3 | Wraparound (depth=4, push 8)        | wraps after cq_head credit; conservation |
| 4 | CQ full → backpressure              | cqe_ready deasserts; once doorbell credits, push resumes |
| 5 | Disabled → no push                  | cfg_enable=0 holds cqe_ready low |
| 6 | AVMM waitrequest                    | retry; no double-write |
| 7 | Counter accuracy                    | cnt_cqe_posted == # of host-observed CQEs |
| 8 | (Phase 2 only) MSI-X fires once     | 1 MSI-X req per push when enabled |
| 9 | DEBUG=1 status taps                 | dbg_cur_cq_tail / dbg_cur_cq_head_credit / dbg_cq_full / dbg_aw_pending / dbg_b_inflight / dbg_ring_full_stall_cyc / dbg_state mirror DUT state every cycle, with no functional change vs DEBUG=0 (bit-identical W/AW/B trace) |
| 10 | DEBUG=2 lineage end-to-end         | every host CQ slot (DEBUG=1 monitor) maps back 1:1 to a `(sqe_id, retire_seq, origin_dma_done_seq, push_seq)` tuple injected upstream (DEBUG=2 monitor); shared scoreboard cross-validates DEBUG=1 payload x DEBUG=2 lineage |

## 6. CSR exposure

This IP has **no host-visible CSR** of its own. Surfaces:
- `cq_tail` → `csr.CQ_TAIL` (RO)
- `cnt_cqe_posted` → `csr.CNT_CQE_POSTED`

## 7. Synthesis sign-off

Standalone Quartus project at `syn/quartus/rdma_cq_pusher_standalone.qsf`.
Sign-off corner: 1.1× target = 275 MHz. Synthesized at `DEBUG_LEVEL=1`
to confirm the debug-1 ports add no functional logic on the AXI4
master and the resource delta vs `DEBUG_LEVEL=0` is bounded
(target: < 5% ALM growth, owned mostly by the saturating stall
counter and the FSM state mirror).

Estimated logic at `DEBUG_LEVEL=0`: ~120 ALMs + tiny CQE-latch RAM.
Estimated logic at `DEBUG_LEVEL=1`: ~150 ALMs (small adders + counters).
`DEBUG_LEVEL=2` is **never synthesized**; the gate is asserted in
`rtl/rdma_cq_pusher.sv` via:

```systemverilog
// synthesis translate_off
initial assert (DEBUG_LEVEL <= 2)
    else $fatal(1, "DEBUG_LEVEL must be in {0,1,2}");
// synthesis translate_on
generate
    if (DEBUG_LEVEL >= 2) begin : g_dbg2_check
        // synthesis translate_off
        initial $display("[%m] DEBUG_LEVEL=2 sim-only sidecar active");
        // synthesis translate_on
        // synthesis translate_off
        // CDC: DEBUG=2 wires are sim-only; if you see this in synthesis you
        // mis-set the parameter.
        // synthesis translate_on
    end
endgenerate
```

## 8. Files

```
rdma_cq_pusher/
├── README.md
├── RTL_PLAN.md                              (this file)
├── doc/
├── rtl/
│   ├── rdma_cq_pusher.sv                    (top, owns DEBUG_LEVEL parameter)
│   ├── rdma_cq_ring_state.sv                (head/tail/depth, exposes dbg_* taps)
│   ├── rdma_cq_avmm_writer.sv               (AXI4 master FSM, exposes dbg_* taps)
│   ├── rdma_cq_msix.sv                      (Phase 1 stub: ties msix_req=0)
│   └── rdma_cq_pusher_dbg_meta_fifo.sv      (DEBUG_LEVEL >= 2, sim-only sidecar FIFO)
├── tb/
│   ├── DV_PLAN.md                           (companion to RTL_PLAN.md, dual-env scope)
│   ├── DV_HARNESS.md                        (dual UVM env DEBUG=1 / DEBUG=2 + shared SB)
│   ├── DV_BASIC.md / DV_EDGE.md / DV_PROF.md / DV_ERROR.md
│   ├── DV_COV.md / DV_CROSS.md / BUG_HISTORY.md
│   └── uvm/
│       ├── rdma_cq_pusher_tb_top.sv         (instantiates DUT once, both envs in parallel)
│       ├── rdma_cq_pusher_pkg.sv
│       ├── env_dbg1/                        (DEBUG_LEVEL=1 env: payload monitor + scoreboard probe)
│       ├── env_dbg2/                        (DEBUG_LEVEL=2 env: lineage monitor + scoreboard probe)
│       ├── shared_scoreboard.sv             (cross-validates DEBUG=1 payload x DEBUG=2 lineage)
│       └── Makefile
├── syn/quartus/
│   └── rdma_cq_pusher_standalone.qsf        (synthesizes at DEBUG_LEVEL=1)
├── rdma_cq_pusher_hw.tcl
├── Makefile
└── .git/
```

## 9. Implementation order

1. `rtl/rdma_cq_ring_state.sv` (with DEBUG_LEVEL>=1 dbg_* taps)
2. `rtl/rdma_cq_avmm_writer.sv` (with DEBUG_LEVEL>=1 dbg_* taps)
3. `rtl/rdma_cq_msix.sv` (Phase 1 stub)
4. `rtl/rdma_cq_pusher_dbg_meta_fifo.sv` (DEBUG_LEVEL>=2, sim-only)
5. `rtl/rdma_cq_pusher.sv` top (DEBUG_LEVEL parameter wiring)
6. `tb/DV_PLAN.md`, `tb/DV_HARNESS.md` (already drafted)
7. `tb/uvm/rdma_cq_pusher_tb_top.sv` + dual env (DEBUG=1, DEBUG=2)
8. `tb/uvm/shared_scoreboard.sv` (cross-validates DEBUG=1 ledger x DEBUG=2 lineage)
9. Bucket-file scaffolding (`DV_BASIC.md` / etc.) per `dv-workflow` 15b
10. `rdma_cq_pusher_hw.tcl` (Qsys IP, exposes DEBUG_LEVEL knob defaulting to 0)
11. Standalone signoff (synthesizes at DEBUG_LEVEL=1)

## 10. Risks specific to this IP

- **CQE atomicity**: writing 64 B with one AXI4 beat covers the full
  CQE; no torn write possible at this granularity. If Phase 2 widens
  CQE format, revisit.
- **CQ depth power-of-2** required (same as SQ).
- **MSI-X vector**: Phase 2 needs a real vector. Phase 1 ties to 0.
- **DEBUG_LEVEL=1 must not perturb the functional path.** The dbg_*
  outputs are flopped views of state already inferred by the FSM and
  the AXI4 master. The standalone sign-off compile at
  `DEBUG_LEVEL=1` must hit the same Fmax band as `DEBUG_LEVEL=0`
  (within 5 % timing slack drift); regression must compare
  DEBUG=0 and DEBUG=1 W/AW/B traces and prove byte-identical.
- **DEBUG_LEVEL=2 must remain sim-only.** The `// synthesis translate_off`
  pragma plus the `generate-if (DEBUG_LEVEL >= 2)` guard plus the
  standalone-syn build pin (DEBUG_LEVEL=1) is a triple gate. CI must
  reject any synthesis attempt with `DEBUG_LEVEL=2`.

## 11. Acceptance

Tests 1-7 PASS in cosim at `DEBUG_LEVEL=1`. Test 9 PASS confirms
`DEBUG_LEVEL=0` and `DEBUG_LEVEL=1` produce byte-identical W/AW/B
traces. Test 10 PASS confirms the shared scoreboard cross-validates
DEBUG=1 payload against DEBUG=2 lineage with zero unmatched CQEs.
Standalone Quartus syn at `DEBUG_LEVEL=1` closes at 275 MHz with
< 5 % ALM growth vs `DEBUG_LEVEL=0`. Then ready for subsystem-level
cosim under `rdma_subsystem/tb_int/`.
