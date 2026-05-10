// File name: rdma_cq_msix.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : add Phase 1 MSI-X quiet stub for CQE pusher

`default_nettype none

module rdma_cq_msix #(
    parameter int unsigned DEBUG_LEVEL = 0
) (
    input  wire logic       clk,
    input  wire logic       reset_n,

    input  wire logic       cfg_enable,
    input  wire logic       push_done,

    output logic            msix_req,
    output logic [4:0]      msix_vector,
    input  wire logic       msix_ack
);

    logic phase1_quiet_req;

    assign msix_req    = phase1_quiet_req;
    assign msix_vector = 5'h00;

    // synthesis translate_off
    always_ff @(posedge clk or negedge reset_n) begin : msix_phase1_checker
        if (!reset_n) begin
            assert (!msix_req);
        end else begin
            assert (!msix_req);
            assert (msix_vector == 5'h00);
        end
    end

    initial begin : parameter_sanity
        assert (DEBUG_LEVEL <= 2)
            else $fatal(1, "rdma_cq_msix DEBUG_LEVEL must be 0, 1, or 2");
    end
    // synthesis translate_on

    // Phase 1 consumes these future interrupt inputs without asserting MSI-X.
    always_comb begin : phase1_input_quiet
        phase1_quiet_req = 1'b0 & (cfg_enable | push_done | msix_ack);
    end

endmodule

`default_nettype wire
