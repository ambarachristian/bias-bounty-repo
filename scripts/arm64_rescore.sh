#!/usr/bin/env bash
# Swap the arm64 road lengths into copies of the region DBs, rescore (sql/06), export, compare.
# The original db/*.duckdb are never modified.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tmp/armscore
for R in northern-ca eastern-ok maricopa-az south-central-tx; do
  cp db/$R.duckdb tmp/armscore/$R.duckdb
  { echo ".bail on"; echo "LOAD spatial;"
    echo "CREATE OR REPLACE TABLE road_len_x86 AS SELECT * FROM road_len;"
    echo "CREATE OR REPLACE TABLE road_len AS SELECT * FROM read_parquet('tmp/arm/$R-road_len.parquet');"
    sed -e "s/@R@/$R/g" -e "s/@TIGER_MIN_M@/0/g" sql/06_score.sql
    echo "SELECT '$R' AS region,
       count(*) FILTER (WHERE abs(a.tiger_m - x.tiger_m) > 1e-6) AS tiger_moved,
       max(abs(a.tiger_m - x.tiger_m)) AS tiger_maxdiff_m,
       count(*) FILTER (WHERE abs(a.overture_m - x.overture_m) > 1e-6) AS overture_moved,
       max(abs(a.overture_m - x.overture_m)) AS overture_maxdiff_m
     FROM road_len a JOIN road_len_x86 x USING (GEOID);"
    echo "SELECT count(*) FILTER (WHERE NOT transport_defined) AS transport_undefined FROM gaps WHERE GEOID IN (SELECT GEOID FROM scored);"
  } > tmp/run/armscore_$R.sql
  ./bin/duckdb -markdown tmp/armscore/$R.duckdb < tmp/run/armscore_$R.sql
done
sed -e "s#'db/#'tmp/armscore/#g" -e "s#submissions/zindi-submission-lf.csv#tmp/arm-lf.csv#" sql/11_zindi_format.sql > tmp/run/arm_export.sql
./bin/duckdb < tmp/run/arm_export.sql > /dev/null
sed 's/$/\r/' tmp/arm-lf.csv > submissions/candidate-arm64.csv
python3 - <<'PY'
import pandas as pd, numpy as np
a=pd.read_csv('submissions/candidate-arm64.csv',dtype={'GEOID':str}); b=pd.read_csv('submissions/candidate-poi-fixed.csv',dtype={'GEOID':str})
assert list(a.GEOID)==list(b.GEOID) and a.shape==b.shape and not a.isna().any().any()
d=(a.coverage_gap_score-b.coverage_gap_score)
print('rows changed (6dp coverage):', int((d!=0).sum()), '| sum|d|', round(d.abs().sum(),6))
for c in ['coverage_gap_score','transport_gap','building_gap','poi_gap']:
    print(f'{c:<20} sum={a[c].sum():.6f}')
print('transport window [1048.2955, 1048.3049] (organiser mean 0.111771 x 9379 +/- 5e-7)')
PY
