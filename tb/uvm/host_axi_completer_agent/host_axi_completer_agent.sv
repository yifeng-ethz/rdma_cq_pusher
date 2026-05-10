`ifndef HOST_AXI_COMPLETER_AGENT_SV
`define HOST_AXI_COMPLETER_AGENT_SV

class host_axi_completer_agent extends uvm_agent;
  `uvm_component_utils(host_axi_completer_agent)

  host_axi_completer_cfg cfg;
  host_axi_completer_driver driver;
  host_axi_completer_monitor monitor;
  uvm_analysis_port #(host_axi_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(host_axi_completer_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("HOST_AXI_AGENT", "Missing host_axi_completer_cfg")
    uvm_config_db#(host_axi_completer_cfg)::set(this, "driver", "cfg", cfg);
    uvm_config_db#(host_axi_completer_cfg)::set(this, "monitor", "cfg", cfg);
    driver = host_axi_completer_driver::type_id::create("driver", this);
    monitor = host_axi_completer_monitor::type_id::create("monitor", this);
    ap = new("ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.ap.connect(ap);
  endfunction
endclass

`endif
