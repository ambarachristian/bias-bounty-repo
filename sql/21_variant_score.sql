-- Rescore a region under each road-length variant and compare to the shipped (V0) scores.
-- Emits per-variant: undefined count (must stay at the organisers' published value),
-- SSE of the change in coverage_gap_score, max |delta|, and how concentrated the change is.
CREATE OR REPLACE TABLE variant_scores AS
WITH base AS (
  SELECT c.*, a.tiger_sph, a.ov_sph, a.tiger_alb, a.ov_alb
  FROM components c JOIN road_len_alt a USING (GEOID)
  WHERE c.GEOID IN (SELECT GEOID FROM scored)
),
v AS (
  SELECT GEOID,
    -- V0: as shipped
    tiger_m AS t0, overture_m AS o0,
    -- V1: clip in lon/lat, spheroid length
    tiger_sph AS t1, ov_sph AS o1,
    -- V2: clip in lon/lat, then project, planar length
    tiger_alb AS t2, ov_alb AS o2,
    bldg_ov, bldg_ms, ov_all, ov_fire, ov_ems, ov_school, hf_fire, hf_ems, hf_school, cbp_estab
  FROM base
),
g AS (
  SELECT *,
    bldg_ms > 0 AS building_defined,
    CASE WHEN bldg_ms > 0 THEN 1 - least(1.0, bldg_ov::DOUBLE / bldg_ms) END AS building_raw,
    CASE WHEN hf_fire   > 0 THEN 1 - least(1.0, ov_fire::DOUBLE   / hf_fire)   END AS pg_fire,
    CASE WHEN hf_ems    > 0 THEN 1 - least(1.0, ov_ems::DOUBLE    / hf_ems)    END AS pg_ems,
    CASE WHEN hf_school > 0 THEN 1 - least(1.0, ov_school::DOUBLE / hf_school) END AS pg_school,
    CASE WHEN cbp_estab > 0 THEN 1 - least(1.0, ov_all::DOUBLE / cbp_estab) END AS pg_cbp
  FROM v
),
h AS (
  SELECT *,
    CASE WHEN pg_fire IS NULL AND pg_ems IS NULL AND pg_school IS NULL THEN NULL
         ELSE (coalesce(pg_fire,0)+coalesce(pg_ems,0)+coalesce(pg_school,0))
              / ((pg_fire IS NOT NULL)::INT + (pg_ems IS NOT NULL)::INT + (pg_school IS NOT NULL)::INT) END AS pg_hifld
  FROM g
),
p AS (
  SELECT *,
    CASE WHEN pg_hifld IS NULL AND pg_cbp IS NULL THEN NULL
         ELSE (coalesce(pg_hifld,0)+coalesce(pg_cbp,0))
              / ((pg_hifld IS NOT NULL)::INT + (pg_cbp IS NOT NULL)::INT) END AS poi_raw
  FROM h
)
SELECT GEOID,
  t0 > 0 AS td0, t1 > 0 AS td1, t2 > 0 AS td2,
  CASE WHEN t0 > 0 THEN 1 - least(1.0, o0/t0) END AS tr0,
  CASE WHEN t1 > 0 THEN 1 - least(1.0, o1/t1) END AS tr1,
  CASE WHEN t2 > 0 THEN 1 - least(1.0, o2/t2) END AS tr2,
  building_raw, building_defined, poi_raw,
  pg_fire, pg_ems, pg_school, pg_cbp, pg_hifld,
  hf_fire, hf_ems, hf_school, cbp_estab
FROM p;

CREATE OR REPLACE TABLE variant_final AS
SELECT GEOID,
  (coalesce(tr0,0)+coalesce(building_raw,0)+coalesce(poi_raw,0))
    / nullif(td0::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT, 0) AS s0,
  (coalesce(tr1,0)+coalesce(building_raw,0)+coalesce(poi_raw,0))
    / nullif(td1::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT, 0) AS s1,
  (coalesce(tr2,0)+coalesce(building_raw,0)+coalesce(poi_raw,0))
    / nullif(td2::INT + building_defined::INT + (poi_raw IS NOT NULL)::INT, 0) AS s2,
  td0, td1, td2, tr0, tr1, tr2
FROM variant_scores;

-- sanity: our recomputed s0 must reproduce the shipped gaps table exactly
SELECT CASE WHEN max(abs(f.s0 - g.coverage_gap_score)) > 1e-15
            THEN error('V0 reconstruction mismatch') ELSE 'ok: V0 reproduces shipped scores' END AS check_v0
FROM variant_final f JOIN gaps g USING (GEOID);

SELECT '@R@' AS region, count(*) AS n,
  count(*) FILTER (WHERE NOT td0) AS undef_v0,
  count(*) FILTER (WHERE NOT td1) AS undef_v1,
  count(*) FILTER (WHERE NOT td2) AS undef_v2,
  sum((s1-s0)*(s1-s0)) AS sse_v1, max(abs(s1-s0)) AS maxabs_v1,
  count(*) FILTER (WHERE abs(s1-s0) > 1e-12) AS nchanged_v1,
  sum((s2-s0)*(s2-s0)) AS sse_v2, max(abs(s2-s0)) AS maxabs_v2,
  count(*) FILTER (WHERE abs(s2-s0) > 1e-12) AS nchanged_v2
FROM variant_final;
