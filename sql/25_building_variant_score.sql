-- SSE-of-change for the building-assignment variants.
CREATE OR REPLACE TABLE bldg_variant_score AS
WITH base AS (
  SELECT c.*, a.ov_b1, a.ms_b1, a.ov_b2, a.ms_b2
  FROM components c JOIN bldg_alt a USING (GEOID)
  WHERE c.GEOID IN (SELECT GEOID FROM scored)),
g AS (
  SELECT *,
    CASE WHEN hf_fire   > 0 THEN 1 - least(1.0, ov_fire::DOUBLE   / hf_fire)   END AS pg_fire,
    CASE WHEN hf_ems    > 0 THEN 1 - least(1.0, ov_ems::DOUBLE    / hf_ems)    END AS pg_ems,
    CASE WHEN hf_school > 0 THEN 1 - least(1.0, ov_school::DOUBLE / hf_school) END AS pg_school,
    CASE WHEN cbp_estab > 0 THEN 1 - least(1.0, ov_all::DOUBLE / cbp_estab) END AS pg_cbp,
    CASE WHEN tiger_m > 0 THEN 1 - least(1.0, overture_m / tiger_m) END AS tr
  FROM base),
h AS (SELECT *, CASE WHEN pg_fire IS NULL AND pg_ems IS NULL AND pg_school IS NULL THEN NULL
        ELSE (coalesce(pg_fire,0)+coalesce(pg_ems,0)+coalesce(pg_school,0))
             / ((pg_fire IS NOT NULL)::INT+(pg_ems IS NOT NULL)::INT+(pg_school IS NOT NULL)::INT) END AS pg_hifld FROM g),
p AS (SELECT *, CASE WHEN pg_hifld IS NULL AND pg_cbp IS NULL THEN NULL
        ELSE (coalesce(pg_hifld,0)+coalesce(pg_cbp,0))
             / ((pg_hifld IS NOT NULL)::INT+(pg_cbp IS NOT NULL)::INT) END AS poi_raw FROM h),
q AS (SELECT *, coalesce(tr,0)+coalesce(poi_raw,0) AS rest, (tiger_m>0)::INT + (poi_raw IS NOT NULL)::INT AS nrest FROM p)
SELECT GEOID,
  (rest + CASE WHEN bldg_ms > 0 THEN 1-least(1.0, bldg_ov::DOUBLE/bldg_ms) ELSE 0 END)/nullif(nrest+(bldg_ms>0)::INT,0) AS s0,
  (rest + CASE WHEN ms_b1  > 0 THEN 1-least(1.0, ov_b1::DOUBLE/ms_b1)      ELSE 0 END)/nullif(nrest+(ms_b1 >0)::INT,0) AS sb1,
  (rest + CASE WHEN ms_b2  > 0 THEN 1-least(1.0, ov_b2::DOUBLE/ms_b2)      ELSE 0 END)/nullif(nrest+(ms_b2 >0)::INT,0) AS sb2
FROM q;

SELECT CASE WHEN max(abs(v.s0-g.coverage_gap_score)) > 1e-15 THEN error('B0 reconstruction mismatch')
            ELSE 'ok: B0 reproduces shipped scores' END AS check_b0
FROM bldg_variant_score v JOIN gaps g USING (GEOID);

SELECT '@R@' AS region, v AS variant, sse, maxabs, nchanged, n_over_bound FROM (
  SELECT 'b1_point_on_surface' AS v, sum(power(sb1-s0,2)) AS sse, max(abs(sb1-s0)) AS maxabs,
         count(*) FILTER (WHERE abs(sb1-s0)>1e-12) AS nchanged, count(*) FILTER (WHERE abs(sb1-s0)>3.3e-4) AS n_over_bound FROM bldg_variant_score
  UNION ALL SELECT 'b2_footprint_intersects', sum(power(sb2-s0,2)), max(abs(sb2-s0)),
         count(*) FILTER (WHERE abs(sb2-s0)>1e-12), count(*) FILTER (WHERE abs(sb2-s0)>3.3e-4) FROM bldg_variant_score
) ORDER BY v;
