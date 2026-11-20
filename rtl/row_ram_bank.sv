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
