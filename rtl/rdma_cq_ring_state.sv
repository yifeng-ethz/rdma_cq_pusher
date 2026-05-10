// File name: rdma_cq_ring_state.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : support 16-bit max-depth CQ ring wrap encoding

`default_nettype none

module rdma_cq_ring_state #(
    parameter int unsigned DEBUG_LEVEL = 0
) (
    input  wire logic        clk,
    input  wire logic        reset_n,

    input  wire logic [15:0] cfg_cq_depth,

    input  wire logic        cq_head_dbl_pulse,
    input  wire logic [15:0] cq_head_dbl_value,

    input  wire logic        advance_tail,

    output logic [15:0]      cur_cq_tail,
    output logic [15:0]      cur_cq_head,
    output logic             cq_full,
    output logic             cq_empty
);

    typedef struct packed {
        logic [15:0] tail;
        logic [15:0] head;
    } ring_state_t;

    localparam ring_state_t RING_RESET_CONST = '{
        tail : 16'h0000,
        head : 16'h0000
    };

    ring_state_t ring;

    logic [15:0] ring_depth_mask;
    logic [15:0] ring_next_tail;

    assign ring_depth_mask  = cfg_cq_depth - 16'd1;
    assign ring_next_tail   = (ring.tail + 16'd1) & ring_depth_mask;

    assign cur_cq_tail = ring.tail;
    assign cur_cq_head = ring.head;
    assign cq_empty    = (ring.tail == ring.head);
    assign cq_full     = (ring_next_tail == ring.head);

    always_ff @(posedge clk or negedge reset_n) begin : ring_bookkeeper
        if (!reset_n) begin
            ring <= RING_RESET_CONST;
        end else begin
            if (cq_head_dbl_pulse) begin
                ring.head <= cq_head_dbl_value & ring_depth_mask;
            end

            if (advance_tail) begin
                ring.tail <= ring_next_tail;
            end
        end
    end

    generate
        if (DEBUG_LEVEL >= 2) begin : g_debug2
            // synthesis translate_off
            initial begin
                $display("[%m] DEBUG_LEVEL=%0d observes CQ ring state", DEBUG_LEVEL);
            end
            // synthesis translate_on
        end
    endgenerate

endmodule

`default_nettype wire
