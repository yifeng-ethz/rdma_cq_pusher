TB_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
IP_DIR := $(abspath $(TB_DIR)/../..)

QUESTA_HOME ?= /data1/questaone_sim-2026.1_1/questasim
ETH_LIC_SERVER := 8161@lic-mentor.ethz.ch
export LM_LICENSE_FILE := $(ETH_LIC_SERVER)
export MGLS_LICENSE_FILE := $(LM_LICENSE_FILE)
export SALT_LICENSE_SERVER := $(LM_LICENSE_FILE)
export QSIM_INI := $(QUESTA_HOME)/modelsim.ini

VLIB := $(QUESTA_HOME)/linux_x86_64/vlib
VMAP := $(QUESTA_HOME)/linux_x86_64/vmap
VLOG := $(QUESTA_HOME)/linux_x86_64/vlog
VSIM := $(QUESTA_HOME)/linux_x86_64/vsim
VCOVER := $(QUESTA_HOME)/linux_x86_64/vcover
PYTHON ?= python3

UVM_PKG := $(firstword $(wildcard \
  $(QUESTA_HOME)/verilog_src/questa_uvm_pkg-1.2/src/uvm_pkg.sv \
  $(QUESTA_HOME)/verilog_src/uvm-1.2/src/uvm_pkg.sv))
UVM_SRC := $(dir $(UVM_PKG))
UVM_DPI_SO := $(firstword $(wildcard \
  $(QUESTA_HOME)/uvm-1.2/linux_x86_64/uvm_dpi.so \
  $(QUESTA_HOME)/verilog_src/uvm-1.2/linux_x86_64/uvm_dpi.so))
UVM_DPI_LIB := $(basename $(UVM_DPI_SO))

DEBUG_LEVEL ?= 2
BUILD_DIR ?= $(TB_DIR)/build
WORK_DIR := $(BUILD_DIR)/work
MODELSIM_INI := $(BUILD_DIR)/modelsim.ini
TOP := rdma_cq_pusher_tb_top
TEST ?= rdma_cq_pusher_base_test
CASE_ID ?= BASE
COV_CODE ?= sbecft

RTL_SRCS := \
  $(IP_DIR)/rtl/rdma_cq_ring_state.sv \
  $(IP_DIR)/rtl/rdma_cq_axi_writer.sv \
  $(IP_DIR)/rtl/rdma_cq_msix.sv \
  $(IP_DIR)/rtl/rdma_cq_pusher.sv

SV_SRCS := \
  $(UVM_PKG) \
  $(TB_DIR)/rdma_cq_pusher_if.sv \
  $(RTL_SRCS) \
  $(TB_DIR)/cqe_agent/cqe_agent_pkg.sv \
  $(TB_DIR)/host_axi_completer_agent/host_axi_completer_pkg.sv \
  $(TB_DIR)/rdma_cq_pusher_pkg.sv \
  $(TB_DIR)/tb_top.sv

VLOG_FLAGS := -ini $(MODELSIM_INI) -sv -work work \
  +incdir+$(UVM_SRC) +incdir+$(TB_DIR) \
  +incdir+$(TB_DIR)/cqe_agent \
  +incdir+$(TB_DIR)/host_axi_completer_agent \
  +define+DEBUG_LEVEL=$(DEBUG_LEVEL) +cover=$(COV_CODE)

VSIM_FLAGS := -ini $(MODELSIM_INI) -c -suppress 19 -suppress 3009 \
  -coverage -work work
ifneq ($(strip $(UVM_DPI_LIB)),)
VSIM_FLAGS += -sv_lib $(UVM_DPI_LIB)
endif

.PHONY: all prepare compile run_one smoke merge_ucdb coverage_report clean

all: smoke

prepare:
	mkdir -p $(BUILD_DIR) $(TB_DIR)/cov_after $(TB_DIR)/logs
	@if [ ! -f "$(MODELSIM_INI)" ]; then cp "$(QUESTA_HOME)/modelsim.ini" "$(MODELSIM_INI)"; chmod u+w "$(MODELSIM_INI)"; fi
	@if [ ! -d "$(WORK_DIR)" ]; then cd "$(BUILD_DIR)" && "$(VLIB)" work; fi
	cd "$(BUILD_DIR)" && "$(VMAP)" -modelsimini "$(MODELSIM_INI)" work "$(WORK_DIR)" >/dev/null

compile: prepare
	$(VLOG) $(VLOG_FLAGS) $(SV_SRCS)

run_one: compile
	$(VSIM) $(VSIM_FLAGS) $(TOP) \
	  +UVM_TESTNAME=$(TEST) +CASE_ID=$(CASE_ID) \
	  +SCORECARD=$(TB_DIR)/cov_after/$(CASE_ID).scorecard.json \
	  -l $(TB_DIR)/logs/$(CASE_ID).log \
	  -do "coverage save -onexit $(TB_DIR)/cov_after/$(CASE_ID).ucdb; run -all; quit -f"

smoke:
	$(MAKE) TEST=rdma_cq_pusher_base_test CASE_ID=BASE run_one

merge_ucdb:
	$(VCOVER) merge -out $(BUILD_DIR)/merged.ucdb $(TB_DIR)/cov_after/*.ucdb

coverage_report:
	$(VCOVER) report -details -codeAll $(BUILD_DIR)/merged.ucdb

clean:
	@echo "Manual cleanup required by project rule: no removal command is run by this Makefile."
