`timescale 1ns/1ps
`default_nettype none

// Test-only caller/controller, independent port monitor and raw-image sink.
// No DUT hierarchy is used by any reference or scheduling decision.
module tb_stereo_control;
    parameter integer K=3, P=8, W=9, T=3, S=1, H=3*(K+S)+3;
    localparam integer BANKS=K+S, WORDS=(W+3)/4;
    localparam integer SW=P+$clog2(K*K), DW=(T<=1)?1:$clog2(T);
    localparam integer XW=(W<=1)?1:$clog2(W), YW=(H<=1)?1:$clog2(H);
    localparam integer BW=(BANKS<=1)?1:$clog2(BANKS);
    localparam integer AW=(WORDS<=1)?1:$clog2(WORDS);
    localparam integer LAT=2+$clog2(K)+1+((T<=1)?1:$clog2(T));
    localparam integer FIRST_X=K+T-2;
    localparam integer ABORT_X=(FIRST_X+2<W)?FIRST_X+2:W-1;
    localparam integer WAIT_ROW=0, SCAN=1, DRAIN=2, ROW_CLEAR=3;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0, frame_clear_i=0, row_clear_i=0, read_valid_i=0;
    logic left_write_valid_i=0, right_write_valid_i=0;
    logic [BW-1:0] write_bank_i='0, read_oldest_i='0;
    logic [AW-1:0] write_word_i='0;
    logic [4*P-1:0] left_write_data_i='0, right_write_data_i='0;
    logic [XW-1:0] read_x_i='0;
    logic [YW-1:0] read_y_i='0;
    wire valid_o, row_last_o;
    wire [SW-1:0] sad_o;
    wire [DW-1:0] disparity_o;
    wire [XW-1:0] x_o;
    wire [YW-1:0] y_o;
    wire [31:0] result_o;
    stereo_sad_datapath #(.K(K),.PIXEL_W(P),.IMG_W(W),.IMG_H(H),
        .LANES(T),.SPARE_ROWS(S)) dut (
        .clk(clk),.rst_n(rst_n),.frame_clear_i(frame_clear_i),.row_clear_i(row_clear_i),
        .left_write_valid_i(left_write_valid_i),.right_write_valid_i(right_write_valid_i),
        .write_bank_i(write_bank_i),.write_word_i(write_word_i),
        .left_write_data_i(left_write_data_i),.right_write_data_i(right_write_data_i),
        .read_valid_i(read_valid_i),.read_x_i(read_x_i),.read_y_i(read_y_i),
        .read_oldest_i(read_oldest_i),.valid_o(valid_o),.sad_o(sad_o),
        .disparity_o(disparity_o),.x_o(x_o),.y_o(y_o),.row_last_o(row_last_o),.result_o(result_o)
    );

    integer raw_l[0:H*W-1], raw_r[0:H*W-1];
    // Controller state and the independently reconstructed port history.
    bit loaded_l[0:H*WORDS-1], loaded_r[0:H*WORDS-1];
    integer owner[0:BANKS-1];
    bit seen_l[0:H*WORDS-1], seen_r[0:H*WORDS-1];
    integer observed_owner[0:BANKS-1], observed_x=0, observed_y=K-1;
    bit active_window=0;
    bit due_valid[0:LAT];
    integer due_x[0:LAT], due_y[0:LAT], due_d[0:LAT];
    longint unsigned due_cost[0:LAT];
    bit sink_seen[0:H*W-1];
    logic [31:0] sink_memory[0:H*W-1];
    integer state, scan_x, scan_y, drain_left, frame_height, pattern, job=0;
    integer loader_y, loader_word, completed_rows, first_clear_cycle;
    integer cycle=0, job_reads, job_outputs, job_rowends;
    integer seed=123, random_cycles=2000, pause_budget, fault=0, ignored;
    integer csv, frames_csv;
    integer complete_jobs=0, abort_jobs=0, total_outputs=0, waits=0, tail_waits=0;
    integer overlaps=0, active_bubbles=0, wraps=0, far_prefetch=0, cancelled=0;
    integer single_restarts=0, abort_quiet_edges=0;
    bit resume_without_clear=0, restart_guard=0;
    logic [31:0] rng=32'h318fcafe;

    function automatic logic [31:0] random_word();
        rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
        return rng;
    endfunction
    function automatic integer fixture(input bit left_side, input integer yy, xx);
        logic [31:0] value;
        integer pos;
        begin
            pos=xx-((pattern==3 && left_side)?T-1:0);
            value=32'(pos)*32'h45d9f3b+32'(yy)*32'h119de1f3+32'(seed)+32'(job)*32'h6d2b79f5;
            if(left_side) value=value^32'h9e3779b9;
            value=(value^(value>>16))*32'h45d9f3b;
            value=value^(value>>16);
            if(pattern==1) return 0;
            if(pattern==2) return left_side?((1<<P)-1):0;
            if(pattern==3) return (pos*7+yy*17+job*29)&((1<<P)-1);
            return integer'(value&((1<<P)-1));
        end
    endfunction
    function automatic longint unsigned raw_cost(input integer xx, yy, disparity);
        integer dx,dy,a,b;
        longint unsigned sum;
        begin
            sum=0;
            for(dy=0;dy<K;dy=dy+1) for(dx=0;dx<K;dx=dx+1) begin
                a=raw_l[(yy-dy)*W+xx-dx];
                b=raw_r[(yy-dy)*W+xx-dx-disparity];
                sum=sum+((a>=b)?a-b:b-a);
            end
            return sum;
        end
    endfunction
    function automatic bit controller_ready();
        integer y,w;
        bit ready;
        begin
            ready=(scan_y<frame_height);
            for(y=scan_y-K+1;y<=scan_y;y=y+1)
                for(w=0;w<WORDS;w=w+1)
                    if(y<0 || y>=frame_height) ready=0;
                    else if(!loaded_l[y*WORDS+w] || !loaded_r[y*WORDS+w] || owner[y%BANKS]!=y) ready=0;
            return ready;
        end
    endfunction
    function automatic bit left_ready(input integer y);
        integer w;
        bit ready;
        begin
            ready=(y>=0 && y<frame_height);
            if(ready) for(w=0;w<WORDS;w=w+1) if(!loaded_l[y*WORDS+w]) ready=0;
            return ready;
        end
    endfunction

    task automatic reset_monitor;
        integer n;
        begin
            for(n=0;n<H*WORDS;n=n+1) begin seen_l[n]=0; seen_r[n]=0; end
            for(n=0;n<BANKS;n=n+1) observed_owner[n]=-1;
            observed_x=0; observed_y=K-1; active_window=0;
        end
    endtask
    task automatic check_ports;
        integer y,w,b,j;
        begin
            if(restart_guard && (!rst_n || frame_clear_i))
                $fatal(1,"CONTROL protocol second clear before single-pulse restart");
            if(rst_n && !frame_clear_i) begin
                if(row_clear_i) begin
                    if(observed_x!=W) $fatal(1,"CONTROL protocol row clear before all reads");
                    for(j=0;j<LAT;j=j+1) if(due_valid[j])
                        $fatal(1,"CONTROL protocol drain: clear discards an unconsumed result");
                end
                if(read_valid_i && !row_clear_i) begin
                    if(read_y_i!=observed_y || read_x_i!=observed_x)
                        $fatal(1,"CONTROL protocol coordinates: got %0d,%0d expected %0d,%0d",read_x_i,read_y_i,observed_x,observed_y);
                    if(read_oldest_i!=(observed_y-K+1)%BANKS)
                        $fatal(1,"CONTROL protocol oldest bank");
                    // Do not reuse controller_ready or its completion flags.
                    for(y=observed_y-K+1;y<=observed_y;y=y+1) begin
                        if(y<0 || y>=frame_height || observed_owner[y%BANKS]!=y)
                            $fatal(1,"CONTROL protocol unready ownership");
                        for(w=0;w<WORDS;w=w+1) if(!seen_l[y*WORDS+w] || !seen_r[y*WORDS+w])
                            $fatal(1,"CONTROL protocol unready L/R word row=%0d word=%0d",y,w);
                    end
                end
                if(left_write_valid_i || right_write_valid_i) begin
                    b=integer'(write_bank_i); w=integer'(write_word_i);
                    if(loader_y<0 || loader_y>=frame_height || b!=loader_y%BANKS || w>=WORDS)
                        $fatal(1,"CONTROL protocol producer address");
                    if(active_window && observed_owner[b]>=observed_y-K+1 && observed_owner[b]<=observed_y)
                        $fatal(1,"CONTROL protocol active-bank overwrite, including a read bubble");
                    if(observed_owner[b]!=loader_y && observed_owner[b]>=observed_y-K+1)
                        $fatal(1,"CONTROL protocol reuse of an unretired bank");
                    if((left_write_valid_i && seen_l[loader_y*WORDS+w]) ||
                       (right_write_valid_i && seen_r[loader_y*WORDS+w]))
                        $fatal(1,"CONTROL protocol duplicate input word");
                    for(j=0;j<4;j=j+1) if(w*4+j<W) begin
                        if(left_write_valid_i && left_write_data_i[j*P+:P]!==P'(raw_l[loader_y*W+w*4+j]))
                            $fatal(1,"CONTROL protocol producer left payload");
                        if(right_write_valid_i && right_write_data_i[j*P+:P]!==P'(raw_r[loader_y*W+w*4+j]))
                            $fatal(1,"CONTROL protocol producer right payload");
                    end
                end
            end
        end
    endtask
    task automatic check_output;
        logic [31:0] expected;
        begin
            expected='0;
            if(due_valid[LAT]) begin
                expected[31]=1'b1; expected[0+:SW]=SW'(due_cost[LAT]); expected[SW+:DW]=DW'(due_d[LAT]);
            end
            if(valid_o!==due_valid[LAT] || result_o!==expected)
                $fatal(1,"CONTROL oracle valid/record job=%0d cycle=%0d got=%h expected=%h",job,cycle,result_o,expected);
            if(due_valid[LAT] && (sad_o!==SW'(due_cost[LAT]) || disparity_o!==DW'(due_d[LAT]) ||
               x_o!==XW'(due_x[LAT]) || y_o!==YW'(due_y[LAT]) || row_last_o!==(due_x[LAT]==W-1)))
                $fatal(1,"CONTROL oracle payload/tag job=%0d cycle=%0d xy=%0d,%0d cost/d=%0d/%0d expected xy=%0d,%0d cost/d=%0d/%0d",
                    job,cycle,x_o,y_o,sad_o,disparity_o,due_x[LAT],due_y[LAT],due_cost[LAT],due_d[LAT]);
            if(!due_valid[LAT] && row_last_o!==1'b0) $fatal(1,"CONTROL oracle invalid row-last");
        end
    endtask
    task automatic tick;
        integer n,d,b,index;
        longint unsigned candidate,best;
        begin
            check_ports(); // Before the edge: illegal stimulus cannot race DUT assertions.
            @(posedge clk);
            if(cycle!=0) check_output();
            // A synchronous sink sees OLD registered outputs, even on row-clear.
            if(rst_n && !frame_clear_i && valid_o) begin
                index=integer'(y_o)*W+integer'(x_o);
                if(sink_seen[index]) $fatal(1,"CONTROL oracle duplicate sink pixel");
                sink_seen[index]=1; sink_memory[index]=result_o;
                job_outputs=job_outputs+1; total_outputs=total_outputs+1;
                if(row_last_o) job_rowends=job_rowends+1;
                $fwrite(csv,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%08h\n",job,pattern,x_o,y_o,sad_o,disparity_o,row_last_o,result_o);
            end
            if(!rst_n || frame_clear_i || row_clear_i) begin
                for(n=0;n<=LAT;n=n+1) begin due_valid[n]=0; due_x[n]=0; due_y[n]=0; due_d[n]=0; due_cost[n]=0; end
            end else begin
                for(n=LAT;n>0;n=n-1) begin
                    due_valid[n]=due_valid[n-1]; due_x[n]=due_x[n-1]; due_y[n]=due_y[n-1]; due_d[n]=due_d[n-1]; due_cost[n]=due_cost[n-1];
                end
                due_valid[0]=read_valid_i && read_x_i>=FIRST_X && read_y_i>=K-1;
                due_x[0]=integer'(read_x_i); due_y[0]=integer'(read_y_i); due_d[0]=0; due_cost[0]=0;
                if(due_valid[0]) begin
                    best='1;
                    for(d=0;d<T;d=d+1) begin
                        candidate=raw_cost(integer'(read_x_i),integer'(read_y_i),d);
                        if(candidate<best) begin best=candidate; due_d[0]=d; end
                    end
                    due_cost[0]=best;
                end
            end
            if(!rst_n || frame_clear_i) reset_monitor();
            else begin
                if(active_window && !read_valid_i && !row_clear_i) active_bubbles=active_bubbles+1;
                if(left_write_valid_i || right_write_valid_i) begin
                    b=integer'(write_bank_i); observed_owner[b]=loader_y;
                    if(left_write_valid_i) seen_l[loader_y*WORDS+integer'(write_word_i)]=1;
                    if(right_write_valid_i) seen_r[loader_y*WORDS+integer'(write_word_i)]=1;
                    if(read_valid_i) overlaps=overlaps+1;
                    if(loader_y>observed_y+1) far_prefetch=far_prefetch+1;
                end
                if(read_valid_i && !row_clear_i) begin
                    if(restart_guard) begin single_restarts=single_restarts+1; restart_guard=0; end
                    if(observed_x==0 && observed_y>K-1 && read_oldest_i==0) wraps=wraps+1;
                    observed_x=observed_x+1; active_window=1; job_reads=job_reads+1;
                end
                if(row_clear_i) begin observed_x=0; observed_y=observed_y+1; active_window=0; end
            end
            #1; check_output(); cycle=cycle+1;
        end
    endtask

    task automatic default_inputs;
        begin
            rst_n=1; frame_clear_i=0; row_clear_i=0; read_valid_i=0;
            left_write_valid_i=0; right_write_valid_i=0;
            write_bank_i='0; write_word_i='0; loader_y=-1; loader_word=0;
            left_write_data_i='0; right_write_data_i='0;
            read_x_i=XW'(scan_x); read_y_i=YW'(scan_y);
            read_oldest_i=BW'((scan_y-K+1)%BANKS);
        end
    endtask
    task automatic choose_load;
        integer y,w,j,b;
        bit found,allow_l,allow_r;
        logic [31:0] noise;
        begin
            found=0; noise=random_word();
            for(y=scan_y-K+1;y<frame_height && y<=scan_y+S && !found;y=y+1) begin
                b=y%BANKS;
                if(owner[b]==y || owner[b]<scan_y-K+1)
                    for(w=0;w<WORDS && !found;w=w+1) begin
                        allow_l=!loaded_l[y*WORDS+w] && ((noise&3)!=0);
                        allow_r=!loaded_r[y*WORDS+w] && (((noise>>2)&3)!=0);
                        // Force a genuine incomplete next-row tail at the first rotation.
                        if(y==K && w==WORDS-1 && (completed_rows==0 || cycle<first_clear_cycle+7)) allow_r=0;
                        if(allow_l || allow_r) begin
                            found=1; loader_y=y; loader_word=w;
                            write_bank_i=BW'(b); write_word_i=AW'(w);
                            left_write_valid_i=allow_l; right_write_valid_i=allow_r;
                            for(j=0;j<4;j=j+1) begin
                                left_write_data_i[j*P+:P]=(w*4+j<W)?P'(raw_l[y*W+w*4+j]):P'('hA5);
                                right_write_data_i[j*P+:P]=(w*4+j<W)?P'(raw_r[y*W+w*4+j]):P'('h5A);
                            end
                        end
                    end
            end
        end
    endtask
    task automatic run_job(input integer selected_pattern, height, abort_kind);
        integer n,y,x,start_cycle,expected,expected_rows,pending;
        bit done,aborted,ready,all_loaded;
        logic [31:0] noise;
        begin
            pattern=selected_pattern; frame_height=height;
            for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) begin
                raw_l[y*W+x]=fixture(1,y,x); raw_r[y*W+x]=fixture(0,y,x);
                sink_seen[y*W+x]=0; sink_memory[y*W+x]='0;
            end
            for(n=0;n<H*WORDS;n=n+1) begin loaded_l[n]=0; loaded_r[n]=0; end
            for(n=0;n<BANKS;n=n+1) owner[n]=-1;
            state=WAIT_ROW; scan_y=K-1; scan_x=0; drain_left=0;
            completed_rows=0; first_clear_cycle=0; job_outputs=0; job_rowends=0; job_reads=0;
            if(resume_without_clear) resume_without_clear=0;
            else begin
                @(negedge clk); default_inputs(); frame_clear_i=1; read_valid_i=1;
                left_write_valid_i=1; right_write_valid_i=1; loader_y=0; tick();
            end
            done=0; aborted=0; start_cycle=cycle;
            while(!done && cycle-start_cycle<30*H*WORDS+100*W*(H+1)+1000) begin
                @(negedge clk); default_inputs(); choose_load();
                if(state==SCAN) begin
                    noise=random_word(); read_valid_i=1;
                    if(pause_budget>0 && (noise&3)==0) begin read_valid_i=0; pause_budget=pause_budget-1; end
                end
                if(state==ROW_CLEAR) row_clear_i=1;
                if(fault==2 && state==SCAN && scan_x==1) begin
                    read_valid_i=0; left_write_valid_i=1; right_write_valid_i=0;
                    loader_y=scan_y-K+1; write_bank_i=read_oldest_i; write_word_i=0;
                end
                if(fault==3 && state==DRAIN) row_clear_i=1;
                if(fault==4 && state==SCAN) read_oldest_i=BW'((integer'(read_oldest_i)+1)%BANKS);
                if(fault==5 && state==SCAN && scan_x==1 && read_valid_i) read_x_i=0;
                tick();
                if(left_write_valid_i || right_write_valid_i) begin
                    owner[loader_y%BANKS]=loader_y;
                    if(left_write_valid_i) loaded_l[loader_y*WORDS+loader_word]=1;
                    if(right_write_valid_i) loaded_r[loader_y*WORDS+loader_word]=1;
                end
                case(state)
                    WAIT_ROW: begin
                        ready=controller_ready();
                        if(fault==1 && scan_y==K && left_ready(scan_y)) ready=1;
                        if(ready) state=SCAN;
                        else begin
                            waits=waits+1;
                            if(scan_y==K && left_ready(scan_y)) tail_waits=tail_waits+1;
                        end
                        if(frame_height<K) begin
                            all_loaded=1;
                            for(n=0;n<frame_height*WORDS;n=n+1) if(!loaded_l[n] || !loaded_r[n]) all_loaded=0;
                            if(all_loaded) done=1;
                        end
                    end
                    SCAN: if(read_valid_i) begin
                        if(abort_kind!=0 && scan_x==((abort_kind==1)?ABORT_X:W-1)) begin
                            pending=0;
                            for(n=0;n<=LAT;n=n+1) if(due_valid[n]) pending=pending+1;
                            if(pending==0) $fatal(1,"CONTROL abort requires an in-flight winner");
                            cancelled=cancelled+pending;
                            @(negedge clk); default_inputs();
                            rst_n=(abort_kind==1); frame_clear_i=(abort_kind==1);
                            read_valid_i=1; left_write_valid_i=1; right_write_valid_i=1; loader_y=0;
                            tick(); aborted=1; done=1; abort_jobs=abort_jobs+1;
                            // One abort pulse only: detect delayed leakage before
                            // reloading, then start the next job without another clear.
                            restart_guard=1; resume_without_clear=1;
                            for(n=0;n<LAT+2;n=n+1) begin
                                @(negedge clk); default_inputs(); tick();
                                abort_quiet_edges=abort_quiet_edges+1;
                            end
                        end else if(scan_x==W-1) begin state=DRAIN; drain_left=LAT; end
                        else scan_x=scan_x+1;
                    end
                    DRAIN: begin
                        drain_left=drain_left-1;
                        if(drain_left==0) state=ROW_CLEAR;
                    end
                    ROW_CLEAR: begin
                        completed_rows=completed_rows+1;
                        if(completed_rows==1) first_clear_cycle=cycle;
                        scan_y=scan_y+1; scan_x=0; state=WAIT_ROW;
                        if(scan_y==frame_height) done=1;
                    end
                    default: $fatal(1,"CONTROL protocol unknown state");
                endcase
            end
            if(!done) $fatal(1,"CONTROL watchdog: controller failed to complete");
            if(!aborted) begin
                expected_rows=(frame_height>=K)?frame_height-K+1:0;
                expected=((W>FIRST_X)?W-FIRST_X:0)*expected_rows;
                if(job_outputs!=expected || job_reads!=expected_rows*W ||
                   job_rowends!=((W>FIRST_X)?expected_rows:0))
                    $fatal(1,"CONTROL oracle frame coverage outputs=%0d expected=%0d reads=%0d rowends=%0d",job_outputs,expected,job_reads,job_rowends);
                for(y=0;y<frame_height;y=y+1) for(x=0;x<W;x=x+1)
                    if(sink_seen[y*W+x] !== (y>=K-1 && x>=FIRST_X))
                        $fatal(1,"CONTROL oracle missing/unexpected framebuffer pixel %0d,%0d",x,y);
                complete_jobs=complete_jobs+1;
            end
            $fwrite(frames_csv,"%0d,%0d,%0d,%0d,%0d,%0d\n",job,pattern,aborted,job_reads,job_outputs,job_rowends);
            job=job+1;
        end
    endtask

    integer n;
    initial begin
        if(K<1 || P<1 || W<1 || T<1 || S<1 || H<1 || SW+DW>31)
            $fatal(1,"CONTROL positive dimensions and fitting result record required");
        ignored=$value$plusargs("SEED=%d",seed); rng=32'(seed);
        ignored=$value$plusargs("RANDOM_CYCLES=%d",random_cycles); pause_budget=random_cycles;
        ignored=$value$plusargs("CONTROL_FAULT=%d",fault);
        if($test$plusargs("VCD")) begin $dumpfile("waveform.vcd"); $dumpvars(0,tb_stereo_control); end
        csv=$fopen("control_results.csv","w"); frames_csv=$fopen("control_frames.csv","w");
        if(csv==0 || frames_csv==0) $fatal(1,"CONTROL cannot open result artifacts");
        $fwrite(csv,"job,pattern,x,y,sad,disparity,row_last,result_hex\n");
        $fwrite(frames_csv,"job,pattern,aborted,reads,results,row_ends\n");
        for(n=0;n<=LAT;n=n+1) begin due_valid[n]=0; due_x[n]=0; due_y[n]=0; due_d[n]=0; due_cost[n]=0; end
        run_job(0,H,0);
        if(H>=K && W>FIRST_X) run_job(0,H,1);
        run_job(1,(H<K)?H:K,0);
        if(H>=K && W>FIRST_X) run_job(0,H,2);
        run_job(2,(H<K)?H:K,0);
        run_job(3,H,0);
        if(fault!=0) $fatal(1,"CONTROL injected controller fault was not exercised");
        if(H>K && (tail_waits==0 || overlaps==0)) $fatal(1,"CONTROL missing readiness/prefetch coverage");
        if(H>K+2*BANKS && wraps==0) $fatal(1,"CONTROL missing bank wrap coverage");
        if(H>K+1 && S>1 && far_prefetch==0) $fatal(1,"CONTROL missing extra-spare headroom coverage");
        if(H>=K && W>FIRST_X && (abort_jobs!=2 || single_restarts!=2 ||
           abort_quiet_edges!=2*(LAT+2) || cancelled==0 || restart_guard || resume_without_clear))
            $fatal(1,"CONTROL missing single-pulse abort/restart coverage");
        $fclose(csv); $fclose(frames_csv);
        $display("PASS control K=%0d P=%0d W=%0d H=%0d T=%0d S=%0d cycles=%0d frames=%0d aborts=%0d results=%0d waits=%0d tail_waits=%0d overlaps=%0d bubbles=%0d wraps=%0d far_prefetch=%0d cancelled=%0d single_restarts=%0d quiet_edges=%0d",
            K,P,W,H,T,S,cycle,complete_jobs,abort_jobs,total_outputs,waits,tail_waits,overlaps,active_bubbles,wraps,far_prefetch,cancelled,single_restarts,abort_quiet_edges);
        $finish;
    end
endmodule
`default_nettype wire
