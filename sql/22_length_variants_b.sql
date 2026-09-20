-- Second batch of length variants, designed to separate "clip order" from "length metric".
-- V3: EXACTLY the V0 clip (project to 5070, clip against the projected tract), but the clipped
--     piece is sent back to lon/lat and measured with ST_Length_Spheroid. No membership can flip,
--     so V3-vs-V0 isolates the length metric alone.
-- V4: V0 clip, measured planar in 5070 but with ST_Intersection applied unconditionally
--     (no ST_CoveredBy fast path) - tests whether the overlay itself perturbs lengths.
SET geometry_always_xy = false;

WITH s AS (SELECT ST_GeomFromText('LINESTRING(-122.0 40.0, -122.0 40.01)') AS g),
m AS (SELECT ST_Length(ST_Transform(g,'EPSG:4326','EPSG:5070', always_xy := true)) AS len_5070,
             ST_Length_Spheroid(ST_FlipCoordinates(g)) AS len_spheroid,
             ST_Length_Spheroid(ST_FlipCoordinates(ST_Transform(ST_Transform(g,'EPSG:4326','EPSG:5070', always_xy := true),'EPSG:5070','EPSG:4326', always_xy := true))) AS len_roundtrip
     FROM s)
SELECT *, CASE WHEN abs(len_5070-1111.2) < 15 AND abs(len_spheroid-1111.2) < 5 AND abs(len_roundtrip-len_spheroid) < 1e-3
               AND NOT isnan(len_roundtrip) AND NOT isinf(len_roundtrip)
          THEN 'ok: axis order + roundtrip verified' ELSE error('axis/roundtrip check FAILED') END AS check_axis
FROM m;

CREATE OR REPLACE TEMP TABLE tiger_seg AS
SELECT ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) AS g
FROM read_parquet('data/reference/@R@/@R@-census-tiger-roads.parquet') WHERE MTFCC IN ('S1100','S1200');
CREATE OR REPLACE TEMP TABLE ov_seg AS
SELECT ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) AS g
FROM read_parquet('data/reference/@R@/@R@-overture-roads.parquet') WHERE class IN ('motorway','trunk','primary','secondary');

CREATE OR REPLACE TEMP TABLE tiger_c5070 AS
SELECT t.GEOID,
       CASE WHEN ST_CoveredBy(s.g, t.g5070) THEN s.g
            ELSE ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2) END AS c,
       ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2) AS c_always
FROM tiger_seg s JOIN tracts t ON ST_Intersects(s.g, t.g5070);
CREATE OR REPLACE TEMP TABLE ov_c5070 AS
SELECT t.GEOID,
       CASE WHEN ST_CoveredBy(s.g, t.g5070) THEN s.g
            ELSE ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2) END AS c,
       ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2) AS c_always
FROM ov_seg s JOIN tracts t ON ST_Intersects(s.g, t.g5070);

CREATE OR REPLACE TABLE road_len_alt_b AS
WITH a AS (
  SELECT GEOID,
    sum(ST_Length_Spheroid(ST_FlipCoordinates(ST_Transform(c,'EPSG:5070','EPSG:4326', always_xy := true)))) AS tiger_v3,
    sum(ST_Length(c_always)) AS tiger_v4
  FROM tiger_c5070 GROUP BY 1),
b AS (
  SELECT GEOID,
    sum(ST_Length_Spheroid(ST_FlipCoordinates(ST_Transform(c,'EPSG:5070','EPSG:4326', always_xy := true)))) AS ov_v3,
    sum(ST_Length(c_always)) AS ov_v4
  FROM ov_c5070 GROUP BY 1)
SELECT t.GEOID, coalesce(a.tiger_v3,0) AS tiger_v3, coalesce(b.ov_v3,0) AS ov_v3,
       coalesce(a.tiger_v4,0) AS tiger_v4, coalesce(b.ov_v4,0) AS ov_v4
FROM tracts t LEFT JOIN a USING (GEOID) LEFT JOIN b USING (GEOID);

SELECT CASE WHEN count(*) = 0 THEN 'ok: v3/v4 lengths finite' ELSE error('non-finite v3/v4 length') END AS check_b
FROM road_len_alt_b WHERE isnan(tiger_v3) OR isinf(tiger_v3) OR isnan(ov_v3) OR isinf(ov_v3)
                       OR isnan(tiger_v4) OR isinf(tiger_v4) OR isnan(ov_v4) OR isinf(ov_v4);
