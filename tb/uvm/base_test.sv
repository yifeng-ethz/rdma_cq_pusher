`ifndef RDMA_CQ_PUSHER_BASE_TEST_SV
`define RDMA_CQ_PUSHER_BASE_TEST_SV

class rdma_cq_pusher_base_test extends uvm_test;
  `uvm_component_utils(rdma_cq_pusher_base_test)

  rdma_cq_pusher_env_top env;
  virtual rdma_cq_pusher_if vif;
  string case_id;
  string scorecard_path;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    case_id = "BASE";
    scorecard_path = "";
  endfunction

  function string default_case_id();
    return "BASE";
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rdma_cq_pusher_env_top::type_id::create("env", this);
    if (!$value$plusargs("CASE_ID=%s", case_id))
      case_id = default_case_id();
    void'($value$plusargs("SCORECARD=%s", scorecard_path));
  endfunction

  task apply_reset();
    if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
      `uvm_fatal("BASE", "Missing rdma_cq_pusher_if")

    vif.cfg_cq_base <= 64'h0000_1000_0000_0000;
    vif.cfg_cq_depth <= 16'd256;
    vif.cfg_enable <= 1'b1;
    vif.cq_head_dbl_pulse <= 1'b0;
    vif.cq_head_dbl_value <= 16'h0000;
    vif.s_axis_cqe_tdata <= '0;
    vif.s_axis_cqe_tvalid <= 1'b0;
    vif.s_axis_cqe_tlast <= 1'b1;
    vif.s_axis_cqe_tuser <= 16'h0000;
    vif.s_axis_cqe_tuser_meta <= '0;
    vif.m_axi_awready <= 1'b0;
    vif.m_axi_wready <= 1'b0;
    vif.m_axi_bid <= 4'h0;
    vif.m_axi_bresp <= 2'b00;
    vif.m_axi_bvalid <= 1'b0;
    vif.msix_ack <= 1'b0;
    vif.reset_n <= 1'b0;
    repeat (16) @(posedge vif.clk);
    vif.reset_n <= 1'b1;
    repeat (4) @(posedge vif.clk);
  endtask

  task wait_cycles(input int unsigned cycles);
    repeat (cycles) @(posedge vif.clk);
  endtask

  virtual task run_case();
    wait_cycles(4);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    apply_reset();
    `uvm_info("BASE", $sformatf("Starting case %s", case_id), UVM_LOW)
    run_case();
    wait_cycles(8);
    phase.drop_objection(this);
  endtask
endclass

`endif
