# Reconstructing the coverage-gap score

**Bias Bounty Mapping Equity Challenge — methodology writeup**

Public leaderboard score **0.00000301** — under the metric the scorer actually applies, which is
mean absolute error rather than the RMSE the competition page states (§11). Everything below
runs in DuckDB SQL over the challenge data only. No machine learning, no outside sources, no paid APIs. The whole pipeline rebuilds
from an empty directory with `scripts/run_all.sh` in roughly fifteen minutes, and is reproduced
independently in Python/Shapely under `python/` (§7.4).

---

## 1. What kind of problem this is

The rules describe the coverage gap completely: three components, a stated ratio, and a mean
over the components that are defined. There is no latent target to predict. The organisers
computed a reference score with an algorithm, and the leaderboard measures how exactly you
reproduce it.

We treated it accordingly. Every decision below is either quoted from the challenge
documentation or chosen because it reproduces a number the organisers published. Where we had
to guess, we say so and give the sensitivity.

## 2. Data sources

All from the challenge bucket, read as cloud-native GeoParquet:

| purpose | layer |
|---|---|
| road numerator | `<region>-overture-roads.parquet`, `class IN (motorway, trunk, primary, secondary)` |
| road denominator | `<region>-census-tiger-roads.parquet`, `MTFCC IN (S1100, S1200)` |
| building numerator | `<region>-overture-buildings.parquet` (count) |
| building denominator | `<region>-microsoft-buildings.parquet` (count) |
| facility numerator | `<region>-overture-pois.parquet`, by `categories.primary` |
| facility denominator | `<region>-hifld-{fire-stations,ems-stations,schools}.parquet` |
| establishment denominator | `<region>-census-cbp.parquet`, `cbp_estab` |
| tract geometry / spine | `strata/<region>/<region>-census-tracts.parquet` |
| scored tract list | `reference/<region>/<region>-sample-submission.csv` |

ACS housing units are deliberately unused. The rules flag them as a sanity check only: ACS
counts dwellings where Microsoft counts structures, so using ACS as a denominator floor
manufactures an urban coverage gap out of dwelling density.

Hospitals are excluded, as instructed — Overture's hospital category runs about twelve times
the reference count, so the term can never show a deficit.

## 3. The formula

Per component, for tract *t*:

```
gap = 1 - min(1, overture / reference)        defined iff reference > 0
```

```
transport_gap = 1 - min(1, overture_hwy_metres / tiger_hwy_metres)
building_gap  = 1 - min(1, overture_bldg_count / microsoft_bldg_count)
poi_gap       = mean of the defined halves of {facilities, establishments}
  facilities     = mean of the defined members of {fire, ems, schools}, each 1 - min(1, ov/usgs)
  establishments = 1 - min(1, all_overture_places / cbp_estab)

coverage_gap_score = mean of the defined components
```

The divisor varies per tract. A component with no reference to compare against is excluded
rather than counted as zero, so the denominator is 1, 2 or 3 depending on the tract.

## 4. Edge cases

**Tracts with no reference for a component.** Excluded from the mean, not zero-filled. This is
the single most consequential rule in the spec and it is not a rare case: at least one component
is undefined in 55% of Maricopa tracts, 37% of Northern California, 28% of South-Central Texas
and 21% of Eastern Oklahoma. Maricopa is the extreme — over half the region has no named-highway
road to score against at all.

In the submission file, an undefined component is written as `0` with its `*_defined` flag set
`FALSE`, matching the sample submission's convention. The zero is a placeholder; it never enters
the mean.

**Tracts with no Overture data.** These are not undefined. The reference exists, Overture has
nothing, so the gap is a legitimate 1.0. Suppressing these would erase exactly the signal the
challenge is looking for.

**Water-dominated tracts.** Seven South-Central Texas tracts (all `99xx`) carry no scorable
reference at all and are absent from the sample submission. We take that file as authoritative
rather than the membership list: 6,010 members minus 7 unscorable = 6,003 scored rows.

**Zero-population tracts.** Not special-cased. Population is not in the formula, and a tract
with no residents can still contain roads and buildings that matter for through-routing during
an evacuation.

**The lone New Mexico tract.** `35023970000` (Hidalgo County, the bootheel) is a Maricopa member
on the same terms as every Arizona tract. Our regional assignment is asserted against the
sample submission's own `region` column, so this cannot drift.

**GEOID as text.** Maricopa is state FIPS `04`. An integer read drops the leading zero and
silently breaks 1,592 joins. Every read pins `GEOID` to `VARCHAR`.

## 5. Two silent failure modes worth naming

Both of these corrupt an entire run without raising an error, and both are flagged in the
organisers' own README. We assert against both on every run and abort on failure.

**Axis order.** The layers are lon/lat `OGC:CRS84`, but DuckDB's spatial extension follows EPSG
authority axis order for `EPSG:4326`, which is lat/lon. So
`ST_Transform(geom, 'EPSG:4326', 'EPSG:5070')` returns `POINT(inf inf)` for every feature unless
you pass `always_xy := true`, and `ST_Length_Spheroid` returns `NaN` unless you
`ST_FlipCoordinates` first. Neither raises. `sum()` propagates both, so a run finishes
"successfully" with nothing usable in it. `sql/02_axis_check.sql` measures a segment of known
length before any layer is touched: EPSG:5070 must return ≈1120 m and the spheroid ≈1110 m, and
the run aborts otherwise.

**Bounding-box filters.** Comparing only `xmin`/`ymin` is a corner-in-box test, not an overlap
test, and silently drops features straddling the window edge. All four comparisons, always.

## 6. The decision that mattered: road clipping

Roads are the only component measured as a continuous quantity, and how you attribute a road
segment to a tract dominates everything else. We tested four readings against the
transport-undefined counts the organisers published, using Northern California:

| reading | undefined tracts | published |
|---|---|---|
| **clip each road at the tract boundary (`ST_Intersection`)** | **218** | 218 |
| assign whole segments to every tract they intersect | 214 | 218 |
| assign whole segments to one tract by representative point | 346 | 218 |
| clip, but count shared-edge length once (lowest GEOID) | 246 | 218 |

Only clipping reproduces the published figure, and it then reproduces all four regions exactly:

| region | our transport-undefined | published |
|---|---|---|
| northern-ca | 218 | 218 |
| eastern-ok | 253 | 253 |
| maricopa-az | 869 | 869 |
| south-central-tx | 1,704 | 1,704 |

Four independent exact integer matches across 9,379 tracts. The distance between this reading
and the representative-point alternative is RMSE 0.065–0.091 — roughly ten times every other
open question combined. Lengths are measured in EPSG:5070 Albers, the README's own recipe.

**A known artifact, kept deliberately.** TIGER roads frequently *are* tract boundaries.
`ST_Intersection` returns such a road to both adjacent tracts, so clipped TIGER length sums
14–21% above the file total (Northern California: 11,606 km clipped against 10,013 km in the
file). Overture's offset centreline for the same road falls inside one tract only, so the
neighbouring tract sees `overture = 0` and scores a perfect gap of 1.0. This looks like a bug.
We kept it because it is inherent to the only reading that reproduces the published counts — the
organisers' reference presumably contains the same artifact, and matching the reference is the
task. It is worth flagging for anyone interpreting individual tract scores: a 1.0 on a
boundary-road tract may be an attribution artifact rather than a genuine mapping failure.

## 7. Remaining choices and their cost

Each of these is a judgment call the rules do not settle. Measured sensitivity on the final
score:

| choice | reading taken | RMSE if wrong |
|---|---|---|
| point assignment | buildings by centroid, POIs point-in-polygon | untestable offline; building_gap averages ≈0.005 so the effect is small |
| POI half undefined | mean of the defined halves | 0.003–0.009 |
| `cbp_estab` threshold | `> 0` (values are ZIP→tract apportioned, hence fractional) | 0.000–0.004 |
| divisor | variable, per spec | 0.007–0.017 vs a fixed ÷3 |
| school categories | the README's six-category list, literally | excluded by the bound in §7.1 |

### 7.1 Bounding what can still be wrong

An RMSE of 3.406×10⁻⁶ over 9,379 tracts puts the total squared error at 1.088×10⁻⁷. The largest
possible absolute error on any single tract is therefore √(1.088×10⁻⁷) = **3.30×10⁻⁴**.

That bound is decisive, and it eliminates most of the table above without spending a submission.
Adding or removing one school or fire station shifts that tract's `poi_gap` by roughly 0.33 and
its composite by ~0.11 — a single such tract would produce an RMSE near 10⁻³, three hundred
times what we observe. The same argument disposes of any change to the divisor rule, the CBP
threshold, or the POI-half rule: all move individual tracts far above 3.3×10⁻⁴.

Buildings are the one count-based term that survives the bound, because tracts hold thousands of
them: moving a single building across a boundary shifts the ratio by ~1/1500 and the composite
by ~2.2×10⁻⁴, just underneath the limit. Section 7.2 rules it out on other grounds.

What remains is numerical, not structural.

### 7.2 The reference means, and what they rule out

The `SampleSubmission.csv` on the Data page carries a constant in every row. Those constants are
the organisers' own reference **means** over all 9,379 scored tracts. Comparing against them
gives four ground-truth calibration points with no submission cost. Since they are printed to
six decimals, each implies a true mean within ±5×10⁻⁷:

| component | ours | their interval | diff vs printed | inside? |
|---|---|---|---|---|
| building  | 0.005600831 | [0.0056005, 0.0056015] | −1.687×10⁻⁷ | **yes** |
| poi       | 0.051414383 | [0.0514135, 0.0514145] | +3.831×10⁻⁷ | **yes** |
| coverage  | 0.058437032 | [0.0584355, 0.0584365] | +1.032×10⁻⁶ | no |
| transport | 0.111772282 | [0.1117705, 0.1117715] | +1.282×10⁻⁶ | no |

(`poi` is shown after the boundary-assignment fix in §7.6; before it, the figure was
0.051414740, i.e. +7.403×10⁻⁷ and outside the interval.)

The building mean sits *inside* their rounding interval, which closes the one hypothesis §7.1
left open. `poi` was brought inside by a genuine bug fix. `transport` is the sole component
still outside, and is therefore the entire remaining discrepancy.

### 7.3 Projection: tested and rejected

Road length is the only continuous quantity in the score, so it is the only place a systematic
numerical difference can originate. We recomputed Northern California from raw parquet under
both length methods the organisers' README demonstrates:

| method | mean `transport_gap` | undefined tracts |
|---|---|---|
| EPSG:5070 Albers (used) | 0.10253044 | 218 |
| `ST_Length_Spheroid(ST_FlipCoordinates(…))` | 0.10249886 | 218 |

Switching to the spheroid moves this region by −3.16×10⁻⁵, while the global transport mean needs
to move by roughly −1.3×10⁻⁶. It overshoots by a factor of twenty-three. Albers is the closer
reading and the projection choice is not the residual. Both preserve the 218-tract constraint,
so that constraint cannot discriminate between them.

### 7.4 The engine hypothesis, tested and refuted

The obvious remaining explanation was floating-point divergence between geometry engines: the
organisers' tutorial is Python, so presumably GeoPandas/Shapely over GEOS against our DuckDB
spatial, with `ST_Intersection` over tens of thousands of road segments accumulating exactly the
observed signature of near-zero bias with small scatter.

We tested it rather than asserted it. `python/` is an independent reimplementation of the whole
computation in Shapely 2.0.7 / GEOS 3.11.4, pyproj 3.6.1 (PROJ 9.3.0) and pyarrow, streaming one
parquet row group at a time. It shares no code with the SQL pipeline: different WKB reader,
different spatial index (`shapely.STRtree` against DuckDB's R-tree join), different GEOS build,
different arithmetic driver.

One fact had to be established first: **DuckDB's spatial extension is itself GEOS**, vendoring
3.14.2dev against Shapely's 3.11.4. So this is a clean test of the actual hypothesis — two GEOS
versions, three minor releases apart, disagreeing on the overlay — not a strawman.

| check | result |
|---|---|
| projection, pyproj vs `ST_Transform` | **bit-identical doubles** |
| transport-undefined counts, computed independently | **218 / 253 / 869 / 1704 — all exact** |
| integer counts, 9 layers, ~36M point-in-polygon tests | **zero mismatches** |
| `building_gap`, `poi_gap` per tract | **bit-identical; SSE of change exactly 0** |
| `coverage_gap_score` SSE of change | **2.663×10⁻³⁰** vs a 1.088×10⁻⁷ target |
| four component means | agree to 15 decimals (max diff 1.4×10⁻¹⁷) |

The only difference anywhere is road length at ≤1.4×10⁻¹⁵ relative — summation order, sub-
nanometre over 11,000 km.

**Refuted by twenty-two orders of magnitude.** Two independent implementations agree to 23
significant figures and both sit 1.15×10⁻⁶ above the organisers' coverage mean. The residual is
not in the geometry and not a property of the toolchain.

### 7.5 What remains

Nothing in the computation survives. Excluded by arithmetic rather than judgement: every
facility-category question, the CBP threshold, the POI-half rule, the divisor, the length metric,
the clip order, the projection used for point assignment, float precision, the building-assignment
convention, rounding (0.42% of the residual), the geometry engine, the GEOS version, and the
projection library.

Two possibilities remain, both outside the computation.

**Input vintage.** The rules quote the Overture/TIGER road ratio as spanning 0.71 to 1.59. Ours
spans 0.719 to 1.542. The low end matches by truncation; the high end does not, and the high end
is South-Central Texas — 64% of all scored tracts. The README records that the bucket was
re-issued from Overture release `2026-06-17.0` to `2026-08-19.0`. A reference computed before
that re-issue would produce exactly this: correct method, small mean offset, scatter concentrated
in one region.

**The scoring path.** The same values at 15 decimals scored *worse* than at 6 (0.00000355 against
0.000003406). We first read that as the reference being quantised to 10⁻⁶, but the algebra
refuses it. With `f` our full value, `r = round6(f)`, `ρ = r − f`, `t` theirs and `e = f − t`, the
identity `SSE_round = SSE_full + 2Σeρ + Σρ²` with the measured `Σρ² = 4.608×10⁻¹⁰` pins `Σeρ` at
−4.928×10⁻⁹. A 10⁻⁶-quantised reference supplies at most `9379 × (5×10⁻⁷)² = 2.345×10⁻⁹` —
**2.1× short** — and that ceiling requires every tract to round onto the truth, which would make
the 6dp SSE zero rather than 1.088×10⁻⁷. Reaching it at the per-tract maximum needs 19,711
tracts; there are 9,379. The two files are otherwise identical: same GEOIDs in the same order,
same flags and region labels, every numeric cell equal to `round(fullprec, 6)` bar two `.5` ties
worth 2×10⁻¹² of SSE.

The two reported scores therefore differ by more than any precision argument permits. Emit 6
decimals, because that is what scored better — but the mechanism is unexplained, and it implicates
the scorer or the submitted file rather than the geometry.

Every POI, building and facility is asserted to be assigned exactly once; features on a shared
tract edge are de-duplicated by feature id.

### 7.6 A real bug: assignment rules must match on both sides of the ratio

Every hypothesis above was refuted, which made it easy to assume the method was finished. It was
not. The bug, when it surfaced, was not in the geometry or the arithmetic but in a *consistency*
the spec never states explicitly: **the numerator and the denominator of a ratio must be assigned
to tracts by the same rule.**

Our Overture place assignment read:

```sql
SELECT DISTINCT ON (p.id) t.GEOID ... JOIN tracts t ON ST_Intersects(t.g, p.g)
```

`ST_Intersects` is boundary-inclusive, so a place lying exactly on a shared tract edge matches
both neighbours; `DISTINCT ON` then kept one (lowest GEOID). The reference facility layers in the
same file were joined with a plain `ST_Intersects` and no de-duplication. So boundary places were
dropped from the Overture side while boundary facilities were kept on the reference side — the
two halves of every POI ratio used different rules, and the gap was biased upward wherever it
mattered.

Removing `DISTINCT ON` — counting each place in every tract it intersects, exactly as the
reference is counted — is the fix.

| region | boundary places | tracts affected |
|---|---|---|
| northern-ca | 4 | |
| eastern-ok | 2 | |
| maricopa-az | 3 | |
| south-central-tx | 57 | |
| **total** | **66** | **59** |

Only **three** tracts move the score. The other 56 sit in tracts whose gap is already clipped at
zero, and an extra place cannot lower a gap that is already zero:

| GEOID | Overture places | `poi_gap` | `coverage_gap_score` |
|---|---|---|---|
| 06061023400 | 115 → 116 | 0.001513 → 0.000000 | 0.063285 → 0.062781 |
| 48085031508 | 1015 → 1017 | 0.027884 → 0.026954 | 0.009295 → 0.008985 |
| 48209010817 | 497 → 498 | 0.215626 → 0.214718 | 0.239743 → 0.239441 |

Public leaderboard: **0.000003406 → 0.00000301**. The `poi` mean moved from +7.403×10⁻⁷ to
+3.831×10⁻⁷, i.e. from outside the organisers' rounding interval to inside — a 48% reduction in
that component's error. `transport_gap` and `building_gap` changed in **zero** of 9,379 tracts,
and every `*_defined` flag is unchanged, so the fix is surgical.

**Buildings were checked for the same defect and are clean.** Both the Overture and Microsoft
sides already used a plain `ST_Intersects` on centroids with no de-duplication, so the rule was
already symmetric — and measured directly, **zero** building centroids fall exactly on a tract
boundary in any of the four regions.

The general lesson is worth more than the 0.0000004 it bought: when a score is a ratio of two
spatially-joined counts, an asymmetry in the join predicate is invisible to every sanity check
that examines one side at a time. Our undefined-tract counts, our totals, and our per-layer
assertions all passed throughout, because each was internally consistent. Only comparing the two
sides against *each other* exposed it.

## 8. Component behaviour

| region | mean score | mean transport (defined) | mean building | mean poi |
|---|---|---|---|---|
| northern-ca | 0.0655 | 0.1624 | 0.0080 | 0.0773 |
| maricopa-az | 0.0435 | 0.1655 | 0.0019 | 0.0427 |
| eastern-ok | 0.1242 | 0.3571 | 0.0050 | 0.0840 |
| south-central-tx | 0.0486 | 0.1239 | 0.0065 | 0.0450 |

The road term carries the score. Buildings are near-saturated — Overture is a superset of
Microsoft in most tracts, so `building_gap` averages half a percent. Within the POI term, fire
stations dominate (Maricopa: 462 Overture `fire_department` against 520 USGS stations, mean
per-tract gap 0.26), EMS is too thin to carry weight (15 stations across Maricopa), and schools
are nearly saturated (3,501 against 1,939).

Eastern Oklahoma is the worst-covered region on every measure, with a mean gap of 0.124 and a
whole-file Overture/TIGER road ratio of 0.719 — Overture holds barely seven-tenths of the named
highway length the Census records there.

## 9. Reproducing this

```
scripts/fetch.sh <region...>        # ~4 GB from the public bucket, resumable, no credentials
scripts/run_region.sh <region>      # sql/01..07 → submissions/<region>-submission.csv
./bin/duckdb < sql/08_combine_verify.sql    # row counts, ranges, blanks
./bin/duckdb < sql/11_zindi_format.sql      # 17-column submission in Zindi's exact schema
sql/09_sensitivity.sql, sql/10_road_dedupe_probe.sql   # the sensitivity figures quoted above
```

Every step asserts its own invariants with `error()` under `.bail on`: projected geometries
finite, the axis-order test segment correct to the metre, road lengths finite, every point
feature assigned exactly once, no NaN or infinity in any component, scores within [0,1], every
scored tract holding at least one defined component, and the submission's header, row order and
region labels byte-matching the sample.

## 10. Submission format, for anyone reproducing this

Two files in this challenge are called a sample submission and they are not the same artifact.

The per-region `reference/<region>/<region>-sample-submission.csv` files in the data bucket have
five columns and are the authoritative *scored tract list*. The file the platform validates
against is `SampleSubmission.csv` on the Data page: **17 columns, CRLF line endings**, a `region`
label, and a `*_defined` boolean beside every component including the four POI sub-components.
Build against the latter.

The failure modes are worth recording because neither error names its cause:

| submitted | response |
|---|---|
| bucket's 5-column shape | `error: Invalid score (nan)` |
| `GEOID,coverage_gap_score` only | `Missing entries for IDs …` — listing IDs present in the file |
| Data-page 17-column shape | scores normally |

We spent two submissions establishing this. Anyone rebuilding from the bucket alone will hit the
same wall, which is why it is documented here rather than left as folklore.

Two further details that matter: booleans must be uppercase `TRUE`/`FALSE`, and undefined
components carry a placeholder `0` with their flag set `FALSE` rather than being left blank — a
blank cell in any included column rejects the submission.

## 11. The evaluation metric is MAE, not RMSE

The competition page states Root Mean Squared Error. The scorer's responses say otherwise, and
the distinction changes how every subsequent decision should be reasoned about, so it is recorded
here with its evidence.

Two independent measurements, from our own submissions:

| change made | measured, in absolute value | score moved | implied N |
|---|---|---|---|
| three tract corrections | 0.001116 | 0.000003406 → 0.00000301 | 0.001116 / 3.960×10⁻⁷ = **2,818** |
| a separate variant | 0.005 | +1.777×10⁻⁶ | 0.005 / 1.7749×10⁻⁶ = **2,817** |

The score moves *linearly* in the absolute size of the change, with a constant divisor of
~2,817 — which is 30% of 9,379, the public split. Under RMSE the response would depend on the
pre-existing per-tract errors, not on the size of the change alone, and no constant divisor
would appear.

So: **score = Σ|ours − reference| / 2,817** over the public tracts.

### Why it matters

It sets the total error budget exactly. At 0.00000301 our total absolute error is
`0.00000301 × 2,817 = 0.008479`, spread over 2,817 tracts — a mean of 3×10⁻⁶ per tract.

It also makes the leaderboard a precise instrument. A candidate change moving public tracts by a
total of S drops the score by exactly S/2,817 **if every changed tract was wrong in that
direction by at least the amount moved**; anything less resolves the split exactly. Our building
test is a worked example: a change with total movement 0.011921 raised the score by 1.084×10⁻⁶,
which decodes to 93% of the movement being away from the reference and 7% toward it — a verdict
far sharper than "worse".

And it yields a hard exclusion rule, by the reverse triangle inequality: any candidate whose
total movement exceeds `2 × Σ|e| = 0.0565` is **guaranteed** to score worse, whatever its
merits. That eliminated every road variant, the closed-POI filter and the CBP threshold with no
submissions spent.

We flag the discrepancy rather than exploit it. If the intended metric is RMSE, the scorer
should be checked; if the intended metric is MAE, the page should be corrected. Either way
participants reasoning from the published metric — as we did for most of this work — will draw
wrong conclusions about which hypotheses are even possible.

## 12. What we could not explain

Three of the four components agree with the organisers' published means to within their rounding
interval. `transport_gap` does not: it sits +1.28×10⁻⁶ high and is the entire remaining
discrepancy.

Refuted with evidence, each recorded above: every facility-category variant (by the published
means, independently of the metric); all four road-assignment readings; the length metric; clip
order; the projection library; the GEOS version; float precision; the CBP threshold; the POI-half
rule; the divisor; the closed-POI filter; the Overture release vintage; a quantised reference;
and building assignment by representative point. One real bug was found — the boundary-POI
asymmetry of §7.6 — and fixing it produced exactly the improvement it should have.

We do not know what the residual is. Two independent implementations, in different languages on
different geometry engines, agree to 23 significant figures and both sit the same distance from
the reference. The method above reproduces four published tract counts exactly and three of four
published means to six decimals. Whatever remains is not visible from the published data.

Stating that plainly seems more useful than fitting a scale factor to close it. We tested two
such factors and discarded both: they have no mechanism, and a correction tuned to the public
30% has no reason to hold on the private 70%.
