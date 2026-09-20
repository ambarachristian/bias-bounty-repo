-- SSE-of-change for assigning POIs to tracts in EPSG:5070 instead of lon/lat (table poi_proj).
CREATE OR REPLACE TABLE poi_proj_score AS
WITH base AS (
  SELECT c.*, coalesce(p.ov_all_p,0) AS ov_all_p, coalesce(p.ov_fire_p,0) AS ov_fire_p,
         coalesce(p.ov_ems_p,0) AS ov_ems_p, coalesce(p.ov_school_p,0) AS ov_school_p
  FROM components c LEFT JOIN poi_proj p USING (GEOID)
  WHERE c.GEOID IN (SELECT GEOID FROM scored)),
g AS (
  SELECT *,
    CASE WHEN tiger_m > 0 THEN 1 - least(1.0, overture_m/tiger_m) END AS tr,
    CASE WHEN bldg_ms > 0 THEN 1 - least(1.0, bldg_ov::DOUBLE/bldg_ms) END AS br,
    CASE WHEN hf_fire  >0 THEN 1-least(1.0, ov_fire::DOUBLE/hf_fire)     END AS f0,
    CASE WHEN hf_fire  >0 THEN 1-least(1.0, ov_fire_p::DOUBLE/hf_fire)   END AS f1,
    CASE WHEN hf_ems   >0 THEN 1-least(1.0, ov_ems::DOUBLE/hf_ems)       END AS e0,
    CASE WHEN hf_ems   >0 THEN 1-least(1.0, ov_ems_p::DOUBLE/hf_ems)     END AS e1,
    CASE WHEN hf_school>0 THEN 1-least(1.0, ov_school::DOUBLE/hf_school) END AS c0,
    CASE WHEN hf_school>0 THEN 1-least(1.0, ov_school_p::DOUBLE/hf_school) END AS c1,
    CASE WHEN cbp_estab>0 THEN 1-least(1.0, ov_all::DOUBLE/cbp_estab)    END AS k0,
    CASE WHEN cbp_estab>0 THEN 1-least(1.0, ov_all_p::DOUBLE/cbp_estab)  END AS k1
  FROM base),
h AS (SELECT *,
    CASE WHEN f0 IS NULL AND e0 IS NULL AND c0 IS NULL THEN NULL ELSE (coalesce(f0,0)+coalesce(e0,0)+coalesce(c0,0))
      /((f0 IS NOT NULL)::INT+(e0 IS NOT NULL)::INT+(c0 IS NOT NULL)::INT) END AS hf0,
    CASE WHEN f1 IS NULL AND e1 IS NULL AND c1 IS NULL THEN NULL ELSE (coalesce(f1,0)+coalesce(e1,0)+coalesce(c1,0))
      /((f1 IS NOT NULL)::INT+(e1 IS NOT NULL)::INT+(c1 IS NOT NULL)::INT) END AS hf1
  FROM g),
p AS (SELECT *,
    CASE WHEN hf0 IS NULL AND k0 IS NULL THEN NULL ELSE (coalesce(hf0,0)+coalesce(k0,0))/((hf0 IS NOT NULL)::INT+(k0 IS NOT NULL)::INT) END AS pr0,
    CASE WHEN hf1 IS NULL AND k1 IS NULL THEN NULL ELSE (coalesce(hf1,0)+coalesce(k1,0))/((hf1 IS NOT NULL)::INT+(k1 IS NOT NULL)::INT) END AS pr1
  FROM h),
q AS (SELECT *, coalesce(tr,0)+coalesce(br,0) AS rest, (tiger_m>0)::INT+(bldg_ms>0)::INT AS nrest FROM p)
SELECT GEOID,
  (rest+coalesce(pr0,0))/nullif(nrest+(pr0 IS NOT NULL)::INT,0) AS s0,
  (rest+coalesce(pr1,0))/nullif(nrest+(pr1 IS NOT NULL)::INT,0) AS sp
FROM q;

SELECT CASE WHEN max(abs(v.s0-g.coverage_gap_score)) > 1e-15 THEN error('P0 reconstruction mismatch')
            ELSE 'ok: P0 reproduces shipped scores' END AS check_p0
FROM poi_proj_score v JOIN gaps g USING (GEOID);

SELECT '@R@' AS region, 'p2_poi_assign_in_5070' AS variant,
  sum(power(sp-s0,2)) AS sse, max(abs(sp-s0)) AS maxabs,
  count(*) FILTER (WHERE abs(sp-s0)>1e-12) AS nchanged,
  count(*) FILTER (WHERE abs(sp-s0)>3.2985e-4) AS n_over_bound
FROM poi_proj_score;
