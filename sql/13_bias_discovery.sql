ATTACH 'db/eastern-ok.duckdb' AS o (READ_ONLY);
ATTACH 'db/maricopa-az.duckdb' AS m (READ_ONLY);
ATTACH 'db/northern-ca.duckdb' AS c (READ_ONLY);
ATTACH 'db/south-central-tx.duckdb' AS t (READ_ONLY);
CREATE OR REPLACE TEMP TABLE j AS
SELECT 'eastern-ok' AS region, g.*, x.tribal_any FROM o.gaps g JOIN read_parquet('data/strata/eastern-ok/eastern-ok-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM o.scored)
UNION ALL SELECT 'maricopa-az', g.*, x.tribal_any FROM m.gaps g JOIN read_parquet('data/strata/maricopa-az/maricopa-az-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM m.scored)
UNION ALL SELECT 'northern-ca', g.*, x.tribal_any FROM c.gaps g JOIN read_parquet('data/strata/northern-ca/northern-ca-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM c.scored)
UNION ALL SELECT 'south-central-tx', g.*, x.tribal_any FROM t.gaps g JOIN read_parquet('data/strata/south-central-tx/south-central-tx-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM t.scored);

SELECT tribal_any,
  sum(hf_fire) AS usgs_fire, sum(ov_fire) AS overture_fire,
  round(100.0*(1 - sum(ov_fire)::DOUBLE/sum(hf_fire)),1) AS pct_fire_missing,
  count(*) FILTER (WHERE hf_fire>0) AS tracts_with_station,
  count(*) FILTER (WHERE hf_fire>0 AND ov_fire=0) AS tracts_station_invisible,
  round(100.0*count(*) FILTER (WHERE hf_fire>0 AND ov_fire=0)/count(*) FILTER (WHERE hf_fire>0),1) AS pct_invisible
FROM j GROUP BY 1 ORDER BY 1;

SELECT region, tribal_any, count(*) FILTER (WHERE hf_fire>0) AS n,
  round(100.0*count(*) FILTER (WHERE hf_fire>0 AND ov_fire=0)/nullif(count(*) FILTER (WHERE hf_fire>0),0),1) AS pct_invisible
FROM j GROUP BY 1,2 ORDER BY 1,2;
