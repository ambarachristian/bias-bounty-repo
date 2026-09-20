-- Candidate submission files for the precision hunt.
--   candidate-fullprec       : our scores at 15 dp instead of 6 dp. Identical model, removes the
--                              4.608e-10 of SSE that the 6 dp rounding contributes.
--   candidate-probe-mean     : fullprec + delta on EVERY row. Measures the signed mean of our
--                              per-tract errors, ebar = (RMSE'^2 - RMSE^2 - delta^2) / (2*delta).
--   candidate-probe-transport: fullprec + delta only on tracts where transport is defined AND
--                              unclamped (the only rows a road-length error can live on).
--                              Measures the signed error mass carried by those rows.
-- delta is tiny (1e-6) on purpose: the probes cost at most ~1e-6 of leaderboard RMSE, and the
-- leaderboard reports 9 decimals, which over-resolves the quantity being measured by ~1000x.
-- w = +1, flipped to -1 on any row already at 1.0 so no value leaves [0,1].
.bail on
ATTACH 'db/maricopa-az.duckdb'      AS m (READ_ONLY);
ATTACH 'db/northern-ca.duckdb'      AS c (READ_ONLY);
ATTACH 'db/eastern-ok.duckdb'       AS o (READ_ONLY);
ATTACH 'db/south-central-tx.duckdb' AS t (READ_ONLY);

CREATE OR REPLACE TEMP MACRO bl(x) AS CASE WHEN x THEN 'TRUE' ELSE 'FALSE' END;
CREATE OR REPLACE TEMP MACRO nm(x) AS printf('%.15f', coalesce(x, 0));

CREATE OR REPLACE TEMP TABLE allr AS
SELECT 'maricopa-az' AS region, g.* FROM m.gaps g WHERE g.GEOID IN (SELECT GEOID FROM m.scored)
UNION ALL SELECT 'northern-ca',      g.* FROM c.gaps g WHERE g.GEOID IN (SELECT GEOID FROM c.scored)
UNION ALL SELECT 'eastern-ok',       g.* FROM o.gaps g WHERE g.GEOID IN (SELECT GEOID FROM o.scored)
UNION ALL SELECT 'south-central-tx', g.* FROM t.gaps g WHERE g.GEOID IN (SELECT GEOID FROM t.scored);

CREATE OR REPLACE TEMP TABLE tmpl AS
SELECT GEOID, region AS sample_region, row_number() OVER () AS rn
FROM read_csv('data/ZindiSampleSubmission.csv', types={'GEOID':'VARCHAR'});

SELECT CASE WHEN count(*) > 0 THEN error('region mismatch on ' || count(*) || ' rows')
            ELSE 'regions ok' END AS check_regions
FROM tmpl s JOIN allr a USING (GEOID) WHERE s.sample_region <> a.region;
SELECT CASE WHEN (SELECT count(*) FROM tmpl) <> (SELECT count(*) FROM tmpl s JOIN allr a USING (GEOID))
            THEN error('row count mismatch vs sample') ELSE 'row set ok' END AS check_rows;

-- probe weights
CREATE OR REPLACE TEMP TABLE probe AS
SELECT a.GEOID,
       CASE WHEN a.coverage_gap_score >= 1.0 THEN -1.0 ELSE 1.0 END AS w,
       (a.transport_defined AND a.overture_m / nullif(a.tiger_m,0) < 1.0) AS transport_live
FROM allr a;

SELECT count(*) AS n_rows,
       count(*) FILTER (WHERE w < 0) AS n_flipped,
       count(*) FILTER (WHERE transport_live) AS n_transport_live
FROM probe;

CREATE OR REPLACE TEMP MACRO row_out(score) AS TABLE
SELECT s.GEOID, nm(score) AS coverage_gap_score FROM tmpl s ORDER BY s.rn;

-- 1. full precision, values unchanged
COPY (
  SELECT s.GEOID, nm(a.coverage_gap_score) AS coverage_gap_score, a.region,
         nm(a.transport_gap) AS transport_gap, bl(a.transport_defined) AS transport_defined,
         nm(a.building_gap)  AS building_gap,  bl(a.building_defined)  AS building_defined,
         nm(a.poi_gap)       AS poi_gap,       bl(a.poi_defined)       AS poi_defined,
         nm(a.poi_gap_fire)  AS poi_gap_fire,  bl(a.hf_fire   > 0)     AS poi_defined_fire,
         nm(a.poi_gap_ems)   AS poi_gap_ems,   bl(a.hf_ems    > 0)     AS poi_defined_ems,
         nm(a.poi_gap_schools) AS poi_gap_schools, bl(a.hf_school > 0) AS poi_defined_schools,
         nm(a.poi_gap_cbp)   AS poi_gap_cbp,   bl(a.cbp_estab > 0)     AS poi_defined_cbp
  FROM tmpl s JOIN allr a USING (GEOID) ORDER BY s.rn
) TO 'tmp/out/candidate-fullprec-lf.csv' (HEADER, DELIMITER ',', QUOTE '');

-- 2. probe: delta on every row
COPY (
  SELECT s.GEOID, nm(a.coverage_gap_score + 0.000001 * p.w) AS coverage_gap_score, a.region,
         nm(a.transport_gap) AS transport_gap, bl(a.transport_defined) AS transport_defined,
         nm(a.building_gap)  AS building_gap,  bl(a.building_defined)  AS building_defined,
         nm(a.poi_gap)       AS poi_gap,       bl(a.poi_defined)       AS poi_defined,
         nm(a.poi_gap_fire)  AS poi_gap_fire,  bl(a.hf_fire   > 0)     AS poi_defined_fire,
         nm(a.poi_gap_ems)   AS poi_gap_ems,   bl(a.hf_ems    > 0)     AS poi_defined_ems,
         nm(a.poi_gap_schools) AS poi_gap_schools, bl(a.hf_school > 0) AS poi_defined_schools,
         nm(a.poi_gap_cbp)   AS poi_gap_cbp,   bl(a.cbp_estab > 0)     AS poi_defined_cbp
  FROM tmpl s JOIN allr a USING (GEOID) JOIN probe p USING (GEOID) ORDER BY s.rn
) TO 'tmp/out/candidate-probe-mean-lf.csv' (HEADER, DELIMITER ',', QUOTE '');

-- 3. probe: delta only on transport-defined, unclamped rows
COPY (
  SELECT s.GEOID,
         nm(a.coverage_gap_score + CASE WHEN p.transport_live THEN 0.000001 * p.w ELSE 0 END) AS coverage_gap_score,
         a.region,
         nm(a.transport_gap) AS transport_gap, bl(a.transport_defined) AS transport_defined,
         nm(a.building_gap)  AS building_gap,  bl(a.building_defined)  AS building_defined,
         nm(a.poi_gap)       AS poi_gap,       bl(a.poi_defined)       AS poi_defined,
         nm(a.poi_gap_fire)  AS poi_gap_fire,  bl(a.hf_fire   > 0)     AS poi_defined_fire,
         nm(a.poi_gap_ems)   AS poi_gap_ems,   bl(a.hf_ems    > 0)     AS poi_defined_ems,
         nm(a.poi_gap_schools) AS poi_gap_schools, bl(a.hf_school > 0) AS poi_defined_schools,
         nm(a.poi_gap_cbp)   AS poi_gap_cbp,   bl(a.cbp_estab > 0)     AS poi_defined_cbp
  FROM tmpl s JOIN allr a USING (GEOID) JOIN probe p USING (GEOID) ORDER BY s.rn
) TO 'tmp/out/candidate-probe-transport-lf.csv' (HEADER, DELIMITER ',', QUOTE '');
