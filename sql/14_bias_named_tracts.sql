-- Named tribal tracts where every real (USGS) fire station is absent from Overture. Run: ./bin/duckdb -markdown < sql/14_bias_named_tracts.sql
ATTACH 'db/eastern-ok.duckdb' AS o (READ_ONLY);
ATTACH 'db/maricopa-az.duckdb' AS m (READ_ONLY);
ATTACH 'db/northern-ca.duckdb' AS c (READ_ONLY);
ATTACH 'db/south-central-tx.duckdb' AS t (READ_ONLY);
CREATE OR REPLACE TEMP TABLE j AS
SELECT 'eastern-ok' AS region, g.*, x.tribal_any FROM o.gaps g JOIN read_parquet('data/strata/eastern-ok/eastern-ok-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM o.scored)
UNION ALL SELECT 'maricopa-az', g.*, x.tribal_any FROM m.gaps g JOIN read_parquet('data/strata/maricopa-az/maricopa-az-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM m.scored)
UNION ALL SELECT 'northern-ca', g.*, x.tribal_any FROM c.gaps g JOIN read_parquet('data/strata/northern-ca/northern-ca-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM c.scored)
UNION ALL SELECT 'south-central-tx', g.*, x.tribal_any FROM t.gaps g JOIN read_parquet('data/strata/south-central-tx/south-central-tx-tribal-tract-table.parquet') x USING (GEOID) WHERE g.GEOID IN (SELECT GEOID FROM t.scored);
CREATE OR REPLACE TEMP TABLE names AS SELECT GEOID, aiannh_name, round(tribal_pct,2) AS tribal_pct FROM read_parquet('data/strata/*/*-tribal-tract-table.parquet');
SELECT j.region, j.GEOID, n.aiannh_name AS tribal_area, n.tribal_pct, j.hf_fire AS usgs_stations, j.ov_fire AS in_overture
FROM j LEFT JOIN names n USING (GEOID)
WHERE j.tribal_any AND j.hf_fire >= 3 AND j.ov_fire = 0
ORDER BY j.hf_fire DESC, j.GEOID LIMIT 12;
SELECT count(*) AS n_tracts_3plus_all_invisible FROM j WHERE tribal_any AND hf_fire>=3 AND ov_fire=0;
