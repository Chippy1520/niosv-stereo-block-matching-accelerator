`timescale 1ns/1ps
`default_nettype none

// Match the right-column cache's single sampling register, not its tap depth.
// Accepted at edge t -> output after edge t; a consumer samples at edge t+1.
// Bubbles hold payload but suppress valid. Reset/clear discards simultaneous input.
module left_column_delay #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    valid_i,
    input  wire [K*PIXEL_W-1:0]     column_i,
    output logic                   valid_o,
    output logic [K*PIXEL_W-1:0]    column_o
);
    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            valid_o <= 1'b0;
            column_o <= '0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) column_o <= column_i;
        end
    end

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1)
            $fatal(1, "K and PIXEL_W must be positive");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
