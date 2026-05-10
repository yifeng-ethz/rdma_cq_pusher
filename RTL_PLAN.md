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
rdma_cq_pusher.sv           (top)
├── rdma_cq_ring_state.sv   (head/tail/depth state)
├── rdma_cq_avmm_writer.sv  (AVMM master that issues 8-byte writes)
└── rdma_cq_msix.sv         (Phase 2 — interrupt generator; Phase 1 stub)
```

## 3. Top-level interface

CQE = 64 B (one cacheline). AXI4 master uses `WQE_BUS_W = 512` so one CQE
write = one AXI4 beat = one host cacheline atomic update. Inter-IP CQE bus
is **AXI4-Stream**.

```systemverilog
module rdma_cq_pusher #(
    parameter int unsigned WQE_BUS_W = 512   // 64 B CQE = one beat
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
    output logic [31:0]          cnt_cqe_posted
);
```

The 512-bit AXI4 wdata + all-1s wstrb means the host sees a **single
atomic cacheline write** for each CQE. No torn read: the host either
sees the entire previous CQE or the entire new one.

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

Lives at `tb/uvm/rdma_cq_pusher_tb_top.sv`.

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

## 6. CSR exposure

This IP has **no host-visible CSR** of its own. Surfaces:
- `cq_tail` → `csr.CQ_TAIL` (RO)
- `cnt_cqe_posted` → `csr.CNT_CQE_POSTED`

## 7. Synthesis sign-off

Standalone Quartus project at `syn/quartus/rdma_cq_pusher_standalone.qsf`.
Sign-off corner: 1.1× target = 275 MHz.

Estimated logic: ~120 ALMs + tiny CQE-latch RAM.

## 8. Files

```
rdma_cq_pusher/
├── README.md
├── RTL_PLAN.md                      (this file)
├── doc/
├── rtl/
│   ├── rdma_cq_pusher.sv
│   ├── rdma_cq_ring_state.sv
│   ├── rdma_cq_avmm_writer.sv
│   └── rdma_cq_msix.sv               (Phase 1 stub: ties msix_req=0)
├── tb/uvm/
│   ├── rdma_cq_pusher_tb_top.sv
│   └── Makefile
├── syn/quartus/
│   └── rdma_cq_pusher_standalone.qsf
├── rdma_cq_pusher_hw.tcl
├── Makefile
└── .git/
```

## 9. Implementation order

1. `rtl/rdma_cq_ring_state.sv`
2. `rtl/rdma_cq_avmm_writer.sv`
3. `rtl/rdma_cq_msix.sv` (Phase 1 stub)
4. `rtl/rdma_cq_pusher.sv` top
5. `tb/uvm/rdma_cq_pusher_tb_top.sv` + tests 1..7
6. `rdma_cq_pusher_hw.tcl`
7. Standalone signoff

## 10. Risks specific to this IP

- **CQE atomicity**: writing 8 bytes with one AVMM beat covers the full
  CQE; no torn write possible at this granularity. If Phase 2 widens
  CQE format (e.g. 16-byte for 64-bit phys-addr in CQE), revisit.
- **CQ depth power-of-2** required (same as SQ).
- **MSI-X vector**: Phase 2 needs a real vector. Phase 1 ties to 0.

## 11. Acceptance

Tests 1-7 PASS in cosim. Standalone Quartus syn closes at 275 MHz.
Then ready for subsystem-level cosim.
