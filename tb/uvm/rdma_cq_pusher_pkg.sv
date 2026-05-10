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

  class rdma_cq_pusher_scoreboard;
  endclass

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
    endfunction
  endclass

  class rdma_cq_pusher_env_dbg2 extends uvm_env;
    `uvm_component_utils(rdma_cq_pusher_env_dbg2)

    virtual rdma_cq_pusher_if vif;
    cqe_meta_agent_cfg meta_cfg;
    cqe_meta_agent cqe_meta_agent_i;

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
    endfunction
  endclass

  class rdma_cq_pusher_env_top extends uvm_env;
    `uvm_component_utils(rdma_cq_pusher_env_top)

    virtual rdma_cq_pusher_if vif;
    rdma_cq_pusher_env_dbg1 env_dbg1;
    rdma_cq_pusher_env_dbg2 env_dbg2;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
        `uvm_fatal("ENV_TOP", "Missing rdma_cq_pusher_if")
      env_dbg1 = rdma_cq_pusher_env_dbg1::type_id::create("env_dbg1", this);
      env_dbg2 = rdma_cq_pusher_env_dbg2::type_id::create("env_dbg2", this);
    endfunction
  endclass

  `include "base_test.sv"
endpackage

`endif
