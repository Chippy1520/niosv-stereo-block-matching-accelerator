---
aliases: [row_ram_bank]
tags: [rtl, frontend, memory, verification]
---
# Row RAM bank

**Up:** [[Circular Row Buffer]] → [[Stereo Frontend]] → [[Accelerator Architecture]]
**Source:** `rtl/row_ram_bank.sv` · **Standalone bench:** `tests/rtl/tb_row_ram_bank.sv`

This is the internal memory primitive for the **same row-storage block**, not another accelerator stage. One bank holds one row slot. The parent instantiates K banks, selects the slot to write, and ignores the written bank's read value.

## Interface and timing contract

- Parameters: `PIXEL_W=8`, `DEPTH=640`, `ADDR_W=max(1,clog2(DEPTH))`.
- Inputs: `clk`, one-bit `enable_i`, one-bit `write_i`, `address_i[ADDR_W-1:0]`, `pixel_i[PIXEL_W-1:0]`.
- Output: `pixel_o[PIXEL_W-1:0]`. There is no ready/valid, reset, or status port here.
- Disabled edge: memory and output hold. Inputs changing between edges do not change the output.
- Enabled non-write edge: the word at `address_i` appears after that rising edge. The address must be in `[0,DEPTH-1]`; read only words that have already been written.
- Enabled write edge: store `pixel_i`. **The simultaneous read value is unspecified**; do not depend on simulation's old-data value. The parent bypasses the newest pixel and never selects this bank for an older tap on that edge.
- No memory reset. The parent masks stale contents until enough new rows have arrived.

## Complete source

The first SystemVerilog block is an exact copy of the source, checked automatically.

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Internal row-store bank. Read output updates after an enabled rising edge.
// No reset: the parent owns warmup and masks unread/unwritten image history.
// On a write edge pixel_o is unspecified; the parent uses a newest-pixel bypass.
module row_ram_bank #(
    parameter integer PIXEL_W = 8,
    parameter integer DEPTH = 640,
    parameter integer ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  wire                  clk,
    input  wire                  enable_i,
    input  wire                  write_i,
    input  wire [ADDR_W-1:0]     address_i,
    input  wire [PIXEL_W-1:0]    pixel_i,
    output logic [PIXEL_W-1:0]   pixel_o
);
    (* ramstyle = "M9K, no_rw_check" *) logic [PIXEL_W-1:0] memory [0:DEPTH-1];
    always_ff @(posedge clk) begin
        if (enable_i) begin
            if (write_i) memory[address_i] <= pixel_i;
            pixel_o <= memory[address_i];
        end
    end

    // synthesis translate_off
    initial begin
        if (PIXEL_W < 1 || DEPTH < 1 || ADDR_W < ((DEPTH <= 1) ? 1 : $clog2(DEPTH)))
            $fatal(1, "Positive dimensions and a sufficient address width are required");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Read the code beside its explanation

| RTL line/code | Explanation |
|---|---|
| 1–2: `` `timescale`` / `` `default_nettype none`` | Define simulation units and reject accidental implicit wires. |
| 4–6: contract comments | State clocked output, parent-owned initialization and unspecified write-edge output before any implementation. |
| 7–10: `PIXEL_W`, `DEPTH`, `ADDR_W` | Width of one word, number of addresses and address-port width. Clamp depth-one addressing to one bit. |
| 11–18: input/output declarations | `enable_i` is a common read/write clock enable; `write_i` only requests a write when enabled. Data and address widths follow the parameters. |
| 19: `memory [0:DEPTH-1]` | An unpacked array of packed pixel words. `M9K` requests the intended device RAM type; `no_rw_check` permits unspecified same-address read/write behavior. Neither attribute alone is proof of inference. |
| 20: `always_ff @(posedge clk)` | State changes only on rising edges. |
| 21: `if (enable_i)` | Hold both memory and read output on bubbles. |
| 22: `if (write_i) memory[address_i] <= pixel_i;` | Write one addressed pixel with a nonblocking assignment; never clear the array in a reset loop. |
| 23: `pixel_o <= memory[address_i];` | The read result is clocked on the same enabled edge. On non-write edges it is the addressed stored pixel. On write edges the hardware contract deliberately does not choose old/new data. |
| 24–25: closing blocks | End common enable and clocked process. |
| 27–32: `translate_off`, `initial`, `$fatal` | Simulation-only parameter guards reject invalid dimensions and undersized addresses; this is not reset hardware. |
| 33–34: `endmodule`, `` `default_nettype wire`` | Close this module and restore the conventional net setting for following source files. |

## Why keep a separate bank module?

The local Quartus 22.1 experiments did not infer RAM for the tested memories declared inside the generated row-buffer implementation, even with synchronous reads and `ramstyle`. The same small template **inside a bank-module boundary** did infer it. Keep the measured working boundary rather than relying on a stylistic RAM hint. This is a result for this implementation/tool configuration, not a claim that all generated memories fail in Quartus.

The production K=11, width=640 parent maps to 11 M9K RAM nodes, 56,320 logical memory bits, 697 logic elements and 33 registers in Analysis & Synthesis. See `docs/verification/row-buffer-synthesis.md`; this does not prove fitted block count, timing closure or board behavior.

## Standalone checks

`python scripts/run_tests.py --suite row-bank` runs depth 1, 2, 3, 7, 16, 640 and 641 with representative 1-, 8- and 10-bit words. The bench initializes through public ports, checks forward/reverse readback, disabled writes, bubble holds, before/after-edge behavior and seeded random traffic. It intentionally does **not** require old data on a write edge. The targeted `bank_writes_on_read` mutation is rejected by this bench.

**Review checkpoint:** understand the RAM primitive first, then follow the parent's bank-selection tag and newest-pixel bypass in [[Circular Row Buffer]]. The controller is deferred until after datapath review.
