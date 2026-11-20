// Shared test-only stimulus/oracle; no DUT rolling sum, ring or shift model.
localparam integer SW = P+$clog2(K*K);
localparam integer DW = (T <= 1) ? 1 : $clog2(T);
localparam integer XW = (W <= 1) ? 1 : $clog2(W);
localparam integer YW = (H <= 1) ? 1 : $clog2(H);
localparam integer BANKS = K+S;
localparam integer BW = (BANKS <= 1) ? 1 : $clog2(BANKS);
localparam integer AW = ((W+3)/4 <= 1) ? 1 : $clog2((W+3)/4);
localparam integer E = $clog2(K)+1;
localparam integer R = (T <= 1) ? 1 : $clog2(T);
localparam integer DELAY = E+R+(PACKED ? 2 : 0);
localparam integer LANE_DELAY = E+(PACKED ? 2 : 0);
logic clk = 0;
always #5 clk = ~clk;
logic rst_n=0, frame_clear_i=0, row_clear_i=0, read_valid_i=0;
logic left_write_valid_i=0, right_write_valid_i=0;
logic [BW-1:0] write_bank_i='0, read_oldest_i='0;
logic [AW-1:0] write_word_i='0;
logic [4*P-1:0] left_write_data_i='0, right_write_data_i='0;
logic [XW-1:0] read_x_i='0;
logic [YW-1:0] read_y_i='0;
logic [K*P-1:0] left_column_i='0;
logic [T*K*P-1:0] right_columns_i='0;
logic [T-1:0] right_valid_i='0;
wire valid_o, row_last_o;
wire [SW-1:0] sad_o;
wire [DW-1:0] disparity_o;
wire [XW-1:0] x_o;
wire [YW-1:0] y_o;
wire [31:0] result_o;
wire [T*SW-1:0] observed_costs;
wire [T-1:0] observed_valid;
bit ev[0:DELAY];
integer ex[0:DELAY], ey[0:DELAY], ed[0:DELAY];
longint unsigned ec[0:DELAY];
logic [T*SW-1:0] expected_lanes[0:DELAY];
integer phase=0, cycles=0, outputs=0, nonzero_winners=0, row_ends=0;
integer prefetch_beats=0, same_word_prefetch=0;
// Cache only immutable raw fixture pixels, never SADs or DUT-derived history.
integer raw_left[0:H*W-1], raw_right[0:H*W-1];
integer cached_phase=-1;
integer random_cycles=2000, ignored, seed=123;
logic [31:0] rng=32'h318fcafe;
function automatic logic [31:0] next_random();
    rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
    return rng;
endfunction
function automatic integer pixel(input bit left_side, input integer yy, xx);
    logic [31:0] v;
    integer shifted;
    begin
        shifted=xx;
        if (phase==3 && left_side) shifted=xx-(T-1);
        v=32'(shifted)*32'h45d9f3b+32'(yy)*32'h119de1f3+32'(seed);
        if (phase!=3 && left_side) v=v^32'h9e3779b9;
        v=(v^(v>>16))*32'h45d9f3b;
        v=v^(v>>16);
        if (phase==1) pixel=0;
        else if (phase==2) pixel=left_side ? ((1<<P)-1) : 0;
        else pixel=integer'(v & ((1<<P)-1));
    end
endfunction
function automatic longint unsigned raw_cost(input integer xx, yy, dd);
    integer a,b,dx,dy;
    longint unsigned sum;
    begin
        sum=0;
        for(dy=0;dy<K;dy=dy+1)
            for(dx=0;dx<K;dx=dx+1) begin
                a=raw_left[(yy-dy)*W+xx-dx];
                b=raw_right[(yy-dy)*W+xx-dx-dd];
                sum=sum+((a>=b)?a-b:b-a);
            end
        return sum;
    end
endfunction
task automatic check_result;
    logic [31:0] packed_expected;
    begin
        if(valid_o !== ev[DELAY])
            $fatal(1,"DATAPATH K=%0d T=%0d cycle=%0d valid got=%b expected=%b",K,T,cycles,valid_o,ev[DELAY]);
        if(ev[DELAY] && (sad_o !== SW'(ec[DELAY]) || disparity_o !== DW'(ed[DELAY]) ||
            x_o !== XW'(ex[DELAY]) || y_o !== YW'(ey[DELAY]) || row_last_o !== (ex[DELAY]==W-1)))
            $fatal(1,"DATAPATH K=%0d T=%0d cycle=%0d xy=%0d,%0d got cost/d=%0d/%0d expected=%0d/%0d xy=%0d,%0d",K,T,cycles,x_o,y_o,sad_o,disparity_o,ec[DELAY],ed[DELAY],ex[DELAY],ey[DELAY]);
        packed_expected=0;
        if(ev[DELAY]) begin
            packed_expected[31]=1;
            packed_expected[0+:SW]=SW'(ec[DELAY]);
            packed_expected[SW+:DW]=DW'(ed[DELAY]);
        end
        if(PACKED && result_o !== packed_expected)
            $fatal(1,"DATAPATH K=%0d packed result got=%h expected=%h",K,result_o,packed_expected);
        if(!ev[DELAY] && row_last_o !== 1'b0)
            $fatal(1,"DATAPATH K=%0d spurious row_last",K);
    end
endtask
task automatic tick(input bit rn,fc,rc,vi, input integer xx,yy,wy,ww, input bit lw,rw);
    integer n,d,j,a,b,chosen;
    longint unsigned cost,best;
    begin
        if(cached_phase!=phase) begin
            for(a=0;a<H;a=a+1) for(b=0;b<W;b=b+1) begin
                raw_left[a*W+b]=pixel(1,a,b);
                raw_right[a*W+b]=pixel(0,a,b);
            end
            cached_phase=phase;
        end
        @(negedge clk);
        rst_n=rn; frame_clear_i=fc; row_clear_i=rc; read_valid_i=vi;
        read_x_i=XW'(xx); read_y_i=YW'(yy);
        read_oldest_i=BW'((yy-K+1+BANKS*H)%BANKS);
        left_write_valid_i=lw; right_write_valid_i=rw;
        write_bank_i=BW'(wy%BANKS); write_word_i=AW'(ww);
        for(n=0;n<4;n=n+1) begin
            left_write_data_i[n*P+:P]=P'(pixel(1,wy,ww*4+n));
            right_write_data_i[n*P+:P]=P'(pixel(0,wy,ww*4+n));
        end
        for(j=0;j<K;j=j+1) left_column_i[j*P+:P]=P'(pixel(1,yy-K+1+j,xx));
        for(d=0;d<T;d=d+1) begin
            right_valid_i[d]=vi && xx>=d;
            for(j=0;j<K;j=j+1)
                right_columns_i[(d*K+j)*P+:P]=P'(pixel(0,yy-K+1+j,xx-d));
        end
        if(!PACKED && $test$plusargs("INJECT_LANE_HOLE") && vi && xx==K+T-2)
            right_valid_i[T-1]=0;
        @(posedge clk);
        // Check what a clocked consumer sees BEFORE any NBA updates.
        if(cycles!=0) check_result();
        if(!rn || fc || rc) begin
            for(n=0;n<=DELAY;n=n+1) begin ev[n]=0; ex[n]=0; ey[n]=0; ed[n]=0; ec[n]=0; expected_lanes[n]='0; end
        end else begin
            for(n=DELAY;n>0;n=n-1) begin
                ev[n]=ev[n-1]; ex[n]=ex[n-1]; ey[n]=ey[n-1]; ed[n]=ed[n-1]; ec[n]=ec[n-1]; expected_lanes[n]=expected_lanes[n-1];
            end
            ev[0]=vi && xx>=K+T-2 && yy>=K-1;
            ex[0]=xx; ey[0]=yy; ed[0]=0; ec[0]=0; expected_lanes[0]='0;
            if(ev[0]) begin
                best='1; chosen=0;
                for(d=0;d<T;d=d+1) begin
                    cost=raw_cost(xx,yy,d);
                    expected_lanes[0][d*SW+:SW]=SW'(cost);
                    if(cost<best) begin best=cost; chosen=d; end
                end
                ec[0]=best; ed[0]=chosen;
            end
        end
        #1;
        check_result();
        if(ev[LANE_DELAY]) begin
            if(observed_valid !== {T{1'b1}})
                $fatal(1,"DATAPATH K=%0d lane validity mismatch",K);
            for(d=0;d<T;d=d+1)
                if(observed_costs[d*SW+:SW] !== expected_lanes[LANE_DELAY][d*SW+:SW])
                    $fatal(1,"DATAPATH K=%0d lane=%0d full-window cost mismatch",K,d);
        end
        if(valid_o) begin
            outputs=outputs+1;
            if(disparity_o!=0) nonzero_winners=nonzero_winners+1;
            if(row_last_o) row_ends=row_ends+1;
        end
        if(PACKED && rn && !fc && !rc && vi && (lw || rw)) begin
            if((wy-yy+K-1+BANKS*H)%BANKS < K)
                $fatal(1,"DATAPATH K=%0d scheduler overwrote active bank",K);
            prefetch_beats=prefetch_beats+1;
            if(ww==xx/4) same_word_prefetch=same_word_prefetch+1;
        end
        cycles=cycles+1;
    end
endtask
task automatic idle(input integer count);
    integer n;
    begin for(n=0;n<count;n=n+1) tick(1,0,0,0,0,K-1,0,0,0,0); end
endtask
task automatic load_row(input integer yy);
    integer w;
    begin
        if(PACKED) for(w=0;w<(W+3)/4;w=w+1) begin
            tick(1,0,0,0,0,K-1,yy,w,1,0);
            tick(1,0,0,0,0,K-1,yy,w,0,1);
        end
    end
endtask
integer f,y,x,n,before_count,expected_count,rows,frame_height;
initial begin
    ignored=$value$plusargs("RANDOM_CYCLES=%d",random_cycles);
    ignored=$value$plusargs("SEED=%d",seed); rng=32'(seed);
    if($test$plusargs("VCD")) begin $dumpfile("waveform.vcd"); $dumpvars(0); end
    for(n=0;n<=DELAY;n=n+1) begin ev[n]=0; ex[n]=0; ey[n]=0; ed[n]=0; ec[n]=0; expected_lanes[n]='0; end
    tick(0,0,0,0,0,K-1,0,0,0,0);
    for(f=0;f<4;f=f+1) begin
        phase=f;
        // One full selected-height frame; three directed single-row patterns.
        frame_height=(f==0 || H<K)?H:K;
        tick(1,1,0,1,0,K-1,0,0,1,1);
        for(y=0;y<K && y<H;y=y+1) load_row(y);
        before_count=outputs;
        for(y=K-1;y<frame_height;y=y+1) begin
            // No between-row reload: the previous scan populated the next row
            // in a spare bank, including its final partial word.
            for(x=0;x<W;x=x+1) begin
                if((next_random()&3)==0) idle(1);
                tick(1,0,0,1,x,y,(y+1<frame_height)?y+1:0,x/4,
                     PACKED && y+1<frame_height && x%4==0,
                     PACKED && y+1<frame_height && x%4==0);
            end
            idle(DELAY);
            tick(1,0,1,0,0,y,0,0,0,0);
        end
        expected_count=((W>=K+T-1)?W-K-T+2:0)*((frame_height>=K)?frame_height-K+1:0);
        if(outputs-before_count!=expected_count)
            $fatal(1,"DATAPATH K=%0d frame=%0d output count got=%0d expected=%0d",K,f,outputs-before_count,expected_count);
        // Abort an outstanding read, reload all rows, then restart from x=0.
        if(H>=K) tick(1,0,0,1,0,K-1,0,0,0,0);
        tick(1,1,0,1,1,K-1,0,0,1,1);
        idle(DELAY+1);
    end
    // Backend border qualification is checked even when columns are supplied
    // for an in-range y that has no complete vertical window.
    if(!PACKED && K>1) begin
        for(x=0;x<W;x=x+1) tick(1,0,0,1,x,0,0,0,0,0);
        idle(DELAY); tick(1,0,1,0,0,0,0,0,0,0);
    end
    // Abort qualified work with both frame-clear and reset, not just warmup.
    phase=0;
    if(H>=K) for(n=0;n<2;n=n+1) begin
        for(y=0;y<K;y=y+1) load_row(y);
        for(x=0;x<W;x=x+1) tick(1,0,0,1,x,K-1,0,0,0,0);
        tick(n==0,n==0,0,1,0,K-1,0,0,1,1);
        idle(DELAY+1);
    end
    // Configurable stress consists of repeated legal complete rows with bubbles.
    phase=0;
    for(y=0;y<K && y<H;y=y+1) load_row(y);
    rows=(random_cycles==0 || H<K)?0:((random_cycles+W-1)/W);
    for(y=0;y<rows;y=y+1) begin
        for(x=0;x<W;x=x+1) begin
            if((next_random()&1)!=0) idle(1);
            tick(1,0,0,1,x,K-1,0,0,0,0);
        end
        idle(DELAY+1); tick(1,0,1,0,0,K-1,0,0,0,0);
    end
    if(W>=K+T-1 && H>=K && outputs==0) $fatal(1,"DATAPATH K=%0d missing output coverage",K);
    if(W>=K+T-1 && H>=K && T>1 && P>=8 && nonzero_winners==0)
        $fatal(1,"DATAPATH K=%0d missing nonzero-disparity coverage",K);
    if(PACKED && H>K && (prefetch_beats==0 || same_word_prefetch==0))
        $fatal(1,"DATAPATH K=%0d missing concurrent spare-row prefetch",K);
    $display("PASS datapath packed=%0d K=%0d P=%0d W=%0d H=%0d T=%0d S=%0d cycles=%0d outputs=%0d nonzero=%0d rowends=%0d prefetch=%0d sameword=%0d",PACKED,K,P,W,H,T,S,cycles,outputs,nonzero_winners,row_ends,prefetch_beats,same_word_prefetch);
    $finish;
end
