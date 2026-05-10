`ifndef DBG1_TAP_MONITOR_SV
`define DBG1_TAP_MONITOR_SV

class dbg1_tap_monitor extends uvm_component;
  `uvm_component_utils(dbg1_tap_monitor)

  virtual rdma_cq_pusher_if vif;
  uvm_analysis_port #(dbg1_tap_item) ap;
  longint unsigned cycle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
      `uvm_fatal("DBG1_MON", "Missing rdma_cq_pusher_if")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      cycle++;
      if (vif.reset_n !== 1'b1)
        continue;
      #1;
      begin
        dbg1_tap_item item;
        item = dbg1_tap_item::type_id::create("item");
        item.cq_tail = vif.dbg_cur_cq_tail;
        item.cq_head = vif.dbg_cur_cq_head_credit;
        item.cq_full = vif.dbg_cq_full;
        item.aw_pending = vif.dbg_aw_pending;
        item.b_inflight = vif.dbg_b_inflight;
        item.ring_full_stall_cyc = vif.dbg_ring_full_stall_cyc;
        item.state = vif.dbg_state;
        item.cnt_bresp_error = vif.dbg_cnt_bresp_error;
        item.cycle = cycle;
        ap.write(item);
      end
    end
  endtask
endclass

`endif
