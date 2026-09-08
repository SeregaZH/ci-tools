#!/usr/bin/env bash
# Runs the full charts-ci gate over several charts in one go.
#
#   ci-tools/monorepo/validate-charts.sh <chart> [chart ...]
#   ci-tools/monorepo/validate-charts.sh            # all charts in the repo
#
# charts-ci fans out one runner per chart via a matrix; charts-publish validates
# the changed set sequentially in a single job, which is what this is for.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

here="$(dirname "${BASH_SOURCE[0]}")"

charts=("$@")
if [ ${#charts[@]} -eq 0 ]; then
  mapfile -t charts < <(find "${REPO_ROOT}/charts" -mindepth 2 -maxdepth 2 -name Chart.yaml -printf '%h\n' \
                        | xargs -r -n1 basename | sort -u)
fi

[ ${#charts[@]} -gt 0 ] || die "no charts found"

for chart in "${charts[@]}"; do
  "${here}/validate-chart.sh" "$chart"
done

echo
info "validated: ${charts[*]}"
