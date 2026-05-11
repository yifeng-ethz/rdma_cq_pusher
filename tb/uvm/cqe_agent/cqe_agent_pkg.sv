`ifndef CQE_AGENT_PKG_SV
`define CQE_AGENT_PKG_SV

package cqe_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class cqe_item extends uvm_sequence_item;
    `uvm_object_utils(cqe_item)

    bit [511:0]      data;
    bit [15:0]       rqe_id;
    bit              last;
    bit [63:0]       meta;
    longint unsigned cycle;

    function new(string name = "cqe_item");
      super.new(name);
      data = '0;
      rqe_id = '0;
      last = 1'b1;
      meta = '0;
      cycle = 0;
    endfunction
  endclass

  class cqe_agent_cfg extends uvm_object;
    `uvm_object_utils(cqe_agent_cfg)

    virtual rdma_cq_pusher_if vif;
    cqe_item pending_q[$];

    function new(string name = "cqe_agent_cfg");
      super.new(name);
    endfunction

    function void enqueue(cqe_item item);
      pending_q.push_back(item);
    endfunction

    function bit has_pending();
      return (pending_q.size() != 0);
    endfunction

    function cqe_item pop_front();
      cqe_item item;
      if (pending_q.size() == 0)
        return null;
      item = pending_q[0];
      pending_q.delete(0);
      return item;
    endfunction
  endclass

  `include "cqe_driver.sv"
  `include "cqe_monitor.sv"
  `include "cqe_agent.sv"
endpackage

`endif
