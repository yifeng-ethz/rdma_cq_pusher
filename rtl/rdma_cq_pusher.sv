// File name: rdma_cq_pusher.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : wire CQ ring, AXI4 writer, MSI-X stub, and debug taps

`default_nettype none

module rdma_cq_pusher #(
    parameter int unsigned WQE_BUS_W     = 512,
    parameter int unsigned DEBUG_LEVEL   = 0,
    parameter int unsigned DBG_META_W    = 64
) (
    input  wire logic                 clk,
    input  wire logic                 reset_n,

    input  wire logic [63:0]          cfg_cq_base,
    input  wire logic [15:0]          cfg_cq_depth,
    input  wire logic                 cfg_enable,

    input  wire logic                 cq_head_dbl_pulse,
    input  wire logic [15:0]          cq_head_dbl_value,

    input  wire logic [WQE_BUS_W-1:0] s_axis_cqe_tdata,
    input  wire logic                 s_axis_cqe_tvalid,
    output logic                      s_axis_cqe_tready,
    input  wire logic                 s_axis_cqe_tlast,
    input  wire logic [15:0]          s_axis_cqe_tuser,

    output logic [15:0]               cq_tail,

    output logic [3:0]                m_axi_awid,
    output logic [63:0]               m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  wire logic                 m_axi_awready,

    output logic [WQE_BUS_W-1:0]      m_axi_wdata,
    output logic [WQE_BUS_W/8-1:0]    m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  wire logic                 m_axi_wready,

    input  wire logic [3:0]           m_axi_bid,
    input  wire logic [1:0]           m_axi_bresp,
    input  wire logic                 m_axi_bvalid,
    output logic                      m_axi_bready,

    output logic                      msix_req,
    output logic [4:0]                msix_vector,
    input  wire logic                 msix_ack,

    output logic [31:0]               cnt_cqe_posted,

    output logic [15:0]               dbg_cur_cq_tail,
    output logic [15:0]               dbg_cur_cq_head_credit,
    output logic                      dbg_cq_full,
    output logic [3:0]                dbg_aw_pending,
    output logic [3:0]                dbg_b_inflight,
    output logic [31:0]               dbg_ring_full_stall_cyc,
    output logic [3:0]                dbg_state,
    output logic [31:0]               dbg_cnt_bresp_error

    // synthesis translate_off
    , input  wire logic [DBG_META_W-1:0] s_axis_cqe_tuser_meta
    , output logic [DBG_META_W-1:0]      dbg_last_pushed_meta
    // synthesis translate_on
);

    localparam int unsigned CQE_BYTES_CONST      = WQE_BUS_W / 8;
    localparam int unsigned CQE_BYTE_SHIFT_CONST = $clog2(CQE_BYTES_CONST);
    localparam logic [31:0] COUNTER_MAX_CONST    = 32'hffff_ffff;

    typedef struct packed {
        logic [31:0] cqe_posted_count;
    } pusher_state_t;

    localparam pusher_state_t PUSHER_RESET_CONST = '{
        cqe_posted_count : 32'h0000_0000
    };

    pusher_state_t pusher;

    logic [15:0]          cur_cq_tail;
    logic [15:0]          cur_cq_head;
    logic                 cq_full;
    logic                 cq_empty;
    logic                 cqe_stream_well_formed;
    logic                 writer_cmd_valid;
    logic                 writer_cmd_ready;
    logic                 writer_done;
    logic [63:0]          cqe_byte_offset;
    logic [63:0]          writer_addr;
    logic [3:0]           writer_dbg_aw_pending;
    logic [3:0]           writer_dbg_b_inflight;
    logic [3:0]           writer_dbg_state;
    logic [31:0]          writer_dbg_cnt_bresp_error;

    assign cqe_stream_well_formed = !s_axis_cqe_tvalid || s_axis_cqe_tlast;
    assign s_axis_cqe_tready      =
        cfg_enable && !cq_full && writer_cmd_ready && cqe_stream_well_formed;
    assign writer_cmd_valid       = s_axis_cqe_tvalid && s_axis_cqe_tready;

    assign cqe_byte_offset = {48'h0000_0000_0000, cur_cq_tail} << CQE_BYTE_SHIFT_CONST;
    assign writer_addr     = cfg_cq_base + cqe_byte_offset;

    assign cq_tail        = cur_cq_tail;
    assign cnt_cqe_posted = pusher.cqe_posted_count;

    rdma_cq_ring_state #(
        .DEBUG_LEVEL(DEBUG_LEVEL)
    ) ring_state_i (
        .clk               (clk),
        .reset_n           (reset_n),
        .cfg_cq_depth      (cfg_cq_depth),
        .cq_head_dbl_pulse (cq_head_dbl_pulse),
        .cq_head_dbl_value (cq_head_dbl_value),
        .advance_tail      (writer_done),
        .cur_cq_tail       (cur_cq_tail),
        .cur_cq_head       (cur_cq_head),
        .cq_full           (cq_full),
        .cq_empty          (cq_empty)
    );

    rdma_cq_axi_writer #(
        .WQE_BUS_W  (WQE_BUS_W),
        .DEBUG_LEVEL(DEBUG_LEVEL),
        .DBG_META_W (DBG_META_W)
    ) axi_writer_i (
        .clk                 (clk),
        .reset_n             (reset_n),
        .write_addr          (writer_addr),
        .write_data          (s_axis_cqe_tdata),
        .write_cmd_valid     (writer_cmd_valid),
        .write_cmd_ready     (writer_cmd_ready),
        .write_done          (writer_done),
        .m_axi_awid          (m_axi_awid),
        .m_axi_awaddr        (m_axi_awaddr),
        .m_axi_awlen         (m_axi_awlen),
        .m_axi_awsize        (m_axi_awsize),
        .m_axi_awburst       (m_axi_awburst),
        .m_axi_awvalid       (m_axi_awvalid),
        .m_axi_awready       (m_axi_awready),
        .m_axi_wdata         (m_axi_wdata),
        .m_axi_wstrb         (m_axi_wstrb),
        .m_axi_wlast         (m_axi_wlast),
        .m_axi_wvalid        (m_axi_wvalid),
        .m_axi_wready        (m_axi_wready),
        .m_axi_bid           (m_axi_bid),
        .m_axi_bresp         (m_axi_bresp),
        .m_axi_bvalid        (m_axi_bvalid),
        .m_axi_bready        (m_axi_bready),
        .dbg_aw_pending      (writer_dbg_aw_pending),
        .dbg_b_inflight      (writer_dbg_b_inflight),
        .dbg_state           (writer_dbg_state),
        .dbg_cnt_bresp_error (writer_dbg_cnt_bresp_error)
        // synthesis translate_off
        , .write_meta         (s_axis_cqe_tuser_meta)
        , .dbg_last_pushed_meta(dbg_last_pushed_meta)
        // synthesis translate_on
    );

    rdma_cq_msix #(
        .DEBUG_LEVEL(DEBUG_LEVEL)
    ) msix_i (
        .clk        (clk),
        .reset_n    (reset_n),
        .cfg_enable (cfg_enable),
        .push_done  (writer_done),
        .msix_req   (msix_req),
        .msix_vector(msix_vector),
        .msix_ack   (msix_ack)
    );

    always_ff @(posedge clk or negedge reset_n) begin : pusher_counters
        if (!reset_n) begin
            pusher <= PUSHER_RESET_CONST;
        end else if (writer_done && (pusher.cqe_posted_count != COUNTER_MAX_CONST)) begin
            pusher.cqe_posted_count <= pusher.cqe_posted_count + 32'd1;
        end
    end

    generate
        if (DEBUG_LEVEL >= 1) begin : g_debug1
            logic [31:0] debug_ring_full_stall_count;

            always_ff @(posedge clk or negedge reset_n) begin : debug1_counter
                if (!reset_n) begin
                    debug_ring_full_stall_count <= 32'h0000_0000;
                end else if (cq_full && s_axis_cqe_tvalid && !s_axis_cqe_tready &&
                             (debug_ring_full_stall_count != COUNTER_MAX_CONST)) begin
                    debug_ring_full_stall_count <= debug_ring_full_stall_count + 32'd1;
                end
            end

            assign dbg_cur_cq_tail         = cur_cq_tail;
            assign dbg_cur_cq_head_credit  = cur_cq_head;
            assign dbg_cq_full             = cq_full;
            assign dbg_aw_pending          = writer_dbg_aw_pending;
            assign dbg_b_inflight          = writer_dbg_b_inflight;
            assign dbg_ring_full_stall_cyc = debug_ring_full_stall_count;
            assign dbg_state               = writer_dbg_state;
            assign dbg_cnt_bresp_error     = writer_dbg_cnt_bresp_error;
        end else begin : g_no_debug1
            assign dbg_cur_cq_tail         = 16'h0000;
            assign dbg_cur_cq_head_credit  = 16'h0000;
            assign dbg_cq_full             = 1'b0;
            assign dbg_aw_pending          = 4'h0;
            assign dbg_b_inflight          = 4'h0;
            assign dbg_ring_full_stall_cyc = 32'h0000_0000;
            assign dbg_state               = 4'h0;
            assign dbg_cnt_bresp_error     = 32'h0000_0000;
        end
    endgenerate

    // synthesis translate_off
    always_ff @(posedge clk) begin : cqe_stream_assertions
        if (reset_n) begin
            if (s_axis_cqe_tvalid && s_axis_cqe_tready) begin
                assert (s_axis_cqe_tlast);
                assert (s_axis_cqe_tdata[159:144] == s_axis_cqe_tuser);
                if (DEBUG_LEVEL >= 2) begin
                    assert (s_axis_cqe_tuser_meta[15:0] == s_axis_cqe_tuser);
                end
            end
        end
    end

    initial begin : parameter_sanity
        assert (WQE_BUS_W == 512)
            else $fatal(1, "rdma_cq_pusher expects 512-bit CQE writes");
        assert (DEBUG_LEVEL <= 2)
            else $fatal(1, "rdma_cq_pusher DEBUG_LEVEL must be 0, 1, or 2");
        assert (DBG_META_W >= 16)
            else $fatal(1, "rdma_cq_pusher DBG_META_W must include sqe_id");
    end
    // synthesis translate_on

endmodule

`default_nettype wire
