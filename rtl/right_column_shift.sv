`timescale 1ns/1ps
`default_nettype none

// Shift whole K-pixel columns, not pixels or SAD costs. Tap d is R[x-d].
// Accepted at edge t -> registered taps after that edge; no backpressure.
// valid_i=0 holds history and suppresses every output-valid bit for that beat.
// x advances ONLY on accepted columns. Clear between rows; clear discards input.
// A separate one-register left alignment is required before engine pairing.
module right_column_shift #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer TAPS = 32
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_i,
    input  wire                         valid_i,
    input  wire [K*PIXEL_W-1:0]          column_i,
    output wire [TAPS-1:0]              tap_valid_o,
    output wire [TAPS*K*PIXEL_W-1:0]     columns_o
);
    localparam integer COL_W = K * PIXEL_W;
    logic [COL_W-1:0] columns [0:TAPS-1];
    logic [TAPS-1:0] occupied;
    logic beat_valid;
    integer d;

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            occupied <= '0;
            beat_valid <= 1'b0;
            for (d = 0; d < TAPS; d = d + 1) columns[d] <= '0;
        end else begin
            beat_valid <= valid_i;
            if (valid_i) begin
                columns[0] <= column_i;
                occupied[0] <= 1'b1;
                for (d = 1; d < TAPS; d = d + 1) begin
                    columns[d] <= columns[d-1];
                    occupied[d] <= occupied[d-1];
                end
            end
        end
    end

    assign tap_valid_o = occupied & {TAPS{beat_valid}};
    genvar tap;
    generate
        for (tap = 0; tap < TAPS; tap = tap + 1) begin : g_output
            assign columns_o[tap*COL_W +: COL_W] = columns[tap];
        end
    endgenerate

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || TAPS < 1)
            $fatal(1, "K, PIXEL_W and TAPS must be positive");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
