# Half the fire stations on tribal land are missing from the map

**Bias Bounty Mapping Equity Challenge — Best Bias Discovery entry**

Entry submission `63DPbbxz` (public score 0.000000000, exact reproduction of the reference). Every
number below is recomputed from the challenge data alone; no additional sources are used. The
final road correction that took the score to 0 (DOCUMENTATION.md §13) changed only
`transport_gap` and `coverage_gap_score` in 21 tracts. It does not touch a single facility count,
so this finding is identical under both builds.

## The finding

Across all four study regions, Overture Maps is missing **51.9% of the fire stations that exist
on tribal land**, against 17.4% elsewhere. Not a percentage-point difference — three times the
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

## Why this is the number that matters

There is a difference between a road being slightly short and a fire station not existing.

A missing road segment degrades a route. A missing fire station changes which station gets
dispatched. Any routing engine built on open map data — and that includes a great deal of
consumer navigation, volunteer disaster mapping, and the logistics tooling relief organisations
reach for first — cannot dispatch from a station it has no record of. It will route from the
next one it knows about, which on tribal land in Eastern Oklahoma may be a county away.

We therefore measured a second thing the composite score cannot express: tracts that contain a
real fire station but where Overture shows **none at all**. Not undercounted — invisible.

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
them. The infrastructure exists. The record of it does not.

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

The mechanism is almost certainly the ordinary one: Overture inherits heavily from OpenStreetMap
and commercial point-of-interest feeds, both of which are built by contributors mapping where
they live, work and sell. Tribal areas are rural, under-surveyed, and commercially uninteresting
to the vendors whose data flows upstream. Nobody excluded them. They were simply never added,
and no process exists to notice the absence.

Note also that EMS shows no such disparity. Across the three regions that contain tribal land,
the EMS gap is 0.575 on tribal tracts against 0.607 elsewhere — tribal areas are marginally
*better* served by the map on that measure, and Overture holds 111 of 112 tribal EMS stations.
Schools likewise show only a slight difference (0.046 against 0.039). So this is not a blanket
rural under-mapping effect that happens to land on tribal land. It is specific to fire stations,
which are exactly the facilities that matter in the two hazards these regions face.

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
tractable remedy. The missing records are 542 fire stations whose locations are already public
in the USGS National Map — this is a reconciliation task against an authoritative open dataset,
not a survey. It does require care rather than a bulk import: tribal sovereignty over data about
tribal land is a real consideration, conflation against existing OSM features needs review, and
some stations may be seasonal or volunteer-staffed in ways a point record does not capture. But
the information exists and the gap is closable, which is not true of most equity findings.

No aggregate metric will surface this on its own. That is the argument for facility-class
reporting alongside the composite score in future bias scorecards.

---

*Reproducible from the challenge data alone. Fire-station counts are raw USGS National Map
structures against Overture places with `categories.primary = fire_department`, assigned to
tracts by point-in-polygon, each feature assigned exactly once. Tribal status is `tribal_any`
from the challenge's own tribal stratum table. Query in `sql/13_bias_discovery.sql` (headline
figures) and `sql/14_bias_named_tracts.sql` (the named-tract table); full method in
`DOCUMENTATION.md`. Code: https://github.com/ambarachristian/bias-bounty-repo*
