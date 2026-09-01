#!/usr/bin/env python3
"""Summarise UI-thread (build) and raster-thread frame timing from a raw
Dart VM Service timeline export (GET .../getVMTimeline).

Usage:
    curl -s "$VM_SERVICE_URI/getVMTimeline" -o timeline.json
    python3 mobile/scripts/analyze_frame_timeline.py timeline.json [--from SECONDS --to SECONDS]

Without --from/--to, the whole trace is summarised. To isolate a specific
interaction (e.g. a scroll session), find the idle gaps between frames
(printed with --gaps) and pass the window's bounds explicitly: frames are
only emitted while something is actually rebuilding/repainting, so real
user interaction shows up as a dense cluster surrounded by gaps.
"""
import argparse
import json
import sys

JANK_MS = 1000 / 60  # 16.67ms: a frame missing the 60Hz vsync budget
SEVERE_JANK_MS = 2 * JANK_MS


def build_durations(events):
    starts = {}
    durs = []
    for e in events:
        if e.get("name") != "Frame":
            continue
        if e.get("ph") == "b":
            starts[e["id"]] = e["ts"]
        elif e.get("ph") == "e":
            s = starts.pop(e["id"], None)
            if s is not None:
                durs.append((s, e["ts"] - s))
    return sorted(durs)


def raster_durations(events):
    stacks = {}
    durs = []
    for e in events:
        if e.get("name") != "GPURasterizer::Draw":
            continue
        tid = e["tid"]
        if e.get("ph") == "B":
            stacks.setdefault(tid, []).append(e["ts"])
        elif e.get("ph") == "E":
            st = stacks.get(tid)
            if st:
                s = st.pop()
                durs.append((s, e["ts"] - s))
    return sorted(durs)


def summarize(name, durs_us, lo_us, hi_us):
    sel = [d for s, d in durs_us if lo_us <= s <= hi_us]
    ms = sorted(x / 1000.0 for x in sel)
    n = len(ms)
    print(f"--- {name} ---")
    if n == 0:
        print("no frames in this window")
        return
    avg = sum(ms) / n

    def pct(p):
        # Nearest-rank on a 0-indexed, already-sorted list: p=0 -> first
        # element, p=1 -> last. `int(n * p)` is off by one at the top end
        # (e.g. n=10, p=0.9 -> index 9, the max, not the 90th percentile).
        idx = round(p * (n - 1))
        return ms[min(n - 1, max(0, idx))]

    jank = sum(1 for x in ms if x > JANK_MS)
    severe = sum(1 for x in ms if x > SEVERE_JANK_MS)
    print(f"frames: {n}")
    print(f"avg: {avg:.2f} ms (effective {1000/avg:.1f} fps)")
    print(f"p50: {pct(0.5):.2f} ms  p90: {pct(0.9):.2f} ms  p99: {pct(0.99):.2f} ms  max: {ms[-1]:.2f} ms")
    print(f"jank frames (>{JANK_MS:.2f} ms): {jank} ({jank/n*100:.1f}%)")
    print(f"severe jank (>{SEVERE_JANK_MS:.2f} ms): {severe} ({severe/n*100:.1f}%)")


def print_gaps(durs, threshold_s=1.0):
    prev = None
    for i, (s, d) in enumerate(durs):
        ts_s = s / 1e6
        gap = (s - prev) / 1e6 if prev else 0
        if gap > threshold_s:
            print(f"frame {i:4d}  t={ts_s:12.3f}s  gap={gap:7.3f}s  dur={d/1000:6.2f}ms")
        prev = s


def main():
    p = argparse.ArgumentParser()
    p.add_argument("timeline_json")
    p.add_argument("--from", dest="lo", type=float, default=None, help="window start, seconds (raw ts/1e6)")
    p.add_argument("--to", dest="hi", type=float, default=None, help="window end, seconds (raw ts/1e6)")
    p.add_argument("--gaps", action="store_true", help="print idle gaps between build frames instead of stats")
    args = p.parse_args()

    with open(args.timeline_json) as f:
        data = json.load(f)
    events = data["result"]["traceEvents"]

    bd = build_durations(events)
    rd = raster_durations(events)

    if args.gaps:
        print("Idle gaps between UI-thread frames (use these to find a clean interaction window):")
        print_gaps(bd)
        return

    all_ts = [s for s, _ in bd] + [s for s, _ in rd]
    lo_us = args.lo * 1e6 if args.lo is not None else min(all_ts)
    hi_us = args.hi * 1e6 if args.hi is not None else max(all_ts)

    summarize("UI thread (build)", bd, lo_us, hi_us)
    summarize("Raster thread", rd, lo_us, hi_us)


if __name__ == "__main__":
    sys.exit(main())
