# Queue / throughput / atomicity math - `rdma_cq_pusher`

**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-05-10
**Parent docs:** [../RTL_PLAN.md](../RTL_PLAN.md),
[../tb/DV_PLAN.md](../tb/DV_PLAN.md)

This document is the analytical backbone of the `rdma_cq_pusher` DV
contract. It quantifies sustainable CQE rates, backpressure
propagation, host credit-window sizing, the per-CQE atomicity
guarantee, the DEBUG=2 sidecar inertness proof, and the Phase 2
MSI-X impact estimate.

The numerical bounds here back the PROF bucket
(`../tb/DV_PROF.md`) thresholds: every "credit window" or
"sustained throughput" assertion in P065-P096 and P097-P128 is
anchored here.

---

## Notation

| Symbol | Meaning | Default |
|---|---|---|
| `f_clk` | datapath clock frequency | 250 MHz |
| `W_AXI` | AXI4 master data width | 512 b |
| `W_CQE` | CQE size on the wire | 64 B = 512 b = 1 cacheline |
| `T_PCIe_RTT` | host PCIe Gen3 write round-trip (AW issue to BRESP back) | 100 - 300 ns |
| `T_PCIe_typ` | typical PCIe Gen3 posted-write latency | 200 ns |
| `T_FSM_min` | minimum FSM round-trip with zero-lag completer | 5 clk |
| `D_cq` | CQ depth (host-side ring slots) | 256 |
| `R_OPQ_max` | upstream max OPQ event rate | 250 kHz |
| `R_RQ_max` | upstream max RQE/job rate (one RQE per OPQ-event group) | 250 kHz |
| `R_CQE_min` | sustainable CQE post rate target | >= R_RQ_max |

All numbers below assume `f_clk = 250 MHz`, `W_AXI = 512 b`, and
single-id in-order AXI4 master unless otherwise noted.

---

## 1. CQE rate vs RQE retire rate

### 1.1 Minimum FSM round-trip

The push FSM is `IDLE -> AW -> W -> B -> ADVANCE_TAIL -> IDLE`,
five states. With a zero-lag AXI4 completer (every `*ready=1`,
`bvalid` asserted same clk as `wlast`), one CQE retires every
5 clk:

```
T_CQE_min  = 5 clk = 5 / 250e6 = 20 ns
R_CQE_max  = 1 / T_CQE_min     = 50 M CQEs/s
```

This is the analytical upper bound on CQE rate at zero PCIe lag.

### 1.2 PCIe-realistic round-trip

Real PCIe Gen3 write latency adds host round-trip cost that the
AXI4 host completer must model. The round-trip from `awvalid` to
`bvalid` for a posted write is dominated by the host-side memory
controller plus the PCIe TLP path; published reference numbers put
this at `100 - 300 ns`. The B handshake gates `ADVANCE_TAIL`, so
each CQE round-trip is:

```
T_CQE_PCIe = T_FSM_min  +  T_PCIe_RTT - 1  (B handshake replaces
                                             the in-FSM B clk)
           ~= 5 clk + (T_PCIe_RTT / clk) - 1 clk
```

For the typical case `T_PCIe_RTT = 200 ns = 50 clk`:

```
T_CQE_typ  = 5 + 50 - 1 = 54 clk = 216 ns
R_CQE_typ  = 1 / 216e-9 = 4.6 M CQEs/s
```

For the worst-case `T_PCIe_RTT = 300 ns = 75 clk`:

```
T_CQE_worst = 5 + 75 - 1 = 79 clk = 316 ns
R_CQE_worst = 1 / 316e-9 = 3.2 M CQEs/s
```

### 1.3 Sustained CQE rate vs. RQE rate

The RQE / job rate from `rdma_run_manager` is bounded by the OPQ
event rate, which the architecture plan caps at the order of
`250 kHz` per QP for Phase 1 nominal traffic. Therefore:

```
R_CQE_sustain = min(R_CQE_typ, R_OPQ_max)
              = min(4.6 M, 250 k)
              = 250 k CQEs/s
```

### 1.4 Verdict

The CQE pusher is **NOT** the bottleneck. Even at worst-case PCIe
RTT (300 ns), the pusher sustains `~3.2 M CQEs/s`, which is a
factor of `~13` above the sustainable upstream RQE rate at
`250 kHz`. This means:

- the CQ ring depth and credit window are dominated by the host
  poll cadence, not by the pusher's intrinsic rate;
- a clean credit window of even a few hundred slots is plenty to
  absorb host poll jitter at typical PCIe RTT;
- the pusher will spend most cycles in IDLE waiting for the next
  CQE from `rdma_run_manager`, not in B waiting for the host.

This anchors PROF cases:

- **P001-P003** (sustained throughput at depth 256 / 4096 / 65536)
  - expect average per-CQE latency `~5 clk + B_lat`; sustained
    rate at zero-lag is `0.2 CQE/clk = 50 M/s` (§1.1).
- **P017-P032** (throughput vs B-channel latency)
  - per-CQE round trip = `5 + B_lat` clk; rate = `1 / (5 + B_lat)`
    CQE/clk; cross-checked against the analytical curve here.

---

## 2. Backpressure analysis (credit window sizing)

The pusher stalls when the CQ ring is full. The host releases
credit by writing `cq_head` via the doorbell pulse. If the host
poll cadence is slow relative to the CQE arrival rate, the ring
fills, `cq_full=1` asserts, and `s_axis_cqe_tready=0`. That
backpressure propagates back through `rdma_run_manager` (which
stalls RQE retire) and ultimately stalls `rdma_rq_fetcher` (which
stalls RQE consumption from host RQ).

### 2.1 The credit window question

Given a sustained upstream CQE rate `R_CQE` and a host doorbell
service interval `T_doorbell`, what is the minimum CQ depth `D_cq`
such that the host NEVER starves the pusher?

Between consecutive doorbell pulses, the pusher posts up to
`R_CQE * T_doorbell` CQEs. For the pusher to never stall, the
ring must hold that many fresh slots:

```
D_cq_min = R_CQE * T_doorbell + 1   (the +1 prevents tail==head wraparound)
```

### 2.2 Host poll cadence numbers

Practical host poll cadences depend on the application:

| Application class | Typical `T_doorbell` |
|---|---|
| Tight-loop polling (busy-wait by a dedicated core) | 1 us - 10 us |
| Interrupt-driven with IRQ coalescing (Phase 2 MSI-X) | 100 us - 1 ms |
| Periodic poll thread on a shared core (Phase 1) | 100 us - 10 ms |

### 2.3 Credit window for sustained 250 kHz CQE rate

At sustained `R_CQE = 250 kHz` (max upstream rate) and host poll
period `T_doorbell = 1 ms` (a conservative shared-core poll
thread):

```
D_cq_min = 250e3 * 1e-3 + 1 = 251
```

At `T_doorbell = 100 us` (tight loop with thread context switch):

```
D_cq_min = 250e3 * 100e-6 + 1 = 26
```

At `T_doorbell = 10 ms` (poor scheduling, batched CQ harvest):

```
D_cq_min = 250e3 * 10e-3 + 1 = 2501
```

### 2.4 Verdict

- The default `D_cq = 256` is right at the edge for a `1 ms` host
  poll period. P065-P080 sweep this analytically.
- For `T_doorbell >= 4 ms`, the host MUST size `D_cq >= 1024` (or
  ideally `4096`) to avoid sustained backpressure.
- For tight polling (`T_doorbell <= 100 us`), `D_cq = 256` gives
  a 10x safety margin.

The CQ-full propagation chain is a designed-in feature, not a bug:
when the host cannot keep up, FW correctly stalls RQE consumption
so the host never overflows. P081-P096 exercise the propagation
chain end-to-end with deliberately starved doorbells.

This anchors PROF cases:

- **P065-P080** (credit-window sweep across `D_cq` and
  `T_doorbell` bins) -- §2.3.
- **P081-P096** (backpressure chain proof: pusher full propagates
  back to run_manager, which stalls RQ consumption) -- §2.4.

---

## 3. Atomicity proof (64 B CQE = 1 AXI4 W beat = 1 cacheline)

### 3.1 The atomicity claim

Each CQE write is exactly one AXI4 W beat with `wstrb` all-ones,
`wlast=1`, `awsize=$clog2(W_AXI/8)=6`, `awlen=0`. Therefore each
CQE write is exactly:

- one AXI4 transaction (one AW handshake, one W beat, one B
  handshake);
- one cacheline-aligned write (`awaddr = cfg_cq_base + cq_tail*64`
  is naturally 64 B aligned);
- one full cacheline (all 64 B) overwritten.

### 3.2 The host observability claim

A 64 B AXI4-Stream-mapped write to a cacheline-aligned address
that fully overwrites the cacheline (all 64 byte enables, no
partial writes) is observed atomically by the host: the host
either sees the entire previous CQE OR the entire new CQE in that
slot, never a torn fragment. This is true because:

- PCIe TLPs of a single 64 B write are delivered in-order to a
  64 B-aligned target;
- the host's memory controller commits a 64 B aligned write as a
  single cacheline update (regardless of underlying DRAM access
  granularity);
- a host CPU read of a cacheline traverses the cache hierarchy
  with cacheline granularity, so the read either sees pre-write
  or post-write data, never a mix.

Therefore: **no torn read**. The host can poll the CQ slot
contents (e.g. checking the `valid` bit in word 2) without any
fence or memory barrier and is guaranteed to read a fully formed
CQE or a fully old CQE. The host distinguishes "old" from "new"
by the CQE `valid` bit (or, equivalently, by checking that the
`rqe_id` matches the expected next-CQE ID; the FW maintains a
generation bit per slot to disambiguate the wraparound case).

### 3.3 SVA enforcement

Atomicity is enforced by `sva_atomicity` in `tb/uvm/sva/`:

- every cycle `m_axi_wvalid && m_axi_wready`, assert
  `m_axi_wlast == 1` and `m_axi_wstrb == {(W_AXI/8){1'b1}}`;
- exactly one `(wvalid && wready && wlast)` per CQE accepted;
- the W payload at that cycle equals the CQE that drove the
  preceding AW.

A protocol violation here would silently corrupt host CQE state
that the host CPU read as "fully formed" but actually contained a
mix. SVA catches it before silicon.

### 3.4 Verdict

64 B CQE = 1 AXI4 W beat with all-1s WSTRB = single-cacheline
atomic write. **Host either sees full prior or full new CQE; no
torn read.** This is the fundamental safety property the CQE wire
format was sized for; sub-cacheline CQEs (e.g. a Phase 2 16 B CQE
proposal) would lose this property and need an explicit
"write-then-flag" two-phase protocol.

This anchors BASIC cases:

- **B019** (CQE byte-perfect: each of 8 x 64-bit words preserved)
  -- §3.1, §3.2.
- **B044** (`wstrb == all-1s` for full cacheline write) -- §3.1.
- **B081** (full-cacheline write atomically observable on host)
  -- §3.2, §3.3.

---

## 4. DEBUG_LEVEL=2 sidecar inertness proof

### 4.1 The proof obligation

The DEBUG_LEVEL=2 sim-only widening adds a per-CQE metadata
sidecar `(rqe_id, retire_seq, origin_dma_done_seq, push_seq)`
flowing alongside the AXI4-Stream CQE input through a sim-only
meta-FIFO that mirrors the W/B inflight depth. The proof
obligation is: **removing the sidecar must not change any payload
signal of the DUT**.

### 4.2 The argument

The sidecar is structurally:

1. driven by the env_dbg2 driver alongside the env_dbg1 payload
   driver at the DUT's input pins
   (`s_axis_cqe_tuser_meta`, parametrized port group);
2. flowed into a sim-only meta-FIFO inside the DUT
   (`rdma_cq_pusher_dbg_meta_fifo.sv`, gated by
   `generate-if (DEBUG_LEVEL >= 2)` and `// synthesis
   translate_off / _on` pragmas);
3. popped one entry per `m_axi_bvalid && m_axi_bready &&
   m_axi_bresp == OKAY` and exposed at the DUT output port
   `dbg_last_pushed_meta` (also sim-only).

For the inertness proof:

- **No combinational fan-in from sidecar to AXI4 master payload.**
  `m_axi_awaddr` is `cfg_cq_base + cq_tail * 64`, where `cq_tail`
  is updated only on B-OKAY retire and is independent of any
  sidecar bit. `m_axi_wdata` is `s_axis_cqe_tdata` directly,
  which is independent of `s_axis_cqe_tuser_meta`. `m_axi_wstrb`,
  `m_axi_wlast`, `m_axi_awlen`, `m_axi_awsize`, `m_axi_awburst`,
  `m_axi_awvalid`, `m_axi_wvalid`, `m_axi_bready` are all FSM-
  driven; the FSM transitions on `tvalid`, `tready`, `awready`,
  `wready`, `bvalid`, and `bresp`, not on sidecar bits.
- **No combinational fan-in from sidecar to the doorbell mask
  logic or the `cq_full` predicate.** `cq_full` is
  `((cq_tail+1) & (cfg_cq_depth-1)) == cq_head`; both `cq_tail`
  and `cq_head` are payload-domain registers.
- **No combinational fan-in from sidecar to counters.**
  `cnt_cqe_posted` increments on B-OKAY (a payload event); the
  saturating `dbg_ring_full_stall_cyc` and `dbg_cnt_bresp_error`
  also derive from payload events.
- **No combinational fan-in from sidecar to the AXI4-Stream
  source's `tready`.** `s_axis_cqe_tready` is
  `!cq_full && (state == IDLE) && cfg_enable`; all three terms
  are payload-domain.

The sidecar is a **pure passenger** of the payload pipeline. The
meta-FIFO depth and pop pointer are functions of the W/B handshake
events, but those handshakes are payload-driven; the meta-FIFO
state can READ those events without driving them.

### 4.3 The synthesis-build behavior

When `DEBUG_LEVEL = 0`:

- `s_axis_cqe_tuser_meta` is tied to `'0` at the DUT boundary
  (the parameter-controlled port-mux in `rdma_cq_pusher.sv`).
- The meta-FIFO instance is removed by the
  `generate-if (DEBUG_LEVEL >= 2)` guard and the `// synthesis
  translate_off` pragma; the synthesized netlist contains no
  meta-FIFO logic.
- `dbg_last_pushed_meta` is tied to `'0`.

When `DEBUG_LEVEL = 1`:

- Sidecar still tied to `'0` at the DUT boundary.
- Same as DEBUG=0 for sidecar; only the synthesizable `dbg_*`
  status taps (`dbg_cur_cq_tail`, `dbg_cur_cq_head_credit`,
  `dbg_cq_full`, `dbg_aw_pending`, `dbg_b_inflight`,
  `dbg_ring_full_stall_cyc`, `dbg_state`, `dbg_cnt_bresp_error`)
  are exposed.

When `DEBUG_LEVEL = 2`:

- Sidecar input `s_axis_cqe_tuser_meta` becomes live; carries
  the per-CQE meta from env_dbg2.
- Meta-FIFO instance is generated; depth >= max in-flight AW
  (Phase 1: 1).
- `dbg_last_pushed_meta` exposes the per-retire lineage to the
  TB.

### 4.4 The DV-side proof gate

The shared scoreboard cross-validates: for the **same CQE
stimulus**, the DEBUG=1 build and the DEBUG=2 build must produce
**bit-identical** payload signals on:

- `m_axi_awaddr`, `m_axi_awlen`, `m_axi_awsize`, `m_axi_awburst`,
  `m_axi_awvalid`,
- `m_axi_wdata`, `m_axi_wstrb`, `m_axi_wlast`, `m_axi_wvalid`,
  `m_axi_bready`,
- `s_axis_cqe_tready`,
- `cq_tail`, `cnt_cqe_posted`, `dbg_cur_cq_tail`,
  `dbg_cur_cq_head_credit`, `dbg_cq_full`, `dbg_state`,
  `dbg_cnt_bresp_error`,
- `cnt_cqe_posted`.

A separate transparency check (`make transparency_check` per
`DV_HARNESS.md` §7.5) recompiles the DUT at DEBUG_LEVEL=0 (no
dbg_* ports, no sidecar) and re-runs a fixed signature test set,
comparing the AW/W/B trace byte-for-byte. Disagreement between
DEBUG=0 and DEBUG=1, or between DEBUG=1 and DEBUG=2, is a hard
failure (sign-off ladder rung 7 in `DV_PLAN.md`).

### 4.5 Verdict

The DEBUG=2 sidecar is structurally inert by design (pure
passenger; no fan-in into payload). The DV scoreboard's
bit-identity check enforces this at every CQE retire boundary.
**Any disagreement is a closure blocker** per the dv-workflow
OoO-datapath rule.

This anchors:

- **B093, B094, B095** (DEBUG=1 ports tied to 0, no perturbation,
  flopped).
- **B103, B104** (sidecar tied to 0 at DEBUG=0, sidecar does not
  appear in W payload).
- **B108** (shared scoreboard cross-validates 100% lineage
  closure across the BASIC sidecar batch).
- **P099 / P100** style bit-identity cross-build runs in the PROF
  bucket.
- **X122 / X123** ERROR bucket cross-variant equivalence.

---

## 5. MSI-X (Phase 2 stub) impact estimate at 100 kHz CQE rate

### 5.1 Current Phase 1 contract

Phase 1 ties `msix_req = 1'b0`, `msix_vector = '0`, and ignores
`msix_ack`. The host learns about new CQEs by polling the
`csr.CQ_TAIL` register (which mirrors `cq_tail`) or by polling
the CQE slot's `valid` bit directly. There is no interrupt path.

### 5.2 Phase 2 design sketch

Phase 2 will replace `rdma_cq_msix.sv` with a real MSI-X
generator that:

- pulses `msix_req = 1'b1` for one cycle per `ADVANCE_TAIL`
  retire (or per N retires with a programmable coalescing
  counter);
- holds the assertion until `msix_ack = 1'b1` (the PCIe HIP
  signals "TLP delivered");
- uses a single MSI-X vector per CQ (vector index from
  `csr.MSIX_VECTOR_<qp_id>`).

### 5.3 Cost estimate at 100 kHz CQE rate

At sustained `R_CQE = 100 kHz`, MSI-X interrupts fire 100 k
times/s if no coalescing is applied. Each interrupt costs the
host:

| Cost component | Approx. |
|---|---|
| PCIe MSI-X TLP (4 DW posted write) | ~80 - 160 ns |
| Host interrupt-controller dispatch | ~1 - 3 us |
| Host kernel ISR entry / exit | ~1 - 5 us |
| Wakeup / context switch to user thread | ~3 - 10 us |
| **Total per interrupt** | **~5 - 18 us** |

At 100 kHz uncoalesced:

```
fraction_cpu_in_interrupt = 100e3 * 10e-6 = 1.0  (100% of one core)
```

This is unsustainable. With **coalescing factor 16**:

```
R_irq    = 100e3 / 16 = 6.25 kHz
fraction = 6.25e3 * 10e-6 = 6.25%  (of one core)
```

At coalescing 64:

```
R_irq    = 100e3 / 64 = 1.56 kHz
fraction = 1.56e3 * 10e-6 = 1.56%
```

### 5.4 Coalescing recommendation

For `R_CQE` in the `100 kHz - 1 MHz` band that the run_manager is
designed to source, MSI-X coalescing of `16 - 64` per interrupt
keeps host interrupt CPU below ~10 % of one core. A timer-based
fallback ("interrupt at least every T_irq_max regardless of
count") at `T_irq_max = 100 us - 1 ms` ensures latency tail is
bounded for low-rate traffic.

### 5.5 Phase 1 verification impact

Phase 1 must verify that the MSI-X stub never asserts spuriously
under any stimulus that Phase 2 might (post-CQE retire, doorbell
pulse, BRESP error, reset, MSI-X ack pulse). This is the
`sva_msix_quiet` SVA contract enforced in BASIC (B109-B116) and
ERROR (X069-X074) buckets. Once Phase 2 lands, `sva_msix_quiet`
is removed and replaced by `sva_msix_per_retire` (one msix_req
pulse per ADVANCE_TAIL with proper handshake), but the wiring
contract (port stays, vector stays, ack handshake) is locked in
Phase 1 so Phase 2 does not regress integration.

### 5.6 Verdict

Phase 1 MSI-X stub is verifiably inert by `sva_msix_quiet` plus
the BASIC + ERROR bucket cases. Phase 2 wire-up at 100 kHz CQE
rate with coalescing factor 16 - 64 keeps host interrupt CPU
below 10 %, well within budget. The stub-to-real wire-up
contract is preserved across the phase transition.

This anchors:

- **B109-B116** (MSI-X stub quiescence in BASIC).
- **X069-X074** (MSI-X stub poisoning in ERROR).
- Phase 2 follow-on cases that will land in a separate IP
  revision; the Phase 1 contract documented here ensures the
  Phase 1 -> Phase 2 transition is a port-level wire-up rather
  than a cross-bucket regression.

---

## 6. Synthesis cost

For reference (not formally bound here; details land in
`syn/quartus/` standalone signoff):

- DEBUG=0 build: ~120 ALMs (FSM + ring-state + AXI4 master) +
  small CQE-latch (one 512-bit register).
- DEBUG=1 build: ~150 ALMs (DEBUG=0 + 8 status taps including the
  saturating `dbg_ring_full_stall_cyc` and `dbg_cnt_bresp_error`
  counters).
- DEBUG=2 build: not synthesized; `// synthesis translate_off`
  guards + `generate-if (DEBUG_LEVEL >= 2)` removes the
  meta-FIFO. The standalone-syn build is pinned at
  `DEBUG_LEVEL=1` (CI rejects DEBUG_LEVEL=2 synth attempts).

Standalone Quartus 1.1x sign-off corner is `275 MHz` (250 x 1.1).
DEBUG=1 build target with `< 5%` ALM growth vs DEBUG=0.

---

## 7. Linkage to DV bucket cases

Bucket cases that depend on this analysis:

| Case | Anchor |
|------|--------|
| B019 / B044 / B081 (atomicity smoke) | §3.1, §3.2, §3.3 |
| B093 / B094 / B095 (DEBUG=1 transparency) | §4.4 |
| B103 / B104 / B108 (DEBUG=2 inertness) | §4.2, §4.5 |
| B109-B116 (MSI-X stub quiet) | §5.5 |
| P001-P003 (sustained throughput, depth sweep) | §1.1, §1.4 |
| P017-P032 (throughput vs B-channel latency) | §1.2, §1.3 |
| P065-P080 (credit-window sweep) | §2.3, §2.4 |
| P081-P096 (backpressure chain proof) | §2.4 |
| P099 / P100 style (cross-build residual) | §4.4 |
| X069-X074 (MSI-X stub poisoning) | §5.5 |
| X122 / X123 (ERROR cross-variant equivalence) | §4.4 |

This document is the analytical anchor for these cases. When a
PROF or BASIC case fails, the failing residual must be reconciled
against the prediction here before declaring an RTL bug.

---

## 8. Open items

- §1 assumes single-ID AXI4 master with in-order completion. If
  Phase 2 widens to multi-ID (multiple CQEs in flight), the
  meta-FIFO depth and the `dbg_aw_pending` / `dbg_b_inflight`
  counters scale up, and the credit-window math becomes an
  M/M/c queue rather than M/M/1. Re-derive when that happens.
- §2 host poll cadence numbers are estimates; the supercore
  cosim under `rdma_subsystem/tb_int/` will measure real host
  poll cadence on the integration target and substitute measured
  values for §2.3.
- §3 atomicity argument assumes a host that respects the AXI4
  cacheline-aligned, all-byte-enables write contract. PCIe
  endpoints that fragment a 64 B TLP into smaller writes on the
  inbound path would break the atomicity property; the
  `rdma_subsystem` cosim must verify the host TLP shape for the
  target platform.
- §4 inertness proof relies on the codex2 RTL author respecting
  the parameter-controlled port-mux pattern. The DV cross-build
  check is the safety net -- it catches leaks if the proof
  obligation is violated.
- §5 Phase 2 MSI-X coalescing constants (16 / 64) are a starting
  estimate. Real Phase 2 tuning will measure host ISR overhead
  on the target machine and adjust.
