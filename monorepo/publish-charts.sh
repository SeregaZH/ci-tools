#!/usr/bin/env bash
# Versions, packages and publishes charts as OCI artifacts, then tags the repo
#.
#
#   ci-tools/monorepo/publish-charts.sh <chart> [chart ...]
#
# Environment:
#   OCI_REGISTRY   oci:// URL to push to — required, normally set in
#                  the consuming repo's .ci-tools.env
#   GHCR_USER      registry user (skip login if unset)
#   GHCR_TOKEN     registry token
#   BUMP           override the bump level; default reads the commit message
#   DRY_RUN        1 = do everything except push and tag
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -gt 0 ] || die "usage: publish-charts.sh <chart> [chart ...]"

require_cmd helm
here="$(dirname "${BASH_SOURCE[0]}")"

# No default: this repo is shared, and a wrong-but-plausible registry would be
# discovered by finding somebody else's charts in it.
[ -n "${OCI_REGISTRY:-}" ] || die "OCI_REGISTRY is not set — put it in .ci-tools.env"
DRY_RUN="${DRY_RUN:-0}"

cd "$REPO_ROOT"

if [ "$DRY_RUN" = "1" ]; then
  warn "DRY_RUN=1 — will not push or tag"
elif [ -n "${GHCR_USER:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
  registry_host="${OCI_REGISTRY#oci://}"
  registry_host="${registry_host%%/*}"
  group "registry login ${registry_host}"
  printf '%s' "$GHCR_TOKEN" | helm registry login "$registry_host" -u "$GHCR_USER" --password-stdin
  endgroup
else
  die "GHCR_USER/GHCR_TOKEN not set (use DRY_RUN=1 to test without publishing)"
fi

if [ "$DRY_RUN" != "1" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for chart in "$@"; do
  dir="$(chart_dir "$chart")"
  group "publish ${chart}"

  # next_version.py prints `version=` and `tag=` and refuses a tag that already
  # exists, so eval defines both here and the guard stays in one place.
  # GITHUB_OUTPUT is unset for it: this loop runs once per chart, and a step
  # output can only carry one value.
  versioned="$(env -u GITHUB_OUTPUT python3 "${here}/next_version.py" "$chart" "${BUMP:-}")" \
    || die "cannot version ${chart}"
  eval "$versioned"
  info "version: ${version}  (tag ${tag})"

  # Write the version into Chart.yaml in the workspace only. The git tag is the
  # source of truth, so this is never committed back to main — that
  # would add a bot commit to every merge for no benefit.
  #
  # Restore from a copy rather than `git checkout --`: a chart added in this very
  # merge is untracked from git's point of view, and checkout would fail on it.
  backup="${workdir}/${chart}.Chart.yaml.orig"
  cp "${dir}/Chart.yaml" "$backup"
  sed -i -E "s/^version:.*/version: ${version}/" "${dir}/Chart.yaml"
  grep -E '^(name|version|appVersion):' "${dir}/Chart.yaml" | sed 's/^/    /'

  helm package "$dir" -d "$workdir" >/dev/null
  cp "$backup" "${dir}/Chart.yaml"   # leave the tree as we found it

  package="${workdir}/${chart}-${version}.tgz"
  [ -f "$package" ] || die "expected package at ${package}"
  info "packaged: $(basename "$package")"

  if [ "$DRY_RUN" = "1" ]; then
    info "dry run — skipping push and tag"
  else
    helm push "$package" "$OCI_REGISTRY"
    # Tag only after a successful push, so tags and registry never disagree.
    # This is why publishing precedes tagging: a tag with no artifact behind
    # it is worse than a published artifact whose tag lands a second later.
    git tag -a "$tag" -m "$tag"
    git push origin "$tag"
    info "published ${chart} ${version}"
  fi
  endgroup
done
