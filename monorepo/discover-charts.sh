#!/usr/bin/env bash
# Lists the charts in this repo as a compact JSON array, for use as an Actions
# matrix. Charts are discovered rather than hardcoded, so adding one needs no
# workflow edit.
#
#   ci-tools/monorepo/discover-charts.sh            # all charts
#   ci-tools/monorepo/discover-charts.sh my-chart   # just this one, validated to exist
#
# Outputs (also written to $GITHUB_OUTPUT when set):
#   charts  JSON array of chart names, e.g. ["monitoring-extensions"]
#   any     "true" | "false"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd jq

only="${1:-}"

if [ -n "$only" ]; then
  chart_dir "$only" >/dev/null
  charts="$(printf '%s' "$only" | jq -R . | jq -sc .)"
else
  charts="$(find "${REPO_ROOT}/charts" -mindepth 2 -maxdepth 2 -name Chart.yaml -printf '%h\n' 2>/dev/null \
            | xargs -r -n1 basename | sort -u | jq -R . | jq -sc .)"
  [ -n "$charts" ] || charts="[]"
fi

emit charts "$charts"
if [ "$charts" = "[]" ]; then emit any false; else emit any true; fi
