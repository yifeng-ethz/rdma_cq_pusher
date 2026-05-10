`ifndef CQE_DRIVER_SV
`define CQE_DRIVER_SV

class cqe_driver extends uvm_component;
  `uvm_component_utils(cqe_driver)

  cqe_agent_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(cqe_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CQE_DRV", "Missing cqe_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("CQE_DRV", "cqe_agent_cfg.vif is null")
  endfunction

  task drive_idle();
    cfg.vif.s_axis_cqe_tdata <= '0;
    cfg.vif.s_axis_cqe_tvalid <= 1'b0;
    cfg.vif.s_axis_cqe_tlast <= 1'b1;
    cfg.vif.s_axis_cqe_tuser <= 16'h0000;
  endtask

  task run_phase(uvm_phase phase);
    cqe_item item;

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
      cfg.vif.s_axis_cqe_tdata <= item.data;
      cfg.vif.s_axis_cqe_tuser <= item.sqe_id;
      cfg.vif.s_axis_cqe_tlast <= item.last;
      cfg.vif.s_axis_cqe_tvalid <= 1'b1;

      do @(posedge cfg.vif.clk); while (cfg.vif.reset_n === 1'b1 &&
                                        !(cfg.vif.s_axis_cqe_tvalid &&
                                          cfg.vif.s_axis_cqe_tready));

      @(negedge cfg.vif.clk);
      cfg.vif.s_axis_cqe_tvalid <= 1'b0;
      cfg.vif.s_axis_cqe_tdata <= '0;
      cfg.vif.s_axis_cqe_tuser <= 16'h0000;
      cfg.vif.s_axis_cqe_tlast <= 1'b1;
    end
  endtask
endclass

`endif
