# rdma_cq_pusher &mdash; Completion queue descriptor poster

Completion-queue descriptor poster for the Mu3e SWB rdma_subsystem. Writes 64-byte CQEs back to host DRAM after each DMA job completes.

## 1. Title + one-line summary

| Item | Value |
|---|---|
| IP | `rdma_cq_pusher` |
| Role | Completion Queue Entry poster for the SWB-side `rdma_subsystem` |
| Producer | `rdma_run_manager` sends one 64-byte CQE per completed DMA job |
| Consumer | Host software polls the CQ ring in host DRAM through the run-manager CSR aperture |
| External buses | AXI4-Stream CQE sink, AXI4 write-only host-memory master, sideband control/status |

This IP is the completion side of the RDMA-like SWB data path. It accepts
one CQE per AXI4-Stream beat, writes that CQE as one 64-byte AXI4 beat into
the host CQ ring, advances the FW-owned `cq_tail`, and exposes the posted
counter back to `rdma_run_manager`.

## 2. Architectural map

```
                         CSR-owned config and doorbell
                         from rdma_run_manager
                                  |
                                  v
+------------------+   +---------------------+   +---------------------+   +------------------+
| rdma_run_manager |-->| rdma_cq_pusher top  |-->| rdma_cq_axi_writer  |-->| host DRAM CQ ring|
| AXIS CQE source  |   | gate + counters     |   | AXI4 write master   |   | 64-byte CQ slots |
+------------------+   +----------+----------+   +----------+----------+   +------------------+
                                  |                         ^
                                  |                         |
                                  v                         | AXI4 B response
                         +--------+----------+              |
                         | rdma_cq_ring_    |--------------+
                         | state            | advance_tail
                         | head/tail/full   |
                         +--------+----------+
                                  |
                                  v
                         +--------+----------+
                         | rdma_cq_msix     |----> msix_req/msix_vector
                         | Phase 1 quiet    |      tied inactive in Phase 1
                         +------------------+

No IP-local AXI4-Lite or Avalon-MM CSR slave exists. JTAG-master access, when
present in a system, reaches the run-manager CSR aperture rather than this IP.
```

## 3. Contract - databus format

### 3.1 AXI4-Stream CQE sink

| Signal | Width | Role | Notes |
|---|---:|---|---|
| `s_axis_cqe_tdata` | `WQE_BUS_W` (`512`) | sink | One complete 64-byte CQE. The payload is written verbatim to host DRAM. |
| `s_axis_cqe_tvalid` | 1 | sink | CQE beat is valid. Accepted only when the ring is not full, the writer is idle, `cfg_enable=1`, and `tlast=1`. |
| `s_axis_cqe_tready` | 1 | source | Backpressure to `rdma_run_manager`; deasserts on full CQ ring, disabled IP, malformed beat, or active write. |
| `s_axis_cqe_tlast` | 1 | sink | Must be `1` on every accepted beat. Multi-beat CQEs are illegal. |
| `s_axis_cqe_tuser` | 16 | sink | `rqe_id`; RTL asserts that `s_axis_cqe_tdata[159:144] == s_axis_cqe_tuser`. |
| `s_axis_cqe_tuser_meta` | `DBG_META_W` (`64`) | sink, sim-only | DEBUG_LEVEL >= 2 lineage sidecar `{push_seq, origin_dma_done_seq, retire_seq, rqe_id}`. Guarded by `synthesis translate_off`. |
| `dbg_last_pushed_meta` | `DBG_META_W` (`64`) | source, sim-only | Most recent retired CQE lineage tuple for the DEBUG_LEVEL=2 monitor. |

There are no Avalon-ST data ports and no OPQ K-symbol sideband in this IP.
The OPQ 36-bit stream and its K-symbol positions are owned by
`rdma_dma_engine` and the supercore wrapper.

### 3.2 AXI4 host-memory write master

Standard AXI4 AW/W/B channel signals are present and keep their normal AXI4
meaning. This IP uses the constrained write-only subset below.

| Item | Constraint |
|---|---|
| Address | `m_axi_awaddr = cfg_cq_base + cq_tail * 64` |
| ID | `m_axi_awid = 0`; RTL asserts `m_axi_bid == m_axi_awid` on B acceptance |
| Burst length | `m_axi_awlen = 0`; one beat per CQE |
| Beat size | `m_axi_awsize = 6` for `WQE_BUS_W=512` (64 bytes) |
| Burst type | `m_axi_awburst = INCR` |
| Write strobes | `m_axi_wstrb = 64'hffff_ffff_ffff_ffff`; partial CQE writes are illegal |
| Last | `m_axi_wlast = 1` on the only beat |
| Outstanding writes | Maximum 1 CQE push in flight in Phase 1 |
| Ordering | CQEs are posted in ring-tail order; `cq_tail` advances only after an OKAY B response |
| BRESP handling | `OKAY` retires the CQE; non-OKAY increments `dbg_cnt_bresp_error` and retries the same latched CQE without advancing `cq_tail` |
| 4 KB rule | One 64-byte naturally aligned cacheline write; `cfg_cq_base` and host CQ slots must be 64-byte aligned by the integrator |

### 3.3 Sideband control and status

| Signal | Width | Role | Notes |
|---|---:|---|---|
| `cfg_cq_base` | 64 | sink | Host CQ ring base address, supplied by `rdma_run_manager` CSR state. |
| `cfg_cq_depth` | 16 | sink | CQ ring depth. Must be a power of two; ring logic masks pointers with `cfg_cq_depth - 1`. |
| `cfg_enable` | 1 | sink | Enables accepting new CQEs. Doorbell head updates still latch while disabled. |
| `cq_head_dbl_pulse` | 1 | sink | Host-consumer doorbell pulse from run-manager CSR decode. |
| `cq_head_dbl_value` | 16 | sink | New host CQ head value, masked by `cfg_cq_depth - 1`. |
| `cq_tail` | 16 | source | FW producer pointer; sampled by `rdma_run_manager` and exposed to the host as `CQ_TAIL`. |
| `cnt_cqe_posted` | 32 | source | Saturating count of CQEs retired with OKAY BRESP. |
| `msix_req` | 1 | source | Phase 1 quiet stub, tied inactive. |
| `msix_vector` | 5 | source | Phase 1 reserved vector, tied `0`. |
| `msix_ack` | 1 | sink | Consumed by the Phase 1 stub without asserting MSI-X. |
| `dbg_cur_cq_tail` | 16 | source | DEBUG_LEVEL >= 1 mirror of `cq_tail`; tied `0` at DEBUG_LEVEL=0. |
| `dbg_cur_cq_head_credit` | 16 | source | DEBUG_LEVEL >= 1 mirror of the host head pointer. |
| `dbg_cq_full` | 1 | source | DEBUG_LEVEL >= 1 ring-full predicate. |
| `dbg_aw_pending` | 4 | source | DEBUG_LEVEL >= 1 writer AW issued / not retired view; maximum 1 in Phase 1. |
| `dbg_b_inflight` | 4 | source | DEBUG_LEVEL >= 1 B-channel wait view; maximum 1 in Phase 1. |
| `dbg_ring_full_stall_cyc` | 32 | source | DEBUG_LEVEL >= 1 saturating count of ring-full backpressure cycles. |
| `dbg_state` | 4 | source | DEBUG_LEVEL >= 1 AXI writer FSM state. |
| `dbg_cnt_bresp_error` | 32 | source | DEBUG_LEVEL >= 1 saturating count of non-OKAY BRESP retries. |

### 3.4 CQE 64-byte payload layout

The pusher treats the CQE as opaque data except for the `rqe_id` assertion at
`tdata[159:144]`. The current supercore CQE contract is:

| Word | Byte offset | Name | Width | Description |
|---:|---:|---|---:|---|
| 0 | `0x00` | `bytes_written_total` | 64 | Total bytes written across both RQE segments. |
| 1 | `0x08` | `seg0_bytes_written` / `seg1_bytes_written` | 32 / 32 | Segment-local byte counts, low then high. |
| 2 | `0x10` | `status_id` | 64 | `[15:0]=status`, `[31:16]=rqe_id`, `[63:32]=flags`. |
| 3 | `0x18` | `event_count` | 64 | Number of OPQ end-of-event boundaries observed. |
| 4 | `0x20` | `first_event_ts` | 64 | OPQ timestamp of the first event in the drain. |
| 5 | `0x28` | `last_event_ts` | 64 | OPQ timestamp of the last event in the drain. |
| 6 | `0x30` | `opq_drop_snapshot` | 64 | Snapshot of the OPQ drop counter at retire. |
| 7 | `0x38` | `retire_seq` | 64 | Per-engine monotonic CQE sequence number. |

| Status bit | Name | Meaning |
|---:|---|---|
| 0 | `EOE` | Drain ended on end-of-event. |
| 1 | `FULL` | Both host segments were exhausted. |
| 2 | `HALT` | Backpressure/drop condition; host should investigate. |
| 3 | `SEG_BOUNDARY_HIT` | Payload crossed from segment 0 to segment 1. |
| 4 | `SEG0_ONLY` | Only segment 0 was used. |
| 5 | `ALIGN_ERR` | RQE address or span failed alignment constraints upstream. |
| 6-15 | reserved | Must be ignored by host software. |

## 4. How to start

### 4.1 Clone + initialize

```bash
git clone https://github.com/yifeng-ethz/rdma_cq_pusher.git
cd rdma_cq_pusher
# or as a submodule of mu3e-ip-cores:
git submodule update --init --recursive rdma_cq_pusher
```

### 4.2 Standalone simulation

The unit UVM harness is under `tb/uvm` and uses QuestaOne 2026.1 by default.
The canonical smoke target runs B001, B002, and B003.

```bash
cd tb/uvm
make smoke
```

Useful adjacent targets from the same Makefile:

```bash
make compile
make TEST=rdma_cq_pusher_b001_test CASE_ID=B001 run_one
make regress
```

### 4.3 Standalone synthesis

The standalone Quartus project lives under `syn/quartus` and synthesizes the
DEBUG_LEVEL=1 harness at the 275 MHz sign-off corner.

```bash
cd syn/quartus
quartus_sh --flow compile rdma_cq_pusher_standalone -c rdma_cq_pusher_standalone
```

## 5. CSR snapshot

This IP has no IP-local AXI4-Lite or Avalon-MM CSR slave, no checked-in SVD,
and no `_hw.tcl` package in this repo snapshot. The complete IP-local CSR map
is therefore empty; the software-visible aliases are owned by
`rdma_run_manager`.

| Offset | Name | Access | Width | Default | Description |
|-------:|------|:------:|------:|:--------:|-------------|
| `-` | `cq_tail` | RO sideband | 16 | `0x0000` | Exported to `rdma_run_manager.CQ_TAIL`; reset by `rdma_cq_ring_state.RING_RESET_CONST.tail`. |
| `-` | `cnt_cqe_posted` | RO sideband | 32 | `0x00000000` | Exported to `rdma_run_manager.CNT_CQE_POSTED`; reset by `rdma_cq_pusher.PUSHER_RESET_CONST.cqe_posted_count`. |
| `-` | `dbg_ring_full_stall_cyc` | debug sideband | 32 | `0x00000000` | DEBUG_LEVEL >= 1 saturating full-stall counter; tied `0` at DEBUG_LEVEL=0. |
| `-` | `dbg_cnt_bresp_error` | debug sideband | 32 | `0x00000000` | DEBUG_LEVEL >= 1 saturating non-OKAY BRESP counter; reset by `rdma_cq_axi_writer.WRITER_RESET_CONST.bresp_error_count`. |
| `-` | `msix_req` | sideband | 1 | `0` | Phase 1 MSI-X quiet stub output. |
| `-` | `msix_vector` | sideband | 5 | `0x00` | Phase 1 reserved vector. |

No RW register is decoded locally, so there are no local RW bitfield
breakdown tables. The host-visible supercore aliases that touch this IP are:

| Run-manager offset | Name | Direction at this IP | Notes |
|---:|---|---|---|
| `0x20` / `0x24` | `CQ_BASE_LO` / `CQ_BASE_HI` | input | Drive `cfg_cq_base`. |
| `0x28` | `CQ_DEPTH` | input | Drives `cfg_cq_depth`; power-of-two constraint. |
| `0x2C` | `CQ_TAIL` | output | Reads `cq_tail`. |
| `0x30` | `CQ_HEAD_DBL` | input pulse | Drives `cq_head_dbl_pulse` and `cq_head_dbl_value`. |
| `0x38` | `CNT_CQE_POSTED` | output | Reads `cnt_cqe_posted`. |

## 6. Versions + phase status

| Item | Value |
|---|---|
| RTL version | `26.1.0` in all four RTL source headers |
| RTL date | `20260510` |
| Package version | No `_hw.tcl` exists in this IP repo snapshot; parent IP table still marks this repo as `Prototype`. |
| SVD version | No `rdma_cq_pusher.svd` exists in this IP repo snapshot. |
| Current pre-README HEAD | `3625b1d` (`[PATCH] Per-case unique-coverage rule verified and docs updated`) |

The IP-local `PHASE_STATUS.md` file is not present. The sibling supercore
status snapshot at `../rdma_subsystem/PHASE_STATUS.md` records
`rdma_cq_pusher` as:

| Phase | Status | Evidence |
|---|---|---|
| Phase A | DONE all 9 | RTL/UVM/standalone artifact count captured in the supercore status snapshot. |
| Phase B | DONE all 512 evidenced | `tb/DV_REPORT.md`: 512 promoted and evidenced cases, 0 failures, 100.0% promoted functional coverage. |
| Phase C | DONE | `doc/QUEUE_MATH.md`. |
| Phase D | DONE | `syn/SYN_REPORT.md`: static screen PASS, Quartus PASS, 275 MHz timing PASS, resource band PASS. |
| Unique-cov audit | DONE | Supercore snapshot cites `2e1ca03`; this checkout carries later per-case unique-coverage updates through `3625b1d`. |

## 7. Cross-references

| Area | Reference |
|---|---|
| Parent supercore | `../rdma_subsystem/ARCHITECTURE_PLAN.md` |
| Supercore phase status | `../rdma_subsystem/PHASE_STATUS.md` |
| RQE producer sibling | `../rdma_rq_fetcher/RTL_PLAN.md` |
| DMA worker sibling | `../rdma_dma_engine/RTL_PLAN.md` |
| Coordinator and CSR owner | `../rdma_run_manager/RTL_PLAN.md` |
| FEB SciFi project style guide | `/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/README.md` |
| SWB integration consumer | `/home/yifeng/packages/online_sc/online/switching_pc/a10_board/doc/RDMA_SUBSYSTEM_INTEGRATION_20260511.md` |
| SWB bridge include | `/home/yifeng/packages/online_sc/online/common/firmware/a10/swb/rdma_subsystem_include.qip` |
| Parent IP table | `/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/README.md` |
| Relevant memory | `~/.claude/projects/-home-yifeng-packages-mu3e-ip-dev/memory/feedback_swb_datapath_legacy_broken.md` |
| Relevant memory | `~/.claude/projects/-home-yifeng-packages-mu3e-ip-dev/memory/feedback_swb_ring_lock.md` |
| Relevant memory | `~/.claude/projects/-home-yifeng-packages-mu3e-ip-dev/memory/feedback_signoff_slack_at_1p1x.md` |
| Relevant memory | `~/.claude/projects/-home-yifeng-packages-mu3e-ip-dev/memory/feedback_tb_int_uses_generated_rtl.md` |
