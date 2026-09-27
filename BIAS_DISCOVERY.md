# Half the fire stations on tribal land can't be found as fire stations on the open map

**Bias Bounty Mapping Equity Challenge — Best Bias Discovery entry**

Entry submission `63DPbbxz` (public score 0.000000000, exact reproduction of the reference). Every
number below is recomputed from the challenge data alone; no additional sources are used. The
final road correction that took the score to 0 (DOCUMENTATION.md §13) changed only
`transport_gap` and `coverage_gap_score` in 21 tracts. It does not touch a single facility count,
so this finding is identical under both builds.

## The finding

Across all four study regions, Overture Maps has no fire_department record for **51.9% of the fire stations that exist on tribal land**, against 17.4% elsewhere. Not a percentage-point difference — three times the
omission rate.

The automated scorecard puts the tribal coverage gap at **190% larger** than non-tribal, and
rural at **133% larger**. Those ratios are stable: they are unchanged to two decimal places
across two of our submissions that differ in the underlying pipeline — including one that fixed a
real boundary-assignment bug in the POI component. A disparity that does not move when you
correct the code measuring it is a property of the data, not an artifact of the measurement.

| | USGS fire stations | present in Overture | missing |
|---|---|---|---|
| non-tribal tracts | 3,584 | 2,960 | **17.4%** |
| tribal tracts | 1,044 | 502 | **51.9%** |

The automated bias scorecard reports Tribal vs Non-Tribal at 2.90× on the composite coverage
gap. That number is correct, but it averages roads, buildings and facilities together and so
understates what is happening to emergency infrastructure specifically. Buildings are
near-saturated everywhere (mean gap 0.005); pooling them with facilities dilutes the signal.
Isolate fire stations and the disparity is sharper and far more actionable.

Note also that EMS shows no such disparity. Across the three regions that contain tribal land (South-Central Texas has none),
the EMS gap is 0.575 on tribal tracts against 0.607 elsewhere — tribal areas are marginally
*better* served by the map on that measure, and Overture holds 111 of 112 tribal EMS stations.
Schools likewise show only a slight difference (0.046 against 0.039). So this is not a blanket
rural under-mapping effect that happens to land on tribal land. It is specific to fire stations,
which are exactly the facilities that matter first when a fire starts. This holds for the category the scorecard counts; whether the missing fire stations are absent or filed under other labels is taken up below.

## Why this is the number that matters

There is a difference between a road being slightly short and a fire station not existing.

A missing road segment degrades a route. A missing fire station changes which station gets
dispatched. Any routing engine built on open map data — and that includes a great deal of
consumer navigation, volunteer disaster mapping, and the logistics tooling relief organisations
reach for first — cannot send anyone from a station it cannot identify as a fire station. It will route from the
next one it knows about, which on tribal land in Eastern Oklahoma may be a county away.

We therefore measured a second thing the composite score cannot express: tracts that contain a
real fire station but where Overture shows **none at all**. Not undercounted — invisible to a fire-station query.

| | tracts containing a station | station invisible in Overture | rate |
|---|---|---|---|
| non-tribal | 2,723 | 577 | 21.2% |
| tribal | 513 | 163 | **31.8%** |

And it replicates independently in every region that has tribal land:

| region | non-tribal invisible | tribal invisible |
|---|---|---|
| eastern-ok (Cherokee / Muscogee / Choctaw) | 21.2% | 31.1% |
| maricopa-az | 20.4% | 41.7% |
| northern-ca (fire corridor) | 27.9% | 38.5% |
| south-central-tx | 20.4% | no tribal tracts |

Three regions, three different hazards, three different state jurisdictions, same direction
every time. In Maricopa County — a metropolitan area with otherwise excellent map coverage —
*two in five* tribal tracts with a fire station show no fire station.

Northern California is the one that should worry people most. That is the Butte/Shasta/Tehama
wildfire corridor — the same corridor in which the 2018 Camp Fire destroyed Paradise and killed
85 people. We are not claiming tribal tracts burned in that fire; the point is narrower and
still serious. This is a region where wildfire evacuation is a live, recurring operational
problem, and within it nearly four in ten tribal tracts that contain a fire station appear on
the open map as containing none. The sample is small — 13 tribal tracts with a station — so
treat the 38.5% as indicative rather than precise. The direction is what replicates.

## Where it comes from

Eastern Oklahoma is the clearest case because it has the largest tribal population in the study:
805 of its 1,192 scored tracts overlap tribal statistical areas.

| eastern-ok | non-tribal | tribal |
|---|---|---|
| mean coverage gap | 0.078 | 0.147 |
| mean road gap | 0.191 | 0.325 |
| mean facility gap (fire) | 0.291 | 0.477 |
| mean building gap | 0.002 | 0.006 |
| USGS fire stations | 152 | 987 |
| in Overture | 109 | **467** |

Tribal Eastern Oklahoma holds 987 of the region's 1,139 fire stations — the great majority of
emergency response capacity in the region sits on tribal land — and Overture knows about 467 of
them. The infrastructure exists. A findable record of it does not.

### Named tracts

Across the study, **163 tribal tracts contain 274 real fire stations and show none** on the open
map. Twenty-nine of them hold three or more. The worst, all fully inside Oklahoma Tribal
Statistical Areas (`tribal_pct` = 1.0):

| tract (GEOID) | county | tribal area | USGS stations | in Overture |
|---|---|---|---|---|
| 40061279300 | Haskell | Choctaw OTSA | 6 | 0 |
| 40071001200 | Kay | Kaw OTSA | 6 | 0 |
| 40089098900 | McCurtain | Choctaw OTSA | 6 | 0 |
| 40023967300 | Choctaw | Choctaw OTSA | 5 | 0 |
| 40079040700 | Le Flore | Choctaw OTSA | 5 | 0 |
| 40085094300 | Love | Chickasaw OTSA | 5 | 0 |
| 40001376800 | Adair | Cherokee OTSA | 4 | 0 |
| 40029388200 | Coal | Choctaw OTSA | 4 | 0 |
| 40049681900 | Garvin | Chickasaw OTSA | 4 | 0 |
| 40051000702 | Grady | Chickasaw OTSA | 4 | 0 |
| 40055967100 | Greer | Kiowa-Comanche-Apache-Fort Sill Apache OTSA | 4 | 0 |
| 40055967200 | Greer | Kiowa-Comanche-Apache-Fort Sill Apache OTSA | 4 | 0 |

A routing engine built on this map, asked for the nearest fire station to an address in any of
these tracts, cannot answer with the six stations standing inside it. Choctaw Nation territory
alone accounts for six of the twelve. (County names follow from the county FIPS code, characters 3–5 of each
GEOID; tribal area names and percentages are the challenge's own tribal stratum table.)

The mechanism is almost certainly the ordinary one. Overture's places layer is built from business-listing feeds, not OpenStreetMap; in the tracts studied here the largest named upstream source of its fire places is Meta, followed by BrightQuery, Foursquare and Microsoft (the sources field of the challenge's places layer). Tribal areas are rural, under-surveyed, and commercially uninteresting
to the vendors whose data flows upstream. Nobody excluded them. Some were simply never added, others were listed under the wrong category (see below), and no process exists to notice either.

### Missing, or filed under the wrong label?

Our fire-station counts treat a station as present only when Overture files a place under `fire_department`. That is the challenge's own rule. The README lists only that category, our submission reproduces the reference score exactly with it, and adding `fire_protection_service` moves 408 tracts away from the reference (NOTES.md). The gap in this post is the gap in the scorecard's own fire metric.

But a station can be on the map under another label. We re-checked all 740 invisible tracts (577 non-tribal, 163 tribal) using only data that is still published: the tracts from our scored file (`submissions/submission.csv`, rows with `poi_defined_fire = TRUE` and `poi_gap_fire = 1`), the Overture places layer and the tribal stratum table. A tract counts as mislabelled when it holds a place with `fire_department` or `fire_station` in another category field, or a station-like name such as "Fire Department", "Fire Station 3" or "VFD", after excluding businesses and other services. We find 282 such tracts, and a manual check of 40 random matches found 37 real fire stations.

| | invisible tracts | station found under another label | still no fire station | share of tracts with a station that show none |
|---|---|---|---|---|
| non-tribal | 577 | 218 (38%) | 359 | 21.2% → **13.2%** |
| tribal | 163 | 64 (39%) | 99 | 31.8% → **19.3%** |

Mislabelling happens at almost the same rate on tribal and non-tribal land, so it does not explain the tribal gap. Once it is removed, tribal tracts are still 1.46 times as likely to show no fire station at all. The gap holds in each of the three regions with tribal land: Eastern Oklahoma 18.3% against 14.4%, Maricopa 33.3% against 14.2% (24 tribal tracts), and Northern California 30.8% against 17.7% (from only 13 tribal tracts there).

Seven of the twelve tracts named above still show no fire station under any label: 40061279300, 40089098900, 40079040700, 40001376800, 40029388200, 40051000702 and 40055967100. In the other five the stations are in Overture under other labels, for example Boswell, Soper and Nelson Volunteer Fire Departments in 40023967300.

We cannot go further and match station by station. The station points came from the challenge's HIFLD facilities layer (USGS National Map structures), which the organisers withdrew on 25 September 2026, and the rules do not allow an independently obtained copy. The 51.9% headline is a different kind of number from the tract counts. It compares totals of Overture `fire_department` places and USGS stations, so mislabelling pushes it up and duplicate listings push it down. Read it as the gap in what the scorecard counts, not as a census of absent stations.

The mislabelling is a second bias, and the scorecard cannot see it. In about 38% of the tracts where its fire metric finds no station, the station is on the map, mostly filed under `fire_protection_service`, which Overture's taxonomy treats as a home service next to extinguisher servicing. The scorecard counts one category, so a station filed wrongly scores exactly like one that is absent, and none of its strata can tell the two apart. Anything that selects fire stations from Overture by category, such as a "fire stations" map layer or a coverage analysis, misses both kinds; a search by name may still find a mislabelled one. The fixes differ: a mislabelled station needs its category corrected in the source listing, and a missing one needs adding. On tribal land, after that correction, roughly one tract in five with a fire station still has no record of it at all.

## A caveat we are obliged to raise

Our own measurement carries an artifact that inflates some tract-level scores, and an honest
entry should say so rather than let a reader over-read individual tracts.

TIGER road centrelines frequently *are* tract boundaries. Clipping a road at the boundary
attributes its length to both adjacent tracts, while Overture's offset centreline for the same
road falls inside only one. The neighbouring tract then records zero Overture road length and
scores a perfect road gap of 1.0. Clipped TIGER length runs 14–21% above the file total as a
result.

We kept this behaviour because it is the only reading that reproduces the organisers' published
undefined-tract counts exactly in all four regions, so the reference score presumably contains
it too. But it means a 1.0 on a boundary-road tract may be an attribution artifact rather than a
mapping failure.

We have since measured how fragile those boundary-road tracts are (DOCUMENTATION.md §13): the
same roads flip in or out of a tract depending on the processor's floating-point rounding, and
1,427 of the 1,651 tracts that move on ARM hardware are in South-Central Texas. Road-gap values on
boundary-coincident tracts should be read as the least stable part of the whole score.

This caveat does not touch the fire-station finding. Point-in-polygon assignment of facilities
has no boundary-sharing problem, and the counts above are raw station counts, not derived gap
scores.

## The uncomfortable part

The challenge asks whether the communities most vulnerable to climate risk are also the least
well-mapped. On the headline numbers the answer is yes — tribal 2.90×, rural 2.33×, wildfire
hazard 1.75×.

But Summer Heat comes back at **0.59×**. Heat-exposed tracts are *better* mapped than average.

That is not a contradiction and it is not noise. Extreme heat exposure in this dataset is
overwhelmingly urban — Phoenix, San Antonio — and cities are mapped well. So a single "climate
vulnerability" headline averages two opposite failure modes:

- **urban heat risk**, where the map is fine and the problem is cooling centres, grid load and
  housing;
- **rural, tribal, fire- and drought-exposed risk**, where the map itself is the failure.

An aggregate equity metric that pools them reports something moderate and defensible — the
composite High Hazard + High Vulnerability indicator lands at just 1.21× — while concealing that
emergency infrastructure is half-missing in precisely the places where distance, terrain and
single-road access make dispatch accuracy a matter of survival.

The recommendation follows directly: **do not target open-map improvement on composite
vulnerability scores.** They will send effort to cities that already have good data.

Target instead on facility-class gaps within rural and tribal areas. This is an unusually
tractable remedy. The gap is 542 stations (net) whose locations are already public in the USGS National Map; closing it means adding some and recategorising others — this is a reconciliation task against an authoritative open dataset,
not a survey. It does require care rather than a bulk import: tribal sovereignty over data about
tribal land is a real consideration, conflation against existing OSM features needs review, and
some stations may be seasonal or volunteer-staffed in ways a point record does not capture. But
the information exists and the gap is closable, which is not true of most equity findings.

No aggregate metric will surface this on its own. That is the argument for facility-class
reporting alongside the composite score in future bias scorecards.

---

*Data availability. Every figure was computed from the challenge data as published before 25 September 2026, when the organisers removed the TIGER, Microsoft, HIFLD and CBP layers from every region; the mislabel check uses only layers that are still published. Fire-station counts are points from the challenge's `hifld-fire-stations` layer (USGS National Map structures) against Overture places with `categories.primary = fire_department`, assigned to tracts by point-in-polygon. Tribal status is `tribal_any` from the challenge's tribal stratum table. The fire-station tables come from `sql/13_bias_discovery.sql` (headline and per-region figures) and `sql/14_bias_named_tracts.sql` (named tracts) at tag `v1.0-public0`; the mislabel check is `scripts/tract_mislabel_check.py`, with its output in `results/mislabel_check.md` and `results/mislabel_tracts.csv`. The invisible tracts can still be checked today: they are the rows of `submissions/submission.csv` with `poi_defined_fire = TRUE` and `poi_gap_fire = 1`, joined to the tribal stratum table, which is still published. Full method in DOCUMENTATION.md. Code: https://github.com/ambarachristian/bias-bounty-repo*
