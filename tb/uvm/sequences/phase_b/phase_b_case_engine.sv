`ifndef RDMA_CQ_PUSHER_PHASE_B_CASE_ENGINE_SV
`define RDMA_CQ_PUSHER_PHASE_B_CASE_ENGINE_SV

class rdma_cq_pusher_phase_b_case_test extends rdma_cq_pusher_base_test;
  `uvm_component_utils(rdma_cq_pusher_phase_b_case_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function bit is_power_of_two(input int unsigned value);
    return (value != 0) && ((value & (value - 1)) == 0);
  endfunction

  function int unsigned depth_mask_u(input int unsigned depth);
    if ((depth & 16'hffff) == 0)
      return 16'hffff;
    return (depth - 1) & 16'hffff;
  endfunction

  function int unsigned practical_timeout(input int unsigned count,
                                          input int unsigned aw_lag,
                                          input int unsigned w_lag,
                                          input int unsigned b_lag);
    int unsigned per_txn;
    per_txn = aw_lag + w_lag + b_lag + 32;
    if (per_txn < 64)
      per_txn = 64;
    return 2000 + count * per_txn;
  endfunction

  task set_host_lag(input int unsigned aw_lag,
                    input int unsigned w_lag,
                    input int unsigned b_lag);
    env.env_dbg1.host_axi_cfg.awready_lag = aw_lag;
    env.env_dbg1.host_axi_cfg.wready_lag = w_lag;
    env.env_dbg1.host_axi_cfg.bvalid_lag = b_lag;
  endtask

  task wait_for_state(input bit [3:0] state,
                      input int unsigned timeout_cycles = 1024);
    for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
      if (vif.dbg_state == state)
        return;
      @(posedge vif.clk);
    end
    `uvm_fatal("STATE", $sformatf("%s timed out waiting for state %0d; got %0d",
                                  case_id, state, vif.dbg_state))
  endtask

  task local_reset(input int unsigned low_cycles = 4);
    @(negedge vif.clk);
    vif.reset_n <= 1'b0;
    repeat (low_cycles) @(posedge vif.clk);
    @(negedge vif.clk);
    vif.reset_n <= 1'b1;
    repeat (4) @(posedge vif.clk);
    env.scb.reset_model();
    env.scb.configure_case(case_id, scorecard_path);
  endtask

  task pulse_msix_ack(input int unsigned cycles = 1);
    @(negedge vif.clk);
    vif.msix_ack <= 1'b1;
    repeat (cycles) @(posedge vif.clk);
    @(negedge vif.clk);
    vif.msix_ack <= 1'b0;
  endtask

  task set_enable(input bit enable);
    csr_cfg_item item;
    item = csr_cfg_item::type_id::create("enable_item");
    item.base = vif.cfg_cq_base;
    item.depth = vif.cfg_cq_depth;
    item.enable = enable;
    env.env_dbg1.csr_cfg.enqueue(item);
    wait_cycles(2);
  endtask

  task drive_illegal_tlast_low();
    env.scb.expect_posts(0);
    send_cqe_with_last(16'ha5a5, 16'h5a5a, 1'b0);
    wait_cycles(24);
    if (vif.s_axis_cqe_tready)
      `uvm_error("TLAST", "DUT accepted a Phase-B illegal tlast=0 CQE")
    local_reset(2);
  endtask

  task run_reset_state_case(input int unsigned target_state);
    env.scb.expect_posts(0);
    set_host_lag((target_state == 1) ? 32 : 0,
                 (target_state == 2) ? 32 : 0,
                 (target_state == 3) ? 32 : 0);
    send_cqe(16'h0011, 16'h0011, 16'h0011, 16'h0011);
    if (target_state <= 4)
      wait_for_state(target_state[3:0], 512);
    local_reset(4);
    if (vif.dbg_state != 4'd0)
      `uvm_error("RESET", $sformatf("%s state after reset is %0d", case_id, vif.dbg_state))
    if (vif.cq_tail != 16'h0000 || vif.cnt_cqe_posted != 32'h0000_0000)
      `uvm_error("RESET", $sformatf("%s counters not clear tail=%0d posted=%0d",
                                    case_id, vif.cq_tail, vif.cnt_cqe_posted))
  endtask

  task run_pushes(input int unsigned count,
                  input int unsigned depth,
                  input int unsigned aw_lag = 0,
                  input int unsigned w_lag = 0,
                  input int unsigned b_lag = 0,
                  input bit release_each = 1'b1,
                  input bit checkpoints = 1'b0,
                  input int unsigned gap_cycles = 0,
                  input int unsigned bresp_every = 0,
                  input bit [1:0] bresp_code = 2'b10);
    bit [63:0] base;
    int unsigned timeout_cycles;
    int unsigned depth16;

    depth16 = depth & 16'hffff;
    base = 64'h0000_1000_0000_0000 ^ ({48'h0, case_id.len(), depth16} << 6);
    base[5:0] = 6'h00;
    set_host_lag(aw_lag, w_lag, b_lag);
    program_cfg(base, depth16[15:0], 1'b1);
    env.scb.expect_posts(count);
    timeout_cycles = practical_timeout(1, aw_lag, w_lag, b_lag);

    for (int unsigned idx = 0; idx < count; idx++) begin
      bit [15:0] sqe;
      bit [15:0] seq;
      sqe = (idx[15:0] ^ {8'h00, case_id.getc(0)}) + 16'd1;
      seq = idx[15:0] + 16'd1;
      if (bresp_every != 0 && ((idx % bresp_every) == 0))
        env.env_dbg1.host_axi_cfg.push_bresp(bresp_code);
      send_cqe(sqe, seq, seq ^ 16'h1357, seq ^ 16'h2468);
      wait_for_posts(1, timeout_cycles);
      if (release_each)
        pulse_doorbell(vif.cq_tail);
      if (checkpoints && (is_power_of_two(idx + 1) || (idx + 1 == count)))
        save_txn_checkpoint(case_id, idx + 1);
      if (gap_cycles != 0)
        wait_cycles(gap_cycles);
    end
    wait_cycles(8);
  endtask

  task run_fill_and_release(input int unsigned depth,
                            input int unsigned extra_stall_cycles = 16);
    int unsigned fill_count;
    fill_count = depth - 1;
    set_host_lag(0, 0, 0);
    program_cfg(64'h0000_1000_0000_0000, depth[15:0], 1'b1);
    env.scb.expect_posts(fill_count + 1);
    for (int unsigned idx = 0; idx < fill_count; idx++) begin
      send_cqe(idx[15:0] + 16'd1, idx[15:0] + 16'd1, idx[15:0], idx[15:0]);
      wait_for_posts(1, 512);
    end
    wait_cycles(4);
    if (!vif.dbg_cq_full)
      `uvm_error("FULL", $sformatf("%s expected cq_full at depth=%0d", case_id, depth))
    send_cqe(16'h7f00, 16'h7f00, 16'h7f00, 16'h7f00);
    wait_cycles(extra_stall_cycles);
    if (vif.s_axis_cqe_tready)
      `uvm_error("FULL", $sformatf("%s expected tready low while full", case_id))
    pulse_doorbell(vif.cq_tail);
    wait_for_posts(1, 512);
  endtask

  task run_enable_gate_case(input int unsigned num);
    if (num == 125) begin
      program_cfg(64'h0000_1000_0000_0000, 16'd256, 1'b0);
      env.scb.expect_posts(0);
      wait_cycles(8);
      if (vif.s_axis_cqe_tready)
        `uvm_error("ENABLE", "tready high while cfg_enable=0")
    end else if (num == 126) begin
      run_pushes(1, 256);
      set_enable(1'b0);
      send_cqe(16'h1260, 16'h1260, 16'h1260, 16'h1260);
      wait_cycles(16);
      if (vif.cnt_cqe_posted != 32'd1)
        `uvm_error("ENABLE", "disabled push unexpectedly posted")
      local_reset(2);
    end else if (num == 127) begin
      program_cfg(64'h0000_1000_0000_0000, 16'd16, 1'b0);
      pulse_doorbell(16'd4);
      if (vif.dbg_cur_cq_head_credit != 16'd4)
        `uvm_error("ENABLE", "doorbell did not latch while disabled")
    end else begin
      program_cfg(64'h0000_1000_0000_0000, 16'd256, 1'b0);
      env.scb.expect_posts(1);
      send_cqe(16'h1280, 16'h1280, 16'h1280, 16'h1280);
      wait_cycles(8);
      set_enable(1'b1);
      wait_for_posts(1, 512);
    end
  endtask

  task run_basic_case(input int unsigned num);
    if (num <= 2) begin
      env.scb.expect_posts(0);
      wait_cycles(12);
    end else if (num <= 5) begin
      run_reset_state_case(num - 2);
    end else if (num <= 12) begin
      run_fill_and_release(4, 8);
      local_reset(3);
    end else if (num <= 24) begin
      run_pushes(1, 256);
    end else if (num <= 36) begin
      int unsigned counts[12] = '{2, 4, 8, 16, 64, 128, 4, 4, 8, 8, 8, 8};
      int unsigned gaps[12] = '{0, 0, 0, 0, 0, 0, 1, 4, 0, 0, 0, 0};
      run_pushes(counts[num - 25], 256, 0, 0, 0, 1'b1, 1'b0, gaps[num - 25]);
    end else if (num <= 48) begin
      int unsigned depth;
      depth = (num >= 47) ? 16 : 256;
      run_pushes((num >= 47) ? 32 : 8, depth);
    end else if (num <= 60) begin
      if (num <= 56) begin
        program_cfg(64'h0000_1000_0000_0000, 16'd16, 1'b1);
        env.scb.expect_posts(0);
        pulse_doorbell((num == 50) ? 16'h0018 : (num - 48));
      end else begin
        run_fill_and_release(4, 8);
      end
    end else if (num <= 72) begin
      if (num == 72)
        drive_illegal_tlast_low();
      else
        run_pushes((num == 62 || num == 63 || num == 64) ? 8 : 1,
                   256, (num == 65) ? 16 : 0, 0, 0);
    end else if (num <= 84) begin
      run_pushes((num == 78 || num == 83) ? 8 : ((num == 79) ? 4 : 1),
                 256, (num == 73 || num == 76) ? 4 : 0,
                 (num == 74) ? 4 : 0,
                 (num == 77) ? 4 : 0);
    end else if (num <= 96) begin
      if (num == 87 || num == 90)
        run_fill_and_release(4, 24);
      else if (num == 92)
        run_pushes(1, 256, 0, 0, 0, 1'b1, 1'b0, 0, 1, 2'b10);
      else
        run_pushes((num == 95 || num == 96) ? 8 : 4, 256, 0, 0, 4);
    end else if (num <= 108) begin
      run_pushes((num == 108) ? 12 : ((num >= 99 && num <= 102) ? 4 : 1), 256);
    end else if (num <= 116) begin
      fork
        begin
          if (num >= 113)
            pulse_msix_ack((num == 114) ? 16 : 1);
        end
        begin
          run_pushes((num == 111) ? 16 : ((num == 115) ? 4 : 1), 256);
        end
      join
      if (vif.msix_req !== 1'b0)
        `uvm_error("MSIX", "Phase-1 MSI-X request asserted")
    end else if (num <= 124) begin
      run_pushes((num == 120) ? 64 : ((num >= 122) ? 16 : 8),
                 (num >= 122) ? 4 : 256);
    end else begin
      run_enable_gate_case(num);
    end
  endtask

  task run_edge_case(input int unsigned num, input bit checkpoints);
    int unsigned iter;
    iter = rdma_cq_pusher_case_iter(case_id);
    if (num <= 16) begin
      int unsigned depths[6] = '{2, 4, 16, 256, 4096, 0};
      int unsigned depth;
      depth = (num <= 6) ? depths[num - 1] : ((num <= 14) ? 4 : 16);
      run_pushes(iter, depth, 0, 0, 0, 1'b1, checkpoints);
    end else if (num <= 32) begin
      if (num <= 30)
        run_fill_and_release((num == 17) ? 2 : ((num == 19) ? 16 : 4), 32);
      else
        run_pushes(iter, (num == 32) ? 16 : 8, 0, 0, 0, 1'b1, checkpoints);
    end else if (num <= 48) begin
      program_cfg(64'h0000_1000_0000_0000, 16'd16, 1'b1);
      env.scb.expect_posts(0);
      for (int unsigned idx = 0; idx < iter; idx++) begin
        pulse_doorbell((num * 17 + idx) & 16'hffff);
        if (checkpoints && is_power_of_two(idx + 1))
          save_txn_checkpoint(case_id, idx + 1);
      end
    end else if (num <= 64) begin
      int unsigned depth;
      case (num)
        49, 50: depth = 2;
        51, 52: depth = 4;
        53, 54: depth = 16;
        55, 56: depth = 256;
        57, 58: depth = 4096;
        59, 60: depth = 0;
        61: depth = 8;
        62: depth = 32;
        63: depth = 128;
        default: depth = 1024;
      endcase
      run_pushes(iter, depth, 0, 0, 0, 1'b1, checkpoints);
    end else if (num <= 76) begin
      int unsigned lag;
      lag = (num <= 70) ? (1 << ((num - 65 > 5) ? 5 : (num - 65))) : ((num >= 74) ? 8 : 4);
      if (num == 65)
        lag = 0;
      run_pushes(iter, 256, lag, 0, 0, 1'b1, checkpoints);
    end else if (num <= 88) begin
      int unsigned lag;
      lag = (num <= 82) ? (1 << ((num - 77 > 5) ? 5 : (num - 77))) : ((num >= 85) ? 8 : 4);
      if (num == 77)
        lag = 0;
      run_pushes(iter, 256, 0, lag, 0, 1'b1, checkpoints);
    end else if (num <= 100) begin
      int unsigned lag;
      lag = (num <= 94) ? (1 << ((num - 89 > 5) ? 5 : (num - 89))) : ((num >= 97) ? 8 : 16);
      if (num == 89)
        lag = 0;
      run_pushes(iter, 256, 0, 0, lag, 1'b1, checkpoints);
    end else if (num <= 116) begin
      run_pushes(iter, (num == 116) ? 16 : 256,
                 (num == 102) ? 16 : 0,
                 (num == 104) ? 16 : 0,
                 (num == 106) ? 16 : 0,
                 1'b1, checkpoints);
    end else if (num <= 124) begin
      run_pushes(iter, (num == 118 || num == 124) ? 16 : 256, 4, 2, 2);
    end else begin
      run_pushes((num == 127 || num == 128) ? 8 : 1, 256);
    end
  endtask

  task run_prof_case(input int unsigned num, input bit checkpoints);
    int unsigned iter;
    int unsigned depth;
    int unsigned aw_lag;
    int unsigned w_lag;
    int unsigned b_lag;
    int unsigned gap;

    iter = rdma_cq_pusher_case_iter(case_id);
    depth = 256;
    aw_lag = 0;
    w_lag = 0;
    b_lag = 0;
    gap = 0;

    if (num <= 16) begin
      if (num == 2)
        depth = 4096;
      else if (num == 3)
        depth = 0;
      else if (num == 4)
        depth = 4;
      gap = (num == 6) ? 16 : ((num == 7) ? 48 : ((num == 8) ? 5 : 0));
      b_lag = (num >= 13) ? ((num - 12) * 2) : 0;
      aw_lag = (num == 14 || num == 16) ? 4 : 0;
      w_lag = (num == 15 || num == 16) ? 4 : 0;
    end else if (num <= 32) begin
      b_lag = (num <= 28) ? ((num == 28) ? 1000 : (1 << ((num - 17 > 8) ? 8 : (num - 17)))) : 8;
      if (num == 17)
        b_lag = 0;
    end else if (num <= 48) begin
      aw_lag = ((num >= 33 && num <= 35) || num >= 39) ? ((num >= 35 || num == 42 || num == 43) ? 64 : 4) : 0;
      w_lag = ((num >= 36 && num <= 38) || num >= 39) ? ((num >= 38 || num == 42 || num == 43) ? 64 : 4) : 0;
      b_lag = (num >= 41) ? ((num == 43) ? 256 : ((num == 42) ? 64 : 4)) : 0;
    end else if (num <= 64) begin
      depth = (num == 55) ? 2 : ((num == 56) ? 0 : ((num >= 59) ? 256 : 4));
      gap = (num >= 57) ? 8 : 0;
    end else if (num <= 96) begin
      depth = (num >= 91 && num <= 92) ? 2 : ((num >= 93) ? 0 : ((num >= 69 && num <= 78) ? 16 : 256));
      b_lag = (num == 66 || num == 70 || num == 89 || num == 92) ? 64 : ((num == 72) ? 256 : 0);
    end else begin
      depth = (num == 102) ? 4 : ((num == 103) ? 16 : ((num == 104) ? 4096 : ((num == 105) ? 0 : 256)));
      aw_lag = (num == 110 || num == 111 || num == 126) ? 8 : 0;
      w_lag = (num == 110 || num == 111 || num == 126) ? 8 : 0;
      b_lag = (num == 109 || num == 111 || num == 114 || num == 116 || num == 126) ? 16 : 0;
      gap = (num == 108 || num == 120) ? 4 : 0;
    end

    run_pushes(iter, depth, aw_lag, w_lag, b_lag, 1'b1, checkpoints, gap);
  endtask

  task run_error_case(input int unsigned num, input bit checkpoints);
    int unsigned iter;
    iter = rdma_cq_pusher_case_iter(case_id);
    if (num <= 14) begin
      if (num <= 5)
        run_reset_state_case((num == 1) ? 0 : (num - 1));
      else begin
        run_pushes(1, 256, 2, 2, 2);
        local_reset(2);
      end
    end else if (num <= 28) begin
      bit [1:0] resp;
      resp = (num == 16 || num == 22) ? 2'b11 : ((num == 17) ? 2'b01 : 2'b10);
      run_pushes((iter == 0) ? 1 : iter, 256, 0, 0, 0, 1'b1, checkpoints, 0, 1, resp);
    end else if (num <= 40) begin
      run_pushes(1, 256,
                 (num == 29 || num == 36) ? 32 : 0,
                 (num == 30 || num == 37) ? 32 : 0,
                 (num == 40) ? 32 : 0);
    end else if (num <= 48) begin
      if (num == 41)
        drive_illegal_tlast_low();
      else if (num == 46 || num == 47) begin
        program_cfg(64'h0000_1000_0000_0000, (num == 47) ? 16'd4 : 16'd256, (num == 46) ? 1'b0 : 1'b1);
        if (num == 47)
          run_fill_and_release(4, 32);
        else
          run_enable_gate_case(125);
      end else begin
        run_pushes(1, 256, 4, 4, 4);
      end
    end else if (num <= 56) begin
      program_cfg(64'h0000_1000_0000_0000, (num == 53) ? 16'd2 : 16'd16, 1'b1);
      env.scb.expect_posts(0);
      pulse_doorbell((num == 52 || num == 53) ? 16'hffff : (16'h1001 + num[15:0]));
      wait_cycles(8);
    end else if (num <= 68) begin
      if (num <= 62)
        run_enable_gate_case((num == 60) ? 128 : 126);
      else
        run_pushes(1, (num >= 66) ? 16 : 256, 8, 8, 0);
    end else if (num <= 74) begin
      fork
        pulse_msix_ack((num == 70) ? 1024 : 1);
        run_pushes((num == 71) ? 100 : 16, 256);
      join
    end else if (num <= 82) begin
      run_pushes(iter, 16, 2, 2, 2, 1'b1, checkpoints, 0,
                 (num == 75 || num == 81) ? 1 : 0, 2'b10);
    end else if (num <= 88) begin
      run_pushes((num == 85) ? 8 : 1, 256, 8, 8, 16, 1'b1, checkpoints,
                 0, (num == 83 || num == 88) ? 1 : 0, 2'b10);
    end else if (num <= 96) begin
      run_pushes((num == 96) ? 16 : 4, 256, 0, 0, (num == 93) ? 4 : 0,
                 1'b1, checkpoints, 0, (num == 93) ? 1 : 0, 2'b10);
    end else if (num <= 114) begin
      run_pushes((num == 114) ? 100 : 4, 256, 4, 4, 4, 1'b1, checkpoints,
                 0, (num == 100 || num == 111 || num == 112 || num == 114) ? 8 : 0, 2'b10);
    end else begin
      run_pushes(iter, (num == 118 || num == 127) ? 16 : 256, 4, 4, 8,
                 1'b1, checkpoints, 0, (num == 115 || num == 119 || num == 120 || num == 126) ? 16 : 0, 2'b10);
    end
  endtask

  task run_case();
    string bucket;
    string method;
    int unsigned num;
    bit checkpoints;

    bucket = rdma_cq_pusher_case_bucket(case_id);
    method = rdma_cq_pusher_case_method(case_id);
    void'($sscanf(case_id.substr(1, case_id.len() - 1), "%d", num));
    checkpoints = (method == "R") || (bucket == "PROF");

    `uvm_info("PHASE_B", $sformatf("case=%s bucket=%s method=%s iter=%0d",
                                   case_id, bucket, method,
                                   rdma_cq_pusher_case_iter(case_id)), UVM_LOW)

    if (bucket == "BASIC")
      run_basic_case(num);
    else if (bucket == "EDGE")
      run_edge_case(num, checkpoints);
    else if (bucket == "PROF")
      run_prof_case(num, checkpoints);
    else if (bucket == "ERROR")
      run_error_case(num, checkpoints);
    else
      `uvm_fatal("PHASE_B", $sformatf("Unknown Phase B bucket for %s", case_id))
  endtask
endclass

`endif
