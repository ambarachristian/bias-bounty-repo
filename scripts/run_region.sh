#!/usr/bin/env bash
# usage: scripts/run_region.sh <region> [TIGER_MIN_M]
# Runs sql/01..07 against db/<region>.duckdb (persisted intermediates) and writes submissions/<region>-submission.csv
set -euo pipefail
cd "$(dirname "$0")/.."
R=$1; TMIN=${2:-0}
mkdir -p db tmp/spill submissions/diagnostics tmp/run
: > tmp/run/$R.sql
echo ".bail on" >> tmp/run/$R.sql
cat sql/00_init.sql >> tmp/run/$R.sql
for f in sql/01_tracts.sql sql/02_axis_check.sql sql/03_roads.sql sql/04_buildings.sql sql/05_pois.sql sql/06_score.sql sql/07_report_export.sql; do
  sed -e "s/@R@/$R/g" -e "s/@TIGER_MIN_M@/$TMIN/g" $f >> tmp/run/$R.sql
done
./bin/duckdb -markdown db/$R.duckdb < tmp/run/$R.sql
