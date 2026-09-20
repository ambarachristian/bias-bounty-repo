#!/usr/bin/env bash
# usage: scripts/rerun_pois.sh <region> [TIGER_MIN_M]
# Re-runs ONLY sql/05_pois.sql + 06_score.sql + 07_report_export.sql against an existing
# db/<region>.duckdb. tracts/scored/road_len/bldg_ov/bldg_ms are persisted tables, so the
# expensive road + building passes are not repeated. Exports are redirected to tmp/poifix/
# so nothing under submissions/ is overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."
R=$1; TMIN=${2:-0}
mkdir -p tmp/spill tmp/poifix tmp/run
: > tmp/run/$R-poifix.sql
echo ".bail on" >> tmp/run/$R-poifix.sql
cat sql/00_init.sql >> tmp/run/$R-poifix.sql
for f in sql/05_pois.sql sql/06_score.sql sql/07_report_export.sql; do
  sed -e "s/@R@/$R/g" -e "s/@TIGER_MIN_M@/$TMIN/g" \
      -e "s#submissions/$R-submission.csv#tmp/poifix/$R-submission.csv#" \
      -e "s#submissions/diagnostics/$R-components.csv#tmp/poifix/$R-components.csv#" \
      $f >> tmp/run/$R-poifix.sql
done
./bin/duckdb -markdown db/$R.duckdb < tmp/run/$R-poifix.sql
