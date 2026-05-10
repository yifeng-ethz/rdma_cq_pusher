// File name: rdma_cq_pusher_standalone_harness.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : add standalone Quartus harness for rdma_cq_pusher signoff

`default_nettype none

module rdma_cq_pusher_standalone_harness (
    input  wire logic        clk,
    input  wire logic        reset_n,
    output logic [31:0]      harness_status
);

    localparam int unsigned WQE_BUS_W_CONST = 512;

    typedef struct packed {
        logic [WQE_BUS_W_CONST-1:0] cqe_payload;
        logic [15:0]                cqe_id;
        logic [15:0]                doorbell_value;
        logic [7:0]                 doorbell_phase;
        logic                       bvalid;
        logic [31:0]                write_count;
        logic [31:0]                status_mix;
    } harness_state_t;

    localparam harness_state_t HARNESS_RESET_CONST = '{
        cqe_payload    : 512'h0123_4567_89ab_cdef_fedc_ba98_7654_3210_0011_2233_4455_6677_8899_aabb_ccdd_eeff_1020_3040_5060_7080_90a0_b0c0_d0e0_f001_1357_9bdf_2468_ace0_55aa_aa55_0f0f_f0f0,
        cqe_id         : 16'h0001,
        doorbell_value : 16'h0080,
        doorbell_phase : 8'h00,
        bvalid         : 1'b0,
        write_count    : 32'h0000_0000,
        status_mix     : 32'h0000_0000
    };

    harness_state_t harness;

    logic                      s_axis_cqe_tready;
    logic [15:0]               cq_tail;
    logic [3:0]                m_axi_awid;
    logic [63:0]               m_axi_awaddr;
    logic [7:0]                m_axi_awlen;
    logic [2:0]                m_axi_awsize;
    logic [1:0]                m_axi_awburst;
    logic                      m_axi_awvalid;
    logic [WQE_BUS_W_CONST-1:0] m_axi_wdata;
    logic [WQE_BUS_W_CONST/8-1:0] m_axi_wstrb;
    logic                      m_axi_wlast;
    logic                      m_axi_wvalid;
    logic                      m_axi_bready;
    logic                      msix_req;
    logic [4:0]                msix_vector;
    logic [31:0]               cnt_cqe_posted;
    logic [15:0]               dbg_cur_cq_tail;
    logic [15:0]               dbg_cur_cq_head_credit;
    logic                      dbg_cq_full;
    logic [3:0]                dbg_aw_pending;
    logic [3:0]                dbg_b_inflight;
    logic [31:0]               dbg_ring_full_stall_cyc;
    logic [3:0]                dbg_state;
    logic [31:0]               dbg_cnt_bresp_error;
    logic                      cqe_accept;
    logic                      aw_accept;
    logic                      w_accept;
    logic                      b_accept;
    logic [31:0]               harness_status_event_mix;
    logic [WQE_BUS_W_CONST-1:0] harness_next_cqe_payload;

    assign cqe_accept     = s_axis_cqe_tready;
    assign aw_accept      = m_axi_awvalid;
    assign w_accept       = m_axi_wvalid;
    assign b_accept       = harness.bvalid && m_axi_bready;
    assign harness_status = harness.status_mix ^ cnt_cqe_posted ^
                            {16'h0000, cq_tail} ^
                            {27'h000_0000, msix_vector};
    assign harness_next_cqe_payload = {
        harness.cqe_payload[511:160],
        harness.cqe_id,
        16'h0001,
        harness.cqe_payload[126:0],
        harness.cqe_payload[511] ^ harness.cqe_payload[389] ^
        harness.cqe_payload[255] ^ harness.cqe_payload[127]
    };
    assign harness_status_event_mix =
        (aw_accept ? (m_axi_awaddr[31:0] ^
                      m_axi_awaddr[63:32] ^
                      {28'h000_0000, m_axi_awid}) : 32'h0000_0000) ^
        (w_accept ? (m_axi_wdata[31:0] ^
                     m_axi_wdata[287:256] ^
                     m_axi_wdata[511:480] ^
                     m_axi_wstrb[31:0] ^
                     m_axi_wstrb[63:32] ^
                     {24'h00_0000, m_axi_awlen} ^
                     {29'h0000_0000, m_axi_awsize} ^
                     {30'h0000_0000, m_axi_awburst} ^
                     {31'h0000_0000, m_axi_wlast}) : 32'h0000_0000) ^
        {16'h0000, dbg_cur_cq_tail} ^
        {16'h0000, dbg_cur_cq_head_credit} ^
        {31'h0000_0000, dbg_cq_full} ^
        {28'h000_0000, dbg_aw_pending} ^
        {28'h000_0000, dbg_b_inflight} ^
        dbg_ring_full_stall_cyc ^
        {28'h000_0000, dbg_state} ^
        dbg_cnt_bresp_error ^
        harness.write_count;

    rdma_cq_pusher #(
        .WQE_BUS_W  (WQE_BUS_W_CONST),
        .DEBUG_LEVEL(1),
        .DBG_META_W (64)
    ) dut_i (
        .clk                     (clk),
        .reset_n                 (reset_n),
        .cfg_cq_base             (64'h0000_1000_0000_0000),
        .cfg_cq_depth            (16'h0100),
        .cfg_enable              (1'b1),
        .cq_head_dbl_pulse       (harness.doorbell_phase[3]),
        .cq_head_dbl_value       (harness.doorbell_value),
        .s_axis_cqe_tdata        (harness.cqe_payload),
        .s_axis_cqe_tvalid       (1'b1),
        .s_axis_cqe_tready       (s_axis_cqe_tready),
        .s_axis_cqe_tlast        (1'b1),
        .s_axis_cqe_tuser        (harness.cqe_id),
        .cq_tail                 (cq_tail),
        .m_axi_awid              (m_axi_awid),
        .m_axi_awaddr            (m_axi_awaddr),
        .m_axi_awlen             (m_axi_awlen),
        .m_axi_awsize            (m_axi_awsize),
        .m_axi_awburst           (m_axi_awburst),
        .m_axi_awvalid           (m_axi_awvalid),
        .m_axi_awready           (1'b1),
        .m_axi_wdata             (m_axi_wdata),
        .m_axi_wstrb             (m_axi_wstrb),
        .m_axi_wlast             (m_axi_wlast),
        .m_axi_wvalid            (m_axi_wvalid),
        .m_axi_wready            (1'b1),
        .m_axi_bid               (m_axi_awid),
        .m_axi_bresp             (2'b00),
        .m_axi_bvalid            (harness.bvalid),
        .m_axi_bready            (m_axi_bready),
        .msix_req                (msix_req),
        .msix_vector             (msix_vector),
        .msix_ack                (1'b0),
        .cnt_cqe_posted          (cnt_cqe_posted),
        .dbg_cur_cq_tail         (dbg_cur_cq_tail),
        .dbg_cur_cq_head_credit  (dbg_cur_cq_head_credit),
        .dbg_cq_full             (dbg_cq_full),
        .dbg_aw_pending          (dbg_aw_pending),
        .dbg_b_inflight          (dbg_b_inflight),
        .dbg_ring_full_stall_cyc (dbg_ring_full_stall_cyc),
        .dbg_state               (dbg_state),
        .dbg_cnt_bresp_error     (dbg_cnt_bresp_error)
    );

    always_ff @(posedge clk or negedge reset_n) begin : harness_driver
        if (!reset_n) begin
            harness <= HARNESS_RESET_CONST;
        end else begin
            harness.doorbell_phase    <= harness.doorbell_phase + 8'd1;
            harness.cqe_payload       <= cqe_accept ? harness_next_cqe_payload :
                                                      harness.cqe_payload;
            harness.cqe_id            <= cqe_accept ? (harness.cqe_id + 16'd1) :
                                                      harness.cqe_id;
            harness.doorbell_value    <= (harness.doorbell_phase == 8'h0f) ?
                                         (cq_tail + 16'h0080) :
                                         harness.doorbell_value;
            harness.bvalid            <= w_accept ? 1'b1 :
                                         (b_accept ? 1'b0 : harness.bvalid);
            harness.write_count       <= w_accept ? (harness.write_count + 32'd1) :
                                         harness.write_count;
            harness.status_mix        <= harness.status_mix ^ harness_status_event_mix;
        end
    end

endmodule

`default_nettype wire
