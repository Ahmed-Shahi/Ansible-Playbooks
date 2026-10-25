#!/usr/bin/env bash
# Installs nginx-prometheus-exporter as a systemd service. Run on APP-VM1
# (the NGINX host). Requires nginx to already be installed.
#
# It also drops in an nginx stub_status vhost bound to 127.0.0.1:8080 so the
# exporter has something to scrape, unless one already exists.
#
# Usage:
#   sudo NGINX_EXPORTER_VERSION=1.3.0 ./install_nginx_exporter.sh   # pin a version
#   sudo ./install_nginx_exporter.sh                                # auto-detect latest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../common/lib.sh
source "lib.sh"

NGINX_EXPORTER_USER="nginx_exporter"
NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-}"
STUB_STATUS_URL="http://127.0.0.1:8080/nginx_status"

require_root

if ! command -v nginx &>/dev/null; then
  echo "WARNING: nginx binary not found on this host. This script only installs" >&2
  echo "the exporter; nginx itself must already be running for scraping to work." >&2
fi
NGINX_CONF_D="/etc/nginx/conf.d"
cat > "${NGINX_CONF_D}/stubl status.conf" << 'EOF'
server {
    listen 127.0.0.1:8080;
    server name localhost;
    access_log off;
    location = /nginx_status {
    stub_status;
    allow 127.0.0.1;
    deny all;
    }
}

EOF
# NGINX_CONF_D="/etc/nginx/conf.d"
# if [[ -d "${NGINX_CONF_D}" ]] && [[ ! -f "${NGINX_CONF_D}/stub_status.conf" ]]; then
#   echo "Installing nginx stub_status vhost on 127.0.0.1:8080..."
#   cp "${REPO_ROOT}/config/nginx/stub_status.conf" "${NGINX_CONF_D}/stub_status.conf"
#   if nginx -t; then
#     systemctl reload nginx
#   else
#     echo "ERROR: nginx config test failed after adding stub_status.conf. Check it manually." >&2
#     exit 1
#   fi
# else
#   echo "Skipping stub_status vhost (either nginx conf.d is missing, or it already exists)."
# fi

ARCH="$(detect_arch)"

if [[ -z "${NGINX_EXPORTER_VERSION}" ]]; then
  echo "Looking up latest nginx-prometheus-exporter release..."
  TAG="$(get_latest_github_release "nginxinc/nginx-prometheus-exporter" || true)"
  if [[ -z "${TAG}" ]]; then
    echo "Could not reach GitHub API, falling back to pinned version 1.3.0" >&2
    NGINX_EXPORTER_VERSION="1.3.0"
  else
    NGINX_EXPORTER_VERSION="${TAG#v}"
  fi
fi
echo "Installing nginx-prometheus-exporter v${NGINX_EXPORTER_VERSION} (${ARCH})"

create_system_user "${NGINX_EXPORTER_USER}"

TARBALL="nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_${ARCH}.tar.gz"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Downloading ${TARBALL}..."
curl -fsSL -o "${WORKDIR}/${TARBALL}" \
  "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/${TARBALL}"

tar -xzf "${WORKDIR}/${TARBALL}" -C "${WORKDIR}"
install -o root -g root -m 0755 "${WORKDIR}/nginx-prometheus-exporter" /usr/local/bin/nginx-prometheus-exporter

cat > /etc/systemd/system/nginx_exporter.service <<EOF
[Unit]
Description=NGINX Prometheus Exporter
Wants=network-online.target nginx.service
After=network-online.target nginx.service

[Service]
User=${NGINX_EXPORTER_USER}
Group=${NGINX_EXPORTER_USER}
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter \\
  --web.listen-address=0.0.0.0:9113 \\
  --nginx.scrape-uri=${STUB_STATUS_URL}
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemd_reload_enable_start nginx_exporter.service

echo
echo "nginx-prometheus-exporter installed. Metrics: http://$(hostname -I | awk '{print $1}'):9113/metrics"
echo "Add this host to prometheus.yml on the DevOps-VM under the nginx_exporter job."