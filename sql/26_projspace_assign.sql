-- Assignment-in-projected-space variants. Point-in-polygon is projection-invariant except within
-- ~micrometres of a tract edge, so these can only move a handful of features - the only class of
-- hypothesis left whose per-tract effect is small enough to fit the observed residual.
-- P1 buildings: ST_Centroid computed in EPSG:5070, tested against the projected tract.
-- P2 POIs: point tested against the projected tract.
CREATE OR REPLACE TABLE bldg_proj AS
WITH ov AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT ST_Centroid(ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true)) AS c
     FROM read_parquet('data/reference/@R@/@R@-overture-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g5070, b.c) GROUP BY 1),
ms AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT ST_Centroid(ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true)) AS c
     FROM read_parquet('data/reference/@R@/@R@-microsoft-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g5070, b.c) GROUP BY 1)
SELECT t.GEOID, coalesce(ov.n,0) AS ov_p1, coalesce(ms.n,0) AS ms_p1
FROM tracts t LEFT JOIN ov USING (GEOID) LEFT JOIN ms USING (GEOID);

CREATE OR REPLACE TABLE poi_proj AS
WITH q AS (
  SELECT DISTINCT ON (p.id) t.GEOID, p.cat
  FROM (SELECT id, ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) AS g,
               categories.primary AS cat
        FROM read_parquet('data/reference/@R@/@R@-overture-pois.parquet')) p
  JOIN tracts t ON ST_Intersects(t.g5070, p.g)
  ORDER BY p.id, t.GEOID)
SELECT GEOID, count(*) AS ov_all_p,
  count(*) FILTER (WHERE cat='fire_department') AS ov_fire_p,
  count(*) FILTER (WHERE cat='ambulance_and_ems_services') AS ov_ems_p,
  count(*) FILTER (WHERE cat IN ('elementary_school','middle_school','high_school','school','private_school','public_school')) AS ov_school_p
FROM q GROUP BY 1;

SELECT '@R@' AS region,
  (SELECT sum(n) FROM bldg_ov) AS b0_ov_tot, (SELECT sum(ov_p1) FROM bldg_proj) AS p1_ov_tot,
  (SELECT sum(n) FROM bldg_ms) AS b0_ms_tot, (SELECT sum(ms_p1) FROM bldg_proj) AS p1_ms_tot,
  (SELECT count(*) FROM bldg_proj a JOIN bldg_ov o USING (GEOID) WHERE a.ov_p1 <> o.n) AS tracts_ov_differ,
  (SELECT count(*) FROM bldg_proj a JOIN bldg_ms m USING (GEOID) WHERE a.ms_p1 <> m.n) AS tracts_ms_differ,
  (SELECT sum(ov_all_p) FROM poi_proj) AS p2_poi_tot, (SELECT sum(ov_all) FROM poi_ov) AS b0_poi_tot,
  (SELECT count(*) FROM poi_proj a JOIN poi_ov o USING (GEOID) WHERE a.ov_all_p <> o.ov_all) AS tracts_poi_differ;
