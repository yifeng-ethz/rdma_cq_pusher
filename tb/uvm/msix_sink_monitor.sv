`ifndef MSIX_SINK_MONITOR_SV
`define MSIX_SINK_MONITOR_SV

class msix_sink_monitor extends uvm_component;
  `uvm_component_utils(msix_sink_monitor)

  virtual rdma_cq_pusher_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
      `uvm_fatal("MSIX_MON", "Missing rdma_cq_pusher_if")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.reset_n === 1'b1 && vif.msix_req !== 1'b0)
        `uvm_error("MSIX", "msix_req asserted in Phase 1 quiet-stub mode")
    end
  endtask
endclass

`endif
