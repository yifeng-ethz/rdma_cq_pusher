`ifndef DEBUG_LEVEL
`define DEBUG_LEVEL 2
`endif

module rdma_cq_pusher_tb_top;
  import uvm_pkg::*;
  import rdma_cq_pusher_pkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned WQE_BUS_W = 512;
  localparam int unsigned DBG_META_W = 64;
  localparam int unsigned DEBUG = `DEBUG_LEVEL;

  rdma_cq_pusher_if #(
    .WQE_BUS_W(WQE_BUS_W),
    .DBG_META_W(DBG_META_W)
  ) dut_if();

  initial begin
    dut_if.clk = 1'b0;
    forever #2 dut_if.clk = ~dut_if.clk;
  end

  rdma_cq_pusher #(
    .WQE_BUS_W(WQE_BUS_W),
    .DEBUG_LEVEL(DEBUG),
    .DBG_META_W(DBG_META_W)
  ) dut (
    .clk(dut_if.clk),
    .reset_n(dut_if.reset_n),
    .cfg_cq_base(dut_if.cfg_cq_base),
    .cfg_cq_depth(dut_if.cfg_cq_depth),
    .cfg_enable(dut_if.cfg_enable),
    .cq_head_dbl_pulse(dut_if.cq_head_dbl_pulse),
    .cq_head_dbl_value(dut_if.cq_head_dbl_value),
    .s_axis_cqe_tdata(dut_if.s_axis_cqe_tdata),
    .s_axis_cqe_tvalid(dut_if.s_axis_cqe_tvalid),
    .s_axis_cqe_tready(dut_if.s_axis_cqe_tready),
    .s_axis_cqe_tlast(dut_if.s_axis_cqe_tlast),
    .s_axis_cqe_tuser(dut_if.s_axis_cqe_tuser),
    .cq_tail(dut_if.cq_tail),
    .m_axi_awid(dut_if.m_axi_awid),
    .m_axi_awaddr(dut_if.m_axi_awaddr),
    .m_axi_awlen(dut_if.m_axi_awlen),
    .m_axi_awsize(dut_if.m_axi_awsize),
    .m_axi_awburst(dut_if.m_axi_awburst),
    .m_axi_awvalid(dut_if.m_axi_awvalid),
    .m_axi_awready(dut_if.m_axi_awready),
    .m_axi_wdata(dut_if.m_axi_wdata),
    .m_axi_wstrb(dut_if.m_axi_wstrb),
    .m_axi_wlast(dut_if.m_axi_wlast),
    .m_axi_wvalid(dut_if.m_axi_wvalid),
    .m_axi_wready(dut_if.m_axi_wready),
    .m_axi_bid(dut_if.m_axi_bid),
    .m_axi_bresp(dut_if.m_axi_bresp),
    .m_axi_bvalid(dut_if.m_axi_bvalid),
    .m_axi_bready(dut_if.m_axi_bready),
    .msix_req(dut_if.msix_req),
    .msix_vector(dut_if.msix_vector),
    .msix_ack(dut_if.msix_ack),
    .cnt_cqe_posted(dut_if.cnt_cqe_posted),
    .dbg_cur_cq_tail(dut_if.dbg_cur_cq_tail),
    .dbg_cur_cq_head_credit(dut_if.dbg_cur_cq_head_credit),
    .dbg_cq_full(dut_if.dbg_cq_full),
    .dbg_aw_pending(dut_if.dbg_aw_pending),
    .dbg_b_inflight(dut_if.dbg_b_inflight),
    .dbg_ring_full_stall_cyc(dut_if.dbg_ring_full_stall_cyc),
    .dbg_state(dut_if.dbg_state),
    .dbg_cnt_bresp_error(dut_if.dbg_cnt_bresp_error),
    .s_axis_cqe_tuser_meta(dut_if.s_axis_cqe_tuser_meta),
    .dbg_last_pushed_meta(dut_if.dbg_last_pushed_meta)
  );

  default clocking cb @(posedge dut_if.clk); endclocking
  default disable iff (!dut_if.reset_n);

  ap_aw_hold: assert property (
    dut_if.m_axi_awvalid && !dut_if.m_axi_awready |=>
      dut_if.m_axi_awvalid && $stable(dut_if.m_axi_awaddr) &&
      $stable(dut_if.m_axi_awlen) && $stable(dut_if.m_axi_awsize) &&
      $stable(dut_if.m_axi_awburst)
  );

  ap_w_hold: assert property (
    dut_if.m_axi_wvalid && !dut_if.m_axi_wready |=>
      dut_if.m_axi_wvalid && $stable(dut_if.m_axi_wdata) &&
      $stable(dut_if.m_axi_wstrb) && $stable(dut_if.m_axi_wlast)
  );

  ap_aw_shape: assert property (
    dut_if.m_axi_awvalid |->
      (dut_if.m_axi_awlen == 8'h00) && (dut_if.m_axi_awsize == 3'd6) &&
      (dut_if.m_axi_awburst == 2'b01) && ((dut_if.m_axi_awaddr & 64'h3f) == 64'h0)
  );

  ap_w_shape: assert property (
    dut_if.m_axi_wvalid |->
      (dut_if.m_axi_wstrb == 64'hffff_ffff_ffff_ffff) && dut_if.m_axi_wlast
  );

  ap_msix_quiet: assert property (!dut_if.msix_req);

  initial begin
    uvm_config_db#(virtual rdma_cq_pusher_if)::set(null, "*", "vif", dut_if);
    run_test();
  end

  final begin
    uvm_report_server svr;
    int error_count;
    int fatal_count;
    svr = uvm_report_server::get_server();
    error_count = svr.get_severity_count(UVM_ERROR);
    fatal_count = svr.get_severity_count(UVM_FATAL);
    if ((error_count + fatal_count) != 0) begin
      $display("RDMA_CQ_PUSHER_TB_FAIL errors=%0d fatals=%0d", error_count, fatal_count);
      $fatal(1, "UVM reported errors or fatals");
    end
  end
endmodule
