`ifndef CQE_META_DRIVER_SV
`define CQE_META_DRIVER_SV

class cqe_meta_driver extends uvm_component;
  `uvm_component_utils(cqe_meta_driver)

  cqe_meta_agent_cfg cfg;
  uvm_analysis_port #(cqe_meta_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(cqe_meta_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CQE_META_DRV", "Missing cqe_meta_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("CQE_META_DRV", "cqe_meta_agent_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    cqe_meta_item item;

    cfg.vif.s_axis_cqe_tuser_meta <= '0;
    forever begin
      @(posedge cfg.vif.clk);
      if (cfg.vif.reset_n !== 1'b1) begin
        cfg.vif.s_axis_cqe_tuser_meta <= '0;
        continue;
      end
      if (!cfg.has_pending())
        continue;
      item = cfg.pop_front();
      if (item == null)
        continue;
      @(negedge cfg.vif.clk);
      cfg.vif.s_axis_cqe_tuser_meta <= item.packed_meta;
      do @(posedge cfg.vif.clk); while (cfg.vif.reset_n === 1'b1 &&
                                        !(cfg.vif.s_axis_cqe_tvalid &&
                                          cfg.vif.s_axis_cqe_tready));
      if (cfg.vif.reset_n === 1'b1)
        ap.write(item);
      @(negedge cfg.vif.clk);
      cfg.vif.s_axis_cqe_tuser_meta <= '0;
    end
  endtask
endclass

`endif
