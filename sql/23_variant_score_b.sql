-- SSE-of-change for every length variant computed so far, against the shipped V0 scores.
CREATE OR REPLACE TABLE variant_all AS
WITH base AS (
  SELECT c.*, a.tiger_sph, a.ov_sph, a.tiger_alb, a.ov_alb, b.tiger_v3, b.ov_v3, b.tiger_v4, b.ov_v4
  FROM components c JOIN road_len_alt a USING (GEOID) JOIN road_len_alt_b b USING (GEOID)
  WHERE c.GEOID IN (SELECT GEOID FROM scored)),
g AS (
  SELECT *,
    bldg_ms > 0 AS building_defined,
    CASE WHEN bldg_ms > 0 THEN 1 - least(1.0, bldg_ov::DOUBLE / bldg_ms) END AS building_raw,
    CASE WHEN hf_fire   > 0 THEN 1 - least(1.0, ov_fire::DOUBLE   / hf_fire)   END AS pg_fire,
    CASE WHEN hf_ems    > 0 THEN 1 - least(1.0, ov_ems::DOUBLE    / hf_ems)    END AS pg_ems,
    CASE WHEN hf_school > 0 THEN 1 - least(1.0, ov_school::DOUBLE / hf_school) END AS pg_school,
    CASE WHEN cbp_estab > 0 THEN 1 - least(1.0, ov_all::DOUBLE / cbp_estab) END AS pg_cbp
  FROM base),
h AS (SELECT *, CASE WHEN pg_fire IS NULL AND pg_ems IS NULL AND pg_school IS NULL THEN NULL
        ELSE (coalesce(pg_fire,0)+coalesce(pg_ems,0)+coalesce(pg_school,0))
             / ((pg_fire IS NOT NULL)::INT+(pg_ems IS NOT NULL)::INT+(pg_school IS NOT NULL)::INT) END AS pg_hifld FROM g),
p AS (SELECT *, CASE WHEN pg_hifld IS NULL AND pg_cbp IS NULL THEN NULL
        ELSE (coalesce(pg_hifld,0)+coalesce(pg_cbp,0))
             / ((pg_hifld IS NOT NULL)::INT+(pg_cbp IS NOT NULL)::INT) END AS poi_raw FROM h),
q AS (SELECT *, coalesce(building_raw,0)+coalesce(poi_raw,0) AS rest,
        building_defined::INT + (poi_raw IS NOT NULL)::INT AS nrest FROM p)
SELECT GEOID,
  (rest + CASE WHEN tiger_m  > 0 THEN 1-least(1.0, overture_m/tiger_m) ELSE 0 END) / nullif(nrest + (tiger_m  > 0)::INT,0) AS s0,
  (rest + CASE WHEN tiger_sph> 0 THEN 1-least(1.0, ov_sph/tiger_sph)   ELSE 0 END) / nullif(nrest + (tiger_sph> 0)::INT,0) AS s1,
  (rest + CASE WHEN tiger_alb> 0 THEN 1-least(1.0, ov_alb/tiger_alb)   ELSE 0 END) / nullif(nrest + (tiger_alb> 0)::INT,0) AS s2,
  (rest + CASE WHEN tiger_v3 > 0 THEN 1-least(1.0, ov_v3/tiger_v3)     ELSE 0 END) / nullif(nrest + (tiger_v3 > 0)::INT,0) AS s3,
  (rest + CASE WHEN tiger_v4 > 0 THEN 1-least(1.0, ov_v4/tiger_v4)     ELSE 0 END) / nullif(nrest + (tiger_v4 > 0)::INT,0) AS s4,
  (tiger_m>0) AS td0, (tiger_sph>0) AS td1, (tiger_alb>0) AS td2, (tiger_v3>0) AS td3, (tiger_v4>0) AS td4
FROM q;

SELECT CASE WHEN max(abs(v.s0 - g.coverage_gap_score)) > 1e-15 THEN error('V0 reconstruction mismatch')
            ELSE 'ok: V0 reproduces shipped scores' END AS check_v0
FROM variant_all v JOIN gaps g USING (GEOID);

SELECT '@R@' AS region, count(*) AS n,
  count(*) FILTER (WHERE NOT td0) AS u0, count(*) FILTER (WHERE NOT td1) AS u1,
  count(*) FILTER (WHERE NOT td2) AS u2, count(*) FILTER (WHERE NOT td3) AS u3,
  count(*) FILTER (WHERE NOT td4) AS u4
FROM variant_all;

SELECT '@R@' AS region, v AS variant, sse, maxabs, nchanged, n_over_bound FROM (
  SELECT 'v1_lonlat_clip_spheroid' AS v, sum(power(s1-s0,2)) AS sse, max(abs(s1-s0)) AS maxabs,
         count(*) FILTER (WHERE abs(s1-s0)>1e-12) AS nchanged, count(*) FILTER (WHERE abs(s1-s0)>3.3e-4) AS n_over_bound FROM variant_all
  UNION ALL SELECT 'v2_lonlat_clip_albers', sum(power(s2-s0,2)), max(abs(s2-s0)),
         count(*) FILTER (WHERE abs(s2-s0)>1e-12), count(*) FILTER (WHERE abs(s2-s0)>3.3e-4) FROM variant_all
  UNION ALL SELECT 'v3_v0clip_spheroid', sum(power(s3-s0,2)), max(abs(s3-s0)),
         count(*) FILTER (WHERE abs(s3-s0)>1e-12), count(*) FILTER (WHERE abs(s3-s0)>3.3e-4) FROM variant_all
  UNION ALL SELECT 'v4_always_intersection', sum(power(s4-s0,2)), max(abs(s4-s0)),
         count(*) FILTER (WHERE abs(s4-s0)>1e-12), count(*) FILTER (WHERE abs(s4-s0)>3.3e-4) FROM variant_all
) ORDER BY v;
