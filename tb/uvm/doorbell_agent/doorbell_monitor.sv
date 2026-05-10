`ifndef DOORBELL_MONITOR_SV
`define DOORBELL_MONITOR_SV

class doorbell_monitor extends uvm_component;
  `uvm_component_utils(doorbell_monitor)

  doorbell_agent_cfg cfg;
  uvm_analysis_port #(doorbell_item) ap;
  longint unsigned cycle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(doorbell_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("DOORBELL_MON", "Missing doorbell_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("DOORBELL_MON", "doorbell_agent_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge cfg.vif.clk);
      cycle++;
      if (cfg.vif.reset_n !== 1'b1)
        continue;
      #1;
      if (cfg.vif.cq_head_dbl_pulse) begin
        doorbell_item item;
        item = doorbell_item::type_id::create("item");
        item.value = cfg.vif.cq_head_dbl_value;
        item.cycle = cycle;
        ap.write(item);
      end
    end
  endtask
endclass

`endif
