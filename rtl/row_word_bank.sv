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
