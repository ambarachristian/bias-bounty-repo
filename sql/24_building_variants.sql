-- Building-assignment variants. Building counts are large, so a handful of re-assigned footprints
-- moves the composite by ~1e-4 - exactly the order the residual allows. Worth measuring precisely.
-- B0 (shipped): tract containing ST_Centroid(footprint).
-- B1: tract containing ST_PointOnSurface(footprint)  (differs for concave / multipart footprints).
-- B2: every tract the footprint ST_Intersects (a straddling footprint counts in both).
CREATE OR REPLACE TABLE bldg_alt AS
WITH ov1 AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT ST_PointOnSurface(geometry) AS c FROM read_parquet('data/reference/@R@/@R@-overture-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g, b.c) GROUP BY 1),
ms1 AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT ST_PointOnSurface(geometry) AS c FROM read_parquet('data/reference/@R@/@R@-microsoft-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g, b.c) GROUP BY 1),
ov2 AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT geometry AS g FROM read_parquet('data/reference/@R@/@R@-overture-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g, b.g) GROUP BY 1),
ms2 AS (
  SELECT t.GEOID, count(*) AS n FROM
    (SELECT geometry AS g FROM read_parquet('data/reference/@R@/@R@-microsoft-buildings.parquet')) b
    JOIN tracts t ON ST_Intersects(t.g, b.g) GROUP BY 1)
SELECT t.GEOID,
       coalesce(ov1.n,0) AS ov_b1, coalesce(ms1.n,0) AS ms_b1,
       coalesce(ov2.n,0) AS ov_b2, coalesce(ms2.n,0) AS ms_b2
FROM tracts t LEFT JOIN ov1 USING (GEOID) LEFT JOIN ms1 USING (GEOID)
              LEFT JOIN ov2 USING (GEOID) LEFT JOIN ms2 USING (GEOID);

SELECT '@R@' AS region,
  (SELECT sum(n) FROM bldg_ov) AS b0_ov, (SELECT sum(ov_b1) FROM bldg_alt) AS b1_ov, (SELECT sum(ov_b2) FROM bldg_alt) AS b2_ov,
  (SELECT sum(n) FROM bldg_ms) AS b0_ms, (SELECT sum(ms_b1) FROM bldg_alt) AS b1_ms, (SELECT sum(ms_b2) FROM bldg_alt) AS b2_ms,
  (SELECT count(*) FROM bldg_alt a JOIN bldg_ov o USING (GEOID) WHERE a.ov_b1 <> o.n) AS tracts_ov_b1_differ,
  (SELECT count(*) FROM bldg_alt a JOIN bldg_ms m USING (GEOID) WHERE a.ms_b1 <> m.n) AS tracts_ms_b1_differ;
