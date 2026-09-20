#!/usr/bin/env bash
# End to end from a clean checkout: download, compute all four regions, combine + verify.
# Needs ./bin/duckdb (v1.5.x CLI with httpfs + spatial extensions installable) and curl.
set -euo pipefail
cd "$(dirname "$0")/.."
REGIONS="northern-ca maricopa-az eastern-ok south-central-tx"
scripts/fetch.sh $REGIONS
for r in $REGIONS; do scripts/run_region.sh $r 0; done
./bin/duckdb -markdown < sql/08_combine_verify.sql
