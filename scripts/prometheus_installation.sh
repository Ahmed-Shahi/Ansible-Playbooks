#!/usr/bin/env bash
# Installs and runs Prometheus as a systemd service on the DevOps-VM.
#
# Usage:
#   sudo PROMETHEUS_VERSION=2.55.1 ./install_prometheus.sh   # pin a version
#   sudo ./install_prometheus.sh                             # auto-detect latest
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../common/lib.sh
source "lib.sh"

PROMETHEUS_USER="prometheus"
PROMETHEUS_CONFIG_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-}"

require_root

ARCH="$(detect_arch)"

if [[ -z "${PROMETHEUS_VERSION}" ]]; then
  echo "Looking up latest Prometheus release..."
  TAG="$(get_latest_github_release "prometheus/prometheus" || true)"
  if [[ -z "${TAG}" ]]; then
    echo "Could not reach GitHub API, falling back to pinned version 2.55.1" >&2
    PROMETHEUS_VERSION="2.55.1"
  else
    PROMETHEUS_VERSION="${TAG#v}"
  fi
fi
echo "Installing Prometheus v${PROMETHEUS_VERSION} (${ARCH})"

create_system_user "${PROMETHEUS_USER}"
mkdir -p "${PROMETHEUS_CONFIG_DIR}/console_libraries" "${PROMETHEUS_CONFIG_DIR}/consoles" "${PROMETHEUS_DATA_DIR}"

TARBALL="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Downloading ${TARBALL}..."
curl -fsSL -o "${WORKDIR}/${TARBALL}" \
  "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${TARBALL}"

tar -xzf "${WORKDIR}/${TARBALL}" -C "${WORKDIR}"
SRC_DIR="${WORKDIR}/prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}"

install -o root -g root -m 0755 "${SRC_DIR}/prometheus" /usr/local/bin/prometheus
install -o root -g root -m 0755 "${SRC_DIR}/promtool" /usr/local/bin/promtool

# Prometheus 3.x dropped the old console templates feature (and the
# consoles/console_libraries directories + --web.console.* flags along with
# it); 2.x releases still ship them. Only wire the flags in when present.
CONSOLE_ARGS=""
if [[ -d "${SRC_DIR}/consoles" ]]; then
  cp -r "${SRC_DIR}/consoles/." "${PROMETHEUS_CONFIG_DIR}/consoles/"
  cp -r "${SRC_DIR}/console_libraries/." "${PROMETHEUS_CONFIG_DIR}/console_libraries/"
  CONSOLE_ARGS="--web.console.templates=${PROMETHEUS_CONFIG_DIR}/consoles --web.console.libraries=${PROMETHEUS_CONFIG_DIR}/console_libraries"
else
  echo "This release has no consoles/ directory (Prometheus 3.x+), skipping --web.console.* flags."
fi

if [[ ! -f "${PROMETHEUS_CONFIG_DIR}/prometheus.yml" ]]; then
  if [[ -f "${REPO_ROOT}/config/prometheus/prometheus.yml" ]]; then
    echo "Installing bundled prometheus.yml template (edit scrape targets before relying on it!)"
    cp "${REPO_ROOT}/config/prometheus/prometheus.yml" "${PROMETHEUS_CONFIG_DIR}/prometheus.yml"
  else
    cat > "${PROMETHEUS_CONFIG_DIR}/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
EOF
  fi
else
  echo "Existing prometheus.yml found, leaving it untouched."
fi

chown -R "${PROMETHEUS_USER}:${PROMETHEUS_USER}" "${PROMETHEUS_CONFIG_DIR}" "${PROMETHEUS_DATA_DIR}"

cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_USER}
Type=simple
ExecStart=/usr/local/bin/prometheus \\
  --config.file=${PROMETHEUS_CONFIG_DIR}/prometheus.yml \\
  --storage.tsdb.path=${PROMETHEUS_DATA_DIR} \\
  ${CONSOLE_ARGS} \\
  --web.listen-address=0.0.0.0:9090
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemd_reload_enable_start prometheus.service

echo
echo "Prometheus installed. UI: http://$(hostname -I | awk '{print $1}'):9090"
echo "Edit ${PROMETHEUS_CONFIG_DIR}/prometheus.yml to add scrape targets, then:"
echo "  sudo systemctl reload prometheus"