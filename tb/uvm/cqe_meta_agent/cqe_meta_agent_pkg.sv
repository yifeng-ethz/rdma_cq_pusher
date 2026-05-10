`ifndef CQE_META_AGENT_PKG_SV
`define CQE_META_AGENT_PKG_SV

package cqe_meta_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class cqe_meta_item extends uvm_sequence_item;
    `uvm_object_utils(cqe_meta_item)

    bit [15:0]      sqe_id;
    bit [15:0]      retire_seq;
    bit [15:0]      origin_dma_done_seq;
    bit [15:0]      push_seq;
    bit [63:0]      packed_meta;
    longint unsigned cycle;

    function new(string name = "cqe_meta_item");
      super.new(name);
      sqe_id = '0;
      retire_seq = '0;
      origin_dma_done_seq = '0;
      push_seq = '0;
      packed_meta = '0;
      cycle = 0;
    endfunction

    function void repack();
      packed_meta = {push_seq, origin_dma_done_seq, retire_seq, sqe_id};
    endfunction
  endclass

  class cqe_meta_agent_cfg extends uvm_object;
    `uvm_object_utils(cqe_meta_agent_cfg)

    virtual rdma_cq_pusher_if vif;
    cqe_meta_item pending_q[$];

    function new(string name = "cqe_meta_agent_cfg");
      super.new(name);
    endfunction

    function void enqueue(cqe_meta_item item);
      item.repack();
      pending_q.push_back(item);
    endfunction

    function bit has_pending();
      return (pending_q.size() != 0);
    endfunction

    function cqe_meta_item pop_front();
      cqe_meta_item item;
      if (pending_q.size() == 0)
        return null;
      item = pending_q[0];
      pending_q.delete(0);
      return item;
    endfunction
  endclass

  `include "cqe_meta_driver.sv"
  `include "cqe_meta_monitor.sv"
  `include "cqe_meta_agent.sv"
endpackage

`endif
