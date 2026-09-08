#!/usr/bin/env bash
# Chooses which charts to publish: an explicitly named chart when given,
# otherwise the charts changed between two commits.
#
#   ci-tools/monorepo/select-charts.sh [chart] [base-sha] [head-sha]
#
# Always emits a SPACE-SEPARATED list, unlike discover-charts.sh which emits
# JSON for an Actions matrix. Mixing the two forms silently produces a bogus
# chart name, so publishing has its own entry point.
#
# Outputs (also written to $GITHUB_OUTPUT when set):
#   charts  space-separated chart names, empty if none
#   any     "true" | "false"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

chart="${1:-}"
base="${2:-}"
head="${3:-HEAD}"

if [ -n "$chart" ]; then
  chart_dir "$chart" >/dev/null   # fails loudly if the name is wrong
  emit charts "$chart"
  emit any true
  exit 0
fi

exec "$(dirname "${BASH_SOURCE[0]}")/detect-changed-charts.sh" "$base" "$head"
