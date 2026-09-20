-- Tract spine: polygons in CRS84 and EPSG:5070 (always_xy!). Scored list = sample submission.
CREATE OR REPLACE TABLE scored AS
SELECT GEOID FROM read_csv('data/reference/@R@/@R@-sample-submission.csv', header=true, types={'GEOID':'VARCHAR'});

CREATE OR REPLACE TABLE tracts AS
SELECT GEOID, geometry AS g,
       ST_Transform(geometry, 'EPSG:4326', 'EPSG:5070', always_xy := true) AS g5070,
       frac_inside_aoi, pop_total, ALAND
FROM read_parquet('data/strata/@R@/@R@-census-tracts.parquet');

-- traps: no inf/nan in projected tracts, GEOID is 11 chars text
SELECT CASE WHEN count(*) = 0 THEN 'ok: tract projection finite'
            ELSE error('non-finite projected tract geometry: ' || count(*)) END AS check_tracts_finite
FROM tracts WHERE isinf(ST_XMin(g5070)) OR isnan(ST_XMin(g5070)) OR isinf(ST_YMax(g5070)) OR isnan(ST_YMax(g5070));
SELECT CASE WHEN count(*) = 0 THEN 'ok: GEOID width' ELSE error('bad GEOID width') END AS check_geoid
FROM tracts WHERE length(GEOID) <> 11;
SELECT count(*) AS n_tracts, (SELECT count(*) FROM scored) AS n_scored,
       (SELECT count(*) FROM scored s ANTI JOIN tracts t USING (GEOID)) AS scored_not_in_tracts,
       (SELECT count(*) FROM tracts t ANTI JOIN scored s USING (GEOID)) AS tracts_not_scored,
       (SELECT count(*) FROM tracts WHERE NOT ST_IsValid(g)) AS invalid_polys,
       (SELECT min(frac_inside_aoi) FROM tracts) AS min_frac_inside_aoi
FROM tracts;
