`ifndef CSR_CFG_AGENT_SV
`define CSR_CFG_AGENT_SV

class csr_cfg_agent extends uvm_agent;
  `uvm_component_utils(csr_cfg_agent)

  csr_cfg_agent_cfg cfg;
  csr_cfg_driver driver;
  csr_cfg_monitor monitor;
  uvm_analysis_port #(csr_cfg_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(csr_cfg_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CSR_CFG_AGENT", "Missing csr_cfg_agent_cfg")
    uvm_config_db#(csr_cfg_agent_cfg)::set(this, "driver", "cfg", cfg);
    uvm_config_db#(csr_cfg_agent_cfg)::set(this, "monitor", "cfg", cfg);
    driver = csr_cfg_driver::type_id::create("driver", this);
    monitor = csr_cfg_monitor::type_id::create("monitor", this);
    ap = new("ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.ap.connect(ap);
  endfunction
endclass

`endif
