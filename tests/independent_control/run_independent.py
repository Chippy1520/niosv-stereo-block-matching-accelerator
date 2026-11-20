#!/usr/bin/env python3
"""Independent public-port replay authoring/runner; Python standard library only.

This file never imports another project script or reads an RTL body. RTL is only
passed, by explicit filename, to the compiler when --generate-only is absent.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = (
    'row_word_bank.sv', 'packed_circular_row_buffer.sv', 'left_column_delay.sv',
    'right_column_shift.sv', 'stereo_frontend.sv', 'column_sad.sv',
    'column_sum_buffer.sv', 'sad_engine.sv', 'comparator_tree.sv',
    'sad_search_backend.sv', 'stereo_sad_datapath.sv',
)


def clog(n: int) -> int:
    return (n - 1).bit_length()


@dataclass(frozen=True)
class Case:
    name: str
    k: int
    p: int
    w: int
    h: int
    lanes: int
    spare: int

    @property
    def latency(self) -> int:
        return 2 + clog(self.k) + 1 + max(1, clog(self.lanes))

    @property
    def mature(self) -> int:
        return self.k + self.lanes - 2

    @property
    def banks(self) -> int:
        return self.k + self.spare

    @property
    def words(self) -> int:
        return (self.w + 3) // 4

    def validate(self) -> None:
        assert min(self.k, self.p, self.w, self.h, self.lanes, self.spare) > 0
        assert self.h >= self.k and self.w > self.mature
        assert self.p + clog(self.k * self.k) + max(1, clog(self.lanes)) <= 31


DEFAULTS = (
    Case('one_lane_k1', 1, 5, 9, 5, 1, 2),
    Case('odd_k_lane_bank', 3, 8, 17, 9, 3, 2),
    Case('power_lane_reuse', 2, 4, 13, 7, 4, 1),
)


def costs(left: list[list[int]], right: list[list[int]], c: Case,
          x: int, y: int) -> list[int]:
    """Literal full-image raw-pixel definition, not a rolling hardware model."""
    assert x >= c.mature and y >= c.k - 1
    return [sum(abs(left[y - dy][x - dx] - right[y - dy][x - dx - d])
                for dy in range(c.k) for dx in range(c.k))
            for d in range(c.lanes)]


def winner(left: list[list[int]], right: list[list[int]], c: Case,
           x: int, y: int) -> tuple[int, int]:
    values = costs(left, right, c, x, y)
    d = min(range(c.lanes), key=lambda d: (values[d], d))
    return values[d], d


def images(c: Case, style: str, seed: int) -> tuple[list[list[int]], list[list[int]]]:
    rng = random.Random(seed)
    top = (1 << c.p) - 1
    right = [[rng.randrange(top + 1) for _ in range(c.w)] for _ in range(c.h)]
    if style == 'shift':
        shift = c.lanes - 1
        left = [[right[y][x - shift] if x >= shift else rng.randrange(top + 1)
                 for x in range(c.w)] for y in range(c.h)]
    elif style == 'extreme_tie':
        left = [[top] * c.w for _ in range(c.h)]
        right = [[0] * c.w for _ in range(c.h)]
    elif style == 'independent':
        left = [[rng.randrange(top + 1) for _ in range(c.w)] for _ in range(c.h)]
    else:
        raise ValueError(style)
    return left, right


class Replay:
    def __init__(self, c: Case, seed: int):
        self.c = c
        self.rng = random.Random(seed)
        self.events: list[list[int]] = []
        self.labels: list[str] = []
        self.pending: dict[int, list[int]] = {}
        self.frames: list[dict] = []
        self.left: list[list[int]] = []
        self.right: list[list[int]] = []
        self.ready: dict[int, tuple[int, set[int], set[int]]] = {}
        self.active: set[int] = set()
        self.next_x = 0
        self.read_y: int | None = None
        self.read_oldest = 0
        self.stats = dict(reads=0, mature=0, bubbles=0, concurrent_spare=0,
                          left_only=0, right_only=0, same_word_other_bank=0,
                          reset_aborts=0, frame_aborts=0, normal_clears=0)

    def emit(self, *, rst=1, frame=0, row=0, write=None, read=None,
             label='idle') -> None:
        c = self.c
        t = len(self.events)
        # rst frame row Lvalid Rvalid bank word Ldata Rdata read x y oldest
        inp = [rst, frame, row, 0, 0, 0, 0, 0, 0, 0,
               self.rng.randrange(c.w), self.read_y or 0, self.read_oldest]
        if read is not None:
            inp[9:13] = [1, *read]
        if write is not None:
            r, word, lv, rv = write
            mask = (1 << (4 * c.p)) - 1
            # Inactive buses must not silently supply the intended stored word.
            inp[3:9] = [lv, rv, r % c.banks, word,
                        self.pack(self.left[r], word, 1) ^ (0 if lv else mask),
                        self.pack(self.right[r], word, 2) ^ (0 if rv else mask)]
        if not rst or frame or row:
            self.pending.clear()
            self.active.clear()
            self.read_y = None
            self.next_x = 0
            if not rst or frame:
                self.ready.clear()
        if rst and not frame and write is not None:
            r, word, lv, rv = write
            bank = r % c.banks
            protected = self.active
            if read is not None and not row:
                ry = read[1]
                protected = {(ry - dy) % c.banks for dy in range(c.k)}
            assert bank not in protected, 'caller wrote active bank (including bubble)'
            if bank not in self.ready or self.ready[bank][0] != r:
                self.ready[bank] = (r, set(), set())
            _, ls, rs = self.ready[bank]
            if lv:
                ls.add(word)
            if rv:
                rs.add(word)
            self.stats['left_only'] += bool(lv and not rv)
            self.stats['right_only'] += bool(rv and not lv)
            if protected:
                self.stats['concurrent_spare'] += 1
                self.stats['same_word_other_bank'] += bool(
                    read is not None and word == read[0] // 4)
        if rst and not frame and not row and read is not None:
            x, y, oldest = read
            assert x == self.next_x and oldest == (y - c.k + 1) % c.banks
            if self.read_y is None:
                assert x == 0
                self.read_y = y
                self.read_oldest = oldest
                self.active = {(y - dy) % c.banks for dy in range(c.k)}
                for r in range(y - c.k + 1, y + 1):
                    owner, ls, rs = self.ready[r % c.banks]
                    assert owner == r and len(ls) == c.words and len(rs) == c.words
            assert y == self.read_y and oldest == self.read_oldest
            self.next_x += 1
            self.stats['reads'] += 1
            kind = 2 if x >= c.mature else 1
            cost, disp = winner(self.left, self.right, c, x, y) if kind == 2 else (0, 0)
            self.stats['mature'] += kind == 2
            assert t + c.latency not in self.pending
            self.pending[t + c.latency] = [kind, cost, disp, x, y, int(x == c.w - 1)]
        elif rst and not frame and not row and self.active:
            self.stats['bubbles'] += 1
        expected = self.pending.pop(t, [0, 0, 0, 0, 0, 0])
        self.events.append(inp + expected)
        self.labels.append(label)

    def pack(self, pixels: list[int], word: int, salt: int) -> int:
        # Poison padding independently of image values; LSB pixel is first.
        top = (1 << self.c.p) - 1
        return sum((pixels[4 * word + lane] if 4 * word + lane < self.c.w
                    else ((top - lane - salt) & top)) << (lane * self.c.p)
                   for lane in range(4))

    def writes(self, r: int) -> list[tuple[int, int, int, int]]:
        # Deliberately do not make L/R readiness atomic. Word zero splits first.
        ops = [(r, 0, 1, 0), (r, 0, 0, 1)]
        for w in range(1, self.c.words):
            if w % 3 == 2:
                ops.append((r, w, 1, 1))
            elif w % 2:
                ops.extend([(r, w, 0, 1), (r, w, 1, 0)])
            else:
                ops.extend([(r, w, 1, 0), (r, w, 0, 1)])
        return ops

    def load(self, r: int) -> None:
        for op in self.writes(r):
            if self.rng.randrange(4) == 0:
                self.emit(label='write gap')
            self.emit(write=op, label=f'load logical row {r}')

    def start_frame(self, style: str, seed: int) -> None:
        self.left, self.right = images(self.c, style, seed)
        self.frames.append(dict(style=style, seed=seed, edge=len(self.events),
                                left=self.left, right=self.right))
        # Suppressed simultaneous read/write: ownership must be rebuilt afterward.
        self.emit(frame=1, write=(0, 0, 1, 1), read=(0, self.c.k - 1, 0),
                  label='frame clear with suppressed read and load')
        for r in range(self.c.k):
            self.load(r)
        self.emit(row=1, read=(0, self.c.k - 1, 0),
                  label='row clear suppresses read; preserves loaded RAM')

    def drain_clear(self) -> None:
        assert self.next_x == self.c.w
        # LAT+2 idle edges: registered visibility AND next-edge consumer precede clear.
        for _ in range(self.c.latency + 2):
            self.emit(label='normal drain / consumer')
        assert not self.pending
        self.emit(row=1, read=(0, self.read_y, self.read_oldest),
                  label='separate row clear with suppressed read')
        self.stats['normal_clears'] += 1

    def row(self, y: int, *, prefetch=False) -> None:
        oldest = (y - self.c.k + 1) % self.c.banks
        work = self.writes(y + 1) if prefetch else []
        for x in range(self.c.w):
            # Bubble x payload is arbitrary, but row y/oldest remain fixed.
            # Set fixed row context before the first accepted read too.
            self.read_oldest = oldest
            if self.read_y is None:
                assert x == 0
            if x and (x % 4 == 1 or self.rng.randrange(5) == 0):
                for _ in range(1 + (x % 3 == 1)):
                    self.emit(write=work.pop(0) if work else None, label='read bubble / optional spare load')
            self.emit(read=(x, y, oldest), write=work.pop(0) if work else None,
                      label='accepted raw pixel / optional spare prefetch')
        for op in work:
            self.emit(write=op, label='finish spare L/R readiness before advancing')
        self.drain_clear()

    def build(self) -> None:
        self.emit(rst=0, label='initial synchronous reset')
        self.emit(rst=0, label='held reset')
        for f, style in enumerate(('shift', 'extreme_tie', 'independent')):
            self.start_frame(style, 4100 + f)
            for y in range(self.c.k - 1, self.c.h):
                # Repeat first row after a separate clear to test horizontal restart
                # and RAM preservation without any intervening reload.
                if y == self.c.k - 1:
                    self.row(y)
                self.row(y, prefetch=y + 1 < self.c.h)
        for abort in ('reset', 'frame'):
            for phase in sorted({0, self.c.latency // 2, self.c.latency - 1}):
                self.start_frame('shift', 5300 + phase + (100 if abort == 'reset' else 0))
                y = self.c.k - 1
                stop = min(self.c.w - 1, self.c.mature + 2)
                for x in range(stop + 1):
                    if x and x % 3 == 0:
                        self.emit(label='bubble in soon-aborted row')
                    self.emit(read=(x, y, 0), label='accepted before abort')
                for _ in range(phase):
                    self.emit(label='abort phase offset')
                assert self.pending, 'abort must actually strike pending work'
                if abort == 'reset':
                    self.emit(rst=0, read=(0, y, 0), label='busy synchronous reset')
                    self.stats['reset_aborts'] += 1
                else:
                    self.emit(frame=1, write=(0, 0, 1, 1),
                              read=(0, y, 0), label='busy frame clear')
                    self.stats['frame_aborts'] += 1
                for _ in range(self.c.latency + 2):
                    self.emit(label='no aborted winner may leak')
                # New pixels, full reinitialization, then immediate successful restart.
                self.left, self.right = images(self.c, 'independent', 6400 + phase)
                self.frames.append(dict(style='restart_independent', seed=6400 + phase,
                                        edge=len(self.events), left=self.left, right=self.right))
                for r in range(self.c.k):
                    self.load(r)
                self.emit(row=1, label='restart horizontal clear')
                self.row(y)
        for _ in range(self.c.latency + 3):
            self.emit(label='final quiet tail')
        assert not self.pending
        assert self.stats['left_only'] and self.stats['right_only']
        if self.c.h > self.c.k:
            assert self.stats['same_word_other_bank']
        assert self.stats['bubbles']
        assert self.stats['reset_aborts'] and self.stats['frame_aborts']
        if self.c in DEFAULTS and self.c.lanes > 1:
            assert any(e[13] == 2 and e[15] > 0 for e in self.events)
        assert any(e[13] == 2 and e[14] == self.c.k**2 * ((1 << self.c.p) - 1)
                   and e[15] == 0 for e in self.events)


def self_check() -> None:
    # All validity combinations, full/partial words, and the minimum pixel width.
    for p in (1, 5):
        c = Case('inactive_payload', 1, p, 5, 1, 1, 1)
        top, mask = (1 << p) - 1, (1 << (4 * p)) - 1
        for lv, rv in ((0, 0), (0, 1), (1, 0), (1, 1)):
            replay = Replay(c, 1729)
            replay.left, replay.right = [[0, top, 0, top, top]], [[top, 0, top, 0, 0]]
            rng = random.Random(1729)
            for word in (0, 1):
                replay.emit(write=(0, word, lv, rv))
                assert replay.events[-1][10] == rng.randrange(c.w)
                for data, valid, pixels, salt in (
                        (replay.events[-1][7], lv, replay.left[0], 1),
                        (replay.events[-1][8], rv, replay.right[0], 2)):
                    packed = replay.pack(pixels, word, salt)
                    assert 0 <= data <= mask
                    assert data == (packed if valid else packed ^ mask)
                    assert (data == packed) == bool(valid)
            replay.emit()
            assert replay.events[-1][7:9] == [0, 0]
            assert replay.events[-1][10] == rng.randrange(c.w)
            assert replay.rng.getstate() == rng.getstate()
    c = Case('hand', 1, 3, 5, 1, 3, 1)
    l, r = [[7, 2, 5, 2, 0]], [[7, 2, 5, 2, 0]]
    assert costs(l, r, c, 3, 0) == [0, 3, 0]
    assert winner(l, r, c, 3, 0) == (0, 0)
    c = Case('max', 2, 4, 7, 3, 3, 1)
    assert winner([[15]*7 for _ in range(3)], [[0]*7 for _ in range(3)], c, 5, 2) == (60, 0)
    for c in DEFAULTS:
        c.validate()
        for style in ('shift', 'extreme_tie', 'independent'):
            l, r = images(c, style, 9182)
            for y in range(c.k - 1, c.h):
                for x in range(c.mature, c.w):
                    # Alternative whole-window traversal, deliberately no dx/dy order.
                    alt = [sum(abs(l[yy][xx] - r[yy][xx-d])
                               for yy in range(y-c.k+1, y+1)
                               for xx in range(x-c.k+1, x+1))
                           for d in range(c.lanes)]
                    assert alt == costs(l, r, c, x, y)
                    value, d = winner(l, r, c, x, y)
                    assert value == min(alt) and d == alt.index(min(alt))
                    if style == 'shift':
                        assert value == 0
                    if style == 'extreme_tie':
                        assert (value, d) == (c.k*c.k*((1 << c.p)-1), 0)
    print('PYTHON_ORACLE_SELF_CHECK_PASS', flush=True)


def execute(cmd: list[str], folder: Path, log: Path) -> None:
    result = subprocess.run(cmd, cwd=folder, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    log.write_text(result.stdout, encoding='utf-8')
    print(result.stdout, end='')
    if result.returncode:
        raise RuntimeError(f'command exit {result.returncode}; see {log}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rtl-dir', type=Path, default=ROOT/'rtl')
    parser.add_argument('--out-dir', type=Path, default=ROOT/'build'/'independent_control')
    parser.add_argument('--iverilog', type=Path, default=ROOT/'tools'/'mingw64'/'bin'/'iverilog.exe')
    parser.add_argument('--vvp', type=Path, default=ROOT/'tools'/'mingw64'/'bin'/'vvp.exe')
    parser.add_argument('--generate-only', action='store_true', help='never compile or execute RTL')
    parser.add_argument('--self-check', action='store_true', help='check Python oracle before generation/run')
    parser.add_argument('--case', action='append', choices=[c.name for c in DEFAULTS])
    parser.add_argument('--params', metavar='K,P,W,H,LANES,SPARE',
                        help='run one custom case instead of defaults')
    args = parser.parse_args()
    out = args.out_dir.resolve()
    if not out.is_relative_to((ROOT/'build').resolve()):
        parser.error('--out-dir must be inside this repository build/ directory')
    if args.params and args.case:
        parser.error('--params and --case are mutually exclusive')
    if args.params:
        try:
            values = [int(v) for v in args.params.split(',')]
            if len(values) != 6:
                raise ValueError('six positive integers required')
            selected = [Case('custom', *values)]
        except ValueError as exc:
            parser.error(str(exc))
    else:
        selected = [c for c in DEFAULTS if not args.case or c.name in args.case]
    if args.self_check:
        self_check()
    summary = []
    for c in selected:
        c.validate()
        replay = Replay(c, 202701 + c.k*37 + c.lanes)
        replay.build()
        folder = out/c.name
        folder.mkdir(parents=True, exist_ok=True)
        vector = folder/'vectors.hex'
        vector.write_text(''.join(' '.join(format(v, 'x') for v in row)+'\n'
                                  for row in replay.events), encoding='ascii')
        manifest = dict(parameters=asdict(c), latency=c.latency, mature_x=c.mature,
                        events=len(replay.events), coverage=replay.stats,
                        expected_visible_mature=sum(row[13] == 2 for row in replay.events),
                        frames=replay.frames, edge_labels=replay.labels)
        (folder/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
        compile_cmd = [str(args.iverilog.resolve()), '-g2012', '-s', 'tb_independent_replay',
                       '-o', str(folder/'sim.vvp')]
        for key, val in dict(K=c.k, PIXEL_W=c.p, IMG_W=c.w, IMG_H=c.h,
                             LANES=c.lanes, SPARE_ROWS=c.spare).items():
            compile_cmd += ['-P', f'tb_independent_replay.{key}={val}']
        compile_cmd += [str(args.rtl_dir.resolve()/name) for name in SOURCES]
        compile_cmd += [str(Path(__file__).with_name('tb_independent_replay.sv'))]
        run_cmd = [str(args.vvp.resolve()), str(folder/'sim.vvp'),
                   '+VECTORS='+str(vector), '+OBSERVED='+str(folder/'observed.csv')]
        (folder/'commands.json').write_text(json.dumps(dict(compile=compile_cmd, run=run_cmd), indent=2)+'\n', encoding='utf-8')
        entry = dict(case=c.name, edges=len(replay.events), status='GENERATED_NOT_SIMULATED')
        print(f'{c.name}: generated {len(replay.events)} edges, '
              f'{manifest["expected_visible_mature"]} mature expectations; {folder}', flush=True)
        if not args.generate_only:
            execute(compile_cmd, ROOT, folder/'compile.log')
            execute(run_cmd, ROOT, folder/'simulation.log')
            text = (folder/'simulation.log').read_text(encoding='utf-8')
            if 'INDEPENDENT_PASS ' not in text:
                raise RuntimeError('simulation exited without explicit pass marker')
            entry['status'] = 'SIMULATED_PASS'
        summary.append(entry)
    (out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
