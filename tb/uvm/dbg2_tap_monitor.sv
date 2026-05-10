`ifndef DBG2_TAP_MONITOR_SV
`define DBG2_TAP_MONITOR_SV

class dbg2_tap_monitor extends uvm_component;
  `uvm_component_utils(dbg2_tap_monitor)

  virtual rdma_cq_pusher_if vif;
  uvm_analysis_port #(dbg2_lineage_item) ap;
  longint unsigned cycle;
  bit [31:0] last_posted_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle = 0;
    last_posted_count = 32'h0000_0000;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rdma_cq_pusher_if)::get(this, "", "vif", vif))
      `uvm_fatal("DBG2_MON", "Missing rdma_cq_pusher_if")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      cycle++;
      if (vif.reset_n !== 1'b1) begin
        last_posted_count = 32'h0000_0000;
        continue;
      end
      #1;
      if (vif.cnt_cqe_posted != last_posted_count) begin
        dbg2_lineage_item item;
        bit [63:0] meta;
        meta = vif.dbg_last_pushed_meta;
        item = dbg2_lineage_item::type_id::create("item");
        item.packed_meta = meta;
        item.sqe_id = meta[15:0];
        item.retire_seq = meta[31:16];
        item.origin_dma_done_seq = meta[47:32];
        item.push_seq = meta[63:48];
        item.cycle = cycle;
        ap.write(item);
        last_posted_count = vif.cnt_cqe_posted;
      end
    end
  endtask
endclass

`endif
