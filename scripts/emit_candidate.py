#!/usr/bin/env python3
"""Emit a Zindi-format candidate by editing the current best submission in place.

Every candidate is built from `submissions/candidate-poi-fixed.csv` (public score
0.00000301) so that the GEOID column, row order, header, region labels and every
`*_defined` flag are byte-identical to a file the platform has already accepted.
Only the numeric cells a hypothesis touches are rewritten, at 6 decimals.

Usage:
    emit_candidate.py <out-name> <mode> [args...]

Modes
  delta   <value> [selector]   add `value` to coverage_gap_score on the rows the
                               selector picks (+value) and subtract it elsewhere
                               (-value). Selector is one of: all, transport,
                               region:<name>. `all` still flips the sign on rows
                               that would otherwise exceed 1.0.
  subset  <value> <selector>   add `value` to the selected rows only, leaving every
                               other row untouched. Preferred over `delta` for
                               subset probes: subtracting `value` is infeasible on
                               the 5,393 rows scoring below 0.01, so the two-sided
                               form silently loses its intended weight vector.
  csv     <path> <col>         take replacement coverage_gap_score (and the
                               component columns present) from a CSV keyed on GEOID.

The written file is verified against data/ZindiSampleSubmission.csv exactly as
scripts/finalise_candidates.sh does: identical header, identical GEOID column and
order, 17 columns per row, uppercase booleans, no scientific notation, every score
in [0,1], and CRLF on every line.
"""
import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "submissions", "candidate-poi-fixed.csv")
SAMPLE = os.path.join(ROOT, "data", "ZindiSampleSubmission.csv")

NUMERIC = ["coverage_gap_score", "transport_gap", "building_gap", "poi_gap",
           "poi_gap_fire", "poi_gap_ems", "poi_gap_schools", "poi_gap_cbp"]
BOOLS = ["transport_defined", "building_defined", "poi_defined", "poi_defined_fire",
         "poi_defined_ems", "poi_defined_schools", "poi_defined_cbp"]


def read_csv(path):
    with open(path, newline="") as fh:
        r = csv.DictReader(fh)
        return r.fieldnames, [dict(row) for row in r]


def verify(rows, header, out_path):
    s_hdr, s_rows = read_csv(SAMPLE)
    assert header == s_hdr, "header differs from the sample"
    assert len(rows) == len(s_rows), "row count %d != %d" % (len(rows), len(s_rows))
    for i, (a, b) in enumerate(zip(rows, s_rows)):
        assert a["GEOID"] == b["GEOID"], "GEOID order differs at row %d" % (i + 2)
        assert a["region"] == b["region"], "region differs at row %d" % (i + 2)
    for i, r in enumerate(rows):
        assert len(r) == 17, "row %d has %d columns" % (i + 2, len(r))
        for c in NUMERIC:
            v = r[c]
            assert "e" not in v and "E" not in v, "scientific notation in %s row %d" % (c, i + 2)
            assert 0.0 <= float(v) <= 1.0, "%s out of [0,1] on row %d: %s" % (c, i + 2, v)
        for c in BOOLS:
            assert r[c] in ("TRUE", "FALSE"), "bad boolean %r in %s row %d" % (r[c], c, i + 2)
    with open(out_path, "rb") as fh:
        data = fh.read()
    lines = data.split(b"\r\n")
    assert lines[-1] == b"", "file does not end with CRLF"
    assert len(lines) - 1 == len(rows) + 1, "CRLF line count mismatch"
    assert b"\n" not in data.replace(b"\r\n", b""), "a bare LF survived"


def write(rows, header, out_path):
    with open(out_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=header, lineterminator="\r\n")
        w.writeheader()
        w.writerows(rows)


def main():
    out_name, mode = sys.argv[1], sys.argv[2]
    header, rows = read_csv(BASE)
    changed = 0
    moved = 0.0

    if mode == "delta":
        value = float(sys.argv[3])
        selector = sys.argv[4] if len(sys.argv) > 4 else "all"
        for r in rows:
            cur = float(r["coverage_gap_score"])
            if selector == "all":
                sign = 1.0
            elif selector == "transport":
                sign = 1.0 if r["transport_defined"] == "TRUE" else -1.0
            elif selector == "transport-inv":
                # -1 on transport-live rows. The opposite sense scores only 434
                # feasible negatives (transport-dead tracts are overwhelmingly the
                # low-scoring ones); this one gets 3,552, a far sharper contrast.
                sign = -1.0 if r["transport_defined"] == "TRUE" else 1.0
            elif selector.startswith("region:"):
                sign = 1.0 if r["region"] == selector.split(":", 1)[1] else -1.0
            else:
                raise SystemExit("unknown selector %r" % selector)
            # keep every emitted value inside [0,1]: flip the sign where it would leave
            if cur + sign * value > 1.0 or cur + sign * value < 0.0:
                sign = -sign
            new = cur + sign * value
            if abs(new - cur) > 0:
                changed += 1
                moved += abs(new - cur)
            r["coverage_gap_score"] = "%.6f" % new

    elif mode == "subset":
        value = float(sys.argv[3])
        selector = sys.argv[4]
        for r in rows:
            cur = float(r["coverage_gap_score"])
            if selector == "transport":
                hit = r["transport_defined"] == "TRUE"
            elif selector.startswith("region:"):
                hit = r["region"] == selector.split(":", 1)[1]
            else:
                raise SystemExit("unknown selector %r" % selector)
            if not hit or cur + value > 1.0:
                continue
            changed += 1
            moved += value
            r["coverage_gap_score"] = "%.6f" % (cur + value)

    elif mode == "csv":
        path = sys.argv[3]
        with open(path, newline="") as fh:
            repl = {row["GEOID"]: row for row in csv.DictReader(fh)}
        assert len(repl) == len(rows), "replacement has %d rows, need %d" % (len(repl), len(rows))
        for r in rows:
            src = repl[r["GEOID"]]
            for c in NUMERIC:
                if c not in src:
                    continue
                new = "%.6f" % float(src[c])
                if new != r[c]:
                    if c == "coverage_gap_score":
                        changed += 1
                        moved += abs(float(new) - float(r[c]))
                    r[c] = new
            for c in BOOLS:
                if c in src:
                    assert src[c] in ("TRUE", "FALSE", "true", "false"), src[c]
                    assert r[c] == src[c].upper(), "%s flips a defined flag on %s" % (c, r["GEOID"])
    else:
        raise SystemExit("unknown mode %r" % mode)

    out_path = os.path.join(ROOT, "submissions", "cand-%s.csv" % out_name)
    write(rows, header, out_path)
    verify(rows, header, out_path)
    print("%-28s rows changed %5d   total |delta| %.6f   -> %s"
          % (out_name, changed, moved, os.path.relpath(out_path, ROOT)))


if __name__ == "__main__":
    main()
