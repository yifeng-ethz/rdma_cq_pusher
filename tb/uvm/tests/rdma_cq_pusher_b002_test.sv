`ifndef RDMA_CQ_PUSHER_B002_TEST_SV
`define RDMA_CQ_PUSHER_B002_TEST_SV

class rdma_cq_pusher_b002_test extends rdma_cq_pusher_base_test;
  `uvm_component_utils(rdma_cq_pusher_b002_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B002";
  endfunction

  task run_case();
    rdma_cq_pusher_single_cqe_seq seq;
    seq = rdma_cq_pusher_single_cqe_seq::type_id::create("seq");
    seq.rqe_id = 16'h0002;
    seq.retire_seq = 16'h0002;
    seq.origin_dma_done_seq = 16'h0004;
    seq.push_seq = 16'h0002;
    seq.start(this);
    if (vif.cq_tail != 16'd1)
      `uvm_error("B002", $sformatf("cq_tail=%0d expected 1", vif.cq_tail))
    if (vif.cnt_cqe_posted != 32'd1)
      `uvm_error("B002", $sformatf("cnt_cqe_posted=%0d expected 1", vif.cnt_cqe_posted))
  endtask
endclass

`endif
