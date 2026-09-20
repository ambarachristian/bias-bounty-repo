#!/usr/bin/env python3
"""Compute one region with Shapely/GEOS and write full-precision per-tract
results to tmp/py/<region>-shapely.csv (scored tracts only, in the region's
sample-submission order).

    python3 python/run_region.py northern-ca
"""
import csv
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from components import ROOT, compute_region, scored_geoids, log  # noqa: E402
from score import score  # noqa: E402

FIELDS = ["coverage_gap_score", "transport_gap", "building_gap", "poi_gap",
          "poi_gap_fire", "poi_gap_ems", "poi_gap_schools", "poi_gap_cbp"]

# transport-undefined counts published by the organisers (data/README.md)
PUBLISHED_UNDEF = {"northern-ca": 218, "eastern-ok": 253,
                   "maricopa-az": 869, "south-central-tx": 1704}


def main(region):
    t0 = time.time()
    comp = compute_region(region)
    s = score(comp)
    idx = {g: i for i, g in enumerate(comp["GEOID"])}
    scored = scored_geoids(region)
    rows = np.array([idx[g] for g in scored])

    undef = int(np.isnan(s["transport_gap"][rows]).sum())
    pub = PUBLISHED_UNDEF[region]
    log("  transport-undefined: %d (published %d) %s"
        % (undef, pub, "OK" if undef == pub else "*** MISMATCH ***"))
    assert not np.isnan(s["coverage_gap_score"][rows]).any(), "tract with no defined component"

    out = os.path.join(ROOT, "tmp", "py", "%s-shapely.csv" % region)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["GEOID"] + FIELDS + [f + "_defined" for f in FIELDS[1:]]
                   + ["tiger_m", "overture_m", "bldg_ov", "bldg_ms", "ov_all",
                      "ov_fire", "ov_ems", "ov_school", "hf_fire", "hf_ems",
                      "hf_school", "cbp_estab", "n_defined"])
        for g in scored:
            i = idx[g]
            vals = [s[f][i] for f in FIELDS]
            w.writerow(
                [g]
                + ["%.17g" % (0.0 if np.isnan(v) else v) for v in vals]
                + [("FALSE" if np.isnan(s[f][i]) else "TRUE") for f in FIELDS[1:]]
                + ["%.17g" % comp["tiger_m"][i], "%.17g" % comp["overture_m"][i],
                   comp["bldg_ov"][i], comp["bldg_ms"][i], comp["ov_all"][i],
                   comp["ov_fire"][i], comp["ov_ems"][i], comp["ov_school"][i],
                   comp["hf_fire"][i], comp["hf_ems"][i], comp["hf_school"][i],
                   "%.17g" % comp["cbp_estab"][i], s["n_defined"][i]])
    log("  wrote %s (%d rows) in %.1fs" % (out, len(scored), time.time() - t0))


if __name__ == "__main__":
    main(sys.argv[1])
