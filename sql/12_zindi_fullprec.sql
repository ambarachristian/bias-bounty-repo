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

-- fail loudly if our region labels disagree with theirs
SELECT CASE WHEN count(*) > 0
  THEN error('region mismatch on ' || count(*) || ' rows') ELSE 'regions ok' END AS check_regions
FROM tmpl s JOIN allr a USING (GEOID) WHERE s.sample_region <> a.region;

COPY (
  SELECT s.GEOID,
         nm(a.coverage_gap_score) AS coverage_gap_score,
         a.region,
         nm(a.transport_gap)     AS transport_gap,
         bl(a.transport_defined) AS transport_defined,
         nm(a.building_gap)      AS building_gap,
         bl(a.building_defined)  AS building_defined,
         nm(a.poi_gap)           AS poi_gap,
         bl(a.poi_defined)       AS poi_defined,
         nm(a.poi_gap_fire)      AS poi_gap_fire,
         bl(a.hf_fire   > 0)     AS poi_defined_fire,
         nm(a.poi_gap_ems)       AS poi_gap_ems,
         bl(a.hf_ems    > 0)     AS poi_defined_ems,
         nm(a.poi_gap_schools)   AS poi_gap_schools,
         bl(a.hf_school > 0)     AS poi_defined_schools,
         nm(a.poi_gap_cbp)       AS poi_gap_cbp,
         bl(a.cbp_estab > 0)     AS poi_defined_cbp
  FROM tmpl s JOIN allr a USING (GEOID)
  ORDER BY s.rn
) TO 'submissions/zindi-full-lf.csv' (HEADER, DELIMITER ',', QUOTE '');
