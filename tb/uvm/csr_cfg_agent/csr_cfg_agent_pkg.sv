`ifndef CSR_CFG_AGENT_PKG_SV
`define CSR_CFG_AGENT_PKG_SV

package csr_cfg_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class csr_cfg_item extends uvm_sequence_item;
    `uvm_object_utils(csr_cfg_item)

    bit [63:0]      base;
    bit [15:0]      depth;
    bit             enable;
    longint unsigned cycle;

    function new(string name = "csr_cfg_item");
      super.new(name);
      base = 64'h0000_1000_0000_0000;
      depth = 16'd256;
      enable = 1'b1;
      cycle = 0;
    endfunction
  endclass

  class csr_cfg_agent_cfg extends uvm_object;
    `uvm_object_utils(csr_cfg_agent_cfg)

    virtual rdma_cq_pusher_if vif;
    csr_cfg_item pending_q[$];
    bit [63:0] current_base;
    bit [15:0] current_depth;
    bit        current_enable;

    function new(string name = "csr_cfg_agent_cfg");
      super.new(name);
      current_base = 64'h0000_1000_0000_0000;
      current_depth = 16'd256;
      current_enable = 1'b1;
    endfunction

    function void enqueue(csr_cfg_item item);
      pending_q.push_back(item);
      current_base = item.base;
      current_depth = item.depth;
      current_enable = item.enable;
    endfunction

    function bit has_pending();
      return (pending_q.size() != 0);
    endfunction

    function csr_cfg_item pop_front();
      csr_cfg_item item;
      if (pending_q.size() == 0)
        return null;
      item = pending_q[0];
      pending_q.delete(0);
      return item;
    endfunction
  endclass

  `include "csr_cfg_driver.sv"
  `include "csr_cfg_monitor.sv"
  `include "csr_cfg_agent.sv"
endpackage

`endif
