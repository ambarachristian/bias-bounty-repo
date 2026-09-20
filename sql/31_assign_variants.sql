-- Assignment-rule variants that survive the MAE budget (the RMSE bound that killed them is void).
-- B1: buildings assigned by ST_PointOnSurface instead of ST_Centroid (differs for concave /
--     multipart footprints, where the centroid can fall outside the polygon).
-- P2: POIs assigned in EPSG:5070 instead of lon/lat, WITHOUT the DISTINCT ON that sql/05 removed --
--     so this isolates the projection choice alone, not the boundary bug already fixed.
LOAD spatial;
CREATE OR REPLACE TABLE bldg_pos AS
WITH ov AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT ST_PointOnSurface(geometry) AS c FROM read_parquet('data/reference/@R@/@R@-overture-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g, b.c) GROUP BY 1),
ms AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT ST_PointOnSurface(geometry) AS c FROM read_parquet('data/reference/@R@/@R@-microsoft-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g, b.c) GROUP BY 1)
SELECT t.GEOID, coalesce(ov.n,0) AS ov_pos, coalesce(ms.n,0) AS ms_pos
FROM tracts t LEFT JOIN ov USING (GEOID) LEFT JOIN ms USING (GEOID);

CREATE OR REPLACE TABLE poi_proj2 AS
WITH q AS (
  SELECT t.GEOID, p.cat
  FROM (SELECT ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) AS g,
               categories.primary AS cat
        FROM read_parquet('data/reference/@R@/@R@-overture-pois.parquet')) p
  JOIN tracts t ON ST_Intersects(t.g5070, p.g))
SELECT GEOID, count(*) AS ov_all_p,
  count(*) FILTER (WHERE cat='fire_department') AS ov_fire_p,
  count(*) FILTER (WHERE cat='ambulance_and_ems_services') AS ov_ems_p,
  count(*) FILTER (WHERE cat IN ('elementary_school','middle_school','high_school','school','private_school','public_school')) AS ov_school_p
FROM q GROUP BY 1;

SELECT '@R@' AS region,
  (SELECT sum(n) FROM bldg_ov) AS b0_ov, (SELECT sum(ov_pos) FROM bldg_pos) AS b1_ov,
  (SELECT sum(n) FROM bldg_ms) AS b0_ms, (SELECT sum(ms_pos) FROM bldg_pos) AS b1_ms,
  (SELECT count(*) FROM bldg_pos a JOIN bldg_ov o USING (GEOID) WHERE a.ov_pos <> o.n) AS tr_ov_differ,
  (SELECT count(*) FROM bldg_pos a JOIN bldg_ms m USING (GEOID) WHERE a.ms_pos <> m.n) AS tr_ms_differ,
  (SELECT sum(ov_all) FROM poi_ov) AS p0_poi, (SELECT sum(ov_all_p) FROM poi_proj2) AS p2_poi,
  (SELECT count(*) FROM poi_proj2 a JOIN poi_ov o USING (GEOID) WHERE a.ov_all_p <> o.ov_all) AS tr_poi_differ;
