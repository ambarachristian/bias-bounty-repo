#!/usr/bin/env python3
"""Compare the Shapely output against the shipped DuckDB submission.

    python3 python/compare.py [region ...]

Reports, per region and in total: tracts whose coverage_gap_score differs, the
distribution of |difference|, and the SSE of the change. The SSE of change is
directly comparable to the leaderboard budget:

    SSE_total = 9379 * (3.406e-6)^2 = 1.088042e-7

If Shapely-vs-DuckDB lands near that number, the engine hypothesis is live.
If it lands orders of magnitude below it, the engine hypothesis is refuted.
"""
import csv
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_SSE = 9379 * (3.406e-6) ** 2
REGIONS = ["northern-ca", "eastern-ok", "maricopa-az", "south-central-tx"]
COMPS = ["coverage_gap_score", "transport_gap", "building_gap", "poi_gap"]

# organisers' reference means, from data/ZindiSampleSubmission.csv (see ORACLE.md)
REF_MEANS = {"coverage_gap_score": 0.058436, "transport_gap": 0.111771,
             "building_gap": 0.005601, "poi_gap": 0.051414}


def read_duckdb():
    """Full-precision shipped submission, keyed by GEOID."""
    path = os.path.join(ROOT, "submissions", "zindi-submission-fullprec.csv")
    out = {}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            out[r["GEOID"]] = r
    return out


def read_shapely(region):
    path = os.path.join(ROOT, "tmp", "py", "%s-shapely.csv" % region)
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


def main(regions):
    duck = read_duckdb()
    totals = {c: {"sse": 0.0, "ndiff": 0, "maxabs": 0.0} for c in COMPS}
    all_diff = []
    n_rows = 0
    per_region = []

    for region in regions:
        rows = read_shapely(region)
        n_rows += len(rows)
        stats = {}
        for c in COMPS:
            a = np.array([float(r[c]) for r in rows])
            b = np.array([float(duck[r["GEOID"]][c]) for r in rows])
            d = a - b
            stats[c] = {"sse": float((d ** 2).sum()),
                        "ndiff": int((d != 0).sum()),
                        "maxabs": float(np.abs(d).max()),
                        "mean_shapely": float(a.mean()),
                        "mean_duckdb": float(b.mean())}
            totals[c]["sse"] += stats[c]["sse"]
            totals[c]["ndiff"] += stats[c]["ndiff"]
            totals[c]["maxabs"] = max(totals[c]["maxabs"], stats[c]["maxabs"])
            if c == "coverage_gap_score":
                all_diff.append(d)
        # definedness agreement
        flagdiff = sum(1 for r in rows
                       if r["transport_gap_defined"] != duck[r["GEOID"]]["transport_defined"]
                       or r["building_gap_defined"] != duck[r["GEOID"]]["building_defined"]
                       or r["poi_gap_defined"] != duck[r["GEOID"]]["poi_defined"])
        per_region.append((region, len(rows), stats, flagdiff))
        print("\n== %s  (%d tracts)" % (region, len(rows)))
        print("  %-20s %10s %13s %13s" % ("component", "tracts dif", "SSE", "max |diff|"))
        for c in COMPS:
            s = stats[c]
            print("  %-20s %10d %13.6e %13.6e" % (c, s["ndiff"], s["sse"], s["maxabs"]))
        print("  definedness flags differing: %d" % flagdiff)

    print("\n== TOTAL over %d tracts" % n_rows)
    print("  %-20s %10s %13s %13s %10s" % ("component", "tracts dif", "SSE of change",
                                           "max |diff|", "vs budget"))
    for c in COMPS:
        t = totals[c]
        print("  %-20s %10d %13.6e %13.6e %9.3gx"
              % (c, t["ndiff"], t["sse"], t["maxabs"], t["sse"] / TARGET_SSE))
    print("  leaderboard budget SSE  = %.6e  (RMSE 3.406e-6 over 9379 tracts)" % TARGET_SSE)

    d = np.concatenate(all_diff)
    nz = d[d != 0]
    print("\n  coverage_gap_score difference distribution (non-zero only, n=%d):" % len(nz))
    if len(nz):
        for q in (0, 25, 50, 75, 90, 99, 100):
            print("    p%-3d  %+.6e" % (q, np.percentile(np.abs(nz), q)))
        print("    signed mean %+.6e   positive %d   negative %d"
              % (nz.mean(), int((nz > 0).sum()), int((nz < 0).sum())))
        print("    implied RMSE of the change: %.6e" % np.sqrt((d ** 2).sum() / len(d)))

    if len(regions) == len(REGIONS):
        print("\n== four-mean table (all %d scored tracts, undefined counted as 0)" % n_rows)
        print("  %-20s %14s %14s %14s %14s"
              % ("component", "shapely", "duckdb", "organisers", "shapely-org"))
        for c in COMPS:
            sa = np.concatenate([np.array([float(r[c]) for r in read_shapely(g)])
                                 for g in regions])
            sb = np.concatenate([np.array([float(duck[r["GEOID"]][c])
                                           for r in read_shapely(g)]) for g in regions])
            print("  %-20s %14.9f %14.9f %14.6f %+14.3e"
                  % (c, sa.mean(), sb.mean(), REF_MEANS[c], sa.mean() - REF_MEANS[c]))


if __name__ == "__main__":
    main(sys.argv[1:] or REGIONS)
