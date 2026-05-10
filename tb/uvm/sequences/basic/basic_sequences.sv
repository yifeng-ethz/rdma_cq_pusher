`ifndef RDMA_CQ_PUSHER_BASIC_SEQUENCES_SV
`define RDMA_CQ_PUSHER_BASIC_SEQUENCES_SV

class rdma_cq_pusher_b001_idle_seq extends uvm_object;
  `uvm_object_utils(rdma_cq_pusher_b001_idle_seq)

  function new(string name = "rdma_cq_pusher_b001_idle_seq");
    super.new(name);
  endfunction

  task start(rdma_cq_pusher_base_test test);
    test.env.scb.expect_posts(0);
    test.wait_cycles(8);
  endtask
endclass

class rdma_cq_pusher_single_cqe_seq extends uvm_object;
  `uvm_object_utils(rdma_cq_pusher_single_cqe_seq)

  bit [15:0] sqe_id;
  bit [15:0] retire_seq;
  bit [15:0] origin_dma_done_seq;
  bit [15:0] push_seq;

  function new(string name = "rdma_cq_pusher_single_cqe_seq");
    super.new(name);
    sqe_id = 16'h0001;
    retire_seq = 16'h0001;
    origin_dma_done_seq = 16'h0001;
    push_seq = 16'h0001;
  endfunction

  task start(rdma_cq_pusher_base_test test);
    test.env.scb.expect_posts(1);
    test.send_cqe(sqe_id, retire_seq, origin_dma_done_seq, push_seq);
    test.wait_for_posts(1, 200);
    test.wait_cycles(8);
  endtask
endclass

class rdma_cq_pusher_roundtrip_cross_seq extends rdma_cq_pusher_single_cqe_seq;
  `uvm_object_utils(rdma_cq_pusher_roundtrip_cross_seq)

  function new(string name = "rdma_cq_pusher_roundtrip_cross_seq");
    super.new(name);
    sqe_id = 16'h00b3;
    retire_seq = 16'h0003;
    origin_dma_done_seq = 16'h0007;
    push_seq = 16'h0003;
  endfunction

  task start(rdma_cq_pusher_base_test test);
    test.env.scb.set_lineage_required(1'b1);
    super.start(test);
  endtask
endclass

`endif
