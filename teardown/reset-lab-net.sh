#!/usr/bin/env bash
# Full reset: lab-down + restore placeholder TLS certs for a clean ch04 cycle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
LAB_DIR="$(lab_dir_from_script "$0")"
cd "$LAB_DIR"

"${SCRIPT_DIR}/down-lab-net.sh"

CERT_DIR="${LAB_DIR}/certs"
mkdir -p "${CERT_DIR}"

if [[ ! -f "${CERT_DIR}/.placeholder-generated" ]]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "${CERT_DIR}/key.pem" \
    -out "${CERT_DIR}/cert.pem" \
    -subj "/CN=www.lab.3ss.local" 2>/dev/null
  cp "${CERT_DIR}/cert.pem" "${CERT_DIR}/root_ca.crt"
  chmod 600 "${CERT_DIR}/key.pem"
  touch "${CERT_DIR}/.placeholder-generated"
fi

echo "OK: lab reset (placeholder certs in ${CERT_DIR})"
