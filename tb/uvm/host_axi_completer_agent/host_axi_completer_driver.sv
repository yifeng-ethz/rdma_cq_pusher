`ifndef HOST_AXI_COMPLETER_DRIVER_SV
`define HOST_AXI_COMPLETER_DRIVER_SV

class host_axi_completer_driver extends uvm_component;
  `uvm_component_utils(host_axi_completer_driver)

  host_axi_completer_cfg cfg;
  uvm_analysis_port #(host_axi_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(host_axi_completer_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("HOST_AXI_DRV", "Missing host_axi_completer_cfg")
    if (cfg.vif == null)
      `uvm_fatal("HOST_AXI_DRV", "host_axi_completer_cfg.vif is null")
  endfunction

  task drive_idle();
    cfg.vif.m_axi_awready <= 1'b0;
    cfg.vif.m_axi_wready <= 1'b0;
    cfg.vif.m_axi_bid <= 4'h0;
    cfg.vif.m_axi_bresp <= AXI_RESP_OKAY;
    cfg.vif.m_axi_bvalid <= 1'b0;
  endtask

  task run_phase(uvm_phase phase);
    bit [3:0] awid;
    bit [63:0] awaddr;
    bit [511:0] wdata;
    bit [1:0] resp;
    bit [15:0] slot;

    drive_idle();
    forever begin
      @(posedge cfg.vif.clk);
      if (cfg.vif.reset_n !== 1'b1) begin
        drive_idle();
        continue;
      end

      if (cfg.vif.m_axi_awvalid !== 1'b1)
        continue;

      repeat (cfg.awready_lag) @(posedge cfg.vif.clk);
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_awready <= 1'b1;
      do @(posedge cfg.vif.clk); while (cfg.vif.reset_n === 1'b1 &&
                                        !(cfg.vif.m_axi_awvalid &&
                                          cfg.vif.m_axi_awready));
      awid = cfg.vif.m_axi_awid;
      awaddr = cfg.vif.m_axi_awaddr;
      begin
        host_axi_item aw_item;
        aw_item = host_axi_item::type_id::create("aw_item");
        aw_item.kind = HOST_AXI_AW;
        aw_item.id = cfg.vif.m_axi_awid;
        aw_item.addr = cfg.vif.m_axi_awaddr;
        aw_item.len = cfg.vif.m_axi_awlen;
        aw_item.size = cfg.vif.m_axi_awsize;
        aw_item.burst = cfg.vif.m_axi_awburst;
        aw_item.slot = cfg.addr_to_slot(cfg.vif.m_axi_awaddr);
        ap.write(aw_item);
      end
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_awready <= 1'b0;

      do @(posedge cfg.vif.clk); while (cfg.vif.reset_n === 1'b1 &&
                                        cfg.vif.m_axi_wvalid !== 1'b1);
      repeat (cfg.wready_lag) @(posedge cfg.vif.clk);
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_wready <= 1'b1;
      do @(posedge cfg.vif.clk); while (cfg.vif.reset_n === 1'b1 &&
                                        !(cfg.vif.m_axi_wvalid &&
                                          cfg.vif.m_axi_wready));
      wdata = cfg.vif.m_axi_wdata;
      slot = cfg.addr_to_slot(awaddr);
      cfg.host_mem[slot] = wdata;
      begin
        host_axi_item w_item;
        w_item = host_axi_item::type_id::create("w_item");
        w_item.kind = HOST_AXI_W;
        w_item.addr = awaddr;
        w_item.slot = slot;
        w_item.data = cfg.vif.m_axi_wdata;
        w_item.strb = cfg.vif.m_axi_wstrb;
        w_item.last = cfg.vif.m_axi_wlast;
        ap.write(w_item);
      end
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_wready <= 1'b0;

      repeat (cfg.bvalid_lag) @(posedge cfg.vif.clk);
      resp = cfg.next_bresp();
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_bid <= awid;
      cfg.vif.m_axi_bresp <= resp;
      cfg.vif.m_axi_bvalid <= 1'b1;
      do @(posedge cfg.vif.clk); while (cfg.vif.reset_n === 1'b1 &&
                                        !(cfg.vif.m_axi_bvalid &&
                                          cfg.vif.m_axi_bready));
      if (cfg.vif.reset_n === 1'b1) begin
        host_axi_item b_item;
        b_item = host_axi_item::type_id::create("b_item");
        b_item.kind = HOST_AXI_B;
        b_item.id = awid;
        b_item.resp = resp;
        ap.write(b_item);
      end
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_bvalid <= 1'b0;
      cfg.vif.m_axi_bresp <= AXI_RESP_OKAY;
      cfg.vif.m_axi_bid <= 4'h0;
    end
  endtask
endclass

`endif
