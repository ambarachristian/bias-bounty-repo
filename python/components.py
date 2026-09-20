"""Per-tract component counts and lengths, computed with Shapely/GEOS.

This mirrors sql/01..06 exactly. Read those first; every deviation here would
be a bug, not an improvement. The point of the exercise is to hold the METHOD
fixed and swap only the geometry engine (DuckDB spatial -> GEOS via Shapely),
to test whether the 3.406e-6 leaderboard residual is engine divergence.

Method, per sql/03_roads.sql:
  * project every road segment to EPSG:5070, project every tract to EPSG:5070,
  * if the projected tract COVERS the projected segment, take the whole length,
    else take the length of the intersection (linear parts only).
  That is V0 in NOTES.md, the shipped reading. (NOTES V2 -- clip in lon/lat,
  then project -- was measured at 227,000x the error budget and is refuted;
  the task brief's description of the clip order is mistaken.)

Point layers (buildings, POIs, facilities) are assigned in lon/lat, per
sql/04 and sql/05.
"""
import csv
import os
import sys

import numpy as np
import pyarrow.parquet as pq
import shapely
from shapely import STRtree

from geo import row_groups, to_5070, wkb_to_geoms

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HWY_OVERTURE = {"motorway", "trunk", "primary", "secondary"}
HWY_TIGER = {"S1100", "S1200"}
SCHOOL_CATS = {
    "elementary_school", "middle_school", "high_school",
    "school", "private_school", "public_school",
}
FIRE_CAT = "fire_department"
EMS_CAT = "ambulance_and_ems_services"

# Row groups per read. Buildings are the memory driver: south-central-tx's
# Overture layer is 1.27 GB, so take one group at a time.
RG_BATCH = 1


def ref(region, name):
    return os.path.join(ROOT, "data", "reference", region, "%s-%s.parquet" % (region, name))


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def load_tracts(region):
    path = os.path.join(ROOT, "data", "strata", region, "%s-census-tracts.parquet" % region)
    t = pq.read_table(path, columns=["GEOID", "geometry"])
    geoids = t.column("GEOID").to_pylist()
    ll = wkb_to_geoms(t.column("geometry"))             # lon/lat, kept as-is
    proj = to_5070(wkb_to_geoms(t.column("geometry")))  # separate parse, mutated in place
    assert all(len(g) == 11 for g in geoids), "GEOID width"
    assert len(set(geoids)) == len(geoids), "duplicate GEOID"
    return geoids, ll, proj


def scored_geoids(region):
    path = os.path.join(ROOT, "data", "reference", region, "%s-sample-submission.csv" % region)
    with open(path, newline="") as fh:
        return [r["GEOID"] for r in csv.DictReader(fh)]


# --------------------------------------------------------------------------
# roads


def road_length(region, layer, col, keep, tree, tracts_proj, n_tracts):
    """Clipped highway length per tract index, EPSG:5070 metres."""
    out = np.zeros(n_tracts, dtype=float)
    n_seg = 0
    for tb in row_groups(ref(region, layer), [col, "geometry"], RG_BATCH):
        cls = tb.column(col).to_pylist()
        sel = np.fromiter((c in keep for c in cls), dtype=bool, count=len(cls))
        if not sel.any():
            continue
        geoms = to_5070(wkb_to_geoms(tb.column("geometry"))[sel])
        n_seg += len(geoms)
        # exact predicate, same join condition as DuckDB's ST_Intersects
        si, ti = tree.query(geoms, predicate="intersects")
        if len(si) == 0:
            continue
        segs = geoms[si]
        trs = tracts_proj[ti]
        covered = shapely.covered_by(segs, trs)
        lens = np.empty(len(segs), dtype=float)
        lens[covered] = shapely.length(segs[covered])
        nc = ~covered
        if nc.any():
            # ST_CollectionExtract(..., 2) then ST_Length: point parts of a
            # line/polygon overlay carry zero length, so plain length matches.
            lens[nc] = shapely.length(shapely.intersection(segs[nc], trs[nc]))
        assert np.isfinite(lens).all(), "non-finite road length"
        np.add.at(out, ti, lens)
    return out, n_seg


# --------------------------------------------------------------------------
# point layers
#
# Mirrors DuckDB's `JOIN tracts t ON ST_Intersects(t.g, p.g)`: a point on a
# shared edge matches BOTH tracts. sql/05 de-duplicates POIs by id keeping the
# lowest GEOID (DISTINCT ON ... ORDER BY p.id, t.GEOID); sql/04 and the hifld
# join do not de-duplicate.


def scan_points(region, layer, tree, on_hits, extra_cols=()):
    """Stream a point layer, calling on_hits(point_idx, tract_idx, payloads)
    once per row group. `payloads` are python lists for the whole batch."""
    cols = list(extra_cols) + ["geometry"]
    n_rows = n_hits = 0
    for tb in row_groups(ref(region, layer), cols, RG_BATCH):
        pts = wkb_to_geoms(tb.column("geometry"))
        n_rows += len(pts)
        pi, ti = tree.query(pts, predicate="intersects")
        n_hits += len(pi)
        on_hits(pi, ti, [tb.column(c).to_pylist() for c in extra_cols])
    return n_rows, n_hits


def centroid_counts(region, layer, tree, n_tracts):
    """Building count per tract, assigned by lon/lat centroid (sql/04)."""
    out = np.zeros(n_tracts, dtype=np.int64)
    n_rows = n_hits = 0
    for tb in row_groups(ref(region, layer), ["geometry"], RG_BATCH):
        g = wkb_to_geoms(tb.column("geometry"))
        n_rows += len(g)
        c = shapely.centroid(g)
        del g
        _pi, ti = tree.query(c, predicate="intersects")
        n_hits += len(ti)
        if len(ti):
            np.add.at(out, ti, 1)
        del c
    return out, n_rows, n_hits


# --------------------------------------------------------------------------


def compute_region(region):
    log("=== %s" % region)
    geoids, tracts_ll, tracts_proj = load_tracts(region)
    n = len(geoids)
    idx = {g: i for i, g in enumerate(geoids)}
    tree_ll = STRtree(tracts_ll)
    tree_proj = STRtree(tracts_proj)

    tiger_m, n_tiger = road_length(region, "census-tiger-roads", "MTFCC", HWY_TIGER,
                                   tree_proj, tracts_proj, n)
    overture_m, n_ov = road_length(region, "overture-roads", "class", HWY_OVERTURE,
                                   tree_proj, tracts_proj, n)
    log("  roads: %d tiger hwy, %d overture hwy segments" % (n_tiger, n_ov))

    bldg_ov, ov_rows, ov_hits = centroid_counts(region, "overture-buildings", tree_ll, n)
    log("  overture buildings: %d rows -> %d assigned" % (ov_rows, ov_hits))
    bldg_ms, ms_rows, ms_hits = centroid_counts(region, "microsoft-buildings", tree_ll, n)
    log("  microsoft buildings: %d rows -> %d assigned" % (ms_rows, ms_hits))

    # POIs: keep one row per id, lowest GEOID
    best = {}

    def poi_hits(pi, ti, payloads):
        ids, cats = payloads
        for k in range(len(pi)):
            pid = ids[pi[k]]
            g = geoids[ti[k]]
            prev = best.get(pid)
            if prev is None or g < prev[0]:
                c = cats[pi[k]]
                best[pid] = (g, c["primary"] if c else None)

    poi_rows, _ = scan_points(region, "overture-pois", tree_ll, poi_hits,
                              extra_cols=["id", "categories"])
    assert len(best) == poi_rows, "POI assignment mismatch: %d of %d" % (len(best), poi_rows)

    ov_all = np.zeros(n, dtype=np.int64)
    ov_fire = np.zeros(n, dtype=np.int64)
    ov_ems = np.zeros(n, dtype=np.int64)
    ov_school = np.zeros(n, dtype=np.int64)
    for g, cat in best.values():
        i = idx[g]
        ov_all[i] += 1
        if cat == FIRE_CAT:
            ov_fire[i] += 1
        elif cat == EMS_CAT:
            ov_ems[i] += 1
        elif cat in SCHOOL_CATS:
            ov_school[i] += 1
    log("  pois: %d rows, fire %d ems %d school %d"
        % (poi_rows, ov_fire.sum(), ov_ems.sum(), ov_school.sum()))
    del best

    hf = {}
    for typ, layer in (("fire", "hifld-fire-stations"), ("ems", "hifld-ems-stations"),
                       ("school", "hifld-schools")):
        cnt = np.zeros(n, dtype=np.int64)
        rows, hits = scan_points(region, layer, tree_ll,
                                 lambda pi, ti, p, c=cnt: np.add.at(c, ti, 1))
        log("    hifld %s: %d rows -> %d assigned" % (typ, rows, hits))
        hf[typ] = cnt

    cbp_tb = pq.read_table(ref(region, "census-cbp"), columns=["GEOID", "cbp_estab"])
    cbp = np.zeros(n, dtype=float)
    for g, v in zip(cbp_tb.column("GEOID").to_pylist(), cbp_tb.column("cbp_estab").to_pylist()):
        if g in idx:
            cbp[idx[g]] = v if v is not None else 0.0

    return {
        "GEOID": geoids,
        "tiger_m": tiger_m, "overture_m": overture_m,
        "bldg_ov": bldg_ov, "bldg_ms": bldg_ms,
        "ov_all": ov_all, "ov_fire": ov_fire, "ov_ems": ov_ems, "ov_school": ov_school,
        "hf_fire": hf["fire"], "hf_ems": hf["ems"], "hf_school": hf["school"],
        "cbp_estab": cbp,
    }
