`ifndef RDMA_CQ_PUSHER_IF_SV
`define RDMA_CQ_PUSHER_IF_SV

interface rdma_cq_pusher_if #(parameter int unsigned WQE_BUS_W = 512,
                              parameter int unsigned DBG_META_W = 64);
  logic clk;
  logic reset_n;

  logic [63:0]             cfg_cq_base;
  logic [15:0]             cfg_cq_depth;
  logic                    cfg_enable;

  logic                    cq_head_dbl_pulse;
  logic [15:0]             cq_head_dbl_value;

  logic [WQE_BUS_W-1:0]    s_axis_cqe_tdata;
  logic                    s_axis_cqe_tvalid;
  logic                    s_axis_cqe_tready;
  logic                    s_axis_cqe_tlast;
  logic [15:0]             s_axis_cqe_tuser;
  logic [DBG_META_W-1:0]   s_axis_cqe_tuser_meta;

  logic [15:0]             cq_tail;

  logic [3:0]              m_axi_awid;
  logic [63:0]             m_axi_awaddr;
  logic [7:0]              m_axi_awlen;
  logic [2:0]              m_axi_awsize;
  logic [1:0]              m_axi_awburst;
  logic                    m_axi_awvalid;
  logic                    m_axi_awready;

  logic [WQE_BUS_W-1:0]    m_axi_wdata;
  logic [WQE_BUS_W/8-1:0]  m_axi_wstrb;
  logic                    m_axi_wlast;
  logic                    m_axi_wvalid;
  logic                    m_axi_wready;

  logic [3:0]              m_axi_bid;
  logic [1:0]              m_axi_bresp;
  logic                    m_axi_bvalid;
  logic                    m_axi_bready;

  logic                    msix_req;
  logic [4:0]              msix_vector;
  logic                    msix_ack;

  logic [31:0]             cnt_cqe_posted;

  logic [15:0]             dbg_cur_cq_tail;
  logic [15:0]             dbg_cur_cq_head_credit;
  logic                    dbg_cq_full;
  logic [3:0]              dbg_aw_pending;
  logic [3:0]              dbg_b_inflight;
  logic [31:0]             dbg_ring_full_stall_cyc;
  logic [3:0]              dbg_state;
  logic [31:0]             dbg_cnt_bresp_error;
  logic [DBG_META_W-1:0]   dbg_last_pushed_meta;
endinterface

`endif
