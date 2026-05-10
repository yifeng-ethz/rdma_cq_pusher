# `opq_cq_pusher` — RTL Plan

Status: **PLAN — pending review.** Sibling IP of the `opq_rdma_subsystem`
supercore (`mu3e-ip-cores/opq_rdma_subsystem/ARCHITECTURE_PLAN.md`).

## 1. Role within the subsystem

Pushes Completion Queue Entries (CQEs) into the host CQ ring in host DRAM.
Accepts an Avalon-ST CQE stream from `opq_run_manager` and turns each
beat into one AVMM write at the next CQ ring slot, then atomically updates
the FW-owned `cq_tail` pointer (which the host polls from `csr.CQ_TAIL`).

In Phase 2, this is also where MSI-X interrupt generation lives.

The IP is fully **stateless to the data plane** — it only handles control
plane CQE bookkeeping.

## 2. Module hierarchy

```
opq_cq_pusher.sv           (top)
├── opq_cq_ring_state.sv   (head/tail/depth state)
├── opq_cq_avmm_writer.sv  (AVMM master that issues 8-byte writes)
└── opq_cq_msix.sv         (Phase 2 — interrupt generator; Phase 1 stub)
```

## 3. Top-level interface

```systemverilog
module opq_cq_pusher (
    input  logic         clk,
    input  logic         reset_n,

    // Configuration from run_manager (CSR-backed)
    input  logic [63:0]  cfg_cq_base,
    input  logic [15:0]  cfg_cq_depth,        // power of 2
    input  logic         cfg_enable,

    // Doorbell from CSR (host gives credit)
    input  logic         cq_head_dbl_pulse,
    input  logic [15:0]  cq_head_dbl_value,   // host-consumed up to here

    // CQE stream in from run_manager (Avalon-ST sink)
    input  logic [63:0]  cqe_data,            // packed cqe_t
    input  logic         cqe_valid,
    output logic         cqe_ready,

    // CQ tail (FW's producer pointer, sampled by run_manager into csr.CQ_TAIL)
    output logic [15:0]  cq_tail,

    // Avalon-MM master (write path)
    output logic [63:0]  avm_address,
    output logic         avm_write,
    output logic [63:0]  avm_writedata,
    output logic [7:0]   avm_byteenable,
    output logic [3:0]   avm_burstcount,
    input  logic         avm_waitrequest,

    // MSI-X (Phase 2 — tied to 0 in Phase 1)
    output logic         msix_req,
    output logic [4:0]   msix_vector,
    input  logic         msix_ack,

    // Sideband counters
    output logic [31:0]  cnt_cqe_posted
);
```

AVMM data width here is **64 bits** because one CQE is exactly 64b and the
write rate is low (one per SQE completion). Phase 2 may widen if multiple
CQEs queue up.

## 4. Behavior

### 4.1 CQ ring state

Maintains:
- `cq_tail` (FW's producer pointer; FW-owned, host reads via CSR)
- `cq_head` (host's consumer pointer; updated on `cq_head_dbl_pulse`)

`cq_full = ((cq_tail + 1) & (cq_depth-1)) == cq_head`. Push stalls when
full.

### 4.2 Push FSM (3 states)

```
IDLE
  | cqe_valid && !cq_full && cfg_enable
  v
PUSH_REQ                    ← avm_address = cfg_cq_base + cq_tail*8
                              avm_writedata = cqe_data
                              avm_byteenable = 8'hFF
                              avm_burstcount = 1
                              avm_write = 1
  | !waitrequest
  v
ADVANCE_TAIL: cq_tail <- (cq_tail + 1) & (cfg_cq_depth-1)
              cnt_cqe_posted++
              [Phase 2: msix_req <= 1 for one cycle]
  v
IDLE
```

### 4.3 Backpressure

`cqe_ready = !cq_full && (state == IDLE) && cfg_enable`.

If host doesn't drain CQ (no doorbell credit), pusher stalls. Run manager
in turn stalls SQE consumption — this propagates the right way.

## 5. Validation plan (unit-level cosim)

Lives at `tb/uvm/opq_cq_pusher_tb_top.sv`.

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

Standalone Quartus project at `syn/quartus/opq_cq_pusher_standalone.qsf`.
Sign-off corner: 1.1× target = 275 MHz.

Estimated logic: ~120 ALMs + tiny CQE-latch RAM.

## 8. Files

```
opq_cq_pusher/
├── README.md
├── RTL_PLAN.md                      (this file)
├── doc/
├── rtl/
│   ├── opq_cq_pusher.sv
│   ├── opq_cq_ring_state.sv
│   ├── opq_cq_avmm_writer.sv
│   └── opq_cq_msix.sv               (Phase 1 stub: ties msix_req=0)
├── tb/uvm/
│   ├── opq_cq_pusher_tb_top.sv
│   └── Makefile
├── syn/quartus/
│   └── opq_cq_pusher_standalone.qsf
├── opq_cq_pusher_hw.tcl
├── Makefile
└── .git/
```

## 9. Implementation order

1. `rtl/opq_cq_ring_state.sv`
2. `rtl/opq_cq_avmm_writer.sv`
3. `rtl/opq_cq_msix.sv` (Phase 1 stub)
4. `rtl/opq_cq_pusher.sv` top
5. `tb/uvm/opq_cq_pusher_tb_top.sv` + tests 1..7
6. `opq_cq_pusher_hw.tcl`
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
