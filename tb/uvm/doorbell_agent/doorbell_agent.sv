`ifndef DOORBELL_AGENT_SV
`define DOORBELL_AGENT_SV

class doorbell_agent extends uvm_agent;
  `uvm_component_utils(doorbell_agent)

  doorbell_agent_cfg cfg;
  doorbell_driver driver;
  doorbell_monitor monitor;
  uvm_analysis_port #(doorbell_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(doorbell_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("DOORBELL_AGENT", "Missing doorbell_agent_cfg")
    uvm_config_db#(doorbell_agent_cfg)::set(this, "driver", "cfg", cfg);
    uvm_config_db#(doorbell_agent_cfg)::set(this, "monitor", "cfg", cfg);
    driver = doorbell_driver::type_id::create("driver", this);
    monitor = doorbell_monitor::type_id::create("monitor", this);
    ap = new("ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.ap.connect(ap);
  endfunction
endclass

`endif
