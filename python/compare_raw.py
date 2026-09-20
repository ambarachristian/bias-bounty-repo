#!/usr/bin/env python3
"""Full-precision Shapely-vs-DuckDB comparison, straight out of db/<region>.duckdb.

`submissions/zindi-submission-fullprec.csv` is written at 15 decimals, so
comparing against it floors the measurable difference at ~5e-16. This script
dumps the DuckDB `gaps` table at %.17g (round-trippable double) instead, so the
comparison is limited only by the two engines, not by a file format.

    python3 python/compare_raw.py [region ...]
"""
import csv
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGIONS = ["northern-ca", "eastern-ok", "maricopa-az", "south-central-tx"]
TARGET_SSE = 9379 * (3.406e-6) ** 2

INTS = ["bldg_ov", "bldg_ms", "ov_all", "ov_fire", "ov_ems", "ov_school",
        "hf_fire", "hf_ems", "hf_school"]
DBLS = ["tiger_m", "overture_m", "cbp_estab"]
GAPS = ["coverage_gap_score", "transport_gap", "building_gap", "poi_gap"]

SQL = """.bail on
load spatial;
ATTACH 'db/{r}.duckdb' AS d (READ_ONLY);
COPY (SELECT GEOID, {ints}, {dbls}, {gaps}
      FROM d.gaps WHERE GEOID IN (SELECT GEOID FROM d.scored) ORDER BY GEOID)
  TO 'tmp/py/{r}-duckdb-raw.csv' (HEADER);
"""


def dump(region):
    out = os.path.join(ROOT, "tmp", "py", "%s-duckdb-raw.csv" % region)
    if os.path.exists(out):
        return out
    sql = SQL.format(r=region, ints=", ".join(INTS),
                     dbls=", ".join("printf('%%.17g',%s) AS %s" % (c, c) for c in DBLS),
                     gaps=", ".join("printf('%%.17g',coalesce(%s,0)) AS %s" % (c, c)
                                    for c in GAPS))
    subprocess.run([os.path.join(ROOT, "bin", "duckdb")], input=sql, text=True,
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    return out


def main(regions):
    tot_sse = {g: 0.0 for g in GAPS}
    tot_int = {k: 0 for k in INTS}
    tot_n = 0
    worst = {"tiger_m": 0.0, "overture_m": 0.0}
    for region in regions:
        d = {r["GEOID"]: r for r in csv.DictReader(open(dump(region)))}
        s = list(csv.DictReader(open(os.path.join(ROOT, "tmp", "py",
                                                  "%s-shapely.csv" % region))))
        tot_n += len(s)
        bad = {k: sum(1 for r in s if int(r[k]) != int(d[r["GEOID"]][k])) for k in INTS}
        for k in INTS:
            tot_int[k] += bad[k]
        print("\n== %s (%d tracts)" % (region, len(s)))
        print("  integer count mismatches: %s"
              % ("NONE" if not any(bad.values()) else bad))
        for k in DBLS:
            a = np.array([float(r[k]) for r in s])
            b = np.array([float(d[r["GEOID"]][k]) for r in s])
            rel = np.abs(a - b) / np.maximum(np.abs(b), 1e-300)
            if k in worst:
                worst[k] = max(worst[k], rel.max())
            print("  %-11s exact %4d/%-4d  max abs %.3e  max rel %.3e"
                  % (k, int((a == b).sum()), len(a), np.abs(a - b).max(), rel.max()))
        for g in GAPS:
            a = np.array([float(r[g]) for r in s])
            b = np.array([float(d[r["GEOID"]][g]) for r in s])
            sse = float(((a - b) ** 2).sum())
            tot_sse[g] += sse
            print("  %-19s exact %4d/%-4d  SSE %.4e  max|d| %.3e"
                  % (g, int((a == b).sum()), len(a), sse, np.abs(a - b).max()))

    print("\n== TOTAL over %d tracts" % tot_n)
    print("  integer count mismatches across every layer: %d" % sum(tot_int.values()))
    print("  max relative road-length difference: tiger %.3e  overture %.3e"
          % (worst["tiger_m"], worst["overture_m"]))
    for g in GAPS:
        print("  %-19s SSE of change %.6e   = %.3gx the leaderboard budget"
              % (g, tot_sse[g], tot_sse[g] / TARGET_SSE))
    print("  leaderboard budget SSE = %.6e" % TARGET_SSE)


if __name__ == "__main__":
    main(sys.argv[1:] or REGIONS)
