`ifndef RDMA_CQ_PUSHER_PROF_SEQUENCES_SV
`define RDMA_CQ_PUSHER_PROF_SEQUENCES_SV

class rdma_cq_pusher_prof_template_seq extends uvm_object;
  `uvm_object_utils(rdma_cq_pusher_prof_template_seq)

  function new(string name = "rdma_cq_pusher_prof_template_seq");
    super.new(name);
  endfunction

  task start(rdma_cq_pusher_base_test test);
    test.wait_cycles(1);
  endtask
endclass

`endif
