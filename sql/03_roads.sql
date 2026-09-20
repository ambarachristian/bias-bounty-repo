-- Road network gap. Named highways only. Lengths in EPSG:5070 metres, clipped to tract polygons.
-- TIGER S1100/S1200 vs Overture motorway/trunk/primary/secondary.
CREATE OR REPLACE TEMP TABLE tiger_seg AS
SELECT ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) AS g
FROM read_parquet('data/reference/@R@/@R@-census-tiger-roads.parquet')
WHERE MTFCC IN ('S1100','S1200');

CREATE OR REPLACE TEMP TABLE ov_seg AS
SELECT ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) AS g
FROM read_parquet('data/reference/@R@/@R@-overture-roads.parquet')
WHERE class IN ('motorway','trunk','primary','secondary');

SELECT (SELECT count(*) FROM tiger_seg) AS n_tiger_hwy, (SELECT count(*) FROM ov_seg) AS n_overture_hwy,
       CASE WHEN (SELECT count(*) FROM tiger_seg WHERE isinf(ST_Length(g)) OR isnan(ST_Length(g))) = 0
             AND (SELECT count(*) FROM ov_seg WHERE isinf(ST_Length(g)) OR isnan(ST_Length(g))) = 0
            THEN 'ok: finite lengths' ELSE error('non-finite road lengths') END AS check_finite;

-- clipped length per tract (segments crossing a tract line contribute the portion inside each tract)
CREATE OR REPLACE TABLE road_len AS
WITH a AS (
  SELECT t.GEOID, sum(CASE WHEN ST_CoveredBy(s.g, t.g5070) THEN ST_Length(s.g)
       ELSE ST_Length(ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2)) END) AS tiger_m,
       count(*) AS tiger_n
  FROM tiger_seg s JOIN tracts t ON ST_Intersects(s.g, t.g5070) GROUP BY 1),
b AS (
  SELECT t.GEOID, sum(CASE WHEN ST_CoveredBy(s.g, t.g5070) THEN ST_Length(s.g)
       ELSE ST_Length(ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2)) END) AS ov_m,
       count(*) AS ov_n
  FROM ov_seg s JOIN tracts t ON ST_Intersects(s.g, t.g5070) GROUP BY 1)
SELECT t.GEOID, coalesce(a.tiger_m,0) AS tiger_m, coalesce(a.tiger_n,0) AS tiger_n,
       coalesce(b.ov_m,0) AS overture_m, coalesce(b.ov_n,0) AS overture_n
FROM tracts t LEFT JOIN a USING (GEOID) LEFT JOIN b USING (GEOID);

-- alternative reading: whole segment assigned to the tract holding its representative point (ST_PointOnSurface) (sensitivity only)
CREATE OR REPLACE TABLE road_len_mid AS
WITH a AS (
  SELECT t.GEOID, sum(ST_Length(s.g)) AS tiger_m
  FROM tiger_seg s JOIN tracts t ON ST_Intersects(ST_PointOnSurface(s.g), t.g5070) GROUP BY 1),
b AS (
  SELECT t.GEOID, sum(ST_Length(s.g)) AS ov_m
  FROM ov_seg s JOIN tracts t ON ST_Intersects(ST_PointOnSurface(s.g), t.g5070) GROUP BY 1)
SELECT t.GEOID, coalesce(a.tiger_m,0) AS tiger_m, coalesce(b.ov_m,0) AS overture_m
FROM tracts t LEFT JOIN a USING (GEOID) LEFT JOIN b USING (GEOID);
