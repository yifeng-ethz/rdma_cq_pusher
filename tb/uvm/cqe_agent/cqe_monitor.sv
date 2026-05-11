`ifndef CQE_MONITOR_SV
`define CQE_MONITOR_SV

class cqe_monitor extends uvm_component;
  `uvm_component_utils(cqe_monitor)

  cqe_agent_cfg cfg;
  uvm_analysis_port #(cqe_item) ap;
  longint unsigned cycle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(cqe_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CQE_MON", "Missing cqe_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("CQE_MON", "cqe_agent_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge cfg.vif.clk);
      cycle++;
      if (cfg.vif.reset_n !== 1'b1)
        continue;
      #1;
      if (cfg.vif.s_axis_cqe_tvalid && cfg.vif.s_axis_cqe_tready) begin
        cqe_item item;
        item = cqe_item::type_id::create("item");
        item.data = cfg.vif.s_axis_cqe_tdata;
        item.rqe_id = cfg.vif.s_axis_cqe_tuser;
        item.last = cfg.vif.s_axis_cqe_tlast;
        item.meta = cfg.vif.s_axis_cqe_tuser_meta;
        item.cycle = cycle;
        ap.write(item);
      end
    end
  endtask
endclass

`endif
