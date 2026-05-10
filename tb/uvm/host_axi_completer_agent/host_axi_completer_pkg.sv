`ifndef HOST_AXI_COMPLETER_PKG_SV
`define HOST_AXI_COMPLETER_PKG_SV

package host_axi_completer_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam bit [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam bit [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam bit [1:0] AXI_RESP_DECERR = 2'b11;

  typedef enum int unsigned {
    HOST_AXI_AW = 0,
    HOST_AXI_W = 1,
    HOST_AXI_B = 2
  } host_axi_kind_e;

  class host_axi_item extends uvm_sequence_item;
    `uvm_object_utils(host_axi_item)

    host_axi_kind_e kind;
    bit [3:0]       id;
    bit [63:0]      addr;
    bit [7:0]       len;
    bit [2:0]       size;
    bit [1:0]       burst;
    bit [511:0]     data;
    bit [63:0]      strb;
    bit             last;
    bit [1:0]       resp;
    bit [15:0]      slot;
    longint unsigned cycle;

    function new(string name = "host_axi_item");
      super.new(name);
      kind = HOST_AXI_AW;
      id = '0;
      addr = '0;
      len = '0;
      size = '0;
      burst = '0;
      data = '0;
      strb = '0;
      last = 1'b0;
      resp = AXI_RESP_OKAY;
      slot = '0;
      cycle = 0;
    endfunction
  endclass

  class host_axi_completer_cfg extends uvm_object;
    `uvm_object_utils(host_axi_completer_cfg)

    virtual rdma_cq_pusher_if vif;
    bit [63:0] cfg_cq_base;
    bit [15:0] cfg_cq_depth;
    int unsigned awready_lag;
    int unsigned wready_lag;
    int unsigned bvalid_lag;
    bit [1:0] bresp_q[$];
    bit [511:0] host_mem[bit [15:0]];

    function new(string name = "host_axi_completer_cfg");
      super.new(name);
      cfg_cq_base = 64'h0000_1000_0000_0000;
      cfg_cq_depth = 16'd256;
      awready_lag = 0;
      wready_lag = 0;
      bvalid_lag = 0;
    endfunction

    function void configure(input bit [63:0] base, input bit [15:0] depth);
      cfg_cq_base = base;
      cfg_cq_depth = depth;
    endfunction

    function bit [15:0] addr_to_slot(input bit [63:0] addr);
      return ((addr - cfg_cq_base) >> 6) & depth_mask();
    endfunction

    function bit [15:0] depth_mask();
      if (cfg_cq_depth == 16'h0000)
        return 16'hffff;
      return cfg_cq_depth - 16'd1;
    endfunction

    function void push_bresp(input bit [1:0] resp);
      bresp_q.push_back(resp);
    endfunction

    function bit [1:0] next_bresp();
      if (bresp_q.size() == 0)
        return AXI_RESP_OKAY;
      return bresp_q.pop_front();
    endfunction
  endclass

  `include "host_axi_completer_driver.sv"
  `include "host_axi_completer_monitor.sv"
  `include "host_axi_completer_agent.sv"
endpackage

`endif
