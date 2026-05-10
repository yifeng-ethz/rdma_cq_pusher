`ifndef HOST_AXI_COMPLETER_MONITOR_SV
`define HOST_AXI_COMPLETER_MONITOR_SV

class host_axi_completer_monitor extends uvm_component;
  `uvm_component_utils(host_axi_completer_monitor)

  host_axi_completer_cfg cfg;
  uvm_analysis_port #(host_axi_item) ap;
  longint unsigned cycle;
  bit [63:0] awaddr_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(host_axi_completer_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("HOST_AXI_MON", "Missing host_axi_completer_cfg")
    if (cfg.vif == null)
      `uvm_fatal("HOST_AXI_MON", "host_axi_completer_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge cfg.vif.clk);
      cycle++;
      if (cfg.vif.reset_n !== 1'b1) begin
        awaddr_q.delete();
        continue;
      end
      #1;
      if (cfg.vif.m_axi_awvalid && cfg.vif.m_axi_awready) begin
        host_axi_item item;
        item = host_axi_item::type_id::create("aw_item");
        item.kind = HOST_AXI_AW;
        item.id = cfg.vif.m_axi_awid;
        item.addr = cfg.vif.m_axi_awaddr;
        item.len = cfg.vif.m_axi_awlen;
        item.size = cfg.vif.m_axi_awsize;
        item.burst = cfg.vif.m_axi_awburst;
        item.slot = cfg.addr_to_slot(cfg.vif.m_axi_awaddr);
        item.cycle = cycle;
        awaddr_q.push_back(cfg.vif.m_axi_awaddr);
        ap.write(item);
      end
      if (cfg.vif.m_axi_wvalid && cfg.vif.m_axi_wready) begin
        host_axi_item item;
        bit [63:0] addr;
        item = host_axi_item::type_id::create("w_item");
        item.kind = HOST_AXI_W;
        addr = (awaddr_q.size() == 0) ? cfg.cfg_cq_base : awaddr_q.pop_front();
        item.addr = addr;
        item.slot = cfg.addr_to_slot(addr);
        item.data = cfg.vif.m_axi_wdata;
        item.strb = cfg.vif.m_axi_wstrb;
        item.last = cfg.vif.m_axi_wlast;
        item.cycle = cycle;
        ap.write(item);
      end
      if (cfg.vif.m_axi_bvalid && cfg.vif.m_axi_bready) begin
        host_axi_item item;
        item = host_axi_item::type_id::create("b_item");
        item.kind = HOST_AXI_B;
        item.id = cfg.vif.m_axi_bid;
        item.resp = cfg.vif.m_axi_bresp;
        item.cycle = cycle;
        ap.write(item);
      end
    end
  endtask
endclass

`endif
