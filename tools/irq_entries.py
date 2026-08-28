#!/usr/bin/env python3
"""Count interrupt handler entries in an executed-PC trace.

    irq_entries.py TRACE --irq2 001c30 --irq4 001d76 [--max N]

Prints, for each handler address, how many times the trace enters it and
the trace index of the first entry. verif/board/check_m1.sh compares the
counts of MAME's trace and the RTL's over the same span: the interrupts
fire once per frame, so equal counts (within the frame the two runs differ
by) mean the RTL raises them on the same frames. The handler addresses come
from the vector table of each CPU's ROM (vectors 26 and 28).
"""
import argparse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--irq2", required=True)
    ap.add_argument("--irq4", required=True)
    ap.add_argument("--max", type=int, default=0, help="only look at the first N instructions")
    a = ap.parse_args()
    want = {"irq2": a.irq2.lower().zfill(6), "irq4": a.irq4.lower().zfill(6)}
    count = {k: 0 for k in want}
    first = {k: None for k in want}
    n = 0
    with open(a.trace) as f:
        for line in f:
            pc = line.strip()
            for k, v in want.items():
                if pc == v:
                    count[k] += 1
                    if first[k] is None:
                        first[k] = n
            n += 1
            if a.max and n >= a.max:
                break
    for k in want:
        print(f"{k} {want[k]}: {count[k]} entries, first at {first[k]}")


if __name__ == "__main__":
    main()
