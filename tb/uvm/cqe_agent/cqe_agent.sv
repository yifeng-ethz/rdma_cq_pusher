`ifndef CQE_AGENT_SV
`define CQE_AGENT_SV

class cqe_agent extends uvm_agent;
  `uvm_component_utils(cqe_agent)

  cqe_agent_cfg cfg;
  cqe_driver driver;
  cqe_monitor monitor;
  uvm_analysis_port #(cqe_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(cqe_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CQE_AGENT", "Missing cqe_agent_cfg")
    uvm_config_db#(cqe_agent_cfg)::set(this, "driver", "cfg", cfg);
    uvm_config_db#(cqe_agent_cfg)::set(this, "monitor", "cfg", cfg);
    driver = cqe_driver::type_id::create("driver", this);
    monitor = cqe_monitor::type_id::create("monitor", this);
    ap = new("ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.ap.connect(ap);
  endfunction
endclass

`endif
