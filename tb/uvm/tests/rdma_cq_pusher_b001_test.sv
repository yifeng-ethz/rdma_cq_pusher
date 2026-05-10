`ifndef RDMA_CQ_PUSHER_B001_TEST_SV
`define RDMA_CQ_PUSHER_B001_TEST_SV

class rdma_cq_pusher_b001_test extends rdma_cq_pusher_base_test;
  `uvm_component_utils(rdma_cq_pusher_b001_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B001";
  endfunction

  task run_case();
    rdma_cq_pusher_b001_idle_seq seq;
    seq = rdma_cq_pusher_b001_idle_seq::type_id::create("seq");
    seq.start(this);
    if (vif.cq_tail != 16'h0000)
      `uvm_error("B001", $sformatf("cq_tail=%0d after reset", vif.cq_tail))
    if (vif.cnt_cqe_posted != 32'h0000_0000)
      `uvm_error("B001", $sformatf("cnt_cqe_posted=%0d after reset", vif.cnt_cqe_posted))
    if (vif.dbg_state != 4'd0)
      `uvm_error("B001", $sformatf("dbg_state=%0d expected IDLE", vif.dbg_state))
    if (vif.dbg_cq_full)
      `uvm_error("B001", "dbg_cq_full asserted after reset")
    if (!vif.s_axis_cqe_tready)
      `uvm_error("B001", "s_axis_cqe_tready did not assert after reset")
  endtask
endclass

`endif
