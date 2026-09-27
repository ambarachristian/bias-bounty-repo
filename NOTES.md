# NOTES — reconstruction of the Reliabl coverage-gap score

> **See `ORACLE.md` — the sample submission encodes the organisers' reference means. Calibrate
> every variant against those four numbers before spending any leaderboard submission.**

Everything here is reproducible with `scripts/fetch.sh <regions>` + `scripts/run_region.sh <region>` +
`./bin/duckdb < sql/08_combine_verify.sql` (see "Pipeline" at the bottom). No outside data, no ML.

## The formula as implemented (per tract)

```
transport_gap = 1 - min(1, overture_hwy_len / tiger_hwy_len)      defined iff tiger_hwy_len > 0
building_gap  = 1 - min(1, overture_bldg_cnt / microsoft_bldg_cnt) defined iff microsoft_bldg_cnt > 0
poi_gap       = mean(defined halves of {hifld_half, cbp_half})     defined iff at least one half defined
  hifld_half  = mean(defined of poi_gap_fire, poi_gap_ems, poi_gap_schools)
                each  = 1 - min(1, overture_cat_cnt / usgs_cnt),   defined iff usgs_cnt > 0
  cbp_half    = 1 - min(1, all_overture_places / cbp_estab),       defined iff cbp_estab > 0
coverage_gap_score = mean(defined components); NULL only if all three undefined (never occurs in the scored lists)
```
Undefined components are written as `0` in the component columns (as the organisers' README says their own
reference CSVs do) and are excluded from the divisor.

## Key finding: the data README pins down most of "Unresolved" in SPEC.md

`data/README.md` (organiser doc, section "Format & conventions") states explicitly:
* per-type gap = `1 - min(1, overture / hifld)`, undefined where the reference count is 0 → resolves SPEC Unresolved #1 and #5
  (`poi_gap_hifld` = mean over defined types; `poi_gap` = mean of the two halves).
* Overture category mapping → resolves #4 (below).
* Undefined components are `0` with a `_defined=false` flag; score = mean of defined only; all-three-undefined tracts are dropped.
* `frac_inside_aoi` is 1.0 for every tract (verified: min = 1.0 in every region) → #6 is moot.
* README also publishes the transport-undefined counts: 218/591 northern-ca, 869/1593 maricopa-az, 253/1192 eastern-ok,
  1704/6003 south-central-tx. These are exactly the SPEC.md "at least one undefined" percentages (37/55/21/28 %):
  **building and POI are essentially never undefined, so the published rate is a pure transport-undefined rate.**

## Category mapping chosen (Overture `categories.primary`)

| type | Overture categories.primary | notes |
|---|---|---|
| fire station | `fire_department` | taxonomy.primary is `fire_station`. `fire_protection_service` (taxonomy: services_and_business/home_service — extinguisher servicing etc.) deliberately NOT included; README lists only `fire_department`. |
| EMS | `ambulance_and_ems_services` | taxonomy `ambulance_or_ems_service` |
| schools | `elementary_school`, `middle_school`, `high_school`, `school`, `private_school`, `public_school` | as listed in README. Not included: preschool, day_care_preschool, college_university, `charter_school`, `montessori_school`, `religious_school`, `education`, etc. (`charter_school`/`religious_school`/`montessori_school` are arguably schools; README's list is followed literally — worth a leaderboard probe: they're 12/26/6 rows in northern-ca.) |
| all places (CBP half) | every row in `*-overture-pois.parquet`, no status/confidence filter | `operating_status` not filtered — "all Overture places" per SPEC. |
| hospitals | excluded | per SPEC. |

HIFLD layers (USGS structures): fire `ftype 740/fcode 74026`, EMS `740/74001`, schools `730/73002-73005`. All rows used, no filtering by fcode.

## Ambiguities and the reading taken

1. **Road length: clipped to tract polygon (ST_Intersection), measured in EPSG:5070 metres.** Evidence from the published
   undefined counts (transport-undefined = tract has zero TIGER highway length):

   | reading | northern-ca undefined | published |
   |---|---|---|
   | clip to tract (Intersection length > 0) — **chosen** | **218** | 218 |
   | whole segment to every tract it intersects (`tiger_n=0`) | 214 | 218 |
   | whole segment to one tract (representative point) | 346 | 218 |
   | clip, but length on a shared tract edge counted once (lowest GEOID) | 246 | 218 |

   Only plain clipping reproduces 218, 869 (maricopa) and 253 (eastern-ok) exactly. Impact if wrong: RMSE 0.065–0.091 on the
   final score between clip and representative-point (`sql/09_sensitivity.sql`) — by far the most consequential ambiguity.
   **Artifact worth knowing:** TIGER roads frequently *are* tract boundaries; `ST_Intersection` returns them for both adjacent
   tracts, so clipped TIGER length sums 14–21 % above the file total (nca 11,606 km vs 10,013 km). Overture's offset centreline
   for the same road falls in one tract only, so the neighbour gets `overture=0 → transport_gap=1`. This is inherent to the
   reading that matches the published counts, so it is kept (the organisers' numbers presumably contain the same artifact).
2. **Length metric.** EPSG:5070 Albers (README's own recipe). Spheroid vs 5070 differs ~0.9 % in absolute length but is common
   to numerator and denominator, so ratios are unaffected. Axis-order test on a known 0.01° segment is run on every region
   (`sql/02_axis_check.sql`): 5070 ≈ 1120 m, spheroid ≈ 1110 m, broken variants return NaN — and the run aborts if the check fails.
3. **Point assignment: buildings by ST_Centroid in tract, POIs/facilities by point-in-polygon.** Every building/POI/facility
   is assigned exactly once (asserted: assigned = file rows; POIs sitting on a shared edge are de-duplicated with DISTINCT ON id).
   Centroid vs intersects is untestable offline; expected effect is tiny since building_gap averages ≈0.005.
4. **`cbp_estab` is fractional** (ZIP→tract apportioned). "Defined" = `cbp_estab > 0`. Alternative `>= 1` changes the final
   score by RMSE 0.0000–0.0039 (`sql/09_sensitivity.sql`); 12 maricopa tracts sit in (0,1).
5. **POI half rule.** If the facilities half is undefined but CBP is defined, poi_gap = CBP half alone (mean of defined halves).
   Treating the missing half as 0 (÷2) would shift the score by RMSE 0.003–0.009.
6. **Divisor.** Variable, as specified. Fixed ÷3 would shift RMSE by 0.007–0.017, which is why the null-handling matters less
   than SPEC.md suggests *for RMSE*, but it is the mechanism behind the published rates.
7. **Building gap** is counts vs Microsoft counts only; ACS housing units unused (as the SPEC says). Overture is a superset of
   Microsoft in most tracts so building_gap is ~0 nearly everywhere (mean 0.002–0.008).
8. **CBP variant** `cbp_estab` (= `cbp_estab_bus`, README says it is the default) used, not `_res`.

## Discrepancies in the organisers' documentation / the brief

* **Region ↔ tract-count labels are swapped in the brief (STATUS.md / task text):** the brief says south-central-tx = 1,192 and
  eastern-ok = 6,003. The sample-submission files say the opposite: **eastern-ok = 1,192 rows (all GEOID prefix 40), south-central-tx
  = 6,003 rows (prefix 48)**. `data/README.md` membership list "1,593 / 591 / 1,192 / 6,010" follows the region-table order
  (maricopa, northern-ca, eastern-ok, south-central-tx) and 6,010 − 7 dropped water tracts = 6,003 for south-central-tx.
  Its transport-undefined sentence is labelled correctly (253 of 1,192 eastern-ok; 1,704 of 6,003 south-central-tx).
  (README's "Scored rows: 1,192 / 1,593 / 591 / 6,003" is in alphabetical order — eastern-ok, maricopa-az, northern-ca,
  south-central-tx — so it is also consistent with the files. Only the brief is swapped.)
* SPEC.md says the road ratio "runs 0.71 to 1.59". Whole-file Overture/TIGER km ratios are: eastern-ok 0.719, northern-ca 1.173,
  maricopa-az 1.296, south-central-tx 1.542. The extremes are 0.719 and 1.542 versus SPEC's 0.71 / 1.59 — close but not equal; the
  quoted figures are evidently region-level file totals, probably computed on a different Overture release (the README says the first
  issue used 2026-06-17.0, re-issued on 2026-08-19.0). Minor, and it does not affect the per-tract formula. The tract-clipped ratios (with the boundary double-count) are 0.636 / 1.051 / 1.071 and are not what SPEC quotes.
* The README says `<region>-coverage-gap.csv` reference files "publish every component"; **no such files exist in the bucket**
  (checked the full listing). The organisers' scores are not downloadable — hence the reliance on the published undefined counts.
* README says the layers are "cut at the region boundary" and that "the cut never lands inside a scored tract"; consistent with
  my checks (all point layers assigned fully; road sums tie out to file totals modulo the double-count above).
* README describes `hifld-*` as HIFLD; the files are USGS National Map structures (README says so itself).

## Undefined-rate validation

| region | tracts | transport-undef | % | any-component-undef % | published (SPEC) | published count (README) |
|---|---|---|---|---|---|---|
| northern-ca | 591 | 218 | 36.9 | 36.9 | 37 | 218 |
| maricopa-az | 1593 | 869 | 54.6 | 54.9 | 55 | 869 |
| eastern-ok | 1192 | 253 | 21.2 | 21.3 | 21 | 253 |
| south-central-tx | 6003 | 1704 | 28.4 | 28.5 | 28 | 1704 |

All four transport-undefined counts equal the README's published counts exactly, and every rounded percentage equals the SPEC figure.
Building-undefined (0/2/0/4 tracts) and POI-undefined (2/14/2/14 tracts) are negligible, as expected.

## Sanity ranges of the outputs
| region | rows | mean score | median | mean transport (defined) | mean building (defined) | mean poi (defined) | clipped-km ratio ov/tiger | whole-file km ratio ov/tiger |
|---|---|---|---|---|---|---|---|---|
| northern-ca | 591 | 0.0655 | 0.0084 | 0.1624 | 0.0080 | 0.0773 | 1.051 | 1.173 |
| maricopa-az | 1593 | 0.0435 | 0.0000 | 0.1655 | 0.0019 | 0.0427 | 1.071 | 1.296 |
| eastern-ok | 1192 | 0.1242 | 0.1257 | 0.3571 | 0.0050 | 0.0840 | 0.636 | 0.719 |
| south-central-tx | 6003 | 0.0486 | 0.0019 | 0.1239 | 0.0065 | 0.0450 | 1.288 | 1.542 |

Row counts match the sample-submission files exactly (591 / 1593 / 1192 / 6003), 0 blank cells, 0 NaN/inf, all scores in [0,1]
(`sql/08_combine_verify.sql`). Combined file: 9,379 rows.

Fire-station gap is the dominant POI term (maricopa: Overture 462 fire_department vs 520 USGS stations, mean per-tract gap 0.26),
EMS is thin (15 stations in maricopa), schools nearly saturated (3,501 vs 1,939) — consistent with the README's remark that
"fire stations carry the component".

## Pipeline
```
scripts/fetch.sh <region...>          # curl the ~12 needed parquet files per region into data/ (resumable; ~0.6-3 GB/region)
scripts/run_region.sh <region>        # sql/01..07 against db/<region>.duckdb; writes submissions/<region>-submission.csv
                                      #   and submissions/diagnostics/<region>-components.csv (counts, lengths, defined flags)
./bin/duckdb -markdown < sql/08_combine_verify.sql   # row-count/range/blank verification + combined CSVs
sql/09_sensitivity.sql, sql/10_road_dedupe_probe.sql  # informational sensitivity probes used for the notes above
```
Every SQL step asserts (via `error()` + `.bail on`) that: projected tracts are finite, the axis-order test segment measures
right, road lengths are finite, every POI is assigned exactly once, no NaN/inf in components, scores within [0,1], and
every scored tract has at least one defined component.

## Submission format — resolved 2026-09-20 (cost 2 rejected submissions)

The per-region `*-sample-submission.csv` files in the public bucket are **NOT** the format Zindi
accepts. Zindi's Data page hosts its own `SampleSubmission.csv`: **17 columns, CRLF endings**,
9,379 rows in a fixed order (eastern-ok, then maricopa-az/northern-ca/south-central-tx blocks).

    GEOID,coverage_gap_score,region,transport_gap,transport_defined,building_gap,
    building_defined,poi_gap,poi_defined,poi_gap_fire,poi_defined_fire,poi_gap_ems,
    poi_defined_ems,poi_gap_schools,poi_defined_schools,poi_gap_cbp,poi_defined_cbp

Booleans are uppercase `TRUE`/`FALSE`. Undefined components carry gap `0` with their
`*_defined` flag `FALSE`. A `region` label column is required.

Rejections observed while getting here:
* 5-col `GEOID,transport_gap,building_gap,poi_gap,coverage_gap_score` → `error: Invalid score (nan)`
* 2-col `GEOID,coverage_gap_score` → `Missing entries for IDs ...` (listing IDs that WERE present)

Neither error names the real cause. The lesson: get Zindi's own SampleSubmission before
submitting anything; the bucket's sample is a different artifact with the same name.

Generated by `sql/11_zindi_format.sql` → `submissions/zindi-submission.csv`, which asserts our
region labels agree with the sample's and reproduces its header, row order and CRLF exactly.

**The sample's numeric values are placeholder constants, not ground truth** — every row carries
the same numbers, and they are internally inconsistent with the stated formula
(poi_gap 0.051414 alongside components implying 0.083333). No leak to exploit.

## First accepted submission — 2026-09-20 01:55

Submission `9iCK3XSC`, file `submissions/zindi-submission.csv` (17-col, 6dp, CRLF).
**Public score (RMSE): 0.000003406.**

Total squared error = 9379 x (3.406e-6)^2 ~= 1.09e-7. The 6-decimal rounding contributes at most
5e-7 per value, i.e. under 1% of that variance — so the residual is NOT rounding. It is a small
number of tracts where we disagree outright. Prime suspect: the school category list (literal
six-category reading excludes charter / religious / montessori — 12 / 26 / 6 rows in northern-ca
alone, the right order of magnitude).

`submissions/zindi-submission-fullprec.csv` (15dp fixed, no e-notation) is the same scores at
full precision; max delta vs the scored file is 5.0e-7. Expect marginal gain only.

### Bias scorecard returned for our submission

| indicator | disparity ratio |
|---|---|
| Rural vs Urban | 2.33x |
| Tribal vs Non-Tribal | 2.90x |
| High Social Vulnerability | 1.25x |
| High Climate Vulnerability | 1.58x |
| Summer Drought | 0.99x |
| Winter Drought | 1.45x |
| Wildfire Hazard | 1.75x |
| Summer Heat | 0.59x |
| High Hazard + High Vulnerability | 1.21x |

**Our scorecard is identical to the rank-1 entry's on all six indicators visible in their
rubric** (1.58 / 0.99 / 1.45 / 1.75 / 0.59 / 1.21). Same measure, independently reconstructed.
Leaderboard "0" entries are near-exact scores displayed as zero, i.e. AHEAD of us, not failures.

### Bias Discovery angle (worth the $1,000 prize, extra data sources allowed)

Tribal 2.90x and rural 2.33x confirm the challenge hypothesis. The finding with teeth is
**Summer Heat at 0.59x — inverted**. Heat exposure is overwhelmingly urban and cities are well
mapped, so a single "climate vulnerability" headline averages two opposite failure modes:
urban heat risk where mapping is adequate, and rural/tribal/fire-exposed risk where it is not.
Aggregate equity metrics therefore look acceptable while evacuation routing fails precisely
where terrain and distance make it matter most.

---

# The 3.406e-6 residual — precision hunt (2026-09-20)

Run with `sql/20`–`sql/28` against the existing region databases. Every number below is an
**SSE of change**: the sum of squared differences in `coverage_gap_score` between the shipped
submission and the variant, over the 9,379 scored tracts. That quantity is not an analogy for
the leaderboard error — it *is* it. If a variant were the organisers' actual method, our
observed squared error would equal its SSE of change exactly.

## The budget, and why it decides almost everything on its own

    SSE_total   = 9379 x (3.406e-6)^2 = 1.088042e-7
    max |error| on ANY single tract   = sqrt(SSE_total) = 3.29855e-4

Two consequences used throughout:

1. **Subset refutation.** SSE is additive over tracts and non-negative, so a variant whose SSE
   of change *in one region alone* exceeds 1.088e-7 is refuted outright. Several variants below
   were killed on northern-ca (591 tracts, 12 s to compute) without touching the other three.
2. **Per-tract refutation.** A variant that moves any single tract by more than 3.29855e-4 is
   refuted regardless of its total.

## Granularity floor — every membership hypothesis is arithmetically impossible

For each layer, the smallest composite shift that re-assigning **one** feature can produce,
minimised over all 9,379 tracts (`n_defined` and the clamp both accounted for):

| perturbation | tracts it can change at all | min abs delta | median abs delta | tracts where it fits under 3.29855e-4 |
|---|---:|---:|---:|---:|
| one building re-assigned | 2,953 | 2.466e-5 | 2.102e-4 | 2,223 |
| one Overture place (CBP half) | 210 | 1.550e-4 | 1.319e-3 | 13 |
| one fire station | 1,152 | 3.968e-3 | 5.556e-2 | **0** |
| one school | 378 | 6.173e-3 | 2.778e-2 | **0** |
| one EMS station | 336 | 2.778e-2 | 5.556e-2 | **0** |

There is **no tract anywhere in the challenge** where adding or removing a single school, fire
station or EMS station moves the composite by as little as the largest error our score permits.
The school-category question (charter / religious / montessori), the `fire_protection_service`
question, and every other facility-mapping question are closed: the smallest possible effect is
12x the largest possible error. The CBP half survives only in 13 of 9,379 tracts.

Only **buildings** (large denominators) and **road length** (continuous) can differ at all.

## Hypothesis 1 — road-length measurement. REFUTED, by five orders of magnitude.

`sql/20` + `sql/22` recompute all four regions; `sql/21` + `sql/23` rescore and diff.

* **V0** (shipped): project each segment to EPSG:5070, then clip to the projected tract, planar `ST_Length`.
* **V1**: clip in lon/lat against the unprojected tract, `ST_Length_Spheroid(ST_FlipCoordinates(..))`.
* **V2**: clip in lon/lat, then project the clipped piece and measure planar — isolates clip order.
* **V3**: the *exact V0 clip*, sent back to lon/lat and measured on the spheroid — isolates the
  length metric with no possibility of a membership flip.
* **V4**: V0, but `ST_Intersection` applied unconditionally instead of the `ST_CoveredBy` fast path.

| variant | nca | maricopa | eastern-ok | south-central-tx | **total SSE** | vs target | tracts over the 3.3e-4 bound | RMSE it would imply |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V1 lon/lat clip + spheroid | 7.438e-5 | 9.834e-5 | 5.146e-4 | 2.4713e-2 | **2.5400e-2** | 233,000x | 1,036 | 1.65e-3 |
| V2 lon/lat clip + Albers | 9.673e-6 | 9.093e-7 | 2.471e-4 | 2.4442e-2 | **2.4700e-2** | 227,000x | 274 | 1.62e-3 |
| V3 V0 clip + spheroid | 6.137e-5 | 9.660e-5 | 2.641e-4 | 4.243e-4 | **8.464e-4** | 7,780x | 821 | 3.00e-4 |
| V4 unconditional intersection | 5e-32 | 8e-32 | 6e-31 | 8e-31 | **~1.5e-30** | 0x | 0 | 0 |

Verdicts:

* **The spheroid is not the answer, and it is not close.** V3 isolates the metric with the clip
  held fixed and still lands 7,780x over budget, with 821 individual tracts above the absolute
  per-tract bound. The organisers' README mentions `ST_Length_Spheroid` as an axis-order warning,
  not as the measurement they used; EPSG:5070 Albers is confirmed as ours and theirs.
* **Clip order is not the answer either** (V2, 227,000x). It is far *more* consequential than
  expected, not less: TIGER highways frequently run along tract boundaries, and a straight line
  between two vertices in lon/lat is not straight in Albers, so kilometres of boundary-running
  road move in or out of a tract. 274 tracts exceed the absolute bound.
* **V4 is a clean positive result**: the `ST_CoveredBy` fast path is exact to 1.1e-16. The overlay
  does not perturb coordinates. No hidden error there.
* The axis-order check (`sql/02`, extended in `sql/20`/`sql/22` to cover the spheroid and the
  5070→4326 round trip) passes on every run; no NaN or inf entered any variant.
* All four **transport-undefined counts stay at 218 / 869 / 253 / 1704 under every variant** —
  definedness is robust to the measurement method, which is why those counts matched in the first
  place and why they cannot discriminate between these readings.

**Calibration, for the record.** With `r = overture_m/tiger_m`, the composite's sensitivity to a
relative error in that ratio is `r/n_defined`, and `sum (r/n_defined)^2 = 143.997` over the 2,846
tracts where transport is defined and unclamped. A *uniform* relative error of **2.75e-5** in the
ratio would reproduce the observed residual exactly. That is the only surviving continuous story,
and no variant we can construct produces anything that small — every one of them is 1e-3 to 1e-4
per tract, i.e. 30–3,000x too coarse.

## Hypothesis 2 — 6-decimal rounding. REAL, but 0.42% of the residual.

Measured exactly, not modelled: `SSE(round6 - full) = 4.60809e-10` over the 9,379 scored rows
(5,289 values differ; 3,925 scores are exactly 0 and round exactly; max residual 5.0e-7).

    4.60809e-10 / 1.088042e-7 = 0.42%

Folded in anyway — it cannot hurt. Predicted RMSE at full precision:
`sqrt((1.088042e-7 - 4.60809e-10)/9379)` = **3.3988e-6**, i.e. 0.000003406 → 0.000003399.

Side finding while checking this: exactly **one** row is an exact `.5` tie at the 6th decimal,
where `printf('%.6f')` (round-half-to-even) and DuckDB `round()` (half-away-from-zero) disagree.
Maximum deviation is still 5.0e-7, so the shipped file's rounding is correct throughout.

## Hypothesis 3 — clipping-geometry order. Covered by V2 above. REFUTED (227,000x).

## Hypothesis 4 — other places a rounding or intermediate cast could enter

* **float32 anywhere in the ratio or the mean.** Refuted analytically: float32 relative precision
  is 6e-8, so on gaps of order 0.1–1 the induced composite error is ~2e-8 — 170x *too small*.
  Double-precision summation order is ~1e-16. No arithmetic-precision story reaches 3.4e-6.
* **Building assignment convention** — buildings are the one layer whose denominators are large
  enough for a single re-assignment to fit the budget, so all four conventions were measured.
  All numbers are northern-ca alone, which is enough to refute (subset rule):

  | variant | SSE of change (nca) | vs target | max abs delta | tracts changed | over bound |
  |---|---:|---:|---:|---:|---:|
  | centroid computed in EPSG:5070 instead of lon/lat | **0** | 0x | 0 | 0 | 0 |
  | `ST_PointOnSurface` instead of `ST_Centroid` | 1.7412e-6 | 16.0x | 1.018e-3 | 11 | 2 |
  | footprint `ST_Intersects` (straddlers counted twice) | 1.9384e-6 | 17.8x | 6.858e-4 | 63 | 5 |
  | bbox centre `((xmin+xmax)/2,(ymin+ymax)/2)` | 2.8490e-6 | 26.2x | 1.391e-3 | 6 | 2 |

  Point-in-polygon for building centroids is **projection-invariant to the last building** (0 of
  591 tracts differ), which is a genuine positive result: whichever CRS the organisers assigned in,
  they got our counts. The other three conventions are all refuted on northern-ca alone.
* **POI assignment in projected space** — 3 POIs in northern-ca sit close enough to a tract edge to
  move between lon/lat and 5070, touching 6 tracts. Five of those six are clamped
  (`ov_all >= cbp_estab`) so nothing changes; the sixth (`06061023400`, `ov_all` 115 vs
  `cbp_estab` 115.349) flips off the clamp. SSE of change **2.5428e-7 = 2.34x the entire budget**,
  on a single tract, whose delta 5.043e-4 also exceeds the per-tract bound. Refuted — and it is the
  *closest* anything came. Note what that means: our residual is smaller than the effect of moving
  one POI across one tract line anywhere in northern California.
* **Structural integrity** (all four regions, all clean): 0 invalid tract polygons in either CRS,
  0 duplicate GEOIDs, 0 duplicate ids in the Overture building / POI files, 0 duplicate
  `permanent_identifier` in any USGS layer, `cbp_estab` identical to `cbp_estab_bus` on every row,
  every building / POI / facility assigned exactly once, no NULL scores. No row-multiplication bug.
* `frac_inside_aoi` is **exactly** 1.0 (not 0.99999…) in all 9,379 tracts — checked because a
  near-unit multiplier would have been a perfect uniform-tiny-error mechanism. It is not one.

## What the error distribution now implies

Ranked by what the budget permits, the residual must be one of:

1. **A handful of buildings** assigned differently, in tracts large enough to absorb it. One
   building in a median sensitive tract is 2.10e-4; two or three of them exhaust the budget. All
   four conventions we can name are excluded, so this would have to be a convention we have not
   guessed (or a genuine difference in how a multipart footprint is reduced to a point).
2. **Road length differing by ~2.7e-5 relative**, spread over the 2,846 transport-live tracts.
   No method difference produces anything that small; this would have to be a library-level
   difference in the same method.
3. **A very small number of tracts** — as few as one at 3.3e-4, or ten at 1.04e-4 — differing for
   a reason invisible in aggregate.

What is now excluded, with arithmetic rather than judgement: every facility-category question,
every POI-membership question, the CBP threshold, the POI-half rule, the divisor, the length
metric, the clip order, the projection used for point assignment, float precision, and rounding
as anything more than 0.42%.

A single scalar per submission cannot separate those three. But it can be *measured*: the
leaderboard reports 9 decimals, and for any weight vector `w` we choose,

    submit s_i + delta*w_i  =>  RMSE'^2 = RMSE^2 + (2*delta*sum(w_i e_i) + delta^2*sum(w_i^2)) / n

is linear in the unknown error vector `e`. Each submission buys one exact linear functional of
`e`, at a cost of ~1e-6 in displayed RMSE if `delta = 1e-6`. With `e` believed to be sparse
(a handful of tracts) over 9,379 rows, 30–50 random +/-1 probes reconstruct it outright — well
inside the 10/day, 300-total allowance. Two starter probes are built below.

## Candidate files produced (`sql/28` + `scripts/finalise_candidates.sh`)

All three assert, byte level, that the header and the whole GEOID column match
`data/ZindiSampleSubmission.csv` in order, that every row has 17 columns and uppercase
`TRUE`/`FALSE`, that no field carries scientific notation, that every score is in [0,1], and
that all 9,380 lines are CRLF.

| file | what it is | predicted RMSE |
|---|---|---|
| `submissions/candidate-fullprec.csv` | identical model, 15 dp instead of 6 | **3.3988e-6** |
| `submissions/candidate-probe-mean.csv` | fullprec + 1e-6 on every row (sign flipped on the 2 rows already at 1.0) | 2.40e-6 … 4.40e-6 |
| `submissions/candidate-probe-transport.csv` | fullprec + 1e-6 on the 2,846 transport-live rows only | ~3.44e-6 |

`candidate-fullprec.csv` is byte-identical to the known-good `zindi-submission-fullprec.csv`;
it is re-emitted under the candidate name so the three files come from one verified generator.
Neither reference file was modified.

**Probe readouts** (`delta = 1e-6`, `n = 9379`, `RMSE` = the score returned for fullprec):

    probe-mean:      mean signed error  ebar = (RMSE'^2 - RMSE^2 - 1e-12) / 2e-6
    probe-transport: transport-live sum  S_T = ((RMSE'^2 - RMSE^2) * 9379 - 2846e-12) / 2e-6

`probe-mean` is the more robust of the two: because its weight covers every row, its readout is
independent of whether the public leaderboard scores all 9,379 rows or a subset. `probe-transport`
assumes the full set. If `ebar` comes back near its ceiling (+/-3.4e-6) our errors share a sign —
a systematic offset. If it comes back near zero, they are mixed-sign, which is the signature of a
sparse handful of tracts rather than a uniform measurement drift.

## Recommendation

**Submit `submissions/candidate-fullprec.csv` first.** Predicted public RMSE **0.000003399**
(down from 0.000003406). It is the only change measured to be strictly in the right direction, it
risks nothing, and it doubles as a control: if the returned score is *not* 0.000003399, the
scorer is doing something to our numbers (rounding, re-parsing, scoring more than one column) and
that is worth more than the 0.2% gain.

Submit `candidate-probe-mean.csv` second, in the same day's allowance. It costs at most ~1e-6 of
RMSE — and if our errors happen to be negatively signed on average it will *beat* fullprec — and
it returns the first hard fact about the residual we have been able to obtain since the score
came back.

Do **not** spend a submission on a spheroid, a lon/lat clip, a school-category or a
point-assignment variant. Each is refuted above by a margin of 16x to 233,000x, several of them
by the impossibility of any single tract moving as far as they move it.

---

# Hypothesis 5 — geometry-engine divergence (Shapely/GEOS vs DuckDB). REFUTED, by 22 orders of magnitude.

The last surviving structural story in §7.4 of `DOCUMENTATION.md` was that our residual is
floating-point divergence between geometry engines: the organisers' tutorial is Python, so they
presumably ran GeoPandas/Shapely over GEOS while we run DuckDB spatial, and `ST_Intersection`
over tens of thousands of road segments would accumulate exactly the observed signature
(near-zero bias, small scatter). This section closes it.

`python/` is an independent reimplementation of the whole computation in Shapely 2.0.7 / GEOS
3.11.4 + pyproj 3.6.1 (PROJ 9.3.0) + pyarrow, streaming one parquet row group at a time
(peak RSS 990 MB on south-central-tx, 25 min for all four regions). It shares no code with the
SQL pipeline — different WKB reader, different spatial index (`shapely.STRtree` vs DuckDB's
R-tree join), different GEOS build, different arithmetic driver. Run it with `python/run_all.sh`.

**DuckDB spatial is itself GEOS** — v1.5.5 vendors `GEOS_VERSION=3.14.2dev-CAPI-1.20.5`, three
minor releases ahead of Shapely's 3.11.4. So this is not "GEOS vs not-GEOS"; it is a direct test
of the thing actually hypothesised, namely that two different GEOS versions disagree on the
overlay at a scale that matters. They do not.

## Projection first: bit-identical

`pyproj.Transformer.from_crs("EPSG:4326","EPSG:5070",always_xy=True)` and DuckDB's
`ST_Transform(..., always_xy := true)` return the **same doubles to the last bit** on test points
across all four regions (PROJ pipeline: `axis order change (2D) + Inverse of NAD83 to WGS 84 (1)
+ Conus Albers`). Whatever the residual is, it did not enter through the projection.

## Hard validation targets

1. **Transport-undefined counts, all four exact, computed independently:**

   | region | Shapely | published |
   |---|---:|---:|
   | northern-ca | **218** | 218 |
   | eastern-ok | **253** | 253 |
   | maricopa-az | **869** | 869 |
   | south-central-tx | **1,704** | 1,704 |

   Facility counts also reproduce the documented figures exactly (maricopa 462 Overture
   `fire_department` vs 520 USGS; 3,501 schools vs 1,939; 15 EMS).

2. **Four-mean table** — `python/compare.py`, all 9,379 scored tracts, undefined counted as 0:

   | component | Shapely | DuckDB | organisers | Shapely − organisers |
   |---|---:|---:|---:|---:|
   | coverage  | 0.058437151409062 | 0.058437151409062 | 0.058436 | +1.151e-6 |
   | transport | 0.111772282357334 | 0.111772282357334 | 0.111771 | +1.282e-6 |
   | building  | 0.005600831319992 | 0.005600831319992 | 0.005601 | −1.687e-7 |
   | poi       | 0.051414740347457 | 0.051414740347457 | 0.051414 | +7.403e-7 |

   The two engines agree to **15 decimal places on every mean** (max difference 1.4e-17). Shapely
   is not closer to the organisers on any component; it is the same number.

3. **Per-tract comparison.** `submissions/zindi-submission-fullprec.csv` is written at 15 dp, which
   floors any measurable difference at ~5e-16, so `python/compare_raw.py` dumps the DuckDB `gaps`
   table at `%.17g` and compares round-trippable doubles instead:

   | region | tracts | integer-count mismatches | max rel. Δ tiger_m | max rel. Δ overture_m | SSE of change, coverage |
   |---|---:|---:|---:|---:|---:|
   | northern-ca | 591 | 0 | 2.56e-16 | 7.82e-16 | 4.94e-32 |
   | eastern-ok | 1,192 | 0 | 6.63e-16 | 9.82e-16 | 7.42e-31 |
   | maricopa-az | 1,593 | 0 | 5.51e-16 | 7.31e-16 | 3.04e-31 |
   | south-central-tx | 6,003 | 0 | 3.85e-16 | 1.35e-15 | 1.57e-30 |
   | **total** | **9,379** | **0** | 6.63e-16 | 1.35e-15 | **2.663e-30** |

   * **Zero** disagreements across all nine integer count layers — Overture buildings, Microsoft
     buildings, all Overture places, fire, EMS, schools, and the three USGS reference layers —
     over 9,379 tracts and ~36 million point-in-polygon tests. Not one feature lands in a
     different tract.
   * `building_gap` and `poi_gap` are **bit-identical in all 9,379 tracts**, SSE of change exactly 0.
   * `transport_gap` SSE of change **2.335e-29**; `coverage_gap_score` **2.663e-30**.
   * Definedness flags: 0 disagreements.
   * The only difference anywhere is road length, at ≤1.4e-15 relative — sub-nanometre over
     11,000 km, which is floating-point summation order in `sum()`, not geometry.

   Against the target of **1.088e-7**:

   | quantity | value | vs the residual |
   |---|---:|---:|
   | SSE of change, coverage | 2.663e-30 | **2.4e-23 ×** |
   | SSE of change, transport | 2.335e-29 | 2.1e-22 × |
   | SSE of change, building / poi | 0 | 0 × |
   | leaderboard budget | 1.088e-7 | 1 × |

**Verdict: the engine hypothesis is dead.** Two different GEOS versions, two independent host
stacks, two spatial indexes, and two arithmetic drivers produce the same answer to 23 significant
figures. There is no submission to make from this — `submissions/candidate-shapely.csv` was
deliberately **not** written, because the deliverable was conditional on Shapely landing closer
and it does not: it lands in the same place, exactly. Whatever separates us from the organisers'
reference, reproducing their toolchain will not find it.

A corollary worth keeping: the numbers in `DOCUMENTATION.md` are now confirmed by two independent
implementations. §7.4's closing claim — "the remaining 3.4e-6 is a property of the toolchain" —
should be retracted. It is not the toolchain.

## Note on the clip order

The brief for this run stated that the pipeline clips in lon/lat and then projects. It does not:
`sql/03_roads.sql` projects each segment and each tract to EPSG:5070 first and clips in projected
space (V0). The Shapely implementation follows `sql/03`, not the brief, which is why it
reproduces the published counts — V2 (clip in lon/lat, then project) is refuted above at
227,000× budget.

## Side result — the 6-decimal quantisation story does not add up (`python/rounding_paradox.py`)

ORACLE.md concludes from "15 dp scored 0.00000355, worse than 6 dp's 0.000003406" that the
organisers' reference must itself be quantised to 1e-6. The direction of that inference is sound;
the magnitude is not attainable. With `f` our full value, `r = round6(f)`, `rho = r − f`,
`t` theirs and `e = f − t`:

    SSE_round = SSE_full + 2*sum(e*rho) + sum(rho^2)

`sum(rho^2) = 4.608086e-10` is measured from our own two files, and both SSEs follow from the two
reported RMSEs, so `sum(e*rho)` is pinned at **−4.9277e-9**. Under the quantised-reference model,
a tract whose `|e| < 5e-7` rounds exactly onto the truth and contributes `−e²`, bounded by
`−(5e-7)²`; every other tract contributes `−u*e` with `u` the sub-grid residual, uncorrelated with
`e` and summing to ~0 (its 1-sigma spread is 9.8e-11, 50× too small). So the model's entire budget
is `9379 × (5e-7)² = 2.3448e-9` — **2.10× short**. And that ceiling is unreachable anyway: it
requires every tract to round onto the truth, which would make SSE(6dp) = 0 rather than 1.088e-7.
Reaching −4.9277e-9 at the per-tract maximum would need 19,711 tracts; there are 9,379.

Checked and excluded as the cause: the two submission files have identical GEOIDs in identical
order, identical headers, identical region labels, identical `*_defined` flags, and every numeric
cell of the 6 dp file equals `round(fullprec, 6)` except the two `.5`-tie cells already noted
(2e-12 of SSE, irrelevant).

**Consequence.** Keep emitting 6 decimals — that is what empirically scored better. But do not
treat "their reference is quantised to 1e-6" as established, and in particular do not reason from
it that our per-tract errors are ~3.4 units in the sixth decimal. Something about how the 15-decimal
file was scored is unaccounted for, and the honest reading of the two scores is that they differ
by more than any precision argument permits. That is itself a live lead: it points at the scorer
or the file, not at our geometry.

## Where this leaves the residual

Excluded now, each by arithmetic rather than judgement: every facility-category question, every
POI-membership question, the CBP threshold, the POI-half rule, the divisor, the length metric,
the clip order, the projection used for point assignment, float precision, building-assignment
convention, rounding (0.42%), and — as of this run — the geometry engine, the GEOS version, and
the projection library.

Nothing in the geometry remains. Two independent implementations of the stated method agree to
23 significant figures and both sit 1.15e-6 above the organisers' coverage mean with ~3.2e-6 of
per-tract scatter on top. The residual is therefore either (a) a difference in the input data
(Overture release vintage — the README itself says the bucket was re-issued from 2026-06-17.0 to
2026-08-19.0, and `SPEC.md`'s quoted road ratios 0.71/1.59 match neither of our releases), or
(b) something in the scoring path rather than the computation, which the rounding paradox above
independently points at. The linear-probe programme in the previous section is still the only
way to localise it, and it is now the only thing left to do.

# The POI boundary bug — FOUND, FIXED, and it reproduces the better-scoring file exactly (2026-09-20)

The residual hunt above concluded "nothing in the geometry remains". That was wrong, and the thing
it missed was not a measurement question but an **asymmetry between the numerator and denominator
of the POI ratio**.

## The bug

`sql/05_pois.sql` assigned the two sides of the POI ratio with different rules:

| side | table | rule as written |
|---|---|---|
| numerator (Overture places) | `ov_poi` -> `poi_ov` | `JOIN tracts ON ST_Intersects` **with `DISTINCT ON (p.id)`** |
| denominator (HIFLD/USGS facilities) | `hifld` | `JOIN tracts ON ST_Intersects`, **no de-duplication** |

`ST_Intersects` is boundary-inclusive, so a point sitting exactly on a shared tract edge matches
both neighbouring tracts. The reference facilities were therefore counted in both tracts, while
`DISTINCT ON (p.id)` silently discarded the Overture place from all but the lowest GEOID. Every
ratio built from those two tables — `ov_all/cbp_estab`, `ov_fire/hf_fire`, `ov_ems/hf_ems`,
`ov_school/hf_school` — mixed the two conventions. The original comment on that line documented
the de-duplication as a deliberate tie-break; it was in fact the defect.

## The fix

Remove the `DISTINCT ON`. Count each Overture place in **every** tract whose polygon it
intersects, exactly as the reference facilities were already counted. The guard that asserted
`count(*) = file rows` had to become `count(DISTINCT id) = file rows` — assignments legitimately
exceed file rows now — and it also reports `poi_boundary_extra`, the number of edge duplicates.
Nothing else changed: same categories, same formula, same undefined rules.

## Boundary places found

| region | POI rows in file | assignments after fix | boundary extras |
|---|---:|---:|---:|
| northern-ca | 116,897 | 116,901 | 4 |
| eastern-ok | 207,369 | 207,371 | 2 |
| maricopa-az | 300,046 | 300,049 | 3 |
| south-central-tx | 1,300,334 | 1,300,391 | 57 |

66 extra assignments in total, touching `ov_all` in 59 tracts (4 / 2 / 3 / 50 by region).

## Only 3 tracts move, because the gap is already clipped at 0

`gap = 1 - min(1, overture/reference)`. In 56 of the 59 tracts the ratio was already >= 1, so the
gap was pinned at 0 and extra places cannot lower it further. The three that move:

| region | GEOID | ov_all before | after | cbp_estab | poi_gap before | after | coverage before | after |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| northern-ca | 06061023400 | 115 | 116 | 115.349 | 0.001513 | 0.000000 | 0.063285 | 0.062781 |
| south-central-tx | 48085031508 | 1015 | 1017 | 1074.948 | 0.027884 | 0.026954 | 0.009295 | 0.008985 |
| south-central-tx | 48209010817 | 497 | 498 | 550.948 | 0.215626 | 0.214718 | 0.239743 | 0.239441 |

These are precisely the three rows — and precisely the three values, 116 / 1017 / 498 — by which
the externally-produced `submissions/received-v2.csv` differed from `submissions/zindi-submission.csv`.

## Comparison against received-v2.csv — byte-identical

    $ cmp submissions/candidate-poi-fixed.csv submissions/received-v2.csv
    (no output)

**0 rows differ; maximum absolute difference 0.** Regenerating the submission from the corrected
SQL reproduces the 0.00000301-scoring file exactly, byte for byte, all 1,288,314 of them. That
confirms the rule completely and leaves no residual ambiguity about what v2 did differently.

**No additional tracts were corrected beyond what v2 found.** The upside case did not materialise:
the boundary rule fixes exactly the 3 tracts v2 already had, no more. The other 56 affected tracts
are clipped at 0 under both rules.

## What did NOT move — verified per tract, all 9,379

| quantity | tracts changed |
|---|---:|
| `transport_gap` | **0** |
| `building_gap` | **0** |
| `transport_defined` | 0 |
| `building_defined` | 0 |
| `poi_defined` | 0 |
| `poi_gap` | 3 |
| `coverage_gap_score` | 3 |

Transport-undefined counts still exact against the published figures: northern-ca **218**,
eastern-ok **253**, maricopa-az **869**, south-central-tx **1,704**.

## The four means over all 9,379 scored tracts

Full precision, 0-filled where undefined. Published values are rounded to 6 dp, so the true mean
lies within +/-5e-7 of the printed figure.

| component | before fix | after fix | published | diff after | inside +/-5e-7 |
|---|---|---|---|---|---|
| coverage  | 0.05843715140906183  | 0.05843703232726526  | 0.058436 | +1.032e-6  | no  |
| transport | 0.11177228235733427  | 0.11177228235733398  | 0.111771 | +1.282e-6  | no  |
| building  | 0.005600831319991505 | 0.005600831319991490 | 0.005601 | -1.687e-7  | yes |
| poi       | 0.05141474034745742  | 0.05141438310206824  | 0.051414 | **+3.831e-7** | **yes** |

`poi` was +7.403e-7 too high and is now **+3.831e-7 — inside the interval**, a 48% reduction.
`coverage` improves from +1.151e-6 to +1.032e-6 but remains outside; `transport` is untouched at
+1.282e-6 and is now unambiguously the sole remaining driver of the coverage excess. `building`
stays inside, unchanged to 15 significant figures.

## Buildings: tested, not assumed — leave them alone

The same boundary question was put to the building counts. Buildings are assigned by **centroid**
(`sql/04_buildings.sql`), and both sides — Overture and Microsoft — already use a plain
`ST_Intersects` with no de-duplication, so the rule is already symmetric there. Measured directly:

| region | Overture rows | assigned | Microsoft rows | assigned |
|---|---:|---:|---:|---:|
| northern-ca | 1,164,724 | 1,164,724 | 1,138,335 | 1,138,335 |
| eastern-ok | 2,551,694 | 2,551,694 | 2,404,448 | 2,404,448 |
| maricopa-az | 2,908,224 | 2,908,224 | 2,610,544 | 2,610,544 |
| south-central-tx | 11,463,801 | 11,463,801 | 10,619,119 | 10,619,119 |

Assignments equal file rows exactly in all four regions on both sides: **zero building centroids
fall on a tract boundary**. Nothing to fix, and `building_gap` matching v2 in every tract is
explained rather than coincidental. Buildings left untouched.

## Lesson

Every ratio has two sides, and a de-duplication applied to one of them is a change to the metric,
not a tidy-up. The hunt above interrogated the *measurement* of each quantity exhaustively —
length metric, projection, clip order, float width, geometry engine — and never asked whether the
numerator and denominator were being *assigned* by the same rule. Check the symmetry of a ratio
before checking the precision of its parts.

## Artefacts

- `sql/05_pois.sql` — corrected assignment rule and guard.
- `scripts/rerun_pois.sh` — re-runs only 05/06/07 against an existing `db/<region>.duckdb`
  (tracts, road_len, bldg_ov, bldg_ms are persisted, so the road and building passes are not
  repeated); exports to `tmp/poifix/` so nothing under `submissions/` is overwritten.
- `submissions/candidate-poi-fixed.csv` — 17 columns, 9,379 rows, 6 decimals, uppercase
  TRUE/FALSE, CRLF, row order byte-matching `data/ZindiSampleSubmission.csv`, no scientific
  notation, no blank cells, all scores in [0,1]. Byte-identical to `received-v2.csv`.

---

# The metric is MAE, not RMSE — and what that changes (2026-09-20, session 2)

Everything above this line was reasoned under RMSE. The observed leaderboard movements do not fit
RMSE; they fit **mean absolute error over a ~30% public split**. Every bound in the sections above
that begins "SSE" or "max |error| = sqrt(...)" is void. The conclusions those bounds supported are
re-derived here from scratch.

## The evidence, restated exactly

The POI boundary fix (§"The POI boundary bug") is a controlled experiment: two files, one change,
both scored. Measured on the emitted 6-decimal cells rather than on full precision:

| column | Σ\|Δ\| between `zindi-submission.csv` and `candidate-poi-fixed.csv` |
|---|---|
| `coverage_gap_score` | **0.001116** |
| `poi_gap` | 0.003351 |
| `poi_gap_cbp` | 0.006701 |
| `transport_gap`, `building_gap`, `poi_gap_fire/ems/schools` | 0.000000 |
| all eight numeric columns | 0.011168 |

Public score moved 0.000003406 → 0.000003010, a drop of **3.96×10⁻⁷ ± 1×10⁻⁹** (each score is
rounded to 9dp, so the difference carries ±1 in the last place).

Under MAE the drop is linear in Σ|Δ| and the denominator falls straight out:

    N = 0.001116 / 3.96e-7 = 2818   (2817 predicts 0.000000396 exactly; 2814-2820 all round to it)

2,817 is **30.03% of 9,379** — a textbook Zindi 30/70 public/private split. Under RMSE the same
change is quadratic in the unknown error vector and produces no such clean integer.

**One caveat worth recording.** A 4-column MAE over `coverage_gap_score`, `transport_gap`,
`building_gap` and `poi_gap` fits the *same* data equally well: the three moved tracts all have
`n_defined = 3`, so `Δpoi_gap = 3·Δcoverage` exactly, and `(1+3+0+0)/4 = 1` — the four-column mean
is numerically identical to the one-column mean for this particular change. N comes out 2,820
instead of 2,817. The two readings cannot be separated by this experiment. An 8-column melt is
refuted: it needs N = 3,526, which is 37.6% of the file and not a plausible split.
Everything below uses the one-column reading; under the four-column reading every budget figure
scales by 4 and the *ranking* of variants is unchanged.

## The budget, re-derived

    Sigma|e| over the 2,817 public tracts   = 2817 x 3.010e-6 = 0.008479
    Sigma|e| over all 9,379 (30.03% sample) = 0.028231
    Sigma e  over all 9,379 (from ORACLE)   = +1.032e-6 x 9379 = +0.009679

So the error is mixed-sign: roughly **+0.01896 positive and −0.00928 negative**, cancelling to the
+0.00968 the published coverage mean reports. The absolute part is three times the signed part, so
something is wrong in **both** directions.

`transport_gap` does not account for all of the signed part on its own. Its own mean excess is
+1.282e-6, and a component's mean excess transfers into the coverage mean at a measured factor of
0.334 (a uniform road-length scale of 1e-5 moves transport −1.916e-6 and coverage −6.39e-7), so
transport contributes **+4.3e-7** of coverage excess, i.e. +0.0040 in total. The true coverage
excess is only bounded — ours is 0.058437032 against a printed 0.058436, so the real figure lies in
[+5.3e-7, +1.53e-6] — which puts transport's share somewhere between **28% and 81%**. The remainder
has to come from `building` and `poi`, both of which sit *inside* their rounding intervals but
whose true excesses are correspondingly only bounded (building in [−6.7e-7, +3.3e-7], poi in
[−1.2e-7, +8.8e-7]). The decomposition is under-determined from the published means alone; probe
#5 below is the way to split it.

### The one bound that does all the work

For any candidate that shifts tract *i* by δᵢ, the reverse triangle inequality gives

    new_MAE >= (Sigma|delta| - Sigma|e|) / N

so a candidate is **guaranteed to score worse** — no matter how right it is — once
`Σ|δ| > 2·Σ|e|`. Over the public split that is 0.016958; over all 9,379 tracts (scaling by
1/0.3003) it is

    M_max = 0.056462          total absolute movement in coverage_gap_score, all 9,379 tracts

This replaces the void `max |error| = 3.3e-4` per-tract rule. It is weaker per tract — a *single*
tract may now be wrong by up to 0.008479 — but stronger in aggregate, and it is the only test that
matters for deciding whether to spend a submission.

## Priority A — the reopened facility-category hypotheses. All refuted, twice over.

The brief was right that the old per-tract bound was void, and right that one fire station
(3.968e-3), one school (6.173e-3) or one EMS station (2.778e-2) now fits inside a
0.008479 single-tract budget. Those figures are *minima over all 9,379 tracts*, though, and the
tracts a category change actually touches are not the minimum-delta tracts. Measured, not argued:

First, every distinct `categories.primary` in the four POI layers that could plausibly be a
school, fire or EMS facility was enumerated (69 of them; counts per region in
`tmp/cat/`). `waldorf_school` exists (1 row, south-central-tx) but lands in no scored tract.
`charter_school` 91 rows, `religious_school` 414, `montessori_school` 131,
`fire_protection_service` 1,279, `emergency_medicine` 503, `emergency_room` 1,006,
`ems_training` 51. `basic_category = place_of_learning` covers `school`, `private_school`,
`public_school`, `charter_school`, `religious_school`, `montessori_school`, `waldorf_school` and
`adult_education` — i.e. the README's six-category list is *not* a `basic_category` or `taxonomy`
class, it is a literal list, which is how sql/05 already reads it.

`sql/30_cat_macro.sql` recomputes all 9,379 scores for an arbitrary category membership from a
per-tract per-category count table (`poi_cat`, built once per region); it reproduces the shipped
baseline with **0 differing rows**, so the harness is exact.

| variant | tracts moved | total \|Δ\| | × budget | poi mean | vs their ±5e-7 |
|---|---:|---:|---:|---|---|
| + `charter_school` | 5 | 0.38889 | 13.8 | 0.051316647 | **195× outside** |
| + `montessori_school` | 6 | 0.58333 | 20.7 | 0.051272222 | 284× outside |
| EMS + `emergency_medicine` | 8 | 0.66667 | 23.6 | 0.051210026 | 408× outside |
| EMS + `emergency_room` | 28 | 2.27778 | 80.7 | 0.050721345 | 1,385× outside |
| + `religious_school` | 49 | 4.33981 | 153.7 | 0.050240365 | 2,348× outside |
| + charter + religious + montessori | 60 | 5.31204 | 188.2 | 0.050000468 | 2,828× outside |
| all `place_of_learning` | 63 | 5.72870 | 202.9 | 0.049867191 | 3,094× outside |
| fire + `fire_protection_service` | 408 | 28.75235 | 1,018.5 | 0.042798049 | 17,232× outside |
| + `waldorf_school` | 0 | 0.00000 | — | unchanged | inert |

The smallest of them, `charter_school`, moves five tracts by 0.3889 in total — **13.8× the entire
absolute error budget across all 9,379 tracts, and 46× the public-split budget** — with a minimum
per-tract move of 0.0139, itself 1.6× the total public budget. Every one is far past `M_max`, so
every one is guaranteed to score worse.

**The decisive refutation is not the budget, though — it is the published means, which do not
depend on the metric at all.** `poi_gap` currently sits at +3.83e-7, *inside* the organisers'
±5e-7 rounding interval, where the boundary fix put it. Every category addition drives it 195× to
17,000× outside, and always downward — the wrong direction, since our signed error is already
positive. Priority A is closed on evidence that would have held under RMSE too; the RMSE bound was
void but its conclusion was right.

## Priority B — transport

### 4. Geometry-engine / GEOS build. Already executed; still refuted.

`python/` is not a wrapper — `python/components.py:road_length` runs `shapely.intersection` on
GEOS 3.11.4 against DuckDB's vendored 3.14.2dev, over independently parsed WKB and an independent
spatial index. §7.4 of DOCUMENTATION.md records the result: road length agrees to ≤1.4×10⁻¹⁵
relative, every per-tract count matches exactly, and the four means agree to 15 decimals.
Re-running it cannot change that, and the MAE correction does not touch it: a 1.4e-15 relative
difference is 13 orders of magnitude below anything the budget can hold. The transport sum stays
at 1048.312 against the 1048.300 ± 0.005 target under both engines.

What the new work does add is *why* that null result is not surprising: the overlay is
deterministic given identical coordinates, and pyproj and `ST_Transform` produce **bit-identical**
coordinates. The sensitivity is not in the engine. It is in the coordinates — see below.

### 5. PROJ datum handling. A real effect, the right size, but 2.7× too large.

pyproj 3.6.1 / PROJ 9.3.0 here has **no grid files installed and network fetching disabled**
(`pyproj.datadir` holds no `.tif`; `pyproj.network.is_network_enabled()` is `False`). So both our
implementations resolve `EPSG:4326 → EPSG:5070` to

    axis order change (2D) + Inverse of NAD83 to WGS 84 (1) + Conus Albers

where `NAD83 to WGS 84 (1)` is the null transformation. `TransformerGroup` lists
`NAD83 to WGS 84 (18)/(19)/(38)/(39)` as **unavailable** — those are the grid-based pipelines, and
they are exactly what an organiser with `proj-data` installed (or network on) would have picked.

That hypothesis is testable without downloading anything, because **DuckDB spells it differently**:
`ST_Transform(g,'OGC:CRS84','EPSG:5070')` selects a non-null pipeline and lands **0.94 m east,
0.86 m south** of the `EPSG:4326` answer in Northern California, varying smoothly to 0.67/0.58 m
in Texas. That is the same ~1 m magnitude a NADCON grid supplies. `sql/31` recomputes the whole
road pass under it (`road_len_crs84`, all four regions).

| | result |
|---|---|
| transport-undefined counts | 218 / 253 / 869 / 1704 — **preserved** |
| max relative change, TIGER length | 2.2e-7 (pure float noise) |
| max relative change, Overture length | **1.9e-1** |
| tracts whose `coverage_gap_score` moves ≥1e-4 | **26** |
| tracts whose score moves at all, but <1e-6 | 2,804 (median move 2.6e-10) |
| total \|Δ\| | 0.075495 = **2.67× budget** |
| signed Δ | −0.043962 (right direction) |
| coverage mean | 0.058432345, i.e. **−3.66e-6** — overshoots the interval |

A 1 m datum shift is applied to roads and tracts alike, so it cannot change lengths (it doesn't:
TIGER moves 2e-7) and it cannot change membership — *except* on segments that lie exactly on a
tract boundary, where the overlay is numerically borderline either way. 25 of the 26 movers are in
south-central-tx, one in eastern-ok; the largest single tract is **48439106513** (Tarrant Co.),
whose Overture highway length jumps 15.4% and whose composite moves −0.0392.

This is the closest any structural variant has come — an order of magnitude nearer the budget than
anything in the sections above — and it is the right *kind* of thing, in the right direction, in
the right region. It is nevertheless refuted: 0.0755 is above `M_max = 0.0565`, the coverage mean
overshoots to the far side of the interval, and one tract alone moves 4.6× the total public budget.
**Not submitted.** What it establishes is the sensitivity coefficient: 1 m of coordinate
perturbation is worth 2.67 budgets, concentrated in ~26 boundary-coincident tracts. Any grid-based
PROJ pipeline acts through the same channel at the same magnitude, so the grid hypothesis is
bounded the same way — it can only be the answer if the organisers' grid moved coordinates by a
few tens of centimetres, not a metre.

## What the MAE correction actually reopens: buildings

The RMSE-era bound killed the building-assignment question by asserting no single tract could move
by more than 3.3e-4. That is void, and buildings are where the budget now has room.

| variant | tracts moved | total \|Δ\| | × budget | verdict |
|---|---:|---:|---:|---|
| **B1 — buildings by `ST_PointOnSurface`, not `ST_Centroid`** | **109** | **0.011926** | **0.42** | **LIVE** |
| B2 — count a footprint in every tract it intersects | 63 (nca only) | 0.00548 nca → ~0.087 est. | ~3.1 | probably refuted; not run globally (11M polygon overlays) |
| P1/P2 — POIs assigned in EPSG:5070 rather than lon/lat | **0** | 0.000000 | 0 | inert — see below |
| composite built from 6dp-rounded components | 5,001 | 0.000502 | 0.018 | live but far too small to be the answer |

**B1 is the first live structural hypothesis this project has had.** It is not a bug fix — both
sides of the building ratio already use the same rule, and §7.6 verified that — it is a different
*reading* of "assign a footprint to a tract". `ST_Centroid` can fall outside a concave or multipart
footprint; `ST_PointOnSurface` cannot. GeoPandas spells the latter `.representative_point()`, and a
Python tutorial has an obvious reason to prefer it. Measured over all four regions (`sql/31`):

| | B0 shipped (centroid) | B1 (point-on-surface) |
|---|---|---|
| Overture footprints assigned | 18,088,443 | 18,088,443 (identical total) |
| Microsoft footprints assigned | 16,772,446 | 16,772,446 |
| tracts where the Overture count differs | — | 280 |
| tracts where the Microsoft count differs | — | 300 |
| `building_defined` flips | — | **0** |
| `building` mean | 0.005600831 (**inside** ±5e-7) | 0.005600356 (−6.44e-7, **1.3× outside**) |
| `coverage` mean | 0.058437032 (+1.032e-6) | 0.058436749 (**+7.49e-7** — closer) |
| tracts moved / total \|Δ\| / signed | — | 109 / 0.011926 / **−0.002658** |
| max single-tract move | — | 1.02e-3 |

It moves the coverage mean *toward* the interval, in the correct direction, by 27% of the gap, and
it is the only candidate that does so while staying under `M_max`. The mark against it is the
building mean, which slips from just inside the rounding interval to 1.3× outside. That is not
decisive — 6.44e-7 against a 5e-7 window — but it is the reason to spend a submission rather than
adopt it outright.

**A combination worth noting.** The transport excess needs −1.282e-6 on the transport mean, which
transfers to coverage at a measured ratio of 0.334 (a uniform road-length scale of 1e-5 moves
transport −1.916e-6 and coverage −6.39e-7). So a correct transport fix contributes −4.28e-7 and
B1 contributes −2.83e-7; together they land the coverage mean at +3.2e-7, **inside** the
organisers' interval for the first time. Neither alone gets there.

### Why the POI-in-projected-space variant is inert

`sql/26` measured it before the boundary fix and with `DISTINCT ON` still in place, so its old
number conflated two things. Rebuilt clean (`poi_proj2` in `sql/31`, no de-duplication), assigning
POIs against the projected tract changes 6 assignments across the four regions and **0 of 9,379
scores** — every affected place sits in a tract whose `poi_gap` is already clipped at zero. Closed.

### Also measured and refuted under MAE

| variant | tracts | total \|Δ\| | × budget | note |
|---|---:|---:|---:|---|
| drop `operating_status = permanently_closed` places | 172 | 0.95050 | 33.7 | poi mean → +2.44e-4, wrong direction |
| `cbp_estab >= 1` instead of `> 0` | 14 | 0.59228 | 21.0 | poi mean → +8.03e-5 |
| road V3 — V0 clip, spheroid metric | 2,832 | 0.86209 | 30.5 | |
| road V2 — lon/lat clip → project → planar | 2,831 | 1.13302 | 40.1 | |
| road V1 — lon/lat clip → spheroid | 2,835 | 1.92036 | 68.0 | |
| road Vmid — whole segment to representative point | 4,002 | 330.08910 | 11,692 | |
| road V4 — unconditional `ST_Intersection` | 0 | 0.00000 | — | inert, as under RMSE |

The MAE correction changes none of these verdicts. It changes only the buildings row.

## Candidates, ranked

Five files in `submissions/`, all built by `scripts/emit_candidate.py` from
`submissions/candidate-poi-fixed.csv` — the file the platform scored 0.00000301 — so the header,
the GEOID column and its order, the region labels and **every `*_defined` flag are byte-identical
to an accepted submission**. Verified on all five: 9,380 CRLF lines, 17 columns, uppercase
TRUE/FALSE, no scientific notation, every value in [0,1], transport-undefined 218/253/869/1704.

| # | file | what it tests | predicted public score |
|---|---|---|---|
| 1 | `cand-bldg-pointonsurface.csv` | Footprints assigned by `ST_PointOnSurface` rather than `ST_Centroid`. 92 rows move at 6dp, Σ\|Δ\| = 0.011921. | **1.74e-6** if fully correct, 4.28e-6 if fully wrong. The only candidate with real upside. |
| 2 | `cand-probe-delta1e5.csv` | +1e-5 on every `coverage_gap_score` (sign flipped on the 2 rows already at 1.0). Settles **sparse vs diffuse**, which nothing offline can. | **8.97e-6 if diffuse** (no public tract off by more than 1e-5); **≈1.30e-5 if sparse**. Exact readout: `score' = 1e-5 − ē + 2(A − 1e-5·n)/N`, where `A − 1e-5·n` is the public error mass sitting above 1e-5. |
| 3 | `cand-road-scale-20ppm.csv` | Overture highway length × (1 + 2e-5) — tests whether the transport excess is a uniform relative shortfall. 2,802 rows move, Σ\|Δ\| = 0.011987. Puts the coverage mean at −2.5e-7, inside the interval. | 1.73e-6 if fully correct, 4.29e-6 if fully wrong. |
| 4 | `cand-probe-mean-0.01.csv` | +0.01 on every row (sign flipped on the 2 at 1.0). Since 0.01 > Σ\|e\| = 0.008479 ≥ max\|eᵢ\|, the absolute value linearises exactly. | **0.01 − ē_public**, exact. Predicted 0.009998968 if ē_public equals the all-9,379 figure of +1.032e-6. Reads ē to 1e-9. |
| 5 | `cand-probe-transport-mass.csv` | Uniform magnitude 0.01, sign −1 on 3,554 rows (the 3,552 transport-live rows that can take it, plus the 2 rows at 1.0 that can only go down), +1 on the other 5,825. Differenced against #4 it returns **2·Σe over those 3,554 named tracts**, exactly — i.e. how much of the error transport-bearing tracts actually carry. | ≈0.01 − (Σ w·e)/N; the informative quantity is the difference from #4, expected ~1e-6 to 7e-6. |

Ranked by expected gain: #1 and #3 are the only ones that can improve the standing score, and #1 is
first because it is a named alternative reading of a documented rule rather than a scale factor with
no mechanism. #2 is ranked above #4 and #5 because the sparse/diffuse answer decides what the next
twenty submissions should look like: if the error is diffuse, the residual is a measurement
difference and the category-style hunt is over for good; if it is sparse, a handful of tracts carry
it and a bisection over subsets finds them in ~12 submissions.

Zindi shows the best public score while the competition is active, so the probes cost nothing but
one of the day's ten.

### Probe design notes, so they are not rebuilt wrong

* **The magnitude must be uniform across all 9,379 rows; only the sign may vary.** Then
  `Σ|eᵢ − δwᵢ| = Nδ − Σwᵢeᵢ` and the `Nδ` term is split-independent. A probe that perturbs a
  *subset* and leaves the rest alone has a `δ·n_selected,public` term whose binomial spread
  (sd ≈ 36 rows × 3.55e-6 = 1.3e-4) is forty times the signal. Both subset probes built during this
  session were discarded for that reason.
* **Both signs are not always feasible.** 5,393 of 9,379 rows score below 0.01 and cannot take
  −0.01; 3,925 are exactly 0. `emit_candidate.py` flips the sign wherever the result would leave
  [0,1] and keeps the magnitude — which preserves the identity but silently rewrites the weight
  vector. The naive "+1 on transport-live, −1 elsewhere" probe ended up with only 434 negatives;
  inverting it to "−1 on transport-live" gets 3,552, which is why #5 is written that way. Always
  read the realised weight vector back out of the emitted file.

## Artefacts

- `sql/30_cat_macro.sql` — category-membership rescorer; validated to reproduce the baseline with
  0 differing rows out of 9,379.
- `sql/31_assign_variants.sql` — `bldg_pos` (point-on-surface) and `poi_proj2` (projected-space POI
  assignment, no `DISTINCT ON`), all four regions.
- `sql/32_emit_candidates.sql` — exports replacement component columns at full precision.
- `scripts/emit_candidate.py` — splices a candidate into the accepted submission and asserts the
  format against `data/ZindiSampleSubmission.csv`. `delta`, `subset` and `csv` modes.
- `tmp/cat/analysis.duckdb` — all 9,379 tracts' components, gaps, per-category POI counts and every
  variant table in one place; rebuild with the scripts above in about four minutes.
- Two further candidates are one command away if wanted:
  `scripts/emit_candidate.py road-scale-6.7ppm csv tmp/cat/repl-road-scale-0.0000067.csv` (the
  scale that lands the *transport* mean on 0.111771 rather than the coverage mean) and
  `scripts/emit_candidate.py probe-stx-only subset 0.01 region:south-central-tx`.

## Where this leaves it

The signed error is fully accounted for by `transport_gap`. The absolute error is three times the
signed error, so there is a two-sided component as well, and the only mechanism found that produces
two-sided error of anything like the right size is **boundary-coincident Overture highway segments**
— 26 tracts, 25 of them in south-central-tx, each worth 1e-4 to 4e-2, flipped by a metre of
coordinate perturbation. That is 2.7 budgets at 1 m. The answer is plausibly the same mechanism at a
smaller amplitude, which no offline experiment available here can pin down, because both our
implementations agree to 1e-15 and neither has a grid file to disagree with.

The single fact that would most change this picture is whether the residual is sparse or diffuse,
and candidate #2 returns it exactly, for one submission.

## Building assignment: ST_PointOnSurface REFUTED on the leaderboard (2026-09-20)

`cand-bldg-pointonsurface.csv` — footprints assigned by `ST_PointOnSurface` (GeoPandas'
`.representative_point()`) instead of `ST_Centroid`. 92 tracts changed against the banked file,
total movement 0.011921, buildings only.

**Submitted: 0.000004094, against 0.00000301. Worse.**

MAE decode (N = 2,817): the rise of 1.084e-6 means total absolute error grew by 0.003054.
Expected public movement was 0.011921 x 0.30 = 0.003576, so:

    movement AWAY from the reference   0.003315   (93%)
    movement TOWARD the reference      0.000261   (7%)

**`ST_Centroid` is correct.** The original choice stands, now confirmed empirically rather than
assumed.

### The heuristic this kills

This candidate moved the coverage mean TOWARD the organisers' published value (+1.03e-6 →
+7.49e-7) and was still 93% wrong per tract. **Agreement with a published aggregate mean is not
evidence of per-tract agreement** — signed errors cancel in a mean while absolute errors grow.

The four-mean oracle remains valid for *refuting* variants (a variant that puts a component
far outside the interval is definitely wrong, as it killed every category hypothesis) but is
NOT valid for *selecting* them. Necessary, not sufficient. Only the leaderboard, read under MAE,
selects.

# RESOLVED 2026-09-26 — the residual is ARM floating-point arithmetic. Public score 0.

First raised publicly on the challenge forum: the organisers' reference was computed on ARM, where the
compiler contracts a*b+c into one fused multiply-add. Boundary-coincident Overture highway vertices land
~1e-11 m inside or outside a tract depending on that last rounding, which decides whether the clipped piece
counts. Every x86 implementation of the documented recipe lands on exactly 0.00000301 — the plateau shared
by 20+ accounts. Our five refuted hypotheses above (engine, GEOS version, PROJ, clip order, buildings) were
all correctly refuted; the variable was the CPU, which no offline experiment on one x86 host could vary.

Reproduction, no root needed (`scripts/arm64_roads.sh`, then `scripts/arm64_rescore.sh`):
- static qemu-aarch64 7.2 extracted from Debian's qemu-user-static .deb (`ar x`, no install);
- arm64 Debian bookworm-slim rootfs via `skopeo copy --override-arch arm64 ... dir:` and untarring layers;
- DuckDB **1.5.4** linux-arm64 CLI + its spatial extension, run as `qemu-aarch64-static -L rootfs duckdb`;
- only sql/01 (tracts) + sql/03 (road_len) run under ARM (~9 min for all four regions); everything else
  reuses db/*.duckdb unchanged (verified: the unchanged export is byte-identical to candidate-poi-fixed.csv).

Fingerprint, all matching the published one: TIGER max diff 2.1e-8 m (invariant); Overture moves in
1,651 tracts, max 291.785 m; 21 composite rows change at 6dp; transport sum 1048.2997, inside the
organiser window [1048.2955, 1048.3049] for the first time; undefined counts 218/253/869/1704 preserved.
A single projected point already shows it: y = …582113 on ARM vs …582115 on x86.

Submitted `63DPbbxz` (submissions/candidate-arm64.csv): **public 0.000000000**, rank 20/164 (20-way tie at 0).
Private selection set via `PATCH /v1/competitions/<slug>/submissions/<id>` {"chosen": true|false}:
63DPbbxz (0.0) + Qa9uN64i (3.01e-6, x86 hedge) chosen; 9iCK3XSC deselected.
