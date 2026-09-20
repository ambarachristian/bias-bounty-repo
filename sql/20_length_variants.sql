-- Precision hunt: alternative road-length measurements, per tract.
-- V0 (= existing table road_len): project each segment to EPSG:5070 FIRST, then clip to the
--     projected tract polygon, measure planar ST_Length.
-- V1: clip in lon/lat (CRS84) against the unprojected tract polygon, measure
--     ST_Length_Spheroid(ST_FlipCoordinates(..))  -- the README's other published recipe.
-- V2: clip in lon/lat, THEN project the clipped piece to 5070 and measure planar.
--     (V2 vs V0 isolates clip-order alone; V1 vs V2 isolates the length metric alone.)
SET geometry_always_xy = false;   -- keep ST_Length_Spheroid on lat/lon, matching ST_FlipCoordinates

-- axis-order sanity check for BOTH metrics before anything is aggregated
WITH s AS (SELECT ST_GeomFromText('LINESTRING(-122.0 40.0, -122.0 40.01)') AS g),
m AS (SELECT ST_Length(ST_Transform(g,'EPSG:4326','EPSG:5070', always_xy := true)) AS len_5070,
             ST_Length_Spheroid(ST_FlipCoordinates(g)) AS len_spheroid FROM s)
SELECT *, CASE WHEN abs(len_5070 - 1111.2) < 15 AND abs(len_spheroid - 1111.2) < 5
               AND NOT isnan(len_5070) AND NOT isnan(len_spheroid)
               AND NOT isinf(len_5070) AND NOT isinf(len_spheroid)
          THEN 'ok: axis order verified (both metrics)' ELSE error('axis-order check FAILED') END AS check_axis
FROM m;

CREATE OR REPLACE TEMP TABLE tiger_ll AS
SELECT geometry AS g FROM read_parquet('data/reference/@R@/@R@-census-tiger-roads.parquet')
WHERE MTFCC IN ('S1100','S1200');

CREATE OR REPLACE TEMP TABLE ov_ll AS
SELECT geometry AS g FROM read_parquet('data/reference/@R@/@R@-overture-roads.parquet')
WHERE class IN ('motorway','trunk','primary','secondary');

CREATE OR REPLACE TEMP TABLE tiger_clip AS
SELECT t.GEOID,
       CASE WHEN ST_CoveredBy(s.g, t.g) THEN s.g
            ELSE ST_CollectionExtract(ST_Intersection(s.g, t.g), 2) END AS c
FROM tiger_ll s JOIN tracts t ON ST_Intersects(s.g, t.g);

CREATE OR REPLACE TEMP TABLE ov_clip AS
SELECT t.GEOID,
       CASE WHEN ST_CoveredBy(s.g, t.g) THEN s.g
            ELSE ST_CollectionExtract(ST_Intersection(s.g, t.g), 2) END AS c
FROM ov_ll s JOIN tracts t ON ST_Intersects(s.g, t.g);

CREATE OR REPLACE TABLE road_len_alt AS
WITH a AS (
  SELECT GEOID,
         sum(ST_Length_Spheroid(ST_FlipCoordinates(c))) AS tiger_sph,
         sum(ST_Length(ST_Transform(c,'EPSG:4326','EPSG:5070', always_xy := true))) AS tiger_alb
  FROM tiger_clip GROUP BY 1),
b AS (
  SELECT GEOID,
         sum(ST_Length_Spheroid(ST_FlipCoordinates(c))) AS ov_sph,
         sum(ST_Length(ST_Transform(c,'EPSG:4326','EPSG:5070', always_xy := true))) AS ov_alb
  FROM ov_clip GROUP BY 1)
SELECT t.GEOID,
       coalesce(a.tiger_sph,0) AS tiger_sph, coalesce(b.ov_sph,0) AS ov_sph,
       coalesce(a.tiger_alb,0) AS tiger_alb, coalesce(b.ov_alb,0) AS ov_alb
FROM tracts t LEFT JOIN a USING (GEOID) LEFT JOIN b USING (GEOID);

SELECT CASE WHEN count(*) = 0 THEN 'ok: alt road lengths finite'
            ELSE error('non-finite alt road length: ' || count(*)) END AS check_alt_finite
FROM road_len_alt
WHERE isnan(tiger_sph) OR isinf(tiger_sph) OR isnan(ov_sph) OR isinf(ov_sph)
   OR isnan(tiger_alb) OR isinf(tiger_alb) OR isnan(ov_alb) OR isinf(ov_alb);

-- how far apart are the three measurements at region level?
SELECT '@R@' AS region,
       sum(tiger_m)/1000 AS v0_tiger_km, sum(overture_m)/1000 AS v0_ov_km,
       sum(tiger_alb)/1000 AS v2_tiger_km, sum(ov_alb)/1000 AS v2_ov_km,
       sum(tiger_sph)/1000 AS v1_tiger_km, sum(ov_sph)/1000 AS v1_ov_km
FROM road_len JOIN road_len_alt USING (GEOID);
