#!/usr/bin/env bash
# Installs the validation tools charts-ci needs. Idempotent, so it is safe to
# run locally to get the same toolchain CI uses.
#
#   ci-tools/monorepo/install-tools.sh
#
# Versions are pinned here rather than in the workflow so local and CI cannot
# drift apart.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-v0.6.7}"
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-3.6.0}"   # promtool is extracted from this release

# Prefer a writable user-local bin when not root (laptop); use sudo on runners.
if [ -w /usr/local/bin ]; then
  BIN_DIR=/usr/local/bin
  INSTALL="install"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  BIN_DIR=/usr/local/bin
  INSTALL="sudo install"
else
  BIN_DIR="${HOME}/.local/bin"
  INSTALL="install"
  mkdir -p "$BIN_DIR"
fi

group "kubeconform ${KUBECONFORM_VERSION}"
if command -v kubeconform >/dev/null 2>&1; then
  info "already present: $(kubeconform -v)"
else
  tmp="$(mktemp -d)"
  curl -sSLo "${tmp}/kubeconform.tar.gz" \
    "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"
  tar -xzf "${tmp}/kubeconform.tar.gz" -C "$tmp" kubeconform
  $INSTALL "${tmp}/kubeconform" "${BIN_DIR}/"
  rm -rf "$tmp"
  info "installed to ${BIN_DIR}"
fi
endgroup

# promtool is a ~110 MB download for one binary, which is not worth paying on
# every CI run, so it is installed for local development only. CI therefore does
# NOT validate PromQL — a deliberate trade, see README. Force either way with
# INSTALL_PROMTOOL=1 / =0.
if [ "${INSTALL_PROMTOOL:-$([ -n "${GITHUB_ACTIONS:-}" ] && echo 0 || echo 1)}" = "1" ]; then
  group "promtool ${PROMETHEUS_VERSION}"
  if command -v promtool >/dev/null 2>&1; then
    info "already present: $(promtool --version 2>&1 | head -n1)"
  else
    # Only promtool is needed, so the single binary is pulled out of the release
    # tarball rather than installing the `prometheus` distro package, which
    # drags in a server and a systemd unit.
    tmp="$(mktemp -d)"
    archive="prometheus-${PROMETHEUS_VERSION}.linux-amd64"
    curl -sSLo "${tmp}/prometheus.tar.gz" \
      "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${archive}.tar.gz"
    tar -xzf "${tmp}/prometheus.tar.gz" --strip-components=1 -C "$tmp" "${archive}/promtool"
    $INSTALL "${tmp}/promtool" "${BIN_DIR}/"
    rm -rf "$tmp"
    info "installed to ${BIN_DIR}"
  fi
  endgroup
else
  group "promtool"
  info "skipped (CI) — PromQL will not be validated"
  endgroup
fi

group "helm-unittest plugin"
if helm plugin list 2>/dev/null | grep -q '^unittest'; then
  info "already installed"
else
  helm plugin install https://github.com/helm-unittest/helm-unittest
fi
endgroup

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) warn "${BIN_DIR} is not on PATH" ;;
esac
