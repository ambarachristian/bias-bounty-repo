-- Combine the four per-region submissions and verify them against the sample-submission files.
-- Run from project root:  ./bin/duckdb -markdown < sql/08_combine_verify.sql   (after all regions ran)
.bail on
CREATE OR REPLACE TEMP TABLE sub AS
SELECT 'northern-ca' AS region, * FROM read_csv('submissions/northern-ca-submission.csv', types={'GEOID':'VARCHAR'})
UNION ALL SELECT 'maricopa-az', * FROM read_csv('submissions/maricopa-az-submission.csv', types={'GEOID':'VARCHAR'})
UNION ALL SELECT 'eastern-ok', * FROM read_csv('submissions/eastern-ok-submission.csv', types={'GEOID':'VARCHAR'})
UNION ALL SELECT 'south-central-tx', * FROM read_csv('submissions/south-central-tx-submission.csv', types={'GEOID':'VARCHAR'});
CREATE OR REPLACE TEMP TABLE samp AS
SELECT 'northern-ca' AS region, GEOID FROM read_csv('data/reference/northern-ca/northern-ca-sample-submission.csv', types={'GEOID':'VARCHAR'})
UNION ALL SELECT 'maricopa-az', GEOID FROM read_csv('data/reference/maricopa-az/maricopa-az-sample-submission.csv', types={'GEOID':'VARCHAR'})
UNION ALL SELECT 'eastern-ok', GEOID FROM read_csv('data/reference/eastern-ok/eastern-ok-sample-submission.csv', types={'GEOID':'VARCHAR'})
UNION ALL SELECT 'south-central-tx', GEOID FROM read_csv('data/reference/south-central-tx/south-central-tx-sample-submission.csv', types={'GEOID':'VARCHAR'});

SELECT r.region, (SELECT count(*) FROM samp s WHERE s.region=r.region) AS sample_rows, count(*) AS submission_rows,
  (SELECT count(*) FROM samp s ANTI JOIN sub u ON s.GEOID=u.GEOID AND s.region=u.region WHERE s.region=r.region) AS missing_geoids,
  (SELECT count(*) FROM sub u ANTI JOIN samp s ON s.GEOID=u.GEOID AND s.region=u.region WHERE u.region=r.region) AS extra_geoids,
  count(DISTINCT GEOID) AS distinct_geoids,
  sum((GEOID IS NULL OR transport_gap IS NULL OR building_gap IS NULL OR poi_gap IS NULL OR coverage_gap_score IS NULL)::INT) AS blank_cells,
  sum((length(GEOID)<>11)::INT) AS bad_geoid_len,
  min(coverage_gap_score) AS min_score, max(coverage_gap_score) AS max_score,
  sum((isnan(coverage_gap_score) OR isinf(coverage_gap_score))::INT) AS nonfinite,
  CASE WHEN count(*) = (SELECT count(*) FROM samp s WHERE s.region=r.region) AND min(coverage_gap_score)>=0 AND max(coverage_gap_score)<=1
        AND sum((coverage_gap_score IS NULL)::INT)=0 THEN 'OK' ELSE error('VERIFY FAILED '||r.region) END AS status
FROM sub r GROUP BY r.region ORDER BY 1;

COPY (SELECT GEOID, transport_gap, building_gap, poi_gap, coverage_gap_score FROM sub ORDER BY region, GEOID)
TO 'submissions/combined-submission.csv' (HEADER, DELIMITER ',');
COPY (SELECT region, GEOID, transport_gap, building_gap, poi_gap, coverage_gap_score FROM sub ORDER BY region, GEOID)
TO 'submissions/combined-submission-with-region.csv' (HEADER, DELIMITER ',');
