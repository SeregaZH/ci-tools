#!/usr/bin/env bash
# The full charts-ci gate for one chart. Run it locally to get
# exactly what the pull request will run:
#
#   ci-tools/monorepo/validate-chart.sh monitoring-extensions
#
# | Check           | Tool          | Catches                                    |
# |-----------------|---------------|--------------------------------------------|
# | Chart lint      | helm lint     | malformed chart metadata                   |
# | Render          | helm template | template errors, bad indentation           |
# | Schema          | kubeconform   | invalid AlertmanagerConfig/PrometheusRule  |
# | Rule syntax     | promtool      | invalid PromQL                             |
# | Unit tests      | helm-unittest | label/annotation regressions               |
#
# Checks that are specific to one repository are not here: every executable in
# the consumer's ci/checks/ is run last, with the chart directory as its only
# argument.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

chart="${1:?usage: validate-chart.sh <chart>}"
dir="$(chart_dir "$chart")"
here="$(dirname "${BASH_SOURCE[0]}")"

require_cmd helm
require_cmd jq

group "helm lint ${chart}"
helm lint "$dir"
endgroup

rendered="$("${here}/render-chart.sh" "$chart" | tail -n1)"

group "kubeconform ${chart}"
if ! command -v kubeconform >/dev/null 2>&1; then
  die "kubeconform not found — run ci-tools/monorepo/install-tools.sh"
fi
# The operator's CRDs are not in kubeconform's default schema set. Without the
# catalog location, AlertmanagerConfig and PrometheusRule are treated as unknown
# and skipped, so an invalid CR would pass silently.
kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "${rendered}"/*.yaml
endgroup

group "promtool check rules ${chart}"
rules_dir="${rendered}-rules"
found="$(python3 "${here}/extract-rule-groups.py" "$rendered" "$rules_dir")"
if [ "$found" = "0" ]; then
  # Expected until the chart ships PrometheusRule objects.
  info "no PrometheusRule rendered — skipping"
elif ! command -v promtool >/dev/null 2>&1; then
  # Deliberately not fatal: promtool is a ~110 MB download for one binary and is
  # not installed in CI, so PromQL is validated on developer machines only.
  # Loud rather than silent — this is a real gap, and an invalid expression will
  # not be caught until the Prometheus operator loads the rule.
  warn "promtool not installed — ${found} PrometheusRule(s) NOT validated"
  warn "run ci-tools/monorepo/install-tools.sh locally to check PromQL before pushing"
else
  promtool check rules "${rules_dir}"/*.yaml
fi
endgroup

group "helm unittest ${chart}"
if helm plugin list 2>/dev/null | grep -q '^unittest'; then
  helm unittest "$dir"
else
  die "helm-unittest not installed — run ci-tools/monorepo/install-tools.sh"
fi
endgroup

# Repo-specific checks the shared gate cannot know about — a dashboard
# convention, a naming rule, whatever that repository cares about. Each is run
# with the chart directory; none is the normal case.
shopt -s nullglob
for check in "${REPO_ROOT}"/ci/checks/*; do
  [ -x "$check" ] || continue
  group "$(basename "$check") ${chart}"
  "$check" "charts/${chart}"
  endgroup
done
shopt -u nullglob

echo
info "${chart}: all checks passed"
