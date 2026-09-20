-- Probe (northern-ca only, informational): if road length lying exactly on a shared tract edge were counted ONCE
-- (given to the lowest GEOID) instead of in both tracts, how many tracts would lose all TIGER highway length?
LOAD spatial;
CREATE OR REPLACE TEMP TABLE ts AS SELECT row_number() OVER () id, ST_Transform(geometry,'EPSG:4326','EPSG:5070', always_xy := true) g
  FROM 'data/reference/northern-ca/northern-ca-census-tiger-roads.parquet' WHERE MTFCC IN ('S1100','S1200');
CREATE OR REPLACE TEMP TABLE pc AS
  SELECT s.id, t.GEOID, ST_CollectionExtract(ST_Intersection(s.g, t.g5070), 2) AS p
  FROM ts s JOIN tracts t ON ST_Intersects(s.g, t.g5070);
CREATE OR REPLACE TEMP TABLE pc2 AS
  SELECT a.id, a.GEOID,
    CASE WHEN count(b.GEOID)=0 THEN ST_Length(a.p)
         ELSE ST_Length(ST_Difference(a.p, ST_Buffer(ST_Union_Agg(b.p), 0.01))) END AS len_dedup
  FROM pc a LEFT JOIN pc b ON a.id=b.id AND b.GEOID<a.GEOID AND ST_Length(b.p)>0
  GROUP BY a.id, a.GEOID, a.p;
SELECT count(*) AS n_tracts_with_tiger_dedup, (SELECT count(*) FROM tracts) - count(*) AS tracts_undefined_if_dedup,
       round(sum(l)/1000) AS tiger_km_dedup
FROM (SELECT GEOID, sum(len_dedup) l FROM pc2 GROUP BY 1 HAVING sum(len_dedup) > 0);
