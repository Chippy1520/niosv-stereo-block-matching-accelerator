`timescale 1ns/1ps
`default_nettype none

// Synthesis smoke top only. Functional default remains IMG_W=640 in
// circular_row_buffer. The 640-wide combinational column readout did not
// finish Analysis & Synthesis within 300 seconds, so this top uses a short row.
module circular_row_buffer_synth (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      clear_i,
    input  wire                      valid_i,
    input  wire [7:0]                pixel_i,
    output wire                      valid_o,
    output wire                      row_last_o,
    output wire [11*8-1:0]           column_o
);
    circular_row_buffer #(.K(11), .PIXEL_W(8), .IMG_W(16)) u_row (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .pixel_i(pixel_i), .valid_o(valid_o), .row_last_o(row_last_o),
        .column_o(column_o)
    );
endmodule
`default_nettype wire
