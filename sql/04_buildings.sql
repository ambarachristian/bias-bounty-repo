-- Building gap: Overture building COUNT vs Microsoft building COUNT per tract.
-- A footprint is assigned to the tract containing its centroid (CRS84 planar is fine for point-in-polygon).
-- Streamed: only the small tract table is held in memory. bbox prefilter is not needed (we scan everything).
CREATE OR REPLACE TABLE bldg_ov AS
SELECT t.GEOID, count(*) AS n
FROM (SELECT ST_Centroid(geometry) AS c FROM read_parquet('data/reference/@R@/@R@-overture-buildings.parquet')) b
JOIN tracts t ON ST_Intersects(t.g, b.c)
GROUP BY 1;

CREATE OR REPLACE TABLE bldg_ms AS
SELECT t.GEOID, count(*) AS n
FROM (SELECT ST_Centroid(geometry) AS c FROM read_parquet('data/reference/@R@/@R@-microsoft-buildings.parquet')) b
JOIN tracts t ON ST_Intersects(t.g, b.c)
GROUP BY 1;

SELECT (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-overture-buildings.parquet')) AS ov_rows,
       (SELECT sum(n) FROM bldg_ov) AS ov_assigned,
       (SELECT count(*) FROM read_parquet('data/reference/@R@/@R@-microsoft-buildings.parquet')) AS ms_rows,
       (SELECT sum(n) FROM bldg_ms) AS ms_assigned;
