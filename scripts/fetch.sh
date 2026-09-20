#!/usr/bin/env bash
# Download the reference files needed by the pipeline for one or more regions.
# usage: scripts/fetch.sh northern-ca [south-central-tx maricopa-az eastern-ok]
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=https://data.source.coop/humane-intelligence/bias-bounty-mapping-equity-challenge
for r in "$@"; do
  mkdir -p data/reference/$r data/strata/$r
  for f in overture-buildings overture-roads overture-pois microsoft-buildings census-tiger-roads census-cbp census-acs-housing \
           hifld-fire-stations hifld-ems-stations hifld-schools hifld-hospitals; do
    curl -sfL -C - -o data/reference/$r/$r-$f.parquet $BASE/reference/$r/$r-$f.parquet
  done
  curl -sfL -C - -o data/reference/$r/$r-sample-submission.csv $BASE/reference/$r/$r-sample-submission.csv
  curl -sfL -C - -o data/strata/$r/$r-census-tracts.parquet $BASE/strata/$r/$r-census-tracts.parquet
  curl -sfL -C - -o data/reference/$r/$r-tract-geoids.csv $BASE/boundaries/$r-tract-geoids.csv
  echo "fetched $r"
done
