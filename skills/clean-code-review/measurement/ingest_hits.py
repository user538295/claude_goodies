#!/usr/bin/env python3
"""Append one collect.sh hits.txt to results/hits.tsv and emit the adjudication sample.

Usage: ingest_hits.py <project> <hits.txt path>
Prints sampled hits (first 15 per check) as TSV: check, line, excerpt.
"""
import os
import re
import sys
from collections import defaultdict

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
SAMPLE_PER_CHECK = 15

project, hits_path = sys.argv[1], sys.argv[2]
rows = []
for raw in open(hits_path):
    raw = raw.rstrip("\n")
    if not raw:
        continue
    check, rest = raw.split("\t", 1)
    m = re.match(r"^\s*(\d+)\s+(/.+)$", rest)  # wc-style file-level hit
    if m:
        rows.append((check, m.group(2), 1, f"file-level: {m.group(1)} lines"))
        continue
    m = re.match(r"^(/[^:]+):(\d+)(?::(.*))?$", rest)
    if m:
        if m.group(3) is None:
            # `file:N` with no excerpt is a count-style file-level hit (clarity-16's
            # branch-keyword count), not a line. Recording it as a line number sends
            # the adjudicator to an unrelated line and breaks the overlap match.
            rows.append((check, m.group(1), 1, f"file-level: {m.group(2)} matches"))
        else:
            rows.append((check, m.group(1), int(m.group(2)), m.group(3).strip()))
        continue
    rows.append((check, rest, 1, "UNPARSED"))

with open(os.path.join(RESULTS, "hits.tsv"), "a") as out:
    for check, fpath, line, excerpt in rows:
        out.write(f"{project}\t{fpath}\t{check}\t{line}\t{excerpt}\n")

seen = defaultdict(int)
for check, fpath, line, excerpt in rows:
    seen[check] += 1
    if seen[check] <= SAMPLE_PER_CHECK:
        print(f"{check}\t{line}\t{excerpt}")
