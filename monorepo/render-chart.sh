#!/usr/bin/env bash
# Renders a chart against every values profile it ships: values.yaml plus any
# ci/*-values.yaml. Catches template errors and bad indentation, and produces
# the manifests the later checks run against.
#
#   ci-tools/monorepo/render-chart.sh <chart> [outdir]
#
# Default outdir is a fresh directory under $RUNNER_TEMP or /tmp.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd helm

chart="${1:?usage: render-chart.sh <chart> [outdir]}"
dir="$(chart_dir "$chart")"
outdir="${2:-${RUNNER_TEMP:-/tmp}/rendered-${chart}}"

# Namespace is arbitrary for rendering; the chart must not depend on it being
# `monitoring`, so a non-default one is used deliberately here.
ns="${RENDER_NAMESPACE:-monitoring}"

rm -rf "$outdir"
mkdir -p "$outdir"

group "render ${chart} (default values)"
helm template ci "$dir" -n "$ns" > "${outdir}/default.yaml"
info "$(grep -c '^kind:' "${outdir}/default.yaml" || true) objects"
endgroup

shopt -s nullglob
for profile in "${dir}"/ci/*-values.yaml; do
  name="$(basename "$profile" .yaml)"
  group "render ${chart} (${name})"
  helm template ci "$dir" -n "$ns" -f "$profile" > "${outdir}/${name}.yaml"
  info "$(grep -c '^kind:' "${outdir}/${name}.yaml" || true) objects"
  endgroup
done
shopt -u nullglob

echo "$outdir"
