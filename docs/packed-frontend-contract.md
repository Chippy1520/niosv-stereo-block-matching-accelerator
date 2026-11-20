# Packed row storage and stereo frontend — datapath contract

[[Project Plan]] · [[Stereo Frontend]] · [[Verification]]

User-approved direction: datapath first; testbenches supply control. Local controllers and a central coordinator follow only after datapath review. No commit/push in this increment.

## Scope and implementation sequence

1. `row_word_bank`: independent synchronous full-word write and read ports; standalone test.
2. `packed_circular_row_buffer`: K active word banks plus SPARE_ROWS prefetch banks, independently addressed loads and vertical-column reads; standalone raw-image test.
3. `stereo_frontend`: two packed row stores plus existing left delay/right column shift and aligned coordinate tags; standalone raw-image/tap test.

The reviewed `row_ram_bank` / `circular_row_buffer` remain a streaming reference for existing tests and lessons. They do not implement the new load/read interface and are not instantiated by the new frontend. This is a replacement datapath, not an additional pipeline buffer.

## Word-bank interface

Parameters `WORD_W=32`, `DEPTH=160`, `ADDR_W=max(1,clog2(DEPTH))`. Ports: `clk`, `write_i`, `write_address_i[ADDR_W]`, `write_data_i[WORD_W]`, `read_i`, `read_address_i[ADDR_W]`, `read_data_o[WORD_W]`.

One enabled write stores one entire word. One enabled read updates its register after the same edge. Independent addresses/enables allow concurrent different-address reads and writes. No RAM or read-register reset. A disabled read holds its output. Same-address concurrent read/write is prohibited by the caller, checked in simulation; no portable collision value is promised. Out-of-range enabled addresses are prohibited. A separate module boundary preserves RAM inference.

## Packed circular-row interface

Parameters `K=11`, `PIXEL_W=8`, `IMG_W=640`, **`SPARE_ROWS=1` (minimum one)**; `ROW_BANKS=K+SPARE_ROWS`. Derived public widths `X_W=max(1,clog2(IMG_W))`, `BANK_W=max(1,clog2(ROW_BANKS))`, `WORD_AW=max(1,clog2(ceil(IMG_W/4)))`. Spare count is an elaboration-time parameter, not a runtime setting. The output remains exactly K pixels wide.

Ports:
- `clk`, synchronous active-low `rst_n`, synchronous `clear_i`.
- `write_valid_i`, `write_bank_i[BANK_W]`, `write_word_i[WORD_AW]`, `write_data_i[4*PIXEL_W]`.
- `read_valid_i`, `read_x_i[X_W]`, `read_oldest_i[BANK_W]`.
- `column_valid_o`, `column_o[K*PIXEL_W]`.

At the production PIXEL_W=8 setting a write is exactly 32 bits / four adjacent pixels. Parameter sweeps may use other pixel widths for verification; that does not change the production bus choice. Pixel `4*w+n` occupies lane `[n*PIXEL_W +: PIXEL_W]` in word w. Depth is ceil(IMG_W/4); padding lanes in the final word are never output.

On an accepted read edge, **only the K active banks** read word floor(x/4); spare banks hold their read registers. Capture x modulo four and the oldest-bank index on that same edge. After the edge, output tap j selects the corresponding lane of bank `(read_oldest+j) modulo ROW_BANKS`; low slice is oldest, high slice is newest. All pixels, including newest, come from stored data: there is no live input bypass. A downstream registered consumer samples on the following edge. Bubbles hold payload and deassert valid; reset/clear zero output visibility, discard simultaneous loads/reads, but do not erase RAM. K=1 still has one active stored row **and at least one spare row**.

No autonomous cursor, warmup counter, ownership FSM, refill policy or safety scheduling is implemented. The caller only asserts read_valid for fully initialized, still-live windows and preserves all K active rows throughout the scan, **including bubbles**. Prefetch writes target spare banks; a read and write may use the **same word address in different banks**. Simulation rejects any write into the current active set during an accepted read, including different-word writes. This local assertion does not track ownership while reads are paused; the caller still owns that obligation. The primitive's same-bank/same-word collision rule is unchanged.

For sequential rows, map logical row r to `r modulo ROW_BANKS`. Once the next row is **fully loaded in both images**, drain/clear the horizontal path and advance oldest modulo ROW_BANKS. The next active window includes the prefetched row; the retired oldest bank becomes spare. No RAM copy occurs. Additional spare banks can retain further future rows. Incomplete prefetch stalls the next row in the caller; no readiness signal or automatic promotion exists. Frame clear invalidates ownership in the caller; stale RAM is not automatically fresh data. This supersedes the earlier K-only, destructive word-refill contract; see [decision and verification](verification/spare-row-prefetch.md).

## Stereo frontend interface

Parameters `K=11`, `PIXEL_W=8`, `IMG_W=640`, `IMG_H=480`, `TAPS=32`, `SPARE_ROWS=1`, derived `X_W`, `Y_W`, `BANK_W`, `WORD_AW`. Pass the same spare count through the complete datapath into both stores.

Ports:
- `clk`, `rst_n`, `frame_clear_i`, `row_clear_i`.
- `left_write_valid_i`, `right_write_valid_i`, shared `write_bank_i[BANK_W]`, `write_word_i[WORD_AW]`, `left_write_data_i[4*PIXEL_W]`, `right_write_data_i[4*PIXEL_W]`.
- Shared `read_valid_i`, `read_x_i[X_W]`, `read_y_i[Y_W]`, `read_oldest_i[BANK_W]`.
- `left_valid_o`, `left_column_o[K*PIXEL_W]`, `right_valid_o[TAPS]`, `right_columns_o[TAPS*K*PIXEL_W]`, `x_o[X_W]`, `y_o[Y_W]`, `row_last_o`.

The testbench/controller starts each output row at x=0, then increments x by **exactly one for every accepted read** through IMG_W-1. Bubbles do not advance x/history. Keep read_y and read_oldest constant throughout that row and clear horizontal history between rows. Merely increasing x is insufficient: the right cache shifts accepted beats, not coordinate distances; skips, duplicates or mid-row starts would invalidate the meaning of tap d. read_y is the bottom-row image coordinate and must be in range; both images' complete window data must already exist. No autonomous coordinate generation, protocol checking or warmup policy is claimed. Derived public widths must be sufficient for their dimensions; overriding Y_W or supplying out-of-range read_y is not validated by the current frontend.

Left/right write enables and data can arrive independently, but **write_bank/write_word are shared**, not two independent write-address interfaces. Differently addressed L/R arrivals must be serialized by the caller. Promote a future row only after every required word is loaded in both images; sharing addresses does not establish paired readiness or relax active-bank ownership.

Read accepted at edge t -> packed row columns after t -> aligned left/right cache outputs and matching tags after t+1 -> downstream samples at t+2. Consecutive reads and arbitrary bubbles are supported. Right tap d represents R[x-d] at the same image y; negative x taps are invalid. Do not mask early columns merely because full horizontal SAD windows are not mature.

Frame clear resets both row-store output visibility, alignment/history and metadata and suppresses writes/reads. Row clear resets only horizontal delay/cache and metadata, suppresses new reads but does not erase row storage; independent loads may continue. For normal row transitions, allow the last row-store column to hand off before row_clear on a separate edge. A simultaneous clear is an abort, not a drain. Later SAD integration retains its additional documented ceil(log2(K))+1 drain edges and separate clear.

## Verification and limits

Independent flat image/word models; directed and randomized reads, loads, holds, reset/clear priority, every lane and whole-ring rotation, non-power-of-two/partial words, K=1 with multiple x and K>1 with IMG_W=1, same-word-address spare prefetch, active-window replay after loading, multiple spare rows, repeated no-copy bank reuse, full-width frames, pairing/taps/tags/row-end consumer-edge checks. Run bank before row before frontend, then complete-path raw-window checks, all regressions and mutations. Require exact full RTL snapshots and code-adjacent explanations. Measure production-width RAM mapping with Quartus Analysis & Synthesis; no fitted timing, SDRAM master, autonomous ownership/controller or board claim.
