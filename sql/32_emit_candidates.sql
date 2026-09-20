-- Export replacement component tables for the surviving candidates, at full precision.
-- scripts/emit_candidate.py rounds to 6dp and splices them into the accepted submission.
.mode csv
.headers on

-- B1: buildings assigned by ST_PointOnSurface instead of ST_Centroid.
.once tmp/cat/repl-bldg-pos.csv
WITH g AS (
 SELECT b.GEOID, bg.transport_gap, bg.poi_gap, bg.transport_defined, bg.poi_defined,
   coalesce(p.ov_pos,0) AS ov1, coalesce(p.ms_pos,0) AS ms1,
   CASE WHEN coalesce(p.ms_pos,0)>0 THEN 1-least(1.0, coalesce(p.ov_pos,0)::DOUBLE/p.ms_pos) END AS bl1
 FROM base b JOIN basegaps bg USING (GEOID) LEFT JOIN bpos p USING (GEOID))
SELECT GEOID, coalesce(bl1,0) AS building_gap,
  (transport_gap+coalesce(bl1,0)+poi_gap)/(transport_defined::INT+(ms1>0)::INT+poi_defined::INT) AS coverage_gap_score
FROM g;

-- R: uniform relative increase in Overture highway length.
.once tmp/cat/repl-road-scale.csv
WITH g AS (
 SELECT b.GEOID, bg.building_gap, bg.poi_gap, bg.building_defined, bg.poi_defined, bg.transport_defined,
   CASE WHEN b.tiger_m>0 THEN 1-least(1.0, b.overture_m*(1+@S@)/b.tiger_m) ELSE 0 END AS tr
 FROM base b JOIN basegaps bg USING (GEOID))
SELECT GEOID, tr AS transport_gap,
  (tr+building_gap+poi_gap)/(transport_defined::INT+building_defined::INT+poi_defined::INT) AS coverage_gap_score
FROM g;
