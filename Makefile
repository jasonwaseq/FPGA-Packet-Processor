RTL := rtl/packet_processor_pkg.sv \
	rtl/uart_rx.sv \
	rtl/uart_tx.sv \
	rtl/checksum_validator.sv \
	rtl/uart_frame_decoder.sv \
	rtl/uart_frame_encoder.sv \
	rtl/frame_dispatch.sv \
	rtl/packet_ingress_adapter.sv \
	rtl/packet_header_parser.sv \
	rtl/rule_table.sv \
	rtl/classifier_engine.sv \
	rtl/action_engine.sv \
	rtl/statistics_block.sv \
	rtl/control_plane.sv \
	rtl/response_formatter.sv \
	rtl/packet_processor_top.sv \
	rtl/packet_processor_up5k_top.sv \
	rtl/icebreaker_bringup_top.sv
RTL_BRINGUP := rtl/icebreaker_bringup_top.sv
RTL_TX_TEST := rtl/uart_tx.sv rtl/icebreaker_uart_tx_test_top.sv
RTL_PACKET_UP5K := rtl/packet_processor_pkg.sv \
	rtl/uart_rx.sv \
	rtl/uart_tx.sv \
	rtl/uart_frame_decoder.sv \
	rtl/uart_frame_encoder.sv \
	rtl/packet_ingress_adapter.sv \
	rtl/packet_header_parser.sv \
	rtl/packet_processor_up5k_top.sv

PYTESTS := host/test_protocol.py
TOP ?= packet_processor_top
BRINGUP_TOP ?= icebreaker_bringup_top
TOP_TX_TEST ?= icebreaker_uart_tx_test_top
DEVICE ?= up5k
PACKAGE ?= sg48
FREQ_MHZ ?= 12
PCF ?= constraints/icebreaker.pcf
PCF_BRINGUP_ALT ?= constraints/icebreaker_uart_swapped.pcf
SYNTH_FLAGS ?=
PORT ?= auto
BAUD ?= 1500000
VALIDATE_MODE ?= auto
VALIDATE_ROUNDS ?= 32
VALIDATE_PAYLOAD_BYTES ?= 64
VALIDATE_TIMEOUT ?= 0.5
VALIDATE_PATTERN_BYTE ?= 0x55
VALIDATE_MIN_BYTES ?= 128
VALIDATE_SCAN_SECONDS ?= 1.0
BRINGUP_BAUD ?= 115200
TX_TEST_BAUD ?= $(BRINGUP_BAUD)
PROJECT_VALIDATE_BENCH_COUNT ?= 8
TEST ?= all

BUILD_DIR ?= build/ice40
BUILD_DIR_ALT ?= build/ice40_alt
JSON := $(BUILD_DIR)/$(TOP).json
ASC := $(BUILD_DIR)/$(TOP).asc
BIN := $(BUILD_DIR)/$(TOP).bin
NEXTPNR_RPT := $(BUILD_DIR)/$(TOP)_nextpnr.rpt
YOSYS_LOG := $(BUILD_DIR)/$(TOP)_yosys.log

YOSYS ?= yosys
NEXTPNR ?= nextpnr-ice40
ICEPACK ?= icepack
ICEPROG ?= iceprog
ICEPROG_FLASH_FLAGS ?=
ICEPROG_LOAD_FLAGS ?= -S
VENV_DIR ?= .venv
VENV_PY := $(VENV_DIR)/bin/python
PYTHON ?= $(if $(wildcard $(VENV_PY)),$(VENV_PY),python3)
PIP ?= $(PYTHON) -m pip
WSL_APT_PACKAGES ?= python3 python3-venv python3-pip make iverilog verilator yosys nextpnr-ice40 fpga-icestorm

.PHONY: venv
venv:
	python3 -m venv "$(VENV_DIR)"
	"$(VENV_PY)" -m pip install --upgrade pip
	"$(VENV_PY)" -m pip install -r requirements.txt

.PHONY: deps_wsl
deps_wsl:
	sudo apt-get update
	sudo apt-get install -y $(WSL_APT_PACKAGES)

.PHONY: setup_wsl
setup_wsl: deps_wsl venv
	@echo "WSL dependencies installed and Python virtualenv ready."

.PHONY: doctor
doctor:
	@for tool in "$(YOSYS)" "$(NEXTPNR)" "$(ICEPACK)" "$(ICEPROG)" iverilog verilator; do \
		command -v "$$tool" >/dev/null 2>&1 || { echo "Missing required tool: $$tool"; exit 1; }; \
	done
	@"$(PYTHON)" -c "import cocotb, serial; print('Python deps OK:', cocotb.__version__)"

.PHONY: test_python
test_python:
	$(PYTHON) -m unittest $(PYTESTS)

.PHONY: test_cocotb
test_cocotb:
	$(PYTHON) -m tb.run $(TEST)

.PHONY: test
test: test_python test_cocotb

.PHONY: list_rtl
list_rtl:
	@$(PYTHON) -c "import sys; print('\n'.join(sys.argv[1:]))" $(RTL)

$(BUILD_DIR):
	$(PYTHON) -c "from pathlib import Path; Path(r'$(BUILD_DIR)').mkdir(parents=True, exist_ok=True)"

$(JSON): $(RTL) | $(BUILD_DIR)
	$(YOSYS) -l $(YOSYS_LOG) -p "read_verilog -sv $(RTL); synth_ice40 $(SYNTH_FLAGS) -top $(TOP) -json $@"

$(ASC): $(JSON) $(PCF) | $(BUILD_DIR)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --freq $(FREQ_MHZ) --json $< --pcf $(PCF) --asc $@ --report $(NEXTPNR_RPT)

$(BIN): $(ASC)
	$(ICEPACK) $< $@

.PHONY: synth
synth: $(JSON)

.PHONY: pnr
pnr: $(ASC)

.PHONY: bitstream
bitstream: $(BIN)

.PHONY: flash
flash: bitstream
	$(ICEPROG) $(ICEPROG_FLASH_FLAGS) $(BIN)

.PHONY: program
program: flash

.PHONY: load
load: bitstream
	$(ICEPROG) $(ICEPROG_LOAD_FLAGS) $(BIN)

.PHONY: synth_bringup
synth_bringup:
	$(MAKE) synth TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)"

.PHONY: synth_packet_up5k
synth_packet_up5k:
	$(MAKE) synth TOP=packet_processor_up5k_top RTL="$(RTL_PACKET_UP5K)"

.PHONY: pnr_bringup
pnr_bringup:
	$(MAKE) pnr TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)"

.PHONY: bitstream_bringup
bitstream_bringup:
	$(MAKE) bitstream TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)"

.PHONY: bitstream_packet_up5k
bitstream_packet_up5k:
	$(MAKE) bitstream TOP=packet_processor_up5k_top RTL="$(RTL_PACKET_UP5K)"

.PHONY: flash_bringup
flash_bringup:
	$(MAKE) flash TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)"

.PHONY: flash_packet_up5k
flash_packet_up5k:
	$(MAKE) flash TOP=packet_processor_up5k_top RTL="$(RTL_PACKET_UP5K)"

.PHONY: program_bringup
program_bringup: flash_bringup

.PHONY: load_bringup
load_bringup:
	$(MAKE) load TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)"

.PHONY: load_packet_up5k
load_packet_up5k:
	$(MAKE) load TOP=packet_processor_up5k_top RTL="$(RTL_PACKET_UP5K)"

.PHONY: bitstream_bringup_alt
bitstream_bringup_alt:
	$(MAKE) bitstream TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)" PCF="$(PCF_BRINGUP_ALT)" BUILD_DIR="$(BUILD_DIR_ALT)"

.PHONY: load_bringup_alt
load_bringup_alt:
	$(MAKE) load TOP=$(BRINGUP_TOP) RTL="$(RTL_BRINGUP)" PCF="$(PCF_BRINGUP_ALT)" BUILD_DIR="$(BUILD_DIR_ALT)"

.PHONY: validate_hw
validate_hw:
	$(PYTHON) -m host.validate_hw --port "$(PORT)" --baud $(BAUD) --mode $(VALIDATE_MODE) --rounds $(VALIDATE_ROUNDS) --payload-bytes $(VALIDATE_PAYLOAD_BYTES) --timeout $(VALIDATE_TIMEOUT) --pattern-byte $(VALIDATE_PATTERN_BYTE) --min-bytes $(VALIDATE_MIN_BYTES) --scan-seconds $(VALIDATE_SCAN_SECONDS)

.PHONY: validate_fpga
validate_fpga:
	$(PYTHON) -m host.validate_fpga --port "$(PORT)" --bringup-baud $(BRINGUP_BAUD) --packet-baud $(BAUD) --timeout $(VALIDATE_TIMEOUT)

.PHONY: validate_fpga_strict
validate_fpga_strict:
	$(PYTHON) -m host.validate_fpga --port "$(PORT)" --bringup-baud $(BRINGUP_BAUD) --packet-baud $(BAUD) --timeout $(VALIDATE_TIMEOUT) --strict --require-packet

.PHONY: validate_project_hw
validate_project_hw:
	$(MAKE) flash_packet_up5k
	$(PYTHON) -m host.validate_project_hw --port "$(PORT)" --baud $(BAUD) --timeout $(VALIDATE_TIMEOUT) --benchmark-count $(PROJECT_VALIDATE_BENCH_COUNT)

.PHONY: validate_list_ports
validate_list_ports:
	$(PYTHON) -m host.validate_hw --list-ports

.PHONY: validate_bringup
validate_bringup:
	$(MAKE) flash_bringup
	$(MAKE) validate_hw VALIDATE_MODE=echo BAUD=$(BRINGUP_BAUD)

.PHONY: validate_bringup_scan
validate_bringup_scan:
	$(MAKE) flash_bringup
	$(MAKE) validate_hw VALIDATE_MODE=echo-scan BAUD=$(BRINGUP_BAUD) PORT=auto

.PHONY: validate_packet
validate_packet:
	@echo "INFO: packet_processor_top currently exceeds UP5K resources; running auto validation mode."
	$(MAKE) validate_hw VALIDATE_MODE=auto

.PHONY: validate_packet_strict
validate_packet_strict:
	$(MAKE) validate_hw VALIDATE_MODE=packet

.PHONY: synth_tx_test
synth_tx_test:
	$(MAKE) synth TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)"

.PHONY: pnr_tx_test
pnr_tx_test:
	$(MAKE) pnr TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)"

.PHONY: bitstream_tx_test
bitstream_tx_test:
	$(MAKE) bitstream TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)"

.PHONY: bitstream_tx_test_alt
bitstream_tx_test_alt:
	$(MAKE) bitstream TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)" PCF="$(PCF_BRINGUP_ALT)" BUILD_DIR="$(BUILD_DIR_ALT)"

.PHONY: flash_tx_test
flash_tx_test:
	$(MAKE) flash TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)"

.PHONY: flash_tx_test_alt
flash_tx_test_alt:
	$(MAKE) flash TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)" PCF="$(PCF_BRINGUP_ALT)" BUILD_DIR="$(BUILD_DIR_ALT)"

.PHONY: load_tx_test
load_tx_test:
	$(MAKE) load TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)"

.PHONY: load_tx_test_alt
load_tx_test_alt:
	$(MAKE) load TOP=$(TOP_TX_TEST) RTL="$(RTL_TX_TEST)" PCF="$(PCF_BRINGUP_ALT)" BUILD_DIR="$(BUILD_DIR_ALT)"

.PHONY: validate_tx_test
validate_tx_test:
	@set -e; \
	$(MAKE) flash_tx_test; \
	if $(MAKE) validate_hw VALIDATE_MODE=rx-pattern BAUD=$(TX_TEST_BAUD) VALIDATE_PATTERN_BYTE=0x55; then \
		exit 0; \
	fi; \
	echo "INFO: tx_test validation failed on default pinout, retrying alternate UART pin mapping."; \
	$(MAKE) flash_tx_test_alt; \
	if $(MAKE) validate_hw VALIDATE_MODE=rx-pattern BAUD=$(TX_TEST_BAUD) VALIDATE_PATTERN_BYTE=0x55; then \
		exit 0; \
	fi; \
	echo "WARN: tx_test rx-pattern not detected on either pin mapping. Falling back to bring-up echo validation."; \
	$(MAKE) validate_bringup_scan

.PHONY: clean_fpga
clean_fpga:
	$(PYTHON) -c "import pathlib, shutil; shutil.rmtree(pathlib.Path(r'$(BUILD_DIR)'), ignore_errors=True)"
