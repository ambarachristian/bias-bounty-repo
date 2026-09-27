# Bias Bounty Mapping Equity Challenge — coverage-gap reconstruction

Public leaderboard score **0.000000000** (Yanard, submission `63DPbbxz`): an exact reproduction of the reference.

A reconstruction of the organisers' per-tract coverage-gap score for the
[Bias Bounty Mapping Equity Challenge](https://zindi.world/competitions/bias-bounty-mapping-equity-challenge),
run by Humane Intelligence and Reliabl with Zindi.

Everything here computes from the challenge's public data only. No machine learning, no outside
sources, no paid APIs. The scored pipeline is DuckDB SQL; an independent reimplementation in
Python/Shapely is included as a cross-check and agrees with it to 23 significant figures.

The last step to an exact match is running the road step on **ARM** arithmetic, as the organisers did. `scripts/arm64_roads.sh` does that on an ordinary x86 machine with a user-mode QEMU and an arm64 DuckDB: no root, no Docker, nine minutes. See DOCUMENTATION.md §13; the cause was first raised publicly on the challenge forum.

## What's here

| file | what it is |
|---|---|
| **[DOCUMENTATION.md](DOCUMENTATION.md)** | Methodology writeup — sources, per-component computation, edge cases, every alternative tested and why it was rejected. Submitted for **Best Documentation**. |
| **[BIAS_DISCOVERY.md](BIAS_DISCOVERY.md)** | Half the fire stations on tribal land can't be found as fire stations in Overture. Submitted for **Best Bias Discovery**. |
| `results/` | Output of the fire-station mislabel check (`mislabel_check.md`, `mislabel_tracts.csv`), made by `scripts/tract_mislabel_check.py`. |
| [NOTES.md](NOTES.md) | The full investigation log, including the dead ends. Kept because the refutations are the evidence. |
| `sql/` | The scored pipeline. `00`–`08` build and verify; `11` emits the submission; `09`, `10`, `20`–`32` are the sensitivity and variant sweeps. |
| `python/` | Independent reimplementation in Shapely/GEOS + pyproj + pyarrow. |
| `scripts/` | Runners. |
| `submissions/submission.csv` | The earlier x86 submission (0.00000301). |
| `submissions/candidate-arm64.csv` | The exact-reproduction submission (public 0). |

## The task

Not a modelling problem. The organisers computed a reference score with a documented formula and
the leaderboard measures how exactly you reproduce it:

```
gap = 1 - min(1, overture / reference)          defined iff reference > 0

transport_gap = Overture named-highway metres / TIGER S1100+S1200 metres, clipped per tract
building_gap  = Overture building count / Microsoft footprint count
poi_gap       = mean of defined halves of {fire,EMS,schools vs USGS} and {all places vs CBP}

coverage_gap_score = mean of the components that are defined
```

The divisor varies per tract — a component with no reference to compare against is excluded
rather than scored zero. That affects 55% of Maricopa tracts, 37% of Northern California, 28% of
South-Central Texas and 21% of Eastern Oklahoma.

## Reproducing

> **Data availability (read first).** On 25 September 2026 the organisers removed the TIGER/Line roads, Microsoft building footprints, HIFLD facilities and CBP establishments from every region of the challenge bucket. Since then `scripts/fetch.sh` stops with an error at the first removed file, and `scripts/run_all.sh` calls it first, so both fail. A full rebuild needs a copy of the bucket taken before that date, laid out in `data/` the way `fetch.sh` writes it. With that copy in place, skip the download and run:
> `for r in northern-ca maricopa-az eastern-ok south-central-tx; do scripts/run_region.sh $r 0; done && ./bin/duckdb -markdown < sql/08_combine_verify.sql`
> The Overture layers, tract boundaries, strata tables and sample submissions are still published. Everything below was run on the pre-removal data, and the scored file was produced at tag `v1.0-public0` (commit 35c2f9e).

```bash
scripts/fetch.sh <region...>      # ~4 GB from the public bucket, resumable, no credentials
scripts/run_all.sh                # build, verify, emit — about 15 minutes
python/run_all.sh                 # the independent Python cross-check
scripts/arm64_roads.sh northern-ca eastern-ok maricopa-az south-central-tx   # road step under emulated arm64
scripts/arm64_rescore.sh          # swap in ARM road lengths → submissions/candidate-arm64.csv (public 0)
```

`arm64_roads.sh` expects `~/arm64/` to hold a static `qemu-aarch64` (from Debian's `qemu-user-static` .deb, extracted with `ar x`), an arm64 rootfs (`skopeo copy --override-arch arm64 docker://debian:bookworm-slim dir:img`, layers untarred into `rootfs/`), and the DuckDB 1.5.4 `linux-arm64` CLI.

Every SQL step asserts its own invariants and aborts on failure: projected geometries finite, the
axis-order test segment correct to the metre, every point feature assigned exactly once, no NaN
or infinity in any component, scores within [0,1], and the submission's header, row order and
region labels byte-matching the sample.

## Three things worth knowing before you start

**The two "sample submission" files are different artifacts.** The five-column
`<region>-sample-submission.csv` in the data bucket is the authoritative *scored tract list*. The
file the platform validates against is `SampleSubmission.csv` on Zindi's Data page: 17 columns,
CRLF endings, a `region` label and a `*_defined` flag beside every component. Submitting the
bucket's shape returns `Invalid score (nan)`; submitting two columns returns `Missing entries for
IDs` listing IDs that are present in the file. Neither error names its cause. See §10.

**The evaluation metric is mean absolute error, not the RMSE the competition page states.** Two
independent measurements pin it: the score moves linearly in the absolute size of a change, with
a constant divisor of 2,817 — 30% of 9,379, the public split. See §11. This matters: it sets the
error budget exactly and makes the leaderboard a precise instrument rather than a pass/fail.

**Two silent failure modes** corrupt a whole run without raising: DuckDB follows EPSG authority
axis order for `EPSG:4326` (so `ST_Transform` returns `POINT(inf inf)` without `always_xy := true`,
and `ST_Length_Spheroid` returns `NaN` without flipping first), and bbox filters on `xmin`/`ymin`
alone are a corner-in-box test. Both are asserted against on every run. See §5.

## The bug that mattered

Our Overture place assignment used `ST_Intersects` with `DISTINCT ON (id)`, keeping each boundary
place in one tract. The reference facility layers used a plain `ST_Intersects` with no
de-duplication. So the numerator and denominator of the same ratio were assigned to tracts by
different rules — 66 boundary places across 59 tracts, biasing the gap upward.

Fixing it moved the score from 0.000003406 to 0.00000301 and brought `poi_gap` inside the
organisers' published rounding interval.

The general lesson is worth more than the improvement: when a score is a ratio of two spatially
joined counts, an asymmetry in the join predicate is invisible to every check that examines one
side at a time. Our undefined-tract counts, totals and per-layer assertions all passed throughout,
because each was internally consistent. Only comparing the two sides *against each other* exposed
it. See §7.6.

## What we could not explain

Three of the four components agree with the organisers' published means to within their rounding
interval. `transport_gap` sits +1.28×10⁻⁶ high and is the entire remaining discrepancy. §12 lists
everything refuted in trying to find it. We state it rather than fit a scale factor to close it —
a correction tuned to the public 30% has no reason to hold on the private 70%.

## Validation

The organisers publish the count of tracts with no named highway to score against. Reproduced
exactly, independently, in both implementations:

| region | ours | published |
|---|---|---|
| northern-ca | 218 | 218 |
| eastern-ok | 253 | 253 |
| maricopa-az | 869 | 869 |
| south-central-tx | 1,704 | 1,704 |

## Data

`source.coop/humane-intelligence/bias-bounty-mapping-equity-challenge` — public, no credentials.
Overture layers pinned to release `2026-08-19.0`.

## Licence

MIT for the code. The challenge data belongs to its respective sources and is not redistributed
here.
