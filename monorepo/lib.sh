#!/usr/bin/env bash
# Shared helpers for the ci-tools scripts. Sourced, not executed.
#
# Everything here is plain bash with no GitHub Actions dependency, so every
# script runs identically on a laptop and on a runner.
#
# ci-tools is consumed as a submodule at <repo>/ci-tools, and these scripts sit
# one level further down in monorepo/, so REPO_ROOT is two levels up: the
# consuming repository, not this one.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Per-repo settings — registry, conventions, tool versions — live in one file
# at the consumer's root so a laptop and a runner read the same values and no
# workflow has to repeat them. `set -a` exports them, which is what lets the
# python scripts here see them too.
if [ -f "${REPO_ROOT}/.ci-tools.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.ci-tools.env"
  set +a
fi

# Group markers collapse in the Actions log and are harmless locally.
group()    { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$*"; else echo "==> $*"; fi; }
endgroup() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; }
info()     { printf '  %s\n' "$*"; }
warn()     { printf '  WARN  %s\n' "$*" >&2; }
die()      { printf '  ERROR %s\n' "$*" >&2; exit 1; }

# Emit a name=value pair to $GITHUB_OUTPUT when running in Actions, and always
# echo it so local runs are useful too.
emit() {
  local name="$1" value="$2"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  echo "${name}=${value}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required tool '$1' not found on PATH"
}

# Charts live at <repo>/charts/<name> in every repo that uses these scripts.
chart_dir() {
  local chart="$1"
  local dir="${REPO_ROOT}/charts/${chart}"
  [ -f "${dir}/Chart.yaml" ] || die "no chart at charts/${chart}"
  echo "$dir"
}
