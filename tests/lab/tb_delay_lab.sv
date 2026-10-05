`timescale 1ns/1ps
`default_nettype none

// Teaching baseline: explicit expected values, deliberately no random traffic.
module tb_delay_lab;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [7:0] column_i = '0;
    wire valid_o;
    wire [7:0] column_o;
    left_column_delay #(.K(1), .PIXEL_W(8)) dut (.*);
    integer checked = 0;

    task automatic beat(input bit rn, cl, en, input logic [7:0] data,
                        input bit want_valid, input logic [7:0] want_data);
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = en; column_i = data;
            @(posedge clk); #1;
            $display("edge=%0t reset_n=%b clear=%b in_valid=%b in=%h out_valid=%b out=%h",
                     $time, rn, cl, en, data, valid_o, column_o);
            if (valid_o !== want_valid || column_o !== want_data)
                $fatal(1, "LAB beat=%0d got=%b/%h expected=%b/%h",
                       checked, valid_o, column_o, want_valid, want_data);
            checked = checked + 1;
        end
    endtask
    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_delay_lab);
        end
        beat(0, 0, 1, 8'hff, 0, 8'h00); // Reset discards ff.
        beat(1, 0, 1, 8'h12, 1, 8'h12); // First accepted byte.
        beat(1, 0, 1, 8'ha5, 1, 8'ha5); // Back-to-back input.
        beat(1, 0, 0, 8'hff, 0, 8'ha5); // Pause holds payload, not valid.
        beat(1, 1, 1, 8'hff, 0, 8'h00); // Clear wins over valid.
        beat(1, 0, 1, 8'h3c, 1, 8'h3c); // New row starts cleanly.
        beat(0, 1, 1, 8'hff, 0, 8'h00); // Reset and clear together.
        $display("PASS delay lab: %0d directed beats", checked);
        $finish;
    end
    initial begin #1000; $fatal(1, "lab timeout"); end
endmodule
`default_nettype wire
