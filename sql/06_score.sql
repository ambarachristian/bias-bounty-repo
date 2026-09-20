-- Combine components. gap = 1 - min(1, overture/reference); undefined when reference = 0 (or null).
-- Undefined components are written as 0 with *_defined = false and EXCLUDED from the mean.
CREATE OR REPLACE TABLE components AS
SELECT s.GEOID,
  r.tiger_m, r.overture_m,
  coalesce(bo.n,0) AS bldg_ov, coalesce(bm.n,0) AS bldg_ms,
  coalesce(p.ov_all,0) AS ov_all, coalesce(p.ov_fire,0) AS ov_fire, coalesce(p.ov_ems,0) AS ov_ems, coalesce(p.ov_school,0) AS ov_school,
  coalesce(h.hf_fire,0) AS hf_fire, coalesce(h.hf_ems,0) AS hf_ems, coalesce(h.hf_school,0) AS hf_school,
  coalesce(c.cbp_estab,0) AS cbp_estab
FROM scored s
LEFT JOIN road_len r USING (GEOID) LEFT JOIN bldg_ov bo USING (GEOID) LEFT JOIN bldg_ms bm USING (GEOID)
LEFT JOIN poi_ov p USING (GEOID) LEFT JOIN hifld h USING (GEOID) LEFT JOIN cbp c USING (GEOID);

CREATE OR REPLACE TABLE gaps AS
WITH g AS (
  SELECT *,
    tiger_m > @TIGER_MIN_M@ AS transport_defined,
    CASE WHEN tiger_m > @TIGER_MIN_M@ THEN 1 - least(1.0, overture_m / tiger_m) END AS transport_raw,
    bldg_ms > 0 AS building_defined,
    CASE WHEN bldg_ms > 0 THEN 1 - least(1.0, bldg_ov::DOUBLE / bldg_ms) END AS building_raw,
    CASE WHEN hf_fire   > 0 THEN 1 - least(1.0, ov_fire::DOUBLE   / hf_fire)   END AS poi_gap_fire,
    CASE WHEN hf_ems    > 0 THEN 1 - least(1.0, ov_ems::DOUBLE    / hf_ems)    END AS poi_gap_ems,
    CASE WHEN hf_school > 0 THEN 1 - least(1.0, ov_school::DOUBLE / hf_school) END AS poi_gap_schools,
    CASE WHEN cbp_estab > 0 THEN 1 - least(1.0, ov_all::DOUBLE / cbp_estab) END AS poi_gap_cbp
  FROM components),
h AS (
  SELECT *, (SELECT NULL) AS _x,
    -- mean over the defined facility types
    CASE WHEN poi_gap_fire IS NULL AND poi_gap_ems IS NULL AND poi_gap_schools IS NULL THEN NULL
         ELSE (coalesce(poi_gap_fire,0)+coalesce(poi_gap_ems,0)+coalesce(poi_gap_schools,0))
              / ((poi_gap_fire IS NOT NULL)::INT + (poi_gap_ems IS NOT NULL)::INT + (poi_gap_schools IS NOT NULL)::INT) END AS poi_gap_hifld
  FROM g),
p AS (
  SELECT *,
    CASE WHEN poi_gap_hifld IS NULL AND poi_gap_cbp IS NULL THEN NULL
         ELSE (coalesce(poi_gap_hifld,0)+coalesce(poi_gap_cbp,0))
              / ((poi_gap_hifld IS NOT NULL)::INT + (poi_gap_cbp IS NOT NULL)::INT) END AS poi_raw
  FROM h)
SELECT *,
  coalesce(transport_raw,0) AS transport_gap, coalesce(building_raw,0) AS building_gap, coalesce(poi_raw,0) AS poi_gap,
  poi_raw IS NOT NULL AS poi_defined,
  CASE WHEN (transport_defined::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT) = 0 THEN NULL
       ELSE (coalesce(transport_raw,0)+coalesce(building_raw,0)+coalesce(poi_raw,0))
            / (transport_defined::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT) END AS coverage_gap_score,
  (transport_defined::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT) AS n_defined
FROM p;
