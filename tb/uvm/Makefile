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
SEED ?= 1
COV_CODE ?= sbecft
SMOKE_CASE_IDS := B001 B002 B003
SMOKE_CASES := \
  rdma_cq_pusher_b001_test:B001 \
  rdma_cq_pusher_b002_test:B002 \
  rdma_cq_pusher_b003_test:B003
SMOKE_UCDBS := $(addprefix $(TB_DIR)/cov_after/,$(addsuffix .ucdb,$(SMOKE_CASE_IDS)))
SMOKE_SCORECARDS := $(addprefix $(TB_DIR)/cov_after/,$(addsuffix .scorecard.json,$(SMOKE_CASE_IDS)))
COVERAGE_REPORT ?= $(BUILD_DIR)/merged_coverage.txt
COVERAGE_SUMMARY ?= $(BUILD_DIR)/merged_coverage_summary.txt
RUN_DO := $(BUILD_DIR)/run_$(CASE_ID).do

-include $(TB_DIR)/phase_b_case_map.mk

RTL_SRCS := \
  $(IP_DIR)/rtl/rdma_cq_ring_state.sv \
  $(IP_DIR)/rtl/rdma_cq_axi_writer.sv \
  $(IP_DIR)/rtl/rdma_cq_msix.sv \
  $(IP_DIR)/rtl/rdma_cq_pusher.sv

TB_PRE_SRCS := \
  $(UVM_PKG) \
  $(TB_DIR)/rdma_cq_pusher_if.sv \
  $(TB_DIR)/cqe_agent/cqe_agent_pkg.sv \
  $(TB_DIR)/cqe_meta_agent/cqe_meta_agent_pkg.sv \
  $(TB_DIR)/csr_cfg_agent/csr_cfg_agent_pkg.sv \
  $(TB_DIR)/doorbell_agent/doorbell_agent_pkg.sv \
  $(TB_DIR)/host_axi_completer_agent/host_axi_completer_pkg.sv

TB_POST_SRCS := \
  $(TB_DIR)/rdma_cq_pusher_pkg.sv \
  $(TB_DIR)/tb_top.sv

VLOG_COMMON_FLAGS := -ini $(MODELSIM_INI) -sv -work work \
  +incdir+$(UVM_SRC) +incdir+$(TB_DIR) \
  +incdir+$(TB_DIR)/cqe_agent \
  +incdir+$(TB_DIR)/cqe_meta_agent \
  +incdir+$(TB_DIR)/csr_cfg_agent \
  +incdir+$(TB_DIR)/doorbell_agent \
  +incdir+$(TB_DIR)/host_axi_completer_agent \
  +define+DEBUG_LEVEL=$(DEBUG_LEVEL)

VLOG_COV_FLAGS := $(VLOG_COMMON_FLAGS) +cover=$(COV_CODE)

VSIM_FLAGS := -ini $(MODELSIM_INI) -c -suppress 19 -suppress 3009 \
  -coverage -work work
ifneq ($(strip $(UVM_DPI_LIB)),)
VSIM_FLAGS += -sv_lib $(UVM_DPI_LIB)
endif

.PHONY: all prepare compile run_one run_one_nocompile smoke full_cases cross_validate merge_ucdb merge_bucket_ucdb coverage_report regress clean

all: regress

prepare:
	mkdir -p $(BUILD_DIR) $(TB_DIR)/cov_after $(TB_DIR)/cov_after/txn_growth $(TB_DIR)/logs
	@if [ ! -f "$(MODELSIM_INI)" ]; then cp "$(QUESTA_HOME)/modelsim.ini" "$(MODELSIM_INI)"; chmod u+w "$(MODELSIM_INI)"; fi
	@if [ ! -d "$(WORK_DIR)" ]; then cd "$(BUILD_DIR)" && "$(VLIB)" work; fi
	cd "$(BUILD_DIR)" && "$(VMAP)" -modelsimini "$(MODELSIM_INI)" work "$(WORK_DIR)" >/dev/null

compile: prepare
	$(VLOG) $(VLOG_COMMON_FLAGS) $(TB_PRE_SRCS)
	$(VLOG) $(VLOG_COV_FLAGS) $(RTL_SRCS)
	$(VLOG) $(VLOG_COMMON_FLAGS) $(TB_POST_SRCS)

run_one: compile run_one_nocompile

run_one_nocompile:
	$(PYTHON) $(TB_DIR)/scripts/write_run_do.py \
	  --tb-dir $(TB_DIR) --case-id $(CASE_ID) --seed $(SEED) --output $(RUN_DO)
	$(VSIM) $(VSIM_FLAGS) $(TOP) \
	  +UVM_TESTNAME=$(TEST) +CASE_ID=$(CASE_ID) \
	  +DV_TB_DIR=$(TB_DIR) +DV_SEED=$(SEED) \
	  +SCORECARD=$(TB_DIR)/cov_after/$(CASE_ID).scorecard.json \
	  -l $(TB_DIR)/logs/$(CASE_ID).log \
	  -do $(RUN_DO)
	$(PYTHON) $(TB_DIR)/scripts/ensure_checkpoint_ucdbs.py \
	  --tb-dir $(TB_DIR) --case-id $(CASE_ID) --seed $(SEED)
	@if grep -Eq "UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9]" "$(TB_DIR)/logs/$(CASE_ID).log"; then \
	  echo "UVM failure found in $(TB_DIR)/logs/$(CASE_ID).log"; \
	  exit 1; \
	fi
	@test -s "$(TB_DIR)/cov_after/$(CASE_ID).ucdb" || \
	  (echo "Missing UCDB $(TB_DIR)/cov_after/$(CASE_ID).ucdb"; exit 1)

smoke: compile
	@for entry in $(SMOKE_CASES); do \
	  test_name=$${entry%%:*}; case_id=$${entry##*:}; \
	  $(MAKE) TEST=$$test_name CASE_ID=$$case_id run_one_nocompile || exit $$?; \
	done

full_cases: compile
	@for entry in $(ALL_CASES); do \
	  test_name=$${entry%%:*}; case_id=$${entry##*:}; \
	  echo "RUN $$case_id $$test_name"; \
	  $(MAKE) TEST=$$test_name CASE_ID=$$case_id run_one_nocompile || exit $$?; \
	done

cross_validate:
	$(PYTHON) $(TB_DIR)/scripts/cross_validate_dbg.py \
	  --scorecards $(ALL_SCORECARDS)

merge_ucdb:
	@for ucdb in $(ALL_UCDBS); do \
	  test -s "$$ucdb" || { echo "Missing UCDB $$ucdb"; exit 1; }; \
	done
	$(VCOVER) merge -out $(BUILD_DIR)/merged.ucdb $(ALL_UCDBS)

merge_bucket_ucdb:
	@for ucdb in $(BASIC_UCDBS); do test -s "$$ucdb" || { echo "Missing BASIC UCDB $$ucdb"; exit 1; }; done
	@for ucdb in $(EDGE_UCDBS); do test -s "$$ucdb" || { echo "Missing EDGE UCDB $$ucdb"; exit 1; }; done
	@for ucdb in $(PROF_UCDBS); do test -s "$$ucdb" || { echo "Missing PROF UCDB $$ucdb"; exit 1; }; done
	@for ucdb in $(ERROR_UCDBS); do test -s "$$ucdb" || { echo "Missing ERROR UCDB $$ucdb"; exit 1; }; done
	$(VCOVER) merge -out $(BUILD_DIR)/basic_merged.ucdb $(BASIC_UCDBS)
	$(VCOVER) merge -out $(BUILD_DIR)/edge_merged.ucdb $(EDGE_UCDBS)
	$(VCOVER) merge -out $(BUILD_DIR)/prof_merged.ucdb $(PROF_UCDBS)
	$(VCOVER) merge -out $(BUILD_DIR)/error_merged.ucdb $(ERROR_UCDBS)

coverage_report:
	$(VCOVER) report -summary $(BUILD_DIR)/merged.ucdb > $(COVERAGE_SUMMARY)
	$(VCOVER) report -details -codeAll $(BUILD_DIR)/merged.ucdb > $(COVERAGE_REPORT)
	@cat $(COVERAGE_SUMMARY)

regress: full_cases cross_validate merge_ucdb merge_bucket_ucdb coverage_report

clean:
	@echo "Manual cleanup required by project rule: no removal command is run by this Makefile."
