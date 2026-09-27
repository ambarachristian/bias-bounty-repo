"""Tract-level mislabel check for the Best Bias Discovery entry, using only data
that is still published after the organisers removed the reference layers on
25 Sep 2026.

The entry's "invisible" tracts contain a USGS fire station but no Overture place
with categories.primary = 'fire_department'. They are recoverable from the
committed submission file: poi_defined_fire = TRUE (a station exists) and
poi_gap_fire = 1 (no fire_department place). This script measures how many of
them hold the station under another label, split by tribal status, from:

  submissions/submission.csv                      (the entry's own scored file)
  data/strata/<r>/<r>-census-tracts.parquet       (still published)
  data/strata/<r>/<r>-tribal-tract-table.parquet  (still published)
  data/reference/<r>/<r>-overture-pois.parquet    (still published)

A place in a tract counts as a mislabelled station when it is not primary
'fire_department' but either (strict) carries 'fire_department' or
'fire_station' in another category field, or has a station-like name ("... Fire
Department", "VFD", "Fire Station 3", "Fire Protection District"); or (loose)
any name with the word "fire" that is not an obvious business (extinguishers,
sprinklers, restaurants...). Places are assigned to tracts point-in-polygon,
boundary-inclusive, as in sql/05_pois.sql.

usage: python tract_mislabel_check.py --submission submissions/submission.csv [--root DIR] [--out DIR]
"""
import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict

import numpy as np
import pyarrow.parquet as pq
import shapely
from shapely import STRtree

REGIONS = ["eastern-ok", "maricopa-az", "northern-ca", "south-central-tx"]
FIRE_CAT = "fire_department"
FIRE_TAGS = {"fire_department", "fire_station"}
STATION_NAME = re.compile(
    r"\b(fire\s*(dept|department|station|district|rescue|company|house|hall|authority|"
    r"protection\s+district|&\s*rescue|and\s+rescue|engine|co\s*\.?\s*(no\.?\s*)?\d+)|"
    r"firehouse|vfd|v\s*\.\s*f\s*\.\s*d\.?|fpd|volunteer\s+fire|bomberos|"
    r"(engine|ladder|station)\s*(no\.?\s*)?#?\d+)\b", re.I)
FIRE_WORD = re.compile(r"\b(fire|firehouse|firefighters?|vfd|fpd|bomberos)\b", re.I)
NOT_STATION = re.compile(
    r"\b(extinguishers?|sprinklers?|equipment|apparatus|alarms?|suppl(y|ies)|systems|inc|llc|"
    r"fireworks?|fireplaces?|firearms?|pizza|grill|kitchen|bbq|barbecue|restaurant|cafe|"
    r"subs?|sandwich(es)?|vintage|thrift|antiques?|restoration|movers|radio|union|"
    r"brew(ing|ery)|church|ministr(y|ies)|insurance|wood\s*-?\s*fired|stone|marshal'?s?|"
    r"fire\s+protection(?!\s+district)|safety|training|academy)\b", re.I)
# Other emergency services, unless the name also says fire (e.g. "Kaw City Volunteer
# Fire Department" filed as EMS stays; "Granite Police Department" does not).
OTHER_SERVICE = re.compile(r"\b(police|sheriff|ems|ambulance|county\s+office)\b", re.I)
# Added after a manual audit of 30 random strict matches on the full data (27 were
# stations; the misses were a sandwich chain, an EMS station and a county office).


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def wkb(col):
    return shapely.from_wkb(np.asarray(col.to_pylist(), dtype=object))


def strings(v):
    """Every string inside a nested struct/list value."""
    if v is None:
        return []
    if isinstance(v, str):
        return [v]
    if isinstance(v, dict):
        return [s for x in v.values() for s in strings(x)]
    if isinstance(v, (list, tuple)):
        return [s for x in v for s in strings(x)]
    return []


def classify(name, cats, tax):
    """-> 'tagged' | 'strict' | 'loose' | None"""
    prim = (cats or {}).get("primary") if isinstance(cats, dict) else None
    if prim == FIRE_CAT:
        return "tagged"
    if name and (NOT_STATION.search(name) or (OTHER_SERVICE.search(name) and not FIRE_WORD.search(name))):
        return None
    other = set(strings((cats or {}).get("alternate") if isinstance(cats, dict) else None))
    other |= set(strings(tax))
    if other & FIRE_TAGS:
        return "strict"
    if name and STATION_NAME.search(name):
        return "strict"
    if name and FIRE_WORD.search(name):
        return "loose"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--submission", required=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", default="mislabel_out")
    ap.add_argument("regions", nargs="*", default=REGIONS)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    with open(a.submission, newline="", encoding="utf-8-sig") as fh:
        sub = {r["GEOID"]: r for r in csv.DictReader(fh)}
    station = {g for g, r in sub.items() if r["poi_defined_fire"].strip().upper() == "TRUE"}
    invisible = {g for g in station if float(sub[g]["poi_gap_fire"]) == 1.0}
    log(f"submission: {len(sub)} tracts, {len(station)} with a station, {len(invisible)} invisible")

    T = {}                       # GEOID -> tract record (station tracts only)
    places = defaultdict(list)   # GEOID -> candidate places in invisible tracts
    src_all = Counter()          # (tribal, kind, dataset) over station tracts
    for r in a.regions:
        p = lambda *x: os.path.join(a.root, "data", *x)
        t = pq.read_table(p("strata", r, f"{r}-census-tracts.parquet"), columns=["GEOID", "geometry"])
        geoids = t.column("GEOID").to_pylist()
        tree = STRtree(wkb(t.column("geometry")))
        tt = pq.read_table(p("strata", r, f"{r}-tribal-tract-table.parquet")).to_pylist()
        tribal = {x["GEOID"]: bool(x["tribal_any"]) for x in tt}
        tname = {x["GEOID"]: x.get("aiannh_name") for x in tt}
        for g in geoids:
            # the inner join and scored filter of sql/13
            if g in station and g in tribal and sub[g]["region"] == r:
                T[g] = {"region": r, "GEOID": g, "tribal_any": tribal[g], "tribal_area": tname.get(g),
                        "invisible": g in invisible, "tagged": 0, "strict": 0, "loose": 0}
        pf = pq.ParquetFile(p("reference", r, f"{r}-overture-pois.parquet"))
        have = set(pf.schema_arrow.names)
        cols = [c for c in ("geometry", "names", "categories", "taxonomy", "sources") if c in have]
        log(f"  {r}: places columns {cols}")
        n = 0
        for i in range(pf.metadata.num_row_groups):
            tb = pf.read_row_group(i, columns=cols)
            n += tb.num_rows
            col = lambda c: tb.column(c).to_pylist() if c in cols else [None] * tb.num_rows
            names = [(x or {}).get("primary") if isinstance(x, dict) else None for x in col("names")]
            cats, tax, srcs = col("categories"), col("taxonomy"), col("sources")
            kinds = [classify(nm, c, tx) for nm, c, tx in zip(names, cats, tax)]
            idx = np.array([k is not None for k in kinds])
            if not idx.any():
                continue
            sel = np.nonzero(idx)[0]
            pi, ti = tree.query(wkb(tb.column("geometry"))[sel], predicate="intersects")
            for a_, b in zip(pi, ti):
                g = geoids[b]
                if g not in T:
                    continue
                k = sel[a_]
                kind = kinds[k]
                T[g][kind] += 1
                ds = sorted({(s or {}).get("dataset") for s in (srcs[k] or []) if isinstance(s, dict)} - {None})
                for d in ds or ["(none)"]:
                    src_all[(T[g]["tribal_any"], kind, d)] += 1
                if T[g]["invisible"]:
                    places[g].append({"kind": kind, "name": names[k],
                                      "primary": (cats[k] or {}).get("primary") if isinstance(cats[k], dict) else None,
                                      "sources": "+".join(ds)})
        log(f"    {n} places scanned")

    out = []
    w = out.append
    rows = list(T.values())
    grp = lambda tb: [x for x in rows if x["tribal_any"] == tb]
    lab = lambda tb: "tribal" if tb else "non-tribal"
    pct = lambda x, y: f"{100.0 * x / y:.1f}%" if y else "n/a"

    w("## 1. Checks\n")
    w("| | tracts with a station | invisible | invisible tracts holding a fire_department place (must be 0) |")
    w("|---|---|---|---|")
    for tb in (False, True):
        g = grp(tb)
        inv = [x for x in g if x["invisible"]]
        w(f"| {lab(tb)} | {len(g):,} | {len(inv):,} | {sum(1 for x in inv if x['tagged'])} |")
    w("\nPublished: non-tribal 2,723 / 577, tribal 513 / 163.\n")

    w("## 2. Invisible tracts that hold the station under another label\n")
    w("| | invisible tracts | with a strict match | with any match (strict or loose) | "
      "still invisible (strict) | invisible rate before -> after (strict) |")
    w("|---|---|---|---|---|---|")
    for tb in (False, True):
        g = grp(tb)
        inv = [x for x in g if x["invisible"]]
        s = sum(1 for x in inv if x["strict"])
        al = sum(1 for x in inv if x["strict"] or x["loose"])
        left = len(inv) - s
        w(f"| {lab(tb)} | {len(inv):,} | {s:,} ({pct(s, len(inv))}) | {al:,} ({pct(al, len(inv))}) | "
          f"{left:,} | {pct(len(inv), len(g))} -> **{pct(left, len(g))}** |")
    tot = [x for x in rows if x["invisible"]]
    w(f"\nAll regions: {sum(1 for x in tot if x['strict'])} strict, "
      f"{sum(1 for x in tot if x['strict'] or x['loose'])} any, of {len(tot)} invisible tracts.\n")

    w("## 3. By region (strict)\n")
    w("| region | non-tribal: invisible -> still invisible | tribal: invisible -> still invisible |")
    w("|---|---|---|")
    for r in sorted({x["region"] for x in rows}):
        cells = []
        for tb in (False, True):
            g = [x for x in rows if x["region"] == r and x["tribal_any"] == tb]
            inv = [x for x in g if x["invisible"]]
            left = sum(1 for x in inv if not x["strict"])
            cells.append(f"{pct(len(inv), len(g))} -> {pct(left, len(g))} (of {len(g)})" if g else "no tribal tracts")
        w(f"| {r} | {cells[0]} | {cells[1]} |")
    w("")

    w("## 4. What the mislabelled stations are filed as (strict, invisible tracts)\n")
    cat = Counter((T[g]["tribal_any"], p["primary"]) for g, ps in places.items() for p in ps if p["kind"] == "strict")
    w("| primary category | non-tribal | tribal |")
    w("|---|---|---|")
    for c in sorted({c for _, c in cat}, key=lambda c: -(cat[(False, c)] + cat[(True, c)]))[:15]:
        w(f"| {c} | {cat[(False, c)]} | {cat[(True, c)]} |")
    w("")

    w("## 5. Upstream source of fire places, all tracts with a station\n")
    w("| source dataset | correctly tagged, non-tribal | correctly tagged, tribal | mislabelled (strict), non-tribal | mislabelled (strict), tribal |")
    w("|---|---|---|---|---|")
    ds = sorted({d for (_, _, d) in src_all}, key=lambda d: -sum(v for (tb, k, dd), v in src_all.items() if dd == d))
    for d in ds[:10]:
        w(f"| {d} | {src_all[(False, 'tagged', d)]} | {src_all[(True, 'tagged', d)]} | "
          f"{src_all[(False, 'strict', d)]} | {src_all[(True, 'strict', d)]} |")
    w("")

    named = ["40061279300", "40071001200", "40089098900", "40023967300", "40079040700", "40085094300",
             "40001376800", "40029388200", "40049681900", "40051000702", "40055967100", "40055967200"]
    w("## 6. The 12 named tracts in BIAS_DISCOVERY.md\n")
    w("| GEOID | tribal area | fire places under another label |")
    w("|---|---|---|")
    for g in named:
        ps = places.get(g, [])
        txt = "; ".join(f"{p['name']} ({p['primary']}, {p['kind']})" for p in ps[:4]) or "none"
        w(f"| {g} | {T.get(g, {}).get('tribal_area')} | {txt} |")
    w("")

    with open(os.path.join(a.out, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write("# Tract-level mislabel check\n\n" + "\n".join(out) + "\n")
    with open(os.path.join(a.out, "invisible_tracts.csv"), "w", newline="", encoding="utf-8") as fh:
        dw = csv.writer(fh)
        dw.writerow(["region", "GEOID", "tribal_any", "tribal_area", "kind", "name", "primary", "sources"])
        for g in sorted(x["GEOID"] for x in tot):
            x = T[g]
            for p in places.get(g) or [{"kind": "", "name": "", "primary": "", "sources": ""}]:
                dw.writerow([x["region"], g, x["tribal_any"], x["tribal_area"], p["kind"], p["name"], p["primary"], p["sources"]])
    print("\n".join(out))


if __name__ == "__main__":
    main()
