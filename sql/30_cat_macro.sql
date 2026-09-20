-- Reusable scoring macro for POI-category variants.
-- Recomputes the full 9,379-tract score with an arbitrary category membership for
-- fire / EMS / schools, reading per-tract per-category Overture counts from `poicat`.
-- Everything else (roads, buildings, CBP, HIFLD denominators) comes from `base` unchanged.

CREATE OR REPLACE MACRO ovcnt(cats) AS TABLE
  SELECT region, GEOID, sum(n) AS n FROM poicat WHERE cat IN (SELECT unnest(cats)) GROUP BY 1,2;

CREATE OR REPLACE MACRO score_variant(fire_cats, ems_cats, school_cats) AS TABLE
WITH c AS (
  SELECT b.region, b.GEOID, b.tiger_m, b.overture_m, b.bldg_ov, b.bldg_ms,
         b.ov_all,
         coalesce(f.n,0) AS ov_fire, coalesce(e.n,0) AS ov_ems, coalesce(s.n,0) AS ov_school,
         b.hf_fire, b.hf_ems, b.hf_school, b.cbp_estab
  FROM base b
  LEFT JOIN ovcnt(fire_cats)   f USING (region, GEOID)
  LEFT JOIN ovcnt(ems_cats)    e USING (region, GEOID)
  LEFT JOIN ovcnt(school_cats) s USING (region, GEOID)
), g AS (
  SELECT *,
    tiger_m > 0 AS transport_defined,
    CASE WHEN tiger_m > 0 THEN 1 - least(1.0, overture_m / tiger_m) END AS transport_raw,
    bldg_ms > 0 AS building_defined,
    CASE WHEN bldg_ms > 0 THEN 1 - least(1.0, bldg_ov::DOUBLE / bldg_ms) END AS building_raw,
    CASE WHEN hf_fire   > 0 THEN 1 - least(1.0, ov_fire::DOUBLE   / hf_fire)   END AS poi_gap_fire,
    CASE WHEN hf_ems    > 0 THEN 1 - least(1.0, ov_ems::DOUBLE    / hf_ems)    END AS poi_gap_ems,
    CASE WHEN hf_school > 0 THEN 1 - least(1.0, ov_school::DOUBLE / hf_school) END AS poi_gap_schools,
    CASE WHEN cbp_estab > 0 THEN 1 - least(1.0, ov_all::DOUBLE / cbp_estab) END AS poi_gap_cbp
  FROM c
), h AS (
  SELECT *,
    CASE WHEN poi_gap_fire IS NULL AND poi_gap_ems IS NULL AND poi_gap_schools IS NULL THEN NULL
         ELSE (coalesce(poi_gap_fire,0)+coalesce(poi_gap_ems,0)+coalesce(poi_gap_schools,0))
              / ((poi_gap_fire IS NOT NULL)::INT + (poi_gap_ems IS NOT NULL)::INT + (poi_gap_schools IS NOT NULL)::INT) END AS poi_gap_hifld
  FROM g
), p AS (
  SELECT *,
    CASE WHEN poi_gap_hifld IS NULL AND poi_gap_cbp IS NULL THEN NULL
         ELSE (coalesce(poi_gap_hifld,0)+coalesce(poi_gap_cbp,0))
              / ((poi_gap_hifld IS NOT NULL)::INT + (poi_gap_cbp IS NOT NULL)::INT) END AS poi_raw
  FROM h
)
SELECT region, GEOID,
  coalesce(transport_raw,0) AS transport_gap, transport_defined,
  coalesce(building_raw,0)  AS building_gap,  building_defined,
  coalesce(poi_raw,0)       AS poi_gap,       poi_raw IS NOT NULL AS poi_defined,
  coalesce(poi_gap_fire,0)    AS poi_gap_fire,    poi_gap_fire    IS NOT NULL AS poi_defined_fire,
  coalesce(poi_gap_ems,0)     AS poi_gap_ems,     poi_gap_ems     IS NOT NULL AS poi_defined_ems,
  coalesce(poi_gap_schools,0) AS poi_gap_schools, poi_gap_schools IS NOT NULL AS poi_defined_schools,
  coalesce(poi_gap_cbp,0)     AS poi_gap_cbp,     poi_gap_cbp     IS NOT NULL AS poi_defined_cbp,
  (coalesce(transport_raw,0)+coalesce(building_raw,0)+coalesce(poi_raw,0))
    / (transport_defined::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT) AS coverage_gap_score,
  (transport_defined::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT) AS n_defined
FROM p;
