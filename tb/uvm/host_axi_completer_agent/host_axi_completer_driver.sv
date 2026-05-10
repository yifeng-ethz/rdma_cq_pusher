`ifndef HOST_AXI_COMPLETER_DRIVER_SV
`define HOST_AXI_COMPLETER_DRIVER_SV

class host_axi_completer_driver extends uvm_component;
  `uvm_component_utils(host_axi_completer_driver)

  host_axi_completer_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
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
      @(negedge cfg.vif.clk);
      cfg.vif.m_axi_bvalid <= 1'b0;
      cfg.vif.m_axi_bresp <= AXI_RESP_OKAY;
      cfg.vif.m_axi_bid <= 4'h0;
    end
  endtask
endclass

`endif
