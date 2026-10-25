#!/usr/bin/env bash
# Shared helpers sourced by the other install scripts in this repo.
# Not meant to be executed directly.

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: this script must be run as root (use sudo)." >&2
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "ERROR: unsupported architecture $(uname -m)" >&2
      exit 1
      ;;
  esac
}

# get_latest_github_release <owner/repo>
# Prints the latest release tag (e.g. v2.55.1), stripped of nothing.
# Falls back to empty string on failure so callers can pin a version instead.
get_latest_github_release() {
  local repo="$1"
  local response
  # Buffer the full response before piping into grep/sed: piping curl
  # directly into `grep -m1` lets grep exit as soon as it finds a match,
  # which closes the pipe while curl is still writing and makes curl fail
  # with "(23) Failure writing output" even though the data we wanted was
  # already received.
  response="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")" || return 1
  echo "${response}" \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/'
}

create_system_user() {
  local user="$1"
  if ! id "${user}" &>/dev/null; then
    useradd --no-create-home --shell /usr/sbin/nologin "${user}"
    echo "Created system user '${user}'."
  else
    echo "System user '${user}' already exists, skipping."
  fi
}

systemd_reload_enable_start() {
  local service="$1"
  systemctl daemon-reload
  systemctl enable "${service}"
  systemctl restart "${service}"
  sleep 1
  systemctl --no-pager --full status "${service}" | head -n 10
}