#!/usr/bin/env bash
# Placeholder TLS certs so nginx starts before ch04 step-ca provisioning.
set -euo pipefail

ensure_nginx_certs() {
  local cert_dir="${1:?cert_dir required}"
  mkdir -p "${cert_dir}"
  if [[ -f "${cert_dir}/cert.pem" && -f "${cert_dir}/key.pem" ]]; then
    return 0
  fi
  command -v openssl >/dev/null \
    || { echo "FAIL: openssl required for placeholder nginx certs" >&2; return 1; }
  echo "==> generating placeholder TLS certs (${cert_dir})"
  openssl req -x509 -nodes -days 30 -newkey rsa:2048 \
    -keyout "${cert_dir}/key.pem" -out "${cert_dir}/cert.pem" \
    -subj '/CN=www.lab.3ss.local' >/dev/null 2>&1
  chmod 644 "${cert_dir}/cert.pem"
  chmod 600 "${cert_dir}/key.pem"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  # shellcheck source=lab-dir.sh
  source "${SCRIPT_DIR}/lab-dir.sh"
  LAB_DIR="$(lab_dir_from_script "$0")"
  ensure_nginx_certs "${LAB_DIR}/certs"
fi
