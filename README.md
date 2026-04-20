# AXI Stream Packetizer (VITA-Style)

A parameterizable Verilog packetizer that converts a continuous input stream into framed packets with metadata, timestamps, and AXI-Stream compliant output.

This project was developed as part of a software-defined radio (SDR) data pipeline for high-throughput IQ data streaming.

---

## Overview

The packetizer formats incoming samples into structured packets consisting of:

* Header (metadata + timestamps)
* Payload (stream samples)
* AXI-Stream interface with `tvalid`, `tready`, and `tlast`

Each packet includes:

* Packet length
* Stream / channel identifiers
* Sequence counter
* Timestamp (seconds + fractional)

---

## Features

* Parameterizable data width and packet size
* AXI-Stream compliant output interface
* AXI-Lite configurable control and metadata
* Sequence tracking and packet counting
* High-resolution timestamp generation
* Continuous streaming support

---

## Architecture

```
Input Stream → Packetizer → AXI Stream Output
                    ↑
             AXI-Lite Config
                    ↑
          Timestamp Generator
```

---

## Modules

### `packetizer_single.v`

Core FSM that builds packets:

* Header generation
* Payload streaming
* Sequence tracking
* Packet framing

---

### `timestamp_generator.v`

Generates timestamps based on:

* Sample rate increment
* Optional PPS synchronization

---

### `packetizer_axi_lite_top.v`

Top-level wrapper:

* AXI-Lite configuration interface
* Connects packetizer + timestamp generator
* Exposes AXI-Stream output

---

## Configuration (AXI-Lite)

| Address | Description                      |
| ------- | -------------------------------- |
| 0x00    | Control (enable, reset counters) |
| 0x04    | Stream / Channel configuration   |
| 0x08    | Status                           |

---

## Simulation

Testbench:

```
tb/tb_packetizer_axi_lite_top.v
```

Run simulation to observe:

* Packet framing
* Header fields
* Sequence increments
* Timestamp progression

---

## Example Output

```
word=0  data=01000016 last=0
word=1  data=00000102 last=0
word=2  data=00000000 last=0
...
word=21 data=0000000f last=1
---- end of packet ----
```

* 6 header words
* 16 payload words
* `tlast` asserted on final word

---

## Parameters

| Parameter          | Description             |
| ------------------ | ----------------------- |
| DATA_WIDTH         | Input/output data width |
| SAMPLES_PER_PACKET | Payload size            |
| FRAC_INCREMENT     | Timestamp increment     |

---

## Applications

* Software-defined radio (SDR)
* High-throughput data streaming
* FPGA-based packetization pipelines
* Real-time signal processing systems

---

## Notes

* Designed for integration with DMA → DDR → Linux pipelines
* Tested using simulation-only environment
* Fully decoupled from SDR-specific hardware for reuse

---

## Author

Zachary Conlan
Electrical & Computer Engineering — UT Austin
