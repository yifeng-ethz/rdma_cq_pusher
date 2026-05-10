`ifndef CSR_CFG_DRIVER_SV
`define CSR_CFG_DRIVER_SV

class csr_cfg_driver extends uvm_component;
  `uvm_component_utils(csr_cfg_driver)

  csr_cfg_agent_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(csr_cfg_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CSR_CFG_DRV", "Missing csr_cfg_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("CSR_CFG_DRV", "csr_cfg_agent_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    csr_cfg_item item;

    forever begin
      @(posedge cfg.vif.clk);
      if (cfg.vif.reset_n !== 1'b1)
        continue;
      if (!cfg.has_pending())
        continue;
      item = cfg.pop_front();
      if (item == null)
        continue;
      @(negedge cfg.vif.clk);
      cfg.vif.cfg_cq_base <= item.base;
      cfg.vif.cfg_cq_depth <= item.depth;
      cfg.vif.cfg_enable <= item.enable;
    end
  endtask
endclass

`endif
