`ifndef RDMA_CQ_PUSHER_SCOREBOARD_SV
`define RDMA_CQ_PUSHER_SCOREBOARD_SV

class rdma_cq_pusher_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rdma_cq_pusher_scoreboard)

  uvm_analysis_imp_cqe #(cqe_agent_pkg::cqe_item, rdma_cq_pusher_scoreboard) cqe_imp;
  uvm_analysis_imp_meta #(cqe_meta_agent_pkg::cqe_meta_item, rdma_cq_pusher_scoreboard) meta_imp;
  uvm_analysis_imp_host #(host_axi_completer_pkg::host_axi_item, rdma_cq_pusher_scoreboard) host_imp;
  uvm_analysis_imp_cfg #(csr_cfg_agent_pkg::csr_cfg_item, rdma_cq_pusher_scoreboard) cfg_imp;
  uvm_analysis_imp_doorbell #(doorbell_agent_pkg::doorbell_item, rdma_cq_pusher_scoreboard) doorbell_imp;
  uvm_analysis_imp_dbg1 #(dbg1_tap_item, rdma_cq_pusher_scoreboard) dbg1_imp;
  uvm_analysis_imp_dbg2 #(dbg2_lineage_item, rdma_cq_pusher_scoreboard) dbg2_imp;

  virtual rdma_cq_pusher_if vif;
  rdma_cq_pusher_coverage cov;

  string case_id;
  string scorecard_path;
  bit [63:0] cfg_base_m;
  bit [15:0] cfg_depth_m;
  bit        cfg_enable_m;
  bit [15:0] expected_tail;
  bit [15:0] expected_head;
  int unsigned accepted_count;
  int unsigned host_write_count;
  int unsigned b_okay_count;
  int unsigned mismatch_count;
  bit check_expected_posts;
  int unsigned expected_posts;
  bit lineage_required;
  bit have_dbg1;
  dbg1_tap_item last_dbg1;

  cqe_agent_pkg::cqe_item cqe_q[$];
  cqe_meta_agent_pkg::cqe_meta_item meta_q[$];
  paired_cqe_t pending_q[$];
  paired_cqe_t retired_expected_q[$];
  dbg2_lineage_item retired_actual_q[$];
  paired_cqe_t host_by_slot[bit [15:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    case_id = "UNKNOWN";
    scorecard_path = "";
    reset_model();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cqe_imp = new("cqe_imp", this);
    meta_imp = new("meta_imp", this);
    host_imp = new("host_imp", this);
    cfg_imp = new("cfg_imp", this);
    doorbell_imp = new("doorbell_imp", this);
    dbg1_imp = new("dbg1_imp", this);
    dbg2_imp = new("dbg2_imp", this);
    cov = rdma_cq_pusher_coverage::type_id::create("cov", this);
    if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
      `uvm_fatal("SCB", "Missing rdma_cq_pusher_if")
  endfunction

  function bit [15:0] depth_mask(input bit [15:0] depth);
    if (depth == 16'h0000)
      return 16'hffff;
    return depth - 16'd1;
  endfunction

  function void reset_model();
    cfg_base_m = 64'h0000_1000_0000_0000;
    cfg_depth_m = 16'd256;
    cfg_enable_m = 1'b1;
    expected_tail = 16'h0000;
    expected_head = 16'h0000;
    accepted_count = 0;
    host_write_count = 0;
    b_okay_count = 0;
    mismatch_count = 0;
    check_expected_posts = 1'b0;
    expected_posts = 0;
    lineage_required = 1'b1;
    have_dbg1 = 1'b0;
    cqe_q.delete();
    meta_q.delete();
    pending_q.delete();
    retired_expected_q.delete();
    retired_actual_q.delete();
    host_by_slot.delete();
  endfunction

  function void configure_case(input string id, input string path);
    case_id = id;
    scorecard_path = path;
  endfunction

  function void expect_posts(input int unsigned count);
    check_expected_posts = 1'b1;
    expected_posts = count;
  endfunction

  function void set_lineage_required(input bit required);
    lineage_required = required;
  endfunction

  function int unsigned post_count();
    return b_okay_count;
  endfunction

  function void note_mismatch(input string msg);
    mismatch_count++;
    `uvm_error("SCB", $sformatf("%s %s", case_id, msg))
  endfunction

  function void try_pair_inputs();
    while (cqe_q.size() != 0 && meta_q.size() != 0) begin
      cqe_agent_pkg::cqe_item cqe;
      cqe_meta_agent_pkg::cqe_meta_item meta;
      paired_cqe_t pair;
      cqe = cqe_q.pop_front();
      meta = meta_q.pop_front();
      if (cqe.sqe_id != meta.sqe_id)
        note_mismatch($sformatf("CQE/meta sqe_id mismatch cqe=%0d meta=%0d",
                                cqe.sqe_id, meta.sqe_id));
      if (cqe.meta != meta.packed_meta)
        note_mismatch($sformatf("CQE/meta packed mismatch cqe=0x%016h meta=0x%016h",
                                cqe.meta, meta.packed_meta));
      pair.data = cqe.data;
      pair.sqe_id = cqe.sqe_id;
      pair.retire_seq = meta.retire_seq;
      pair.origin_dma_done_seq = meta.origin_dma_done_seq;
      pair.push_seq = meta.push_seq;
      pair.packed_meta = meta.packed_meta;
      pair.slot = expected_tail;
      pending_q.push_back(pair);
      accepted_count++;
    end
  endfunction

  function void write_cqe(cqe_agent_pkg::cqe_item item);
    if (!item.last)
      note_mismatch("accepted CQE without TLAST");
    cqe_q.push_back(item);
    try_pair_inputs();
  endfunction

  function void write_meta(cqe_meta_agent_pkg::cqe_meta_item item);
    meta_q.push_back(item);
    try_pair_inputs();
  endfunction

  function void write_cfg(csr_cfg_agent_pkg::csr_cfg_item item);
    cfg_base_m = item.base;
    cfg_depth_m = item.depth;
    cfg_enable_m = item.enable;
    if (cov != null)
      cov.sample_cfg(item.depth);
  endfunction

  function void write_doorbell(doorbell_agent_pkg::doorbell_item item);
    expected_head = item.value & depth_mask(cfg_depth_m);
  endfunction

  function void write_dbg1(dbg1_tap_item item);
    last_dbg1 = item;
    have_dbg1 = 1'b1;
    if (cov != null)
      cov.sample_state(item.state);
  endfunction

  function void write_dbg2(dbg2_lineage_item item);
    retired_actual_q.push_back(item);
  endfunction

  function void write_host(host_axi_completer_pkg::host_axi_item item);
    bit [63:0] expected_addr;
    paired_cqe_t pair;

    case (item.kind)
      host_axi_completer_pkg::HOST_AXI_AW: begin
        expected_addr = cfg_base_m + ({48'h0, expected_tail} << 6);
        if (item.addr != expected_addr)
          note_mismatch($sformatf("AW address mismatch got=0x%016h expected=0x%016h",
                                  item.addr, expected_addr));
        if (item.len != 8'h00)
          note_mismatch($sformatf("AWLEN mismatch got=0x%02h", item.len));
        if (item.size != 3'd6)
          note_mismatch($sformatf("AWSIZE mismatch got=%0d", item.size));
        if (item.burst != 2'b01)
          note_mismatch($sformatf("AWBURST mismatch got=%0d", item.burst));
      end

      host_axi_completer_pkg::HOST_AXI_W: begin
        if (pending_q.size() == 0) begin
          note_mismatch("host W observed without a pending CQE");
          return;
        end
        pair = pending_q[0];
        if (item.data !== pair.data)
          note_mismatch($sformatf("host W payload mismatch slot=%0d sqe_id=%0d",
                                  item.slot, pair.sqe_id));
        if (item.strb != 64'hffff_ffff_ffff_ffff)
          note_mismatch($sformatf("WSTRB mismatch got=0x%016h", item.strb));
        if (!item.last)
          note_mismatch("WLAST was not asserted on single-beat CQE write");
        pair.slot = item.slot;
        host_by_slot[item.slot] = pair;
        host_write_count++;
      end

      host_axi_completer_pkg::HOST_AXI_B: begin
        if (cov != null)
          cov.sample_bresp(item.resp);
        if (item.resp == host_axi_completer_pkg::AXI_RESP_OKAY) begin
          if (pending_q.size() == 0) begin
            note_mismatch("B-OKAY observed without a pending CQE");
            return;
          end
          pair = pending_q.pop_front();
          if (host_by_slot.exists(pair.slot))
            pair = host_by_slot[pair.slot];
          retired_expected_q.push_back(pair);
          b_okay_count++;
          expected_tail = (expected_tail + 16'd1) & depth_mask(cfg_depth_m);
        end
      end
    endcase
  endfunction

  function void check_dbg1_end();
    bit expected_full;
    expected_full = (((expected_tail + 16'd1) & depth_mask(cfg_depth_m)) == expected_head);
    if (!have_dbg1) begin
      note_mismatch("no DEBUG=1 tap samples observed");
      return;
    end
    if (last_dbg1.cq_tail != expected_tail)
      note_mismatch($sformatf("DEBUG=1 tail mismatch got=%0d expected=%0d",
                              last_dbg1.cq_tail, expected_tail));
    if (last_dbg1.cq_head != expected_head)
      note_mismatch($sformatf("DEBUG=1 head mismatch got=%0d expected=%0d",
                              last_dbg1.cq_head, expected_head));
    if (last_dbg1.cq_full != expected_full)
      note_mismatch($sformatf("DEBUG=1 full mismatch got=%0d expected=%0d",
                              last_dbg1.cq_full, expected_full));
  endfunction

  function void check_lineage_end();
    if (!lineage_required)
      return;
    if (retired_actual_q.size() != retired_expected_q.size()) begin
      note_mismatch($sformatf("DEBUG=2 lineage count mismatch got=%0d expected=%0d",
                              retired_actual_q.size(), retired_expected_q.size()));
    end
    foreach (retired_expected_q[idx]) begin
      bit matched;
      matched = 1'b0;
      if (idx < retired_actual_q.size()) begin
        matched = (retired_actual_q[idx].packed_meta == retired_expected_q[idx].packed_meta);
        if (!matched) begin
          note_mismatch($sformatf(
            "DEBUG=2 meta mismatch idx=%0d got=0x%016h expected=0x%016h",
            idx, retired_actual_q[idx].packed_meta, retired_expected_q[idx].packed_meta));
        end
      end
      if (cov != null) begin
        cov.sample_lineage(retired_expected_q[idx].sqe_id,
                           retired_expected_q[idx].retire_seq,
                           matched);
      end
      if (!host_by_slot.exists(retired_expected_q[idx].slot)) begin
        note_mismatch($sformatf("missing host CQ slot %0d for retired CQE idx=%0d",
                                retired_expected_q[idx].slot, idx));
      end
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    check_dbg1_end();
    check_lineage_end();
    if (cqe_q.size() != 0 || meta_q.size() != 0 || pending_q.size() != 0)
      note_mismatch($sformatf("residual queues cqe=%0d meta=%0d pending=%0d",
                              cqe_q.size(), meta_q.size(), pending_q.size()));
    if (check_expected_posts && b_okay_count != expected_posts)
      note_mismatch($sformatf("post count mismatch got=%0d expected=%0d",
                              b_okay_count, expected_posts));
    if (vif.cnt_cqe_posted != b_okay_count)
      note_mismatch($sformatf("cnt_cqe_posted mismatch got=%0d expected=%0d",
                              vif.cnt_cqe_posted, b_okay_count));
  endfunction

  function void write_scorecard();
    int fd;
    if (scorecard_path == "")
      return;
    fd = $fopen(scorecard_path, "w");
    if (fd == 0) begin
      `uvm_error("SCB", $sformatf("Could not open scorecard %s", scorecard_path))
      return;
    end
    $fwrite(fd, "{\n");
    $fwrite(fd, "  \"case_id\": \"%s\",\n", case_id);
    $fwrite(fd, "  \"accepted_cqes\": %0d,\n", accepted_count);
    $fwrite(fd, "  \"host_writes\": %0d,\n", host_write_count);
    $fwrite(fd, "  \"b_okay\": %0d,\n", b_okay_count);
    $fwrite(fd, "  \"lineage_expected\": %0d,\n", retired_expected_q.size());
    $fwrite(fd, "  \"lineage_actual\": %0d,\n", retired_actual_q.size());
    $fwrite(fd, "  \"mismatch_count\": %0d,\n", mismatch_count);
    $fwrite(fd, "  \"lineage\": [\n");
    foreach (retired_expected_q[idx]) begin
      $fwrite(fd,
        "    {\"slot\": %0d, \"sqe_id\": %0d, \"retire_seq\": %0d, \"meta\": \"%016h\"}%s\n",
        retired_expected_q[idx].slot, retired_expected_q[idx].sqe_id,
        retired_expected_q[idx].retire_seq, retired_expected_q[idx].packed_meta,
        (idx + 1 == retired_expected_q.size()) ? "" : ",");
    end
    $fwrite(fd, "  ]\n");
    $fwrite(fd, "}\n");
    $fclose(fd);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    write_scorecard();
  endfunction
endclass

`endif
