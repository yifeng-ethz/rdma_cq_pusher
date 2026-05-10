`ifndef CSR_CFG_MONITOR_SV
`define CSR_CFG_MONITOR_SV

class csr_cfg_monitor extends uvm_component;
  `uvm_component_utils(csr_cfg_monitor)

  csr_cfg_agent_cfg cfg;
  uvm_analysis_port #(csr_cfg_item) ap;
  longint unsigned cycle;
  bit [63:0] last_base;
  bit [15:0] last_depth;
  bit        last_enable;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
    last_base = 'x;
    last_depth = 'x;
    last_enable = 1'bx;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(csr_cfg_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CSR_CFG_MON", "Missing csr_cfg_agent_cfg")
    if (cfg.vif == null)
      `uvm_fatal("CSR_CFG_MON", "csr_cfg_agent_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge cfg.vif.clk);
      cycle++;
      if (cfg.vif.reset_n !== 1'b1)
        continue;
      #1;
      if (cfg.vif.cfg_cq_base !== last_base ||
          cfg.vif.cfg_cq_depth !== last_depth ||
          cfg.vif.cfg_enable !== last_enable) begin
        csr_cfg_item item;
        item = csr_cfg_item::type_id::create("item");
        item.base = cfg.vif.cfg_cq_base;
        item.depth = cfg.vif.cfg_cq_depth;
        item.enable = cfg.vif.cfg_enable;
        item.cycle = cycle;
        last_base = item.base;
        last_depth = item.depth;
        last_enable = item.enable;
        ap.write(item);
      end
    end
  endtask
endclass

`endif
