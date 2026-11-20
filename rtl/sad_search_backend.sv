`timescale 1ns/1ps
`default_nettype none

// Fixed full-search backend: lane d receives R[x-d]. No scheduling/backpressure.
// Prefix lane warmup is legal; missing spatial columns within a row are not.
// Input edge t -> winner after t+$clog2(K)+1+max(1,$clog2(LANES)).
module sad_search_backend #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer LANES = 32,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer SAD_W = PIXEL_W + $clog2(K*K),
    parameter integer D_W = (LANES <= 1) ? 1 : $clog2(LANES),
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer Y_W = (IMG_H <= 1) ? 1 : $clog2(IMG_H)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          clear_i,
    input  wire                          valid_i,
    input  wire [K*PIXEL_W-1:0]          left_column_i,
    input  wire [LANES*K*PIXEL_W-1:0]    right_columns_i,
    input  wire [LANES-1:0]             right_valid_i,
    input  wire [X_W-1:0]               x_i,
    input  wire [Y_W-1:0]               y_i,
    input  wire                          row_last_i,
    output wire                          valid_o,
    output wire [SAD_W-1:0]             sad_o,
    output wire [D_W-1:0]               disparity_o,
    output wire [X_W-1:0]               x_o,
    output wire [Y_W-1:0]               y_o,
    output wire                          row_last_o
);
    localparam integer ENGINE_DELAY = $clog2(K)+1;
    localparam integer REDUCE_STAGES = (LANES <= 1) ? 1 : $clog2(LANES);
    localparam integer DELAY = ENGINE_DELAY + REDUCE_STAGES;
    localparam integer COL_BITS = K * PIXEL_W;
    wire [LANES-1:0] lane_valid;
    wire [LANES*SAD_W-1:0] lane_sad;
    wire [LANES*D_W-1:0] lane_disparity;
    logic common_valid [0:DELAY];
    logic [X_W-1:0] tag_x [0:DELAY];
    logic [Y_W-1:0] tag_y [0:DELAY];
    logic tag_last [0:DELAY];
    integer i;

    // Engines receive early columns; masking before warmup would lose history.
    genvar d;
    generate
        for (d = 0; d < LANES; d = d + 1) begin : g_lane
            sad_engine #(.K(K), .PIXEL_W(PIXEL_W), .SAD_W(SAD_W)) engine (
                .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
                .valid_i(valid_i && right_valid_i[d]),
                .left_column_i(left_column_i),
                .right_column_i(right_columns_i[d*COL_BITS +: COL_BITS]),
                .valid_o(lane_valid[d]), .sad_o(lane_sad[d*SAD_W +: SAD_W])
            );
            assign lane_disparity[d*D_W +: D_W] = D_W'(d);
        end
    endgenerate

    // Index zero captures this edge; every later index shifts even on bubbles.
    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            for (i = 0; i <= DELAY; i = i + 1) begin
                common_valid[i] <= 1'b0;
                tag_x[i] <= '0;
                tag_y[i] <= '0;
                tag_last[i] <= 1'b0;
            end
        end else begin
            // Do not narrow the thresholds: an impossible interior must stay empty.
            common_valid[0] <= valid_i && x_i >= K+LANES-2 && y_i >= K-1 &&
                               x_i < IMG_W && y_i < IMG_H;
            tag_x[0] <= x_i;
            tag_y[0] <= y_i;
            tag_last[0] <= row_last_i;
            for (i = 1; i <= DELAY; i = i + 1) begin
                common_valid[i] <= common_valid[i-1];
                tag_x[i] <= tag_x[i-1];
                tag_y[i] <= tag_y[i-1];
                tag_last[i] <= tag_last[i-1];
            end
        end
    end

    // All-or-none qualification forbids an accidental partial-search winner.
    wire full_search = common_valid[ENGINE_DELAY] && (&lane_valid);
    comparator_tree #(.LANES(LANES), .SAD_W(SAD_W), .D_W(D_W)) minimum (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .lane_valid_i({LANES{full_search}}), .sad_i(lane_sad),
        .disparity_i(lane_disparity), .valid_o(valid_o),
        .sad_o(sad_o), .disparity_o(disparity_o)
    );
    assign x_o = valid_o ? tag_x[DELAY] : '0;
    assign y_o = valid_o ? tag_y[DELAY] : '0;
    assign row_last_o = valid_o && tag_last[DELAY];

    // Protocol assertions are verification only, not extra datapath control.
    // synthesis translate_off
    integer lane;
    integer next_x, active_y;
    initial begin
        next_x = 0;
        active_y = 0;
        if (K < 1 || PIXEL_W < 1 || LANES < 1 || IMG_W < 1 || IMG_H < 1 ||
            SAD_W < PIXEL_W+$clog2(K*K) || D_W < ((LANES<=1)?1:$clog2(LANES)) ||
            X_W < ((IMG_W<=1)?1:$clog2(IMG_W)) || Y_W < ((IMG_H<=1)?1:$clog2(IMG_H)))
            $fatal(1, "SEARCH_PROTOCOL invalid parameters or undersized widths");
    end
    always @(posedge clk) begin
        if (!rst_n || clear_i) begin
            next_x = 0;
            active_y = 0;
        end else begin
            if (valid_i) begin
                if (x_i != next_x || x_i >= IMG_W || y_i >= IMG_H ||
                    (next_x != 0 && y_i != active_y) || row_last_i !== (x_i == IMG_W-1))
                    $fatal(1, "SEARCH_PROTOCOL rows require consecutive x, fixed y and matching last");
                for (lane = 0; lane < LANES; lane = lane + 1)
                    if (right_valid_i[lane] !== (x_i >= lane))
                        $fatal(1, "SEARCH_PROTOCOL missing lane column at x=%0d lane=%0d", x_i, lane);
                next_x = next_x + 1;
                active_y = y_i;
            end
            if (common_valid[ENGINE_DELAY] && !(&lane_valid))
                $fatal(1, "SEARCH_PROTOCOL common interior requires every engine result");
        end
    end
    // synthesis translate_on
endmodule
`default_nettype wire
