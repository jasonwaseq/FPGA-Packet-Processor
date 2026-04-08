# UART Network Stack / Packet Processor

UART-hosted packet processor for the iCEBreaker FPGA board. The design turns a single UART link into a framed packet transport, parses a compact IPv4/UDP-inspired packet format in hardware, classifies packets against programmable rules, optionally rewrites header fields, maintains counters, and returns metadata or transformed packets back to a Python host.

## Why This Project

This project is meant to feel like a miniature hardware networking datapath rather than a toy loopback:

- Framed transport over UART with escaping and CRC16
- Fixed-format packet parsing with structural checks and header checksum validation
- Configurable rule table with masked address matching and first-match priority
- Actions for `DROP`, `ACCEPT`, `COUNT_ONLY`, and `REWRITE`
- Per-packet metadata responses plus optional transformed packet replay
- Saturating counters and host-side control/traffic tooling

## Repository Layout

- `rtl/`: synthesizable SystemVerilog modules
- `tb/`: cocotb tests, helpers, and thin DUT wrappers
- `host/`: Python 3 transport/client/CLI tooling
- `docs/`: protocol notes and implementation details

## Core RTL Modules

- `uart_rx.sv`, `uart_tx.sv`: parameterized 8N1 UART PHY
- `uart_frame_decoder.sv`, `uart_frame_encoder.sv`: framed UART transport with escaping and CRC16
- `frame_dispatch.sv`: routes validated transport frames to control or datapath ingress
- `packet_ingress_adapter.sv`: one-packet buffer with re-readable stream output
- `packet_header_parser.sv`: 20-byte header decode and validation
- `rule_table.sv`, `classifier_engine.sv`: programmable rule storage and first-match classifier
- `action_engine.sv`: result generation and packet rewrite/forward logic
- `statistics_block.sv`: fixed counter bank
- `control_plane.sv`: command decode, config writes, and readback responses
- `response_formatter.sv`: buffers outgoing frames for the UART encoder
- `packet_processor_top.sv`: top-level integration

## Protocol Summary

On-wire transport frame:

```text
0x7E | ver | msg_type | flags | seq | len_hi | len_lo | payload | crc_hi | crc_lo | 0x7E
```

- Escaping: `0x7E -> 0x7D 0x5E`, `0x7D -> 0x7D 0x5D`
- CRC: CCITT-16 over `ver..payload`
- Max transport payload: `252` bytes

Internal packet header:

```text
Byte  0 : version[7:4]=1, hdr_len_words[3:0]=5
Byte  1 : protocol
Byte  2 : flags
Byte  3 : ttl
Byte 4-5: total_length
Byte 6-7: payload_length
Byte 8-9: src_addr
Byte10-11: dst_addr
Byte12-13: src_port
Byte14-15: dst_port
Byte16-17: packet_id
Byte18-19: hdr_checksum
```

Full protocol details are in [docs/protocol.md](docs/protocol.md).

## Host Tooling

The Python package in `host/` provides:

- `TransportFrame` encode/decode
- `Packet` encode/decode with checksum handling
- `Rule` encode/decode for the 24-byte rule image
- `PacketProcessorClient` high-level command API
- CLI entry points:
  - `python3 -m host.ppctl --port COMx ping`
  - `python3 -m host.ppctl --port COMx info`
  - `python3 -m host.ppsend --port COMx --src-addr 0x1001 --dst-addr 0x2001 --src-port 0x1234 --dst-port 0x2222 --payload-hex deadbeef`
  - `python3 -m host.ppbench --port COMx --count 100 --payload-bytes 64`
  - `python3 -m host.ppdump --port COMx`

## Verification

Included assets:

- `tb/test_uart_loopback.py`
- `tb/test_frame_codec.py`
- `tb/test_packet_parser.py`
- `tb/test_classifier_engine.py`
- `tb/run.py`
- `host/test_protocol.py`

Install Python dependencies:

```bash
make venv
```

On WSL, install all system prerequisites (simulator + FPGA toolchain) and Python dependencies in one step:

```bash
make setup_wsl
```

The Makefile auto-uses `.venv/bin/python` when present, so activating the virtualenv is optional.

Protocol-only unit tests:

```bash
make test_python
```

Run the cocotb suite:

```bash
make test_cocotb
```

`tb/run.py` supports both newer cocotb Python runners and older makefile-based cocotb installs. By default it uses the Python runner path (`COCOTB_LAUNCHER=auto`), which is the most reliable choice in WSL virtualenv setups. Set `COCOTB_LAUNCHER=legacy` only if you specifically need `cocotb-config`/`Makefile.sim`.

The default simulator is Icarus Verilog for all benches, which is the most broadly compatible setup in WSL. If you specifically want another simulator, pass it explicitly (for example `SIM=verilator`).

Or run a single cocotb test target:

```bash
make test_cocotb TEST=packet_parser
```

## Synthesis and Flashing (iCEBreaker)

Toolchain prerequisites:

- `yosys`
- `nextpnr-ice40`
- `icepack`
- `iceprog`

Default FPGA build constraints live in `constraints/icebreaker.pcf` and map:

- `clk_i` to the onboard 12 MHz clock
- `rst_n_i` to the onboard active-low user button
- `uart_rx_i` / `uart_tx_o` to the onboard FTDI UART bridge

Recommended bring-up flow (fits iCEBreaker UP5K):

```bash
# Build a fast UART electrical loopback bitstream (top: icebreaker_bringup_top)
make bitstream_bringup

# Load SRAM immediately (volatile; lost on power cycle)
make load_bringup
```

To write non-volatile SPI flash instead:

```bash
make flash_bringup
```

`make program_bringup` is an alias for `make flash_bringup`.
After `flash_bringup`, power-cycle or reset the board to reload the new image.

Full packet processor build:

```bash
make bitstream TOP=packet_processor_top
```

The current `packet_processor_top` implementation is substantially larger than UP5K capacity and may take a long time to synthesize before failing place-and-route. In a recent run it reached about `43404/5280` LCs (`822%`), so use the bring-up top for toolchain/programming validation first.

For iCEBreaker UP5K packet-protocol hardware validation, use the reduced image top:

```bash
make bitstream_packet_up5k
make flash_packet_up5k
make validate_project_hw PORT=auto BAUD=115200
```

This builds `packet_processor_up5k_top` (UP5K-lt profile), a deliberately reduced packet datapath that fits iCEBreaker UP5K (`~3118/5280` LCs in recent build). The UP5K-lt image supports framed `DATA_PACKET` -> `PKT_RESULT` validation and fixed rule behavior, not the full dynamic control-plane feature set.

Generated artifacts are placed in `build/ice40/` and are named after the selected `TOP` module.

Hardware validation after flashing:

```bash
# Discover serial device names first
make validate_list_ports

# Auto-detects bring-up echo vs packet-processor protocol behavior
make validate_hw PORT=auto VALIDATE_MODE=auto

# Makefile wrappers
make validate_list_ports
make validate_fpga
make validate_project_hw
make validate_bringup
make validate_bringup_scan
make validate_packet
make validate_tx_test
```

One-command end-to-end hardware health check (program + validate):

```bash
make validate_fpga
```

This runs a full staged flow in WSL:
- flashes the bring-up image
- validates UART echo on the detected serial port
- flashes TX test and checks for a `0x55` RX pattern (with automatic alternate-pin retry)
- attempts packet-protocol validation as an informational check

Use strict mode if you want the command to fail unless TX-pattern and packet-protocol checks also pass:

```bash
make validate_fpga_strict
```

Full packet-processor datapath validation (hardware):

```bash
make validate_project_hw PORT=auto
```

`validate_project_hw` (UP5K-lt aligned) exercises:
- parser + checksum path (`PKT_RESULT` fields and flags)
- fixed classification actions (`DROP`, `COUNT_ONLY`, default `ACCEPT`)
- fixed rewrite action metadata (`dst_addr`/`dst_port` rewrite fields in `PKT_RESULT`)
- transport framing/sequence correctness (`DATA_PACKET` request -> matching `PKT_RESULT` response)

`validate_bringup`, `validate_bringup_scan`, and `validate_tx_test` now program the matching bitstream before validating, so they are reproducible from a fresh board state in WSL.
`validate_tx_test` automatically retries with the alternate swapped UART pin mapping if pattern validation fails on the default mapping.
If no RX pattern is observed on either mapping, `validate_tx_test` falls back to `validate_bringup_scan` so the end-to-end validation script still confirms board/serial functionality.
`validate_packet` uses `auto` mode by default because `packet_processor_top` currently exceeds UP5K capacity; use `make validate_packet_strict` when testing a packet-capable image on compatible hardware.

Recommended hardware bring-up sequence:

```bash
# 1) Prove FPGA TX is alive using a dedicated UART TX pattern bitstream
make bitstream_tx_test
make load_tx_test
make validate_tx_test PORT=/dev/ttyUSB0

# 2) Validate RX->TX loopback with the normal bring-up top
make bitstream_bringup
make load_bringup
make validate_bringup PORT=/dev/ttyUSB0
```

`validate_tx_test` expects a continuous `0x55` stream from FPGA TX. If this fails with zero received bytes, focus on configuration state (`cdone`) and UART pin mapping before debugging the echo design.

If TX pattern validation fails, try the alternate swapped UART pin mapping:

```bash
make bitstream_tx_test_alt
make load_tx_test_alt
make validate_tx_test PORT=/dev/ttyUSB0
```

If echo validation still returns zero bytes, try the alternate swapped UART pin mapping:

```bash
make bitstream_bringup_alt
make load_bringup_alt
make validate_bringup PORT=/dev/ttyUSB0
```

If `make load_bringup` reports `cdone: low`, use:

```bash
make flash_bringup
# then press reset (or power-cycle), then:
make validate_bringup PORT=/dev/ttyUSB0
```

If `/dev/ttyUSB0` is missing in WSL, try the detected `/dev/ttyACM*` or `/dev/ttyS*` device instead, or use `--port auto`.

Run a quick environment/tool check before tests or bitstream builds:

```bash
make doctor
```

Useful validation knobs:

- `BAUD` (default `1500000`)
- `BRINGUP_BAUD` (default `115200`, used by `make validate_bringup`)
- `VALIDATE_ROUNDS` (default `32`)
- `VALIDATE_PAYLOAD_BYTES` (default `64`)
- `VALIDATE_TIMEOUT` (default `0.5`)
- `VALIDATE_PATTERN_BYTE` (default `0x55`, used by `rx-pattern` mode)
- `VALIDATE_MIN_BYTES` (default `128`, used by `rx-pattern` mode)
- `VALIDATE_SCAN_SECONDS` (default `1.0`, used by `rx-pattern` mode)

If you need a custom pinout file, override `PCF`:

```bash
make bitstream PCF=constraints/my_board.pcf
```

## Current Status

This repo includes the full greenfield architecture, RTL module set, host tooling, directed benches, and a baseline iCEBreaker synthesis/programming flow for bring-up. It should still be treated as an implementation baseline: broader board support and extended randomized simulation are natural next steps.
