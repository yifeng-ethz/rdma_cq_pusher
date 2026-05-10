# rtl_note.md - rdma_cq_pusher RTL and synthesis note

## Targets

`rdma_cq_pusher` writes one 64 B CQE to the host CQ ring per accepted
AXI4-Stream beat. The standalone synthesis target is Arria 10
`10AX115N2F45E1SG` at 275 MHz, which is 1.1x the 250 MHz production
target.

## RTL Mapping

The maintained RTL source set is:

- `rtl/rdma_cq_ring_state.sv`: CQ head/tail and full/empty predicate.
- `rtl/rdma_cq_axi_writer.sv`: single-beat 512-bit AXI4 write engine.
- `rtl/rdma_cq_msix.sv`: Phase 1 MSI-X quiet stub.
- `rtl/rdma_cq_pusher.sv`: top-level stream gating, address generation,
  counter aggregation, debug taps, and DEBUG_LEVEL 2 sim-only sidecar
  threading.

`DEBUG_LEVEL=2` remains simulation-only through synthesis translate guards.
The standalone Quartus build instantiates the DUT at `DEBUG_LEVEL=1`.

## Evidence

- Static screen: PASS, Lint Error 0, CDC Violations 0, RDC Violations 0.
- Quartus fit: PASS, 197 ALMs, 0 M20K, 0 DSP.
- Quartus STA: PASS, worst setup slack 1.410 ns at the 3.636 ns period.

Detailed synthesis sign-off is in `syn/SYN_REPORT.md`.
