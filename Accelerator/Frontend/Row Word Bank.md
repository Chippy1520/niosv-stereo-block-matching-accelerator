# Row Word Bank

[[Stereo Frontend]] · [[Testbench Guide]] · [Datapath contract](../../docs/packed-frontend-contract.md)

## Exact RTL

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// One full word per write edge, independently addressed synchronous read.
// No RAM reset. Caller owns initialization, lifetime and collision avoidance.
module row_word_bank #(
    parameter integer WORD_W = 32,
    parameter integer DEPTH = 160,
    parameter integer ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  wire                  clk,
    input  wire                  write_i,
    input  wire [ADDR_W-1:0]     write_address_i,
    input  wire [WORD_W-1:0]     write_data_i,
    input  wire                  read_i,
    input  wire [ADDR_W-1:0]     read_address_i,
    output logic [WORD_W-1:0]   read_data_o
);
    (* ramstyle = "M9K, no_rw_check" *) logic [WORD_W-1:0] memory [0:DEPTH-1];
    always_ff @(posedge clk) begin
        if (write_i) memory[write_address_i] <= write_data_i;
    end
    always_ff @(posedge clk) begin
        if (read_i) read_data_o <= memory[read_address_i];
    end

    // synthesis translate_off
    initial begin
        if (WORD_W < 1 || DEPTH < 1 || ADDR_W < ((DEPTH <= 1) ? 1 : $clog2(DEPTH)))
            $fatal(1, "Positive dimensions and a sufficient address width are required");
    end
    always @(posedge clk) begin
        if ((write_i && write_address_i >= DEPTH) || (read_i && read_address_i >= DEPTH))
            $fatal(1, "WORD_RAM address outside bank");
        if (write_i && read_i && write_address_i == read_address_i)
            $fatal(1, "WORD_RAM same-word read/write is outside the contract");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Code-adjacent explanation

| Line | Code | Meaning |
|---|---|---|
| 1 | ``timescale 1ns/1ps` | Compilation directive; no storage or pipeline stage. |
| 2 | ``default_nettype none` | Compilation directive; no storage or pipeline stage. |
| 4 | `// One full word per write edge, independently addressed synchronous read.` | One full word per write edge, independently addressed synchronous read. |
| 5 | `// No RAM reset. Caller owns initialization, lifetime and collision avoidance.` | No RAM reset. Caller owns initialization, lifetime and collision avoidance. |
| 6 | `module row_word_bank #(` | Each bank has independent load and processing ports. |
| 7 | `parameter integer WORD_W = 32,` | One complete word: 32 bits at production settings. |
| 8 | `parameter integer DEPTH = 160,` | Number of words, not number of pixels. |
| 9 | `parameter integer ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)` | Number of words, not number of pixels. |
| 10 | `) (` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 11 | `input  wire                  clk,` | Single common clock, not a clock-domain crossing. |
| 12 | `input  wire                  write_i,` | Write enable; a disabled port preserves storage. |
| 13 | `input  wire [ADDR_W-1:0]     write_address_i,` | Word address width clamped for depth one. |
| 14 | `input  wire [WORD_W-1:0]     write_data_i,` | One complete word: 32 bits at production settings. |
| 15 | `input  wire                  read_i,` | Independent read enable; a disabled read holds its output. |
| 16 | `input  wire [ADDR_W-1:0]     read_address_i,` | Word address width clamped for depth one. |
| 17 | `output logic [WORD_W-1:0]   read_data_o` | One complete word: 32 bits at production settings. |
| 18 | `);` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 19 | `(* ramstyle = "M9K, no_rw_check" *) logic [WORD_W-1:0] memory [0:DEPTH-1];` | One complete word: 32 bits at production settings. |
| 20 | `always_ff @(posedge clk) begin` | Rising-edge sequential logic; no additional autonomous scheduling. |
| 21 | `if (write_i) memory[write_address_i] <= write_data_i;` | Independent destination word address. |
| 22 | `end` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 23 | `always_ff @(posedge clk) begin` | Rising-edge sequential logic; no additional autonomous scheduling. |
| 24 | `if (read_i) read_data_o <= memory[read_address_i];` | Independent processing word address. |
| 25 | `end` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 27 | `// synthesis translate_off` | synthesis translate_off |
| 28 | `initial begin` | Validate parameters in simulation; excluded from synthesis. |
| 29 | `if (WORD_W < 1 &#124;&#124; DEPTH < 1 &#124;&#124; ADDR_W < ((DEPTH <= 1) ? 1 : $clog2(DEPTH)))` | One complete word: 32 bits at production settings. |
| 30 | `$fatal(1, "Positive dimensions and a sufficient address width are required");` | Reject invalid dimensions, addresses or forbidden read/write collisions. |
| 31 | `end` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 32 | `always @(posedge clk) begin` | Simulation-only enabled-access contract checks. |
| 33 | `if ((write_i && write_address_i >= DEPTH) &#124;&#124; (read_i && read_address_i >= DEPTH))` | Number of words, not number of pixels. |
| 34 | `$fatal(1, "WORD_RAM address outside bank");` | Reject invalid dimensions, addresses or forbidden read/write collisions. |
| 35 | `if (write_i && read_i && write_address_i == read_address_i)` | Independent destination word address. |
| 36 | `$fatal(1, "WORD_RAM same-word read/write is outside the contract");` | Reject invalid dimensions, addresses or forbidden read/write collisions. |
| 37 | `end` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 38 | `// synthesis translate_on` | synthesis translate_on |
| 39 | `endmodule` | Declaration/process continuation or scope boundary; no separate hardware beyond the enclosing statement. |
| 40 | ``default_nettype wire` | Compilation directive; no storage or pipeline stage. |

## Timing and ownership

This is a datapath, not a memory reader or row scheduler. The testbench/controller supplies initialized, still-live addresses and does not overwrite needed pixels. Simultaneous same-word read/write is forbidden; different-word loading/reading can overlap. Reset masks output visibility without resetting RAM. An accepted read produces its result after that edge; synchronous consumers sample it on the next edge.

Standalone: `tests/rtl/tb_row_word_bank.sv`; runner `--suite word-bank`. An independent word model checks writes, reads, holds, concurrent different-address accesses and reset-independent storage. [[Packed Circular Row Buffer]] instantiates this primitive.
