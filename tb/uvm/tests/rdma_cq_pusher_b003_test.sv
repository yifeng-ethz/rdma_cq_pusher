`ifndef RDMA_CQ_PUSHER_B003_TEST_SV
`define RDMA_CQ_PUSHER_B003_TEST_SV

class rdma_cq_pusher_b003_test extends rdma_cq_pusher_base_test;
  `uvm_component_utils(rdma_cq_pusher_b003_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B003";
  endfunction

  task run_case();
    rdma_cq_pusher_roundtrip_cross_seq seq;
    seq = rdma_cq_pusher_roundtrip_cross_seq::type_id::create("seq");
    seq.start(this);
    if (vif.cq_tail != 16'd1)
      `uvm_error("B003", $sformatf("cq_tail=%0d expected 1", vif.cq_tail))
    if (vif.cnt_cqe_posted != 32'd1)
      `uvm_error("B003", $sformatf("cnt_cqe_posted=%0d expected 1", vif.cnt_cqe_posted))
    if (vif.dbg_last_pushed_meta != pack_meta(16'h00b3, 16'h0003, 16'h0007, 16'h0003))
      `uvm_error("B003", $sformatf("dbg_last_pushed_meta=0x%016h", vif.dbg_last_pushed_meta))
  endtask
endclass

`endif
