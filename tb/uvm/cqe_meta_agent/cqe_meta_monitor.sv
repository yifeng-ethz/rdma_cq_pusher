`ifndef CQE_META_MONITOR_SV
`define CQE_META_MONITOR_SV

class cqe_meta_monitor extends uvm_component;
  `uvm_component_utils(cqe_meta_monitor)

  cqe_meta_agent_cfg cfg;
  uvm_analysis_port #(cqe_meta_item) ap;
  longint unsigned cycle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(cqe_meta_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CQE_META_MON", "Missing cqe_meta_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("CQE_META_MON", "cqe_meta_agent_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge cfg.vif.clk);
      cycle++;
      if (cfg.vif.reset_n !== 1'b1)
        continue;
      #1;
      if (cfg.vif.s_axis_cqe_tvalid && cfg.vif.s_axis_cqe_tready) begin
        cqe_meta_item item;
        item = cqe_meta_item::type_id::create("item");
        item.packed_meta = cfg.vif.s_axis_cqe_tuser_meta;
        item.sqe_id = cfg.vif.s_axis_cqe_tuser_meta[15:0];
        item.retire_seq = cfg.vif.s_axis_cqe_tuser_meta[31:16];
        item.origin_dma_done_seq = cfg.vif.s_axis_cqe_tuser_meta[47:32];
        item.push_seq = cfg.vif.s_axis_cqe_tuser_meta[63:48];
        item.cycle = cycle;
        ap.write(item);
      end
    end
  endtask
endclass

`endif
