# Custom SPI and AXI4-Stream RTL

## Modules

Sources are in `sd_fpga_controller.srcs/sources_1/new/`.

| Module | Purpose |
| --- | --- |
| `spi_master.vhd` | System-clocked, full-duplex SPI master with a programmable integer clock divider. |
| `spi_slave.vhd` | Native-SCLK full-duplex slave, supporting continuous words under one chip select. |
| `spi_async_fifo.vhd` | Dual-clock, first-word-fall-through FIFO with synchronized Gray pointers. |
| `spi_to_axis.vhd` | SPI slave plus independent RX/TX FIFOs and two 8-bit AXI4-Stream interfaces. |
| `spi_slave_to_axis.vhd` | Explicitly named slave bridge; wraps the compatible `spi_to_axis` implementation. |
| `spi_master_to_axis.vhd` | AXI4-Stream-controlled SPI master with lossless RX backpressure. |
| `axis_byte_packetizer.vhd` | Packs byte streams into 32-bit, fixed-length AXI packets with TLAST. |
| `spi_master_to_axis_fifo.vhd` | Compatible SPI master wrapper with 32-bit RX packets for AXI FIFO MM S. |
| `ad9284_lvds_rx.vhd` | Artix-7 differential DDR receiver and phase-shifted DCO clock. |
| `ad9284_capture.vhd` | Triggered dual-clock RAM capture and 32-bit packet drain. |
| `ad9284_to_axis.vhd` | Physical AD9284 receiver plus 1024-pair triggered acquisition. |

For ADC pin-to-port mapping, trigger controls, packet format, FIFO sizing,
and physical timing requirements, see [AD9284 acquisition](./AD9284.md).
The new SPI FIFO wrapper uses the same 32-bit DATA/VALID/READY/LAST output
as the ADC unit while preserving the original byte-wide SPI modules.

The default word size is **8 bits, MSB first**, with a **100 MHz AXI/system
clock**. Master/slave word lengths are generic (at least two bits); the original
bridges transfer bytes and the FIFO wrapper packs received bytes into words.
Choose **one** SPI bridge for the FPGA's role.
The slave bridge terminates an **external SPI master**:

```text
                              +-- RX asynchronous FIFO --> M_AXIS (received bytes)
External SPI master <--> slave
                              +-- TX asynchronous FIFO <-- S_AXIS (bytes to transmit)
```

This is **AXI4-Stream**, not an AXI4-Lite register interface or an AXI
memory-mapped transaction generator.

## Choosing and wiring a bridge

No extra `spi_master`, `spi_slave`, or `spi_async_fifo` blocks are needed beside
either bridge: each instantiates its required components internally.

| Bridge pin | `spi_master_to_axis` | `spi_slave_to_axis` |
| --- | --- | --- |
| `spi_sclk` | Output to external slave SCLK | Input from external master SCLK |
| `spi_ss_n` | Output to external slave CS | Input from external master CS |
| `spi_mosi` | Output to external slave MOSI | Input from external master MOSI |
| `spi_miso` | Input from external slave MISO | Output to external master MISO |
| `aclk` | 100 MHz system clock | 100 MHz system clock |
| `aresetn` | Active-low system reset | Active-low system reset |
| `s_axis_tdata[7:0]` | Byte to transmit on MOSI | Byte to return on MISO |
| `s_axis_tvalid` | Input from TX producer | Input from TX producer |
| `s_axis_tready` | Output to TX producer | Output to TX producer |
| `m_axis_tdata[7:0]` | Byte received on MISO | Byte received on MOSI |
| `m_axis_tvalid` | Output to RX consumer | Output to RX consumer |
| `m_axis_tready` | Input from RX consumer | Input from RX consumer |

Connect board ground to the external device ground. Use compatible I/O voltage
and assign the physical SPI pins in board-specific constraints.

### Master bridge behavior

`spi_master_to_axis` accepts one TX byte when `s_axis_tvalid` and
`s_axis_tready` are high on a rising `aclk` edge. That handshake automatically
starts one eight-bit SPI transaction. It returns exactly one received byte on
`m_axis`, with chip select released between bytes. For receive-only traffic,
send dummy TX bytes (for example `0x00`) to generate clocks.

There is one reserved RX result slot and one transaction at a time. When the RX
consumer stalls, the result is held stable and no further transaction starts
until storage is available. This prevents RX overflow without error flags.
TX producers must honor `s_axis_tready`; no TX valid means no SPI clocks.
Reset aborts the transaction and discards any pending result; downstream logic
must treat reset as cancelling outstanding requests.

The bridge uses static `cpol`/`cpha` generics and a positive `clk_divider`.
At 100 MHz with divider 1, SCLK is 50 MHz and transactions start every 19
system cycles under continuous AXI traffic: approximately **42.1 Mbit/s**
payload in each direction, including the gaps.
The master bridge does not need idle-clock priming when talking to a normal
external slave. It does not generate the special deselected clocks required by
our asynchronous-FIFO slave bridge, so these two bridges should not be directly
paired for a full-duplex loopback without additional priming support.

Multi-byte commands requiring chip select held low across bytes are not
supported by the master bridge; they need a framing/continuous-CS extension.
There is no `TLAST` port to express such commands.

## SPI modes

Both ends must select the same mode. The slave/bridge use elaboration-time
`cpol` and `cpha` generics, defaulting to mode 0. The master has `cpol`/`cpha`
input ports; set them at least one idle system-clock cycle before `enable` and
keep them stable while busy.

| Mode | CPOL | CPHA | Idle SCLK | Sample edge | Change data edge |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | Low | Rising | Falling |
| 1 | 0 | 1 | Low | Falling | Rising |
| 2 | 1 | 0 | High | Falling | Rising |
| 3 | 1 | 1 | High | Rising | Falling |

For CPHA=0, the first data bit is present before the first clock edge.
Slave MISO is high impedance while deselected or reset; place the slave/bridge
at the FPGA I/O boundary, or use an explicit output-enable buffer in a wrapper.
Do not use internal FPGA tristates to multiplex multiple slaves.

### Master control

`enable` is sampled on a rising `clk` edge while idle. `tx` is latched then,
`busy` goes high, and `ss_n` goes low. Requests while busy are ignored.
`rx` updates and `done` pulses for one system-clock cycle on completion.
A continuously asserted `enable` starts another word when the master returns
to idle; chip select is deasserted between words. Reset aborts the current word.
The original master's principal port names are retained, but it now runs on
rising system-clock edges and adds `done` and `clk_divider`. The original
slave interface is replaced by the streaming-word interface below.

### Slave word interface

`word_clk` is SCLK or its static inversion, with rising edges corresponding
to SPI sample edges. It is **not** a divided byte clock.

* On the final sample edge of a word, `rx_valid` qualifies `rx_data`.
  The bridge's RX FIFO captures that byte on that same edge.
* `tx_data`/`tx_valid` are a first-word-fall-through FIFO head. A byte is
  selected at the start of a word. `tx_ready` consumes it on the final
  sample edge. Keep the FIFO head stable until consumed.
* The phase-0 first bit must already be valid before its first sample edge.
  As with other source-synchronous inputs, meet setup/hold at that edge.
* Raising chip select discards a partial RX word and does not consume its
  TX word. Complete preceding words remain queued.
* `rx_valid`/`tx_ready` are sample-clock strobes, not system-clock pulses.
  Do not connect them directly to logic in the 100 MHz domain.

### Slave bridge reset and idle-clock requirement

`aresetn`/`reset_n` is active low and asynchronously asserted. Reset flushes both
FIFOs and clears the sticky error flags. Keep chip select high during reset.
After releasing reset, provide **at least five complete SCLK cycles with
chip select high**, then wait at least one half-period before selecting.
These cycles release the FIFO-local resets and synchronize the TX write pointer.
The master must be able to generate these deselected clocks; the standalone
`spi_master` does not provide an idle-clock command.

Also provide five deselected SCLK cycles after queuing a new TX burst if SCLK
was stopped. Without them, bytes queued in the AXI domain may not yet be
visible to the SPI domain, so the first word can underrun. The clocks do not
send or consume SPI words while chip select is high.
This requirement is intentional: it avoids unsafe clock-domain crossings when
SCLK is not free-running.

## AXI4-Stream contract

Both interfaces use `aclk` and `aresetn`.
The FIFO/error behavior below applies to the **slave** bridge; the master
bridge instead stops launching transactions under RX backpressure as above.

* `M_AXIS`: received SPI bytes, in wire order.
* `S_AXIS`: bytes to return on MISO, in enqueue order.
* A transfer occurs only on a rising `aclk` edge with `TVALID` and `TREADY`
  both high. The producer must hold data/valid steady during backpressure.
* Each beat contains one byte. There is no `TLAST`, `TKEEP`, command header,
  address, packet framing, or implied chip-select marker. Chip-select
  boundaries are not carried into AXI.
* `fifo_address_bits` defaults to 6: **64 bytes per direction**.
  Valid values are at least 2; depth is `2 ** fifo_address_bits`.
* RX overflow drops the **newest** byte; already queued bytes remain intact.
  `rx_overflow` becomes sticky high in the AXI clock domain.
* If TX is empty at the start of a word, MISO returns an entire zero byte and
  `tx_underrun` becomes sticky high. Data arriving later is used for a later
  word, never spliced into an in-progress byte.
* Both status flags are synchronized into `aclk` and clear only on reset.
  If SCLK stops, RX data already queued can still drain through AXI.

SPI has no ready signal: an AXI consumer must sustain the average SPI rate.
At 50 Mbit/s, 64 empty RX entries cover about **10.24 us** of stalled AXI
reception (less any existing occupancy and CDC latency). TX must likewise
remain supplied. Check both error flags; FIFO depth cannot prevent data loss
under indefinitely stalled traffic.

### Existing communications block design

The existing `communications.bd` is left unchanged. Its AXI FIFO MM S IP has
**32-bit** streaming data and packet/control semantics; it is **not directly
pin-compatible** with the original byte-stream bridges. Use
`spi_master_to_axis_fifo` for 32-bit packetized SPI reception, or add AXI4-Stream
width conversion in both directions and define packet boundaries/`TLAST`
and any required control-channel behavior. Alternatively use byte-wide AXI
stream FIFOs or custom byte-stream logic directly. There is no assumed
packet protocol in these modules.

## Throughput and timing

Master SCLK frequency is:

```text
SCLK = system_clock / (2 * clk_divider)
```

At 100 MHz and the default divider of 1, SCLK is **50 MHz**. Eight-bit master
words have an 18-system-cycle start-to-start interval when requested
immediately: **44.44 Mbit/s payload**, including inter-word gaps.
A divider of 2 would yield only 25 MHz, below the requested 32 Mbit/s.

The slave uses native SCLK rather than 100 MHz oversampling. Simulation verifies
continuous full duplex at **50 Mbit/s per direction** and **33.33 Mbit/s per
direction**, including FIFO wrapping and AXI stalls. Software delays, initial
priming, and gaps between bursts reduce whole-application throughput.

**50 MHz is a design target, not a hardware timing guarantee.** Before
programming the Basys 3 / Artix-7:

1. Assign board pins/IOSTANDARD and use a clock-capable input for external
   SCLK. There are deliberately no guessed pin assignments or external-device
   delays. Check the physical link's signal integrity at the selected rate.
2. Constrain `aclk` to 10 ns and external `spi_sclk` to 20 ns for 50 MHz.
   The static SCLK inversion must retain its derived clock relationship.
   For the master bridge, SCLK is an output derived from `aclk`: constrain it
   as a generated/forwarded clock with the selected divider, not an unrelated
   input clock. Apply the external slave's MISO input and MOSI/CS output delays.
3. Set MOSI, MISO, and chip-select input/output delays from the external
   device's datasheet, PCB delays, and the selected mode. Include both SCLK
   edges as appropriate. TX and RX contain half-cycle paths.
4. Apply Gray-bus CDC constraints to **both FIFOs**. Between `wr_gray` and
   `wr_gray_meta`, and between `rd_gray` and `rd_gray_meta`, bound datapath
   delay and bus skew to at most the faster clock period (10 ns here).
   Resolve synthesized register names and use `set_max_delay -datapath_only`
   and `set_bus_skew`. Preserve the supplied `ASYNC_REG` attributes.
   These FIFO CDC constraints apply only to the slave bridge; the master
   bridge's internal logic runs entirely on `aclk`.
5. Except/waive only the identified first-stage status synchronizers and
   intended asynchronous FIFO RAM crossings. Do not blanket-false-path
   the entire bridge or use clock-group exceptions that override the
   Gray-bus max-delay constraints. Review reset recovery/removal paths;
   chip select must remain high throughout reset/priming.
6. Run synthesis, implementation, `report_timing_summary`, and `report_cdc`.
   Confirm all relevant setup/hold and CDC requirements before claiming
   a hardware throughput guarantee.

## Vivado project

The project lists all RTL and both testbenches. Its design top is
`spi_to_axis`, and its simulation top is `tb_spi_to_axis` (mode 0 by default).
The old standalone master can still be selected as top.
Both explicitly named bridges are registered as design sources. The import
script adds the SPI and ADC testbenches and selects the slave bench by default.
For a master bridge simulation, select `tb_spi_master_to_axis` as simulation
top. In a block design use **Add Module** to add `spi_master_to_axis` or
`spi_slave_to_axis`, then connect the pins from the table above.
The existing generated module-reference metadata is not hand-edited; regenerate
module references in Vivado when reusing the changed entities.

If the project was already open, close/reopen it **without overwriting the
updated project from the stale session**, or source this script in Vivado to
import/update sources in the open project:

```tcl
source "/absolute/path/to/sd_fpga_controller/import_spi.tcl"
launch_simulation
run all
```

The testbenches use VHDL-2008. Testbench generic `mode` is 0..3;
`half_period_ns` is 10 for 50 MHz or 15 for 33.33 MHz. The master bench uses
`width` and `divider`. Simulation top selection does not connect the bridge
to the existing communications block design.

## Reproducible checks

From the project directory:

```sh
bash tests/run_ghdl.sh
```

The script builds in a temporary directory, runs 20 self-checking simulations,
then performs generic GHDL synthesis of the master and both bridges in all
four SPI modes.
Coverage includes all SPI modes, 8/16-bit master words, two clock dividers,
256-byte uninterrupted full-duplex streams, explicit >=32 Mbit/s throughput
assertions, AXI stability under backpressure, FIFO capacity/wraparound,
partial-word abort, overflow/underrun, and reset recovery.
The master bridge tests use an independent behavioral external slave with
distinct MOSI/MISO patterns, two clock dividers, long RX stalls, exact
transaction counts, idle-without-TX behavior, and mid-transfer reset.
GHDL warns that it does not interpret Vivado's `ASYNC_REG` placement attributes;
those attributes are retained for Vivado.

These checks were run with GHDL 5.0.1. Vivado implementation, FPGA pin
constraints, hardware timing closure, and physical-board tests have **not**
been run.
