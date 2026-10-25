#!/usr/bin/env bash
# Installs node_exporter as a systemd service. Run on APP-VM1 and APP-VM2
# (any host you want host-level metrics for: CPU, memory, disk, network).
#
# Usage:
#   sudo NODE_EXPORTER_VERSION=1.8.2 ./install_node_exporter.sh   # pin a version
#   sudo ./install_node_exporter.sh                               # auto-detect latest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "lib.sh"

NODE_EXPORTER_USER="node_exporter"
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-}"

require_root

ARCH="$(detect_arch)"

if [[ -z "${NODE_EXPORTER_VERSION}" ]]; then
  echo "Looking up latest node_exporter release..."
  TAG="$(get_latest_github_release "prometheus/node_exporter" || true)"
  if [[ -z "${TAG}" ]]; then
    echo "Could not reach GitHub API, falling back to pinned version 1.8.2" >&2
    NODE_EXPORTER_VERSION="1.8.2"
  else
    NODE_EXPORTER_VERSION="${TAG#v}"
  fi
fi
echo "Installing node_exporter v${NODE_EXPORTER_VERSION} (${ARCH})"

create_system_user "${NODE_EXPORTER_USER}"

TARBALL="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Downloading ${TARBALL}..."
curl -fsSL -o "${WORKDIR}/${TARBALL}" \
  "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${TARBALL}"

tar -xzf "${WORKDIR}/${TARBALL}" -C "${WORKDIR}"
install -o root -g root -m 0755 \
  "${WORKDIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}/node_exporter" \
  /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemd_reload_enable_start node_exporter.service

echo
echo "node_exporter installed. Metrics: http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo "Add this host to prometheus.yml on the DevOps-VM under the node_exporter job."