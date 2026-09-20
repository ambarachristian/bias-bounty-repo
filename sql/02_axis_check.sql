-- Known-length test segment: 0.01 deg of latitude at lon -122, lat 40..40.01  ~= 1111.2 m on the spheroid.
WITH s AS (SELECT ST_GeomFromText('LINESTRING(-122.0 40.0, -122.0 40.01)') AS g),
m AS (SELECT
  ST_Length(ST_Transform(g,'EPSG:4326','EPSG:5070', always_xy := true)) AS len_5070,
  ST_Length_Spheroid(ST_FlipCoordinates(g)) AS len_spheroid,
  ST_Length(ST_Transform(g,'EPSG:4326','EPSG:5070')) AS len_5070_BROKEN,
  ST_Length_Spheroid(g) AS len_spheroid_BROKEN
  FROM s)
SELECT *, CASE WHEN abs(len_5070 - 1111.2) < 15 AND abs(len_spheroid - 1111.2) < 5
               THEN 'ok: axis order verified' ELSE error('axis-order check FAILED') END AS check_axis
FROM m;
