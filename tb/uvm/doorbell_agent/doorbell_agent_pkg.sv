`ifndef DOORBELL_AGENT_PKG_SV
`define DOORBELL_AGENT_PKG_SV

package doorbell_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class doorbell_item extends uvm_sequence_item;
    `uvm_object_utils(doorbell_item)

    bit [15:0]      value;
    longint unsigned cycle;

    function new(string name = "doorbell_item");
      super.new(name);
      value = 16'h0000;
      cycle = 0;
    endfunction
  endclass

  class doorbell_agent_cfg extends uvm_object;
    `uvm_object_utils(doorbell_agent_cfg)

    virtual rdma_cq_pusher_if vif;
    doorbell_item pending_q[$];

    function new(string name = "doorbell_agent_cfg");
      super.new(name);
    endfunction

    function void enqueue(doorbell_item item);
      pending_q.push_back(item);
    endfunction

    function bit has_pending();
      return (pending_q.size() != 0);
    endfunction

    function doorbell_item pop_front();
      doorbell_item item;
      if (pending_q.size() == 0)
        return null;
      item = pending_q[0];
      pending_q.delete(0);
      return item;
    endfunction
  endclass

  `include "doorbell_driver.sv"
  `include "doorbell_monitor.sv"
  `include "doorbell_agent.sv"
endpackage

`endif
