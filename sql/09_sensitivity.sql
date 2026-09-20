-- RMSE of the final score between the chosen reading and alternative readings (informational only).
-- usage: ./bin/duckdb -markdown db/<region>.duckdb < sql/09_sensitivity.sql
WITH base AS (
  SELECT g.*, m.tiger_m AS tiger_mid, m.overture_m AS ov_mid FROM gaps g JOIN road_len_mid m USING (GEOID)),
alt AS (
  SELECT GEOID, coverage_gap_score AS s0,
    -- A: road length by representative point instead of clipping
    (SELECT s FROM (SELECT (coalesce(CASE WHEN tiger_mid>0 THEN 1-least(1,ov_mid/tiger_mid) END,0)+building_gap*building_defined::INT+poi_gap*poi_defined::INT)
        / nullif((tiger_mid>0)::INT+building_defined::INT+poi_defined::INT,0) AS s)) AS s_roadmid,
    -- B: POI half undefined counted as 0 (divide by 2) instead of mean of defined halves
    (coalesce(transport_raw,0)+coalesce(building_raw,0)
       + CASE WHEN poi_raw IS NULL THEN 0 ELSE (coalesce(poi_gap_hifld,0)+coalesce(poi_gap_cbp,0))/2 END)
       / nullif(n_defined,0) AS s_poi_half0,
    -- C: fixed divisor 3 (ignore the variable-divisor rule) -- expected to be wrong, shows why the rule matters
    (transport_gap+building_gap+poi_gap)/3 AS s_div3,
    -- D: ACS-free but with building gap from raw counts already; CBP threshold >=1 establishment
    (coalesce(transport_raw,0)+coalesce(building_raw,0)
       + coalesce(CASE WHEN hf_fire+hf_ems+hf_school=0 AND cbp_estab<1 THEN NULL
                       ELSE ((coalesce(poi_gap_hifld,0)*(poi_gap_hifld IS NOT NULL)::INT) + (coalesce(CASE WHEN cbp_estab>=1 THEN poi_gap_cbp END,0)*(cbp_estab>=1)::INT))
                            / nullif((poi_gap_hifld IS NOT NULL)::INT+(cbp_estab>=1)::INT,0) END,0))
       / nullif(transport_defined::INT+building_defined::INT+(NOT (hf_fire+hf_ems+hf_school=0 AND cbp_estab<1))::INT,0) AS s_cbp_ge1
  FROM base)
SELECT '@R@' AS region, round(sqrt(avg(power(s0-s_roadmid,2))),4) AS rmse_roadmid, round(sqrt(avg(power(s0-s_poi_half0,2))),4) AS rmse_poi_half_as_0,
       round(sqrt(avg(power(s0-s_div3,2))),4) AS rmse_fixed_divisor_3, round(sqrt(avg(power(s0-s_cbp_ge1,2))),4) AS rmse_cbp_threshold_1
FROM alt;
