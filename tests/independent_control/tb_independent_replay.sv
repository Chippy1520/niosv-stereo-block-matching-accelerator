`timescale 1ns/1ps
`default_nettype none
// Clean-room public-port replay. No hierarchical DUT references.
module tb_independent_replay #(
    parameter integer K=3, PIXEL_W=8, IMG_W=17, IMG_H=9,
    parameter integer LANES=3, SPARE_ROWS=2,
    parameter integer SAD_W=PIXEL_W+$clog2(K*K),
    parameter integer D_W=(LANES<=1)?1:$clog2(LANES),
    parameter integer X_W=(IMG_W<=1)?1:$clog2(IMG_W),
    parameter integer Y_W=(IMG_H<=1)?1:$clog2(IMG_H),
    parameter integer BANK_W=(K+SPARE_ROWS<=1)?1:$clog2(K+SPARE_ROWS),
    parameter integer WORD_AW=((IMG_W+3)/4<=1)?1:$clog2((IMG_W+3)/4)
);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, frame_clear_i=0, row_clear_i=0;
    reg left_write_valid_i=0, right_write_valid_i=0;
    reg [BANK_W-1:0] write_bank_i=0, read_oldest_i=0;
    reg [WORD_AW-1:0] write_word_i=0;
    reg [4*PIXEL_W-1:0] left_write_data_i=0, right_write_data_i=0;
    reg read_valid_i=0;
    reg [X_W-1:0] read_x_i=0;
    reg [Y_W-1:0] read_y_i=0;
    wire valid_o, row_last_o;
    wire [SAD_W-1:0] sad_o;
    wire [D_W-1:0] disparity_o;
    wire [X_W-1:0] x_o;
    wire [Y_W-1:0] y_o;
    wire [31:0] result_o;
    stereo_sad_datapath #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .IMG_H(IMG_H),
        .LANES(LANES), .SPARE_ROWS(SPARE_ROWS)
    ) dut (.*);

    integer fd, logfd, rc, edge_id=0, checked=0, winners=0;
    integer sr, sf, sc, sl, sv, sb, sw, sread, sx, sy, so;
    reg [4*PIXEL_W-1:0] sld, srd;
    integer kind, ecost, edisp, ex, ey, elast;
    integer pk=0, pc=0, pd=0, px=0, py=0, pl=0;
    reg have_previous=0;
    string vector_path, observed_path;

    task automatic check_output;
        input integer expected_kind, cost, disp, tx, ty, last;
        input integer sink_phase;
        reg [31:0] packed_expected;
        begin
            checked=checked+1;
            if ((valid_o !== 1'b0) && (valid_o !== 1'b1))
                $fatal(1,"unknown valid edge=%0d sink=%0d",edge_id,sink_phase);
            if (expected_kind==0 && valid_o !== 1'b0)
                $fatal(1,"unscheduled valid edge=%0d sink=%0d",edge_id,sink_phase);
            if (expected_kind==2 && valid_o !== 1'b1)
                $fatal(1,"missing mature valid edge=%0d sink=%0d tag=(%0d,%0d)",edge_id,sink_phase,tx,ty);
            if (valid_o===1'b0) begin
                if (result_o !== 32'b0 || row_last_o !== 1'b0)
                    $fatal(1,"invalid record/last not zero edge=%0d sink=%0d record=%h last=%b",edge_id,sink_phase,result_o,row_last_o);
            end else begin
                if (x_o !== X_W'(tx) || y_o !== Y_W'(ty) || row_last_o !== 1'(last))
                    $fatal(1,"tag/last mismatch edge=%0d sink=%0d expected=(%0d,%0d,%0d) got=(%0d,%0d,%b)",edge_id,sink_phase,tx,ty,last,x_o,y_o,row_last_o);
                if (disparity_o >= LANES)
                    $fatal(1,"out-of-range disparity edge=%0d",edge_id);
                packed_expected=32'h80000000 | (32'(disparity_o)<<SAD_W) | 32'(sad_o);
                if (result_o !== packed_expected)
                    $fatal(1,"packing mismatch edge=%0d got=%h expected=%h",edge_id,result_o,packed_expected);
                if (expected_kind==2) begin
                    if (sad_o !== SAD_W'(cost) || disparity_o !== D_W'(disp))
                        $fatal(1,"raw-image SAD mismatch edge=%0d sink=%0d tag=(%0d,%0d) expected cost=%0d d=%0d got cost=%0d d=%0d",edge_id,sink_phase,tx,ty,cost,disp,sad_o,disparity_o);
                    if (!sink_phase) winners=winners+1;
                end
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s",vector_path)) $fatal(1,"missing +VECTORS");
        if (!$value$plusargs("OBSERVED=%s",observed_path)) $fatal(1,"missing +OBSERVED");
        fd=$fopen(vector_path,"r");
        logfd=$fopen(observed_path,"w");
        if (!fd || !logfd) $fatal(1,"cannot open replay files");
        $fdisplay(logfd,"edge,valid,x,y,sad,disparity,last,record");
        while (!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                sr,sf,sc,sl,sv,sb,sw,sld,srd,sread,sx,sy,so,kind,ecost,edisp,ex,ey,elast);
            if (rc==19) begin
                @(negedge clk);
                rst_n=sr; frame_clear_i=sf; row_clear_i=sc;
                left_write_valid_i=sl; right_write_valid_i=sv;
                write_bank_i=sb; write_word_i=sw;
                left_write_data_i=sld; right_write_data_i=srd;
                read_valid_i=sread; read_x_i=sx; read_y_i=sy; read_oldest_i=so;
                @(posedge clk);
                // A real synchronous consumer sees the preceding edge's registered winner.
                // An abort edge may discard that consumer sample.
                if (have_previous && sr && !sf && !sc)
                    check_output(pk,pc,pd,px,py,pl,1);
                #1;
                check_output(kind,ecost,edisp,ex,ey,elast,0);
                $fdisplay(logfd,"%0d,%b,%0d,%0d,%0d,%0d,%b,%08h",edge_id,valid_o,x_o,y_o,sad_o,disparity_o,row_last_o,result_o);
                pk=kind; pc=ecost; pd=edisp; px=ex; py=ey; pl=elast;
                have_previous=1;
                edge_id=edge_id+1;
            end else if (rc!=-1) $fatal(1,"malformed replay edge=%0d fields=%0d",edge_id,rc);
        end
        $fclose(fd); $fclose(logfd);
        if (winners==0) $fatal(1,"vacuous replay: no mature winners checked");
        $display("INDEPENDENT_PASS edges=%0d checks=%0d mature_winners=%0d",edge_id,checked,winners);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"replay watchdog expired");
    end
endmodule
`default_nettype wire
