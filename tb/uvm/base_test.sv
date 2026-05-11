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

  function bit [63:0] pack_meta(input bit [15:0] rqe_id,
                                input bit [15:0] retire_seq,
                                input bit [15:0] origin_dma_done_seq,
                                input bit [15:0] push_seq);
    return {push_seq, origin_dma_done_seq, retire_seq, rqe_id};
  endfunction

  function bit [511:0] make_cqe(input bit [15:0] rqe_id,
                                input bit [15:0] retire_seq);
    bit [511:0] data;
    bit [63:0] seed;
    data = '0;
    seed = {rqe_id, retire_seq, rqe_id ^ retire_seq, rqe_id + retire_seq};
    for (int unsigned word = 0; word < 8; word++) begin
      bit [63:0] mixed;
      mixed = seed ^ (64'h9e37_79b9_7f4a_7c15 * (word + 1));
      mixed = {mixed[30:0], mixed[63:31]} ^ (64'hd1b5_4a32_d192_ed03 * (retire_seq + word + 1));
      data[word*64 +: 64] = mixed;
    end
    data[159:144] = rqe_id;
    data[143:128] = 16'h0001;
    return data;
  endfunction

  function string get_dv_tb_dir();
    string tb_dir;
    if ($value$plusargs("DV_TB_DIR=%s", tb_dir))
      return tb_dir;
    return "";
  endfunction

  function int unsigned get_dv_seed();
    int unsigned seed;
    if ($value$plusargs("DV_SEED=%d", seed))
      return seed;
    return 1;
  endfunction

  task save_txn_checkpoint(input string checkpoint_case_id,
                           input int unsigned txn_count);
    `uvm_info("COV", $sformatf("checkpoint marker case=%s txn=%0d seed=%0d",
                               checkpoint_case_id, txn_count, get_dv_seed()), UVM_LOW)
  endtask

  task program_cfg(input bit [63:0] base, input bit [15:0] depth, input bit enable);
    csr_cfg_item item;
    item = csr_cfg_item::type_id::create("cfg_item");
    item.base = base;
    item.depth = depth;
    item.enable = enable;
    env.env_dbg1.csr_cfg.enqueue(item);
    env.env_dbg1.host_axi_cfg.configure(base, depth);
    wait_cycles(2);
  endtask

  task pulse_doorbell(input bit [15:0] value);
    doorbell_item item;
    item = doorbell_item::type_id::create("doorbell_item");
    item.value = value;
    env.env_dbg1.doorbell_cfg.enqueue(item);
    wait_cycles(2);
  endtask

  task send_cqe(input bit [15:0] rqe_id,
                input bit [15:0] retire_seq,
                input bit [15:0] origin_dma_done_seq = 16'h0000,
                input bit [15:0] push_seq = 16'h0000);
    cqe_item cqe;
    cqe_meta_item meta;

    cqe = cqe_item::type_id::create("cqe");
    cqe.rqe_id = rqe_id;
    cqe.last = 1'b1;
    cqe.data = make_cqe(rqe_id, retire_seq);
    cqe.meta = pack_meta(rqe_id, retire_seq, origin_dma_done_seq, push_seq);

    meta = cqe_meta_item::type_id::create("meta");
    meta.rqe_id = rqe_id;
    meta.retire_seq = retire_seq;
    meta.origin_dma_done_seq = origin_dma_done_seq;
    meta.push_seq = push_seq;
    meta.repack();

    env.env_dbg1.cqe_cfg.enqueue(cqe);
    env.env_dbg2.meta_cfg.enqueue(meta);
  endtask

  task send_cqe_with_last(input bit [15:0] rqe_id,
                          input bit [15:0] retire_seq,
                          input bit last);
    cqe_item cqe;
    cqe_meta_item meta;

    cqe = cqe_item::type_id::create("cqe_last");
    cqe.rqe_id = rqe_id;
    cqe.last = last;
    cqe.data = make_cqe(rqe_id, retire_seq);
    cqe.meta = pack_meta(rqe_id, retire_seq, retire_seq, retire_seq);

    meta = cqe_meta_item::type_id::create("meta_last");
    meta.rqe_id = rqe_id;
    meta.retire_seq = retire_seq;
    meta.origin_dma_done_seq = retire_seq;
    meta.push_seq = retire_seq;
    meta.repack();

    env.env_dbg1.cqe_cfg.enqueue(cqe);
    env.env_dbg2.meta_cfg.enqueue(meta);
  endtask

  task wait_for_posts(input int unsigned count, input int unsigned timeout_cycles = 1000);
    int unsigned start_count;
    start_count = vif.cnt_cqe_posted;
    for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
      if ((vif.cnt_cqe_posted - start_count) >= count)
        return;
      @(posedge vif.clk);
    end
    `uvm_fatal("TIMEOUT", $sformatf("%s timed out waiting for %0d posts; observed delta=%0d",
                                    case_id, count, vif.cnt_cqe_posted - start_count))
  endtask

  virtual task run_case();
    wait_cycles(4);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    apply_reset();
    env.scb.reset_model();
    env.scb.configure_case(case_id, scorecard_path);
    `uvm_info("BASE", $sformatf("Starting case %s", case_id), UVM_LOW)
    run_case();
    wait_cycles(8);
    phase.drop_objection(this);
  endtask
endclass

`endif
