-- Verification + export. Any failed assertion aborts the run (runner uses .bail on).
SELECT CASE WHEN count(*) = 0 THEN 'ok: no NaN/inf in components' ELSE error('NaN/inf in gaps: '||count(*)) END AS check_finite
FROM gaps WHERE isinf(tiger_m) OR isnan(tiger_m) OR isinf(overture_m) OR isnan(overture_m)
   OR isinf(transport_gap) OR isnan(transport_gap) OR isinf(building_gap) OR isnan(building_gap)
   OR isinf(poi_gap) OR isnan(poi_gap) OR isinf(coverage_gap_score) OR isnan(coverage_gap_score);
SELECT CASE WHEN count(*) = 0 THEN 'ok: all scored tracts have >=1 defined component' ELSE error('tracts with no defined component: '||count(*)) END AS check_defined
FROM gaps WHERE coverage_gap_score IS NULL;
SELECT CASE WHEN count(*) = 0 THEN 'ok: scores in [0,1]' ELSE error('score out of range') END AS check_range
FROM gaps WHERE coverage_gap_score < 0 OR coverage_gap_score > 1 OR transport_gap NOT BETWEEN 0 AND 1 OR building_gap NOT BETWEEN 0 AND 1 OR poi_gap NOT BETWEEN 0 AND 1;

SELECT '@R@' AS region, count(*) AS n_tracts,
  sum((NOT transport_defined)::INT) AS transport_undef, round(100.0*avg((NOT transport_defined)::INT),1) AS transport_undef_pct,
  sum((NOT building_defined)::INT) AS building_undef, sum((NOT poi_defined)::INT) AS poi_undef,
  round(100.0*avg(((NOT transport_defined) OR (NOT building_defined) OR (NOT poi_defined))::INT),1) AS any_undef_pct,
  round(avg(coverage_gap_score),4) AS mean_score, round(avg(transport_gap) FILTER (WHERE transport_defined),4) AS mean_transport,
  round(avg(building_gap) FILTER (WHERE building_defined),4) AS mean_building, round(avg(poi_gap) FILTER (WHERE poi_defined),4) AS mean_poi,
  round(sum(overture_m)/sum(tiger_m),3) AS road_ratio_ov_over_tiger
FROM gaps;

COPY (SELECT s.GEOID,
        round(g.transport_gap,6) AS transport_gap, round(g.building_gap,6) AS building_gap, round(g.poi_gap,6) AS poi_gap,
        round(g.coverage_gap_score,6) AS coverage_gap_score
      FROM read_csv('data/reference/@R@/@R@-sample-submission.csv', header=true, types={'GEOID':'VARCHAR'}) s
      JOIN gaps g USING (GEOID) ORDER BY s.GEOID)
TO 'submissions/@R@-submission.csv' (HEADER, DELIMITER ',');
-- full diagnostic table (components, counts, defined flags)
COPY (SELECT * EXCLUDE (_x) FROM gaps ORDER BY GEOID) TO 'submissions/diagnostics/@R@-components.csv' (HEADER, DELIMITER ',');
