`ifndef DOORBELL_DRIVER_SV
`define DOORBELL_DRIVER_SV

class doorbell_driver extends uvm_component;
  `uvm_component_utils(doorbell_driver)

  doorbell_agent_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(doorbell_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("DOORBELL_DRV", "Missing doorbell_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("DOORBELL_DRV", "doorbell_agent_cfg.vif is null")
  endfunction

  task drive_idle();
    cfg.vif.cq_head_dbl_pulse <= 1'b0;
    cfg.vif.cq_head_dbl_value <= 16'h0000;
  endtask

  task run_phase(uvm_phase phase);
    doorbell_item item;

    drive_idle();
    forever begin
      @(posedge cfg.vif.clk);
      if (cfg.vif.reset_n !== 1'b1) begin
        drive_idle();
        continue;
      end
      if (!cfg.has_pending())
        continue;
      item = cfg.pop_front();
      if (item == null)
        continue;
      @(negedge cfg.vif.clk);
      cfg.vif.cq_head_dbl_value <= item.value;
      cfg.vif.cq_head_dbl_pulse <= 1'b1;
      @(negedge cfg.vif.clk);
      cfg.vif.cq_head_dbl_pulse <= 1'b0;
    end
  endtask
endclass

`endif
