"""Generate independent deque-reference vectors and exercise real SystemVerilog RTL."""
from collections import deque
from pathlib import Path
import os
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build' / 'legacy-buffer'
BUILD.mkdir(parents=True, exist_ok=True)
(ROOT / 'sim').mkdir(exist_ok=True)
BIN = ROOT / 'tools/mingw64/bin'
os.environ['PATH'] = str(BIN) + os.pathsep + os.environ['PATH']
IVERILOG = shutil.which('iverilog')
VVP = shutil.which('vvp')
if not IVERILOG or not VVP:
    raise SystemExit('Install Icarus Verilog and add iverilog/vvp to PATH.')

TB = '''`timescale 1ns/1ps
module tb;
  localparam K = @K@, P = @P@;
  localparam CW = P + $clog2(K), SW = P + $clog2(K*K);
  reg clk=0;
  always #5 clk=~clk;
  reg rst_n=0, clear_i=0, valid_i=0;
  reg [CW-1:0] column_sum_i=0;
  wire valid_o;
  wire [SW-1:0] sad_o;
  column_sum_buffer #(.K(K), .PIXEL_W(P)) dut(.*);
  integer f, rc, rn, cl, vi, col, ev, es, cycles=0, outputs=0;
  initial begin
    f=$fopen("vectors.txt", "r");
    if (!f) $fatal(1,"Cannot open vectors");
    while (!$feof(f)) begin
      rc=$fscanf(f,"%d %d %d %d %d %d\\n",rn,cl,vi,col,ev,es);
      if (rc != 6) $fatal(1,"Bad vector");
      @(negedge clk);
      rst_n=rn; clear_i=cl; valid_i=vi; column_sum_i=col;
      @(posedge clk); #1;
      if (valid_o !== (ev != 0) || sad_o !== SW'(es))
        $fatal(1,"K=%0d P=%0d cycle=%0d got valid=%b sad=%0d expected valid=%0d sad=%0d",
                 K,P,cycles,valid_o,sad_o,ev,es);
      cycles=cycles+1;
      if (valid_o) outputs=outputs+1;
    end
    $display("PASS K=%0d P=%0d cycles=%0d valid_outputs=%0d",K,P,cycles,outputs);
    $fclose(f); $finish;
  end
endmodule
'''

reports = []
for k, p in [(1,8), (2,8), (3,8), (11,8), (16,8), (11,10)]:
    rng = random.Random(20260922 + k + p)
    limit = k * ((1 << p) - 1)
    inputs = [(0,0,0,0), (0,1,1,limit)]
    # Contiguous maximum columns, wraparound, bubbles, zero windows, clear priority.
    inputs += [(1,0,1,limit)] * (4*k+7)
    inputs += [(1,0,0,limit)] * 3
    inputs += [(1,0,1,0)] * (3*k+2)
    inputs += [(1,1,1,limit)]
    inputs += [(1,0,1,i % (limit+1)) for i in range(3*k+5)]
    inputs += [(1,1,0,0), (1,0,1,limit), (0,0,1,limit)]
    inputs += [(1,0,1,0)] * (k+2)
    for _ in range(5000):
        inputs.append((int(rng.random() > .008), int(rng.random() < .02),
                       int(rng.random() < .77), rng.randint(0,limit)))
    history = deque(maxlen=k)
    last_sad = 0
    vectors = []
    for rn, cl, vi, col in inputs:
        ev = 0
        if not rn or cl:
            history.clear()
            last_sad = 0
        elif vi:
            history.append(col)
            if len(history) == k:
                ev = 1
                last_sad = sum(history)
        vectors.append(f'{rn} {cl} {vi} {col} {ev} {last_sad}\n')
    case = BUILD / f'k{k}_p{p}'
    case.mkdir(exist_ok=True)
    (case/'vectors.txt').write_text(''.join(vectors))
    (case/'tb.sv').write_text(TB.replace('@K@',str(k)).replace('@P@',str(p)))
    for command in [[IVERILOG,'-g2012','-Wall','-s','tb','-o','sim.vvp',
                     str(ROOT/'rtl/column_sum_buffer.sv'),'tb.sv'], [VVP,'sim.vvp']]:
        result = subprocess.run(command,cwd=case,text=True,capture_output=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print(result.stdout + result.stderr,end='')
        reports.append(result.stdout + result.stderr)
(ROOT/'sim/legacy-buffer-results.txt').write_text(''.join(reports))
print('All six configurations passed. Report: sim/legacy-buffer-results.txt')
