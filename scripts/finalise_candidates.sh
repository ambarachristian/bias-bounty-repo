#!/usr/bin/env bash
# Convert the LF candidates in tmp/out to CRLF, then assert - byte level - that each one
# reproduces data/ZindiSampleSubmission.csv's header, its GEOID column and its row order,
# carries no scientific notation, and keeps every score inside [0,1].
set -euo pipefail
cd "$(dirname "$0")/.."
SAMPLE=data/ZindiSampleSubmission.csv

for name in fullprec probe-mean probe-transport; do
  src=tmp/out/candidate-$name-lf.csv
  dst=submissions/candidate-$name.csv
  sed -e 's/$/\r/' "$src" > "$dst"

  # header must be byte-identical to the sample's
  a=$(head -1 "$SAMPLE"); b=$(head -1 "$dst")
  [ "$a" = "$b" ] || { echo "FAIL $name: header differs"; exit 1; }

  # GEOID column, in order, must be byte-identical to the sample's
  cut -d, -f1 "$SAMPLE" > tmp/out/.g_sample
  cut -d, -f1 "$dst"    > tmp/out/.g_cand
  cmp -s tmp/out/.g_sample tmp/out/.g_cand || { echo "FAIL $name: GEOID column / row order differs"; exit 1; }

  # 17 columns on every row, uppercase booleans, no e-notation, scores in [0,1]
  awk -F, -v n="$name" '
    NR>1 {
      if (NF != 17) { print "FAIL " n ": row " NR " has " NF " columns"; bad=1; exit }
      if ($2+0 < 0 || $2+0 > 1) { print "FAIL " n ": score out of [0,1] on row " NR; bad=1; exit }
      for (i=2; i<=17; i++) if ($i ~ /[eE]\+|[eE]-/) { print "FAIL " n ": scientific notation row " NR; bad=1; exit }
      for (i=5; i<=17; i+=2) { v=$i; gsub(/\r/,"",v); if (v != "TRUE" && v != "FALSE") { print "FAIL " n ": bad boolean \"" v "\" row " NR; bad=1; exit } }
    }
    END { if (!bad) print "ok " n ": 17 cols, booleans, no e-notation, scores in range" }' "$dst"

  crlf=$(grep -c $'\r$' "$dst")
  tot=$(wc -l < "$dst")
  [ "$crlf" = "$tot" ] || { echo "FAIL $name: only $crlf of $tot lines are CRLF"; exit 1; }
  echo "ok $name: $tot lines, all CRLF -> $dst"
done
rm -f tmp/out/.g_sample tmp/out/.g_cand
