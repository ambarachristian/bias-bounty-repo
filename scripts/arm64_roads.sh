#!/usr/bin/env bash
# Recompute ONLY the road lengths (sql/01 tracts + sql/03 road_len) under emulated linux/arm64 DuckDB 1.5.4.
# Why: the organisers' reference was produced on ARM, where the compiler fuses a*b+c into one FMA.
# Boundary-coincident Overture roads flip in/out of tracts on that last rounding step (see NOTES.md).
set -uo pipefail
cd "$(dirname "$0")/.."
Q=$HOME/arm64/qx/usr/bin/qemu-aarch64-static; ROOT=$HOME/arm64/rootfs; DB=$HOME/arm64/duckdb
for R in "$@"; do
  f=tmp/arm/$R.sql
  { echo ".bail on"
    sed -e "s#tmp/spill#tmp/spill_arm#" sql/00_init.sql
    sed -e "s/@R@/$R/g" sql/01_tracts.sql
    sed -e "s/@R@/$R/g" sql/03_roads.sql | awk '/road_len_mid/{exit} {print}'
    echo "COPY (SELECT * FROM road_len) TO 'tmp/arm/$R-road_len.parquet' (FORMAT parquet);"
    echo "SELECT '$R done' AS status, count(*) AS n FROM road_len;"
  } > $f
  echo "$(date '+%F %T') start $R" >> tmp/arm/arm.log
  rm -f tmp/arm/$R.duckdb
  $Q -L $ROOT $DB -markdown tmp/arm/$R.duckdb < $f >> tmp/arm/arm.log 2>&1
  echo "$(date '+%F %T') end $R rc=$?" >> tmp/arm/arm.log
done
