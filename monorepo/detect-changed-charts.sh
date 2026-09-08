#!/usr/bin/env bash
# Lists the charts touched between two commits, so a merge bumps only the charts
# that actually changed — versioning is independent per chart.
#
#   ci-tools/monorepo/detect-changed-charts.sh <base-sha> <head-sha>
#
# Outputs (also written to $GITHUB_OUTPUT when set):
#   charts  space-separated chart names, empty if none
#   any     "true" | "false"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

base="${1:-}"
head="${2:-HEAD}"

cd "$REPO_ROOT"

# On a first push to a branch GitHub reports an all-zero "before" sha, and a
# force-push can report a sha that is no longer reachable. Fall back to the
# head commit's first parent, then to the commit's own file list.
if [ -z "$base" ] || [ "$base" = "0000000000000000000000000000000000000000" ] \
   || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  base="$(git rev-parse "${head}^" 2>/dev/null || true)"
fi

if [ -n "$base" ]; then
  files="$(git diff --name-only "$base" "$head")"
else
  files="$(git show --name-only --pretty=format: "$head")"
fi

# Keep the <name> of every charts/<name>/... path that changed.
charts="$(printf '%s\n' "$files" | awk -F/ '$1=="charts" && NF>2 {print $2}' | sort -u | tr '\n' ' ')"
charts="$(echo "$charts" | xargs || true)"

# A chart directory deleted in this commit must not be published.
remaining=""
for chart in $charts; do
  if [ -f "charts/${chart}/Chart.yaml" ]; then
    remaining="${remaining}${chart} "
  else
    warn "charts/${chart} no longer exists — skipping"
  fi
done
charts="$(echo "$remaining" | xargs || true)"

emit charts "$charts"
if [ -z "$charts" ]; then emit any false; else emit any true; fi
