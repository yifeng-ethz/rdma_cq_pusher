`ifndef RDMA_CQ_PUSHER_COVERAGE_SV
`define RDMA_CQ_PUSHER_COVERAGE_SV

class rdma_cq_pusher_coverage extends uvm_component;
  `uvm_component_utils(rdma_cq_pusher_coverage)

  bit [15:0] sampled_depth;
  bit [3:0]  sampled_state;
  bit [1:0]  sampled_bresp;
  bit [15:0] sampled_sqe_id;
  bit [15:0] sampled_retire_seq;
  bit        sampled_lineage_match;

  covergroup cg_cq_depth_bin;
    option.per_instance = 1;
    cp_depth: coverpoint sampled_depth {
      bins d2 = {16'd2};
      bins d4 = {16'd4};
      bins d16 = {16'd16};
      bins d256 = {16'd256};
      bins d4096 = {16'd4096};
      bins d65536 = {16'd0};
    }
  endgroup

  covergroup cg_fsm_state;
    option.per_instance = 1;
    cp_state: coverpoint sampled_state {
      bins idle = {4'd0};
      bins aw = {4'd1};
      bins w = {4'd2};
      bins b = {4'd3};
      bins advance = {4'd4};
    }
  endgroup

  covergroup cg_bresp;
    option.per_instance = 1;
    cp_resp: coverpoint sampled_bresp {
      bins okay = {2'b00};
      bins exokay_illegal = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
  endgroup

  covergroup cg_lineage_match;
    option.per_instance = 1;
    cp_sqe: coverpoint sampled_sqe_id {
      bins low[] = {[16'd0:16'd15]};
      bins high = {[16'd16:16'hffff]};
    }
    cp_retire: coverpoint sampled_retire_seq {
      bins zero = {16'd0};
      bins one = {16'd1};
      bins many = {[16'd2:16'hffff]};
    }
    cp_match: coverpoint sampled_lineage_match {
      bins matched = {1'b1};
      bins unmatched = {1'b0};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_cq_depth_bin = new();
    cg_fsm_state = new();
    cg_bresp = new();
    cg_lineage_match = new();
  endfunction

  function void sample_cfg(input bit [15:0] depth);
    sampled_depth = depth;
    cg_cq_depth_bin.sample();
  endfunction

  function void sample_state(input bit [3:0] state);
    sampled_state = state;
    cg_fsm_state.sample();
  endfunction

  function void sample_bresp(input bit [1:0] resp);
    sampled_bresp = resp;
    cg_bresp.sample();
  endfunction

  function void sample_lineage(input bit [15:0] sqe_id,
                               input bit [15:0] retire_seq,
                               input bit matched);
    sampled_sqe_id = sqe_id;
    sampled_retire_seq = retire_seq;
    sampled_lineage_match = matched;
    cg_lineage_match.sample();
  endfunction
endclass

`endif
