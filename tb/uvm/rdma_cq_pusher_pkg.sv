`ifndef RDMA_CQ_PUSHER_PKG_SV
`define RDMA_CQ_PUSHER_PKG_SV

package rdma_cq_pusher_pkg;
  import uvm_pkg::*;
  import cqe_agent_pkg::*;
  import cqe_meta_agent_pkg::*;
  import csr_cfg_agent_pkg::*;
  import doorbell_agent_pkg::*;
  import host_axi_completer_pkg::*;
  `include "uvm_macros.svh"
  `uvm_analysis_imp_decl(_cqe)
  `uvm_analysis_imp_decl(_meta)
  `uvm_analysis_imp_decl(_host)
  `uvm_analysis_imp_decl(_cfg)
  `uvm_analysis_imp_decl(_doorbell)
  `uvm_analysis_imp_decl(_dbg1)
  `uvm_analysis_imp_decl(_dbg2)

  typedef struct {
    bit [511:0] data;
    bit [15:0]  sqe_id;
    bit [15:0]  retire_seq;
    bit [15:0]  origin_dma_done_seq;
    bit [15:0]  push_seq;
    bit [63:0]  packed_meta;
    bit [15:0]  slot;
  } paired_cqe_t;

  class dbg1_tap_item extends uvm_sequence_item;
    `uvm_object_utils(dbg1_tap_item)

    bit [15:0]      cq_tail;
    bit [15:0]      cq_head;
    bit             cq_full;
    bit [3:0]       aw_pending;
    bit [3:0]       b_inflight;
    bit [31:0]      ring_full_stall_cyc;
    bit [3:0]       state;
    bit [31:0]      cnt_bresp_error;
    longint unsigned cycle;

    function new(string name = "dbg1_tap_item");
      super.new(name);
      cq_tail = '0;
      cq_head = '0;
      cq_full = 1'b0;
      aw_pending = '0;
      b_inflight = '0;
      ring_full_stall_cyc = '0;
      state = '0;
      cnt_bresp_error = '0;
      cycle = 0;
    endfunction
  endclass

  class dbg2_lineage_item extends uvm_sequence_item;
    `uvm_object_utils(dbg2_lineage_item)

    bit [15:0]      sqe_id;
    bit [15:0]      retire_seq;
    bit [15:0]      origin_dma_done_seq;
    bit [15:0]      push_seq;
    bit [63:0]      packed_meta;
    longint unsigned cycle;

    function new(string name = "dbg2_lineage_item");
      super.new(name);
      sqe_id = '0;
      retire_seq = '0;
      origin_dma_done_seq = '0;
      push_seq = '0;
      packed_meta = '0;
      cycle = 0;
    endfunction
  endclass

  `include "coverage.sv"
  `include "dbg1_tap_monitor.sv"
  `include "dbg2_tap_monitor.sv"
  `include "msix_sink_monitor.sv"
  `include "scoreboard.sv"

  class rdma_cq_pusher_env_dbg1 extends uvm_env;
    `uvm_component_utils(rdma_cq_pusher_env_dbg1)

    virtual rdma_cq_pusher_if vif;
    cqe_agent_cfg cqe_cfg;
    csr_cfg_agent_cfg csr_cfg;
    doorbell_agent_cfg doorbell_cfg;
    host_axi_completer_cfg host_axi_cfg;
    cqe_agent cqe_src_agent;
    csr_cfg_agent csr_cfg_agent_i;
    doorbell_agent doorbell_agent_i;
    host_axi_completer_agent host_axi_agent;
    dbg1_tap_monitor dbg1_mon;
    msix_sink_monitor msix_mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
        `uvm_fatal("ENV_DBG1", "Missing rdma_cq_pusher_if")
      cqe_cfg = cqe_agent_cfg::type_id::create("cqe_cfg");
      csr_cfg = csr_cfg_agent_cfg::type_id::create("csr_cfg");
      doorbell_cfg = doorbell_agent_cfg::type_id::create("doorbell_cfg");
      host_axi_cfg = host_axi_completer_cfg::type_id::create("host_axi_cfg");
      cqe_cfg.vif = vif;
      csr_cfg.vif = vif;
      doorbell_cfg.vif = vif;
      host_axi_cfg.vif = vif;
      uvm_config_db#(cqe_agent_cfg)::set(this, "cqe_src_agent", "cfg", cqe_cfg);
      uvm_config_db#(csr_cfg_agent_cfg)::set(this, "csr_cfg_agent_i", "cfg", csr_cfg);
      uvm_config_db#(doorbell_agent_cfg)::set(this, "doorbell_agent_i", "cfg", doorbell_cfg);
      uvm_config_db#(host_axi_completer_cfg)::set(this, "host_axi_agent", "cfg", host_axi_cfg);
      cqe_src_agent = cqe_agent::type_id::create("cqe_src_agent", this);
      csr_cfg_agent_i = csr_cfg_agent::type_id::create("csr_cfg_agent_i", this);
      doorbell_agent_i = doorbell_agent::type_id::create("doorbell_agent_i", this);
      host_axi_agent = host_axi_completer_agent::type_id::create("host_axi_agent", this);
      dbg1_mon = dbg1_tap_monitor::type_id::create("dbg1_mon", this);
      msix_mon = msix_sink_monitor::type_id::create("msix_mon", this);
    endfunction
  endclass

  class rdma_cq_pusher_env_dbg2 extends uvm_env;
    `uvm_component_utils(rdma_cq_pusher_env_dbg2)

    virtual rdma_cq_pusher_if vif;
    cqe_meta_agent_cfg meta_cfg;
    cqe_meta_agent cqe_meta_agent_i;
    dbg2_tap_monitor dbg2_mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
        `uvm_fatal("ENV_DBG2", "Missing rdma_cq_pusher_if")
      meta_cfg = cqe_meta_agent_cfg::type_id::create("meta_cfg");
      meta_cfg.vif = vif;
      uvm_config_db#(cqe_meta_agent_cfg)::set(this, "cqe_meta_agent_i", "cfg", meta_cfg);
      cqe_meta_agent_i = cqe_meta_agent::type_id::create("cqe_meta_agent_i", this);
      dbg2_mon = dbg2_tap_monitor::type_id::create("dbg2_mon", this);
    endfunction
  endclass

  class rdma_cq_pusher_env_top extends uvm_env;
    `uvm_component_utils(rdma_cq_pusher_env_top)

    virtual rdma_cq_pusher_if vif;
    rdma_cq_pusher_env_dbg1 env_dbg1;
    rdma_cq_pusher_env_dbg2 env_dbg2;
    rdma_cq_pusher_scoreboard scb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
        `uvm_fatal("ENV_TOP", "Missing rdma_cq_pusher_if")
      env_dbg1 = rdma_cq_pusher_env_dbg1::type_id::create("env_dbg1", this);
      env_dbg2 = rdma_cq_pusher_env_dbg2::type_id::create("env_dbg2", this);
      scb = rdma_cq_pusher_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      env_dbg1.cqe_src_agent.ap.connect(scb.cqe_imp);
      env_dbg1.host_axi_agent.ap.connect(scb.host_imp);
      env_dbg1.csr_cfg_agent_i.ap.connect(scb.cfg_imp);
      env_dbg1.doorbell_agent_i.ap.connect(scb.doorbell_imp);
      env_dbg1.dbg1_mon.ap.connect(scb.dbg1_imp);
      env_dbg2.cqe_meta_agent_i.ap.connect(scb.meta_imp);
      env_dbg2.dbg2_mon.ap.connect(scb.dbg2_imp);
    endfunction
  endclass

  `include "base_test.sv"
endpackage

`endif
