#!/usr/bin/env bash
# Full Shapely/GEOS reimplementation, end to end. ~25 min, peak RSS ~990 MB
# (south-central-tx). Writes tmp/py/<region>-shapely.csv per region, then the
# two comparisons against the shipped DuckDB pipeline.
#
#   python/run_all.sh
#
# Requires: shapely>=2, pyarrow, pyproj, numpy  (python3 -m pip install --user)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tmp/py
for r in northern-ca eastern-ok maricopa-az south-central-tx; do
  python3 python/run_region.py "$r"
done
echo
echo "### full-precision comparison, straight out of db/<region>.duckdb"
python3 python/compare_raw.py
echo
echo "### comparison against submissions/zindi-submission-fullprec.csv (15 dp)"
python3 python/compare.py
echo
echo "### the 6dp-quantised-reference hypothesis"
python3 python/rounding_paradox.py
