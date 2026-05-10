// File name: rdma_cq_axi_writer.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : implement AXI4 write engine for one-cacheline CQE pushes

`default_nettype none

module rdma_cq_axi_writer #(
    parameter int unsigned WQE_BUS_W     = 512,
    parameter int unsigned DEBUG_LEVEL   = 0,
    parameter int unsigned DBG_META_W    = 64
) (
    input  wire logic                 clk,
    input  wire logic                 reset_n,

    input  wire logic [63:0]          write_addr,
    input  wire logic [WQE_BUS_W-1:0] write_data,
    input  wire logic                 write_cmd_valid,
    output logic                      write_cmd_ready,
    output logic                      write_done,

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

    output logic [3:0]                dbg_aw_pending,
    output logic [3:0]                dbg_b_inflight,
    output logic [3:0]                dbg_state,
    output logic [31:0]               dbg_cnt_bresp_error

    // synthesis translate_off
    , input  wire logic [DBG_META_W-1:0] write_meta
    , output logic [DBG_META_W-1:0]      dbg_last_pushed_meta
    // synthesis translate_on
);

    localparam int unsigned CQE_BYTES_CONST     = WQE_BUS_W / 8;
    localparam int unsigned AXI_SIZE_INT_CONST  = $clog2(CQE_BYTES_CONST);
    localparam logic [2:0] AXI_SIZE_CONST       = AXI_SIZE_INT_CONST[2:0];
    localparam logic [1:0] AXI_BURST_INCR_CONST = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY_CONST  = 2'b00;
    localparam logic [31:0] COUNTER_MAX_CONST   = 32'hffff_ffff;

    typedef enum logic [3:0] {
        IDLING         = 4'd0,
        ISSUING_AW     = 4'd1,
        ISSUING_W      = 4'd2,
        WAITING_B      = 4'd3,
        ADVANCING_TAIL = 4'd4
    } writer_fsm_state_t;

    typedef struct packed {
        writer_fsm_state_t    state;
        logic [63:0]          addr;
        logic [WQE_BUS_W-1:0] data;
        logic [31:0]          bresp_error_count;
    } writer_state_t;

    localparam writer_state_t WRITER_RESET_CONST = '{
        state             : IDLING,
        addr              : 64'h0000_0000_0000_0000,
        data              : '0,
        bresp_error_count : 32'h0000_0000
    };

    writer_state_t writer;

    logic writer_cmd_accept;
    logic writer_aw_accept;
    logic writer_w_accept;
    logic writer_b_accept;
    logic writer_b_okay;

    assign writer_cmd_accept = write_cmd_valid && write_cmd_ready;
    assign writer_aw_accept  = m_axi_awvalid && m_axi_awready;
    assign writer_w_accept   = m_axi_wvalid && m_axi_wready;
    assign writer_b_accept   = m_axi_bvalid && m_axi_bready;
    assign writer_b_okay     = (m_axi_bresp == AXI_RESP_OKAY_CONST);

    assign write_cmd_ready = (writer.state == IDLING);
    assign write_done      = (writer.state == ADVANCING_TAIL);

    assign m_axi_awid     = 4'h0;
    assign m_axi_awaddr   = writer.addr;
    assign m_axi_awlen    = 8'h00;
    assign m_axi_awsize   = AXI_SIZE_CONST;
    assign m_axi_awburst  = AXI_BURST_INCR_CONST;
    assign m_axi_awvalid  = (writer.state == ISSUING_AW);

    assign m_axi_wdata    = writer.data;
    assign m_axi_wstrb    = {CQE_BYTES_CONST{1'b1}};
    assign m_axi_wlast    = 1'b1;
    assign m_axi_wvalid   = (writer.state == ISSUING_W);

    assign m_axi_bready   = (writer.state == WAITING_B);

    assign dbg_aw_pending     =
        ((writer.state == ISSUING_W) ||
         (writer.state == WAITING_B) ||
         (writer.state == ADVANCING_TAIL)) ? 4'd1 : 4'd0;
    assign dbg_b_inflight     = (writer.state == WAITING_B) ? 4'd1 : 4'd0;
    assign dbg_state          = writer.state;
    assign dbg_cnt_bresp_error = writer.bresp_error_count;

    always_ff @(posedge clk or negedge reset_n) begin : axi_write_engine
        if (!reset_n) begin
            writer <= WRITER_RESET_CONST;
        end else begin
            unique case (writer.state)
                IDLING: begin
                    if (writer_cmd_accept) begin
                        writer.addr     <= write_addr;
                        writer.data     <= write_data;
                        writer.state    <= ISSUING_AW;
                    end
                end

                ISSUING_AW: begin
                    if (writer_aw_accept) begin
                        writer.state <= ISSUING_W;
                    end
                end

                ISSUING_W: begin
                    if (writer_w_accept) begin
                        writer.state <= WAITING_B;
                    end
                end

                WAITING_B: begin
                    if (writer_b_accept) begin
                        if (writer_b_okay) begin
                            writer.state <= ADVANCING_TAIL;
                        end else begin
                            if (writer.bresp_error_count != COUNTER_MAX_CONST) begin
                                writer.bresp_error_count <= writer.bresp_error_count + 32'd1;
                            end
                            writer.state <= ISSUING_AW;
                        end
                    end
                end

                ADVANCING_TAIL: begin
                    writer.state <= IDLING;
                end

                default: begin
                    writer.state <= IDLING;
                end
            endcase
        end
    end

    // synthesis translate_off
    generate
        if (DEBUG_LEVEL >= 2) begin : g_debug2_meta
            logic [DBG_META_W-1:0] writer_meta;

            always_ff @(posedge clk or negedge reset_n) begin : debug2_meta_tracker
                if (!reset_n) begin
                    writer_meta             <= '0;
                    dbg_last_pushed_meta    <= '0;
                end else begin
                    if (writer_cmd_accept) begin
                        writer_meta <= write_meta;
                    end

                    if (writer_b_accept && writer_b_okay) begin
                        dbg_last_pushed_meta <= writer_meta;
                    end
                end
            end
        end else begin : g_no_debug2_meta
            always_comb begin : debug2_meta_tieoff
                dbg_last_pushed_meta = '0;
            end
        end
    endgenerate
    // synthesis translate_on

    // synthesis translate_off
    always_ff @(posedge clk) begin : axi_write_protocol_assertions
        if (reset_n) begin
            if (m_axi_awvalid && !m_axi_awready) begin
                assert (m_axi_awaddr == writer.addr);
            end

            if (m_axi_wvalid && !m_axi_wready) begin
                assert (m_axi_wdata == writer.data);
                assert (m_axi_wstrb == {CQE_BYTES_CONST{1'b1}});
                assert (m_axi_wlast);
            end

            if (writer_b_accept) begin
                assert (m_axi_bid == m_axi_awid);
            end
        end
    end
    // synthesis translate_on

    // synthesis translate_off
    initial begin : parameter_sanity
        assert (WQE_BUS_W == 512)
            else $fatal(1, "rdma_cq_axi_writer expects 512-bit CQE writes");
    end
    // synthesis translate_on

endmodule

`default_nettype wire
