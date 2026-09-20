-- POI gap = mean of defined halves: (a) facilities half = mean over defined types of fire/EMS/schools
-- (Overture category counts vs USGS "hifld" counts); (b) establishments half = ALL Overture places vs CBP.
-- Boundary-inclusive assignment: a place is counted in EVERY tract whose polygon it intersects.
-- This is deliberately the same rule the HIFLD/USGS reference facilities below already use (plain
-- ST_Intersects, no de-duplication). An earlier DISTINCT ON (p.id) here kept only the lowest GEOID,
-- so a place on a shared tract edge was dropped from the numerator while the reference denominator
-- still counted it in both tracts -- the two sides of every ratio used different assignment rules.
CREATE OR REPLACE TEMP TABLE ov_poi AS
SELECT p.id, t.GEOID, p.cat
FROM (SELECT id, geometry AS g, categories.primary AS cat
      FROM read_parquet('data/reference/@R@/@R@-overture-pois.parquet')) p
JOIN tracts t ON ST_Intersects(t.g, p.g);
-- every POI must still land in at least one tract; assignments may exceed file rows (edge points).
SELECT count(*) AS poi_rows_in_join,
       count(DISTINCT id) AS poi_distinct_assigned,
       (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-overture-pois.parquet')) AS poi_rows_file,
       count(*) - count(DISTINCT id) AS poi_boundary_extra,
       CASE WHEN count(DISTINCT id) = (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-overture-pois.parquet'))
            THEN 'ok: every POI assigned to >=1 tract' ELSE error('POI assignment mismatch (points outside all tracts?)') END AS check_poi FROM ov_poi;

CREATE OR REPLACE TABLE poi_ov AS
SELECT GEOID,
  count(*) AS ov_all,
  count(*) FILTER (WHERE cat = 'fire_department') AS ov_fire,
  count(*) FILTER (WHERE cat = 'ambulance_and_ems_services') AS ov_ems,
  count(*) FILTER (WHERE cat IN ('elementary_school','middle_school','high_school','school','private_school','public_school')) AS ov_school
FROM ov_poi GROUP BY 1;

-- USGS/HIFLD reference facilities per tract (point-in-polygon)
CREATE OR REPLACE TABLE hifld AS
WITH f AS (
  SELECT 'fire' AS typ, geometry AS g FROM read_parquet('data/reference/@R@/@R@-hifld-fire-stations.parquet')
  UNION ALL SELECT 'ems', geometry FROM read_parquet('data/reference/@R@/@R@-hifld-ems-stations.parquet')
  UNION ALL SELECT 'school', geometry FROM read_parquet('data/reference/@R@/@R@-hifld-schools.parquet')
  UNION ALL SELECT 'hospital', geometry FROM read_parquet('data/reference/@R@/@R@-hifld-hospitals.parquet'))
SELECT t.GEOID,
  count(*) FILTER (WHERE typ='fire') AS hf_fire, count(*) FILTER (WHERE typ='ems') AS hf_ems,
  count(*) FILTER (WHERE typ='school') AS hf_school, count(*) FILTER (WHERE typ='hospital') AS hf_hosp
FROM f JOIN tracts t ON ST_Intersects(t.g, f.g) GROUP BY 1;

SELECT (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-hifld-fire-stations.parquet')) AS fire_rows, (SELECT sum(hf_fire) FROM hifld) AS fire_assigned,
       (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-hifld-ems-stations.parquet')) AS ems_rows, (SELECT sum(hf_ems) FROM hifld) AS ems_assigned,
       (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-hifld-schools.parquet')) AS school_rows, (SELECT sum(hf_school) FROM hifld) AS school_assigned;

CREATE OR REPLACE TABLE cbp AS
SELECT GEOID, cbp_estab, cbp_estab_bus, cbp_estab_res FROM read_parquet('data/reference/@R@/@R@-census-cbp.parquet');
