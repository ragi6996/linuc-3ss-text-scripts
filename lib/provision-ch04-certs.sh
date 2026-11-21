#!/usr/bin/env bash
# Issue nginx TLS certificate from step-ca (ch04 profile must be running).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
LAB_DIR="$(lab_dir_from_script "$0")"
cd "$LAB_DIR"
# shellcheck source=guest-lib.sh
source "${SCRIPT_DIR}/guest-lib.sh"

STEP_CA_PASSWORD="${STEP_CA_PASSWORD:-lab-ca-password}"
CERT_DIR="${LAB_DIR}/certs"
CN="${CERT_CN:-www.lab.3ss.local}"

mkdir -p "${CERT_DIR}"

echo "==> Waiting for step-ca health"
for _ in $(seq 1 45); do
  if vm_compose exec -T ca step ca health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
vm_compose exec -T ca step ca health

echo "==> Issuing certificate for ${CN}"
vm_compose exec -T ca sh -c "echo '${STEP_CA_PASSWORD}' > /tmp/ca-pass && step ca certificate '${CN}' /tmp/cert.pem /tmp/key.pem --provisioner admin --password-file /tmp/ca-pass --san '${CN}' --san lab.3ss.local --force && rm -f /tmp/ca-pass"

vm_compose cp ca:/tmp/cert.pem "${CERT_DIR}/cert.pem"
vm_compose cp ca:/tmp/key.pem "${CERT_DIR}/key.pem"
vm_compose cp ca:/home/step/certs/root_ca.crt "${CERT_DIR}/root_ca.crt"
vm_compose cp ca:/home/step/certs/intermediate_ca.crt "${CERT_DIR}/intermediate_ca.crt"
cat "${CERT_DIR}/cert.pem" "${CERT_DIR}/intermediate_ca.crt" > "${CERT_DIR}/fullchain.pem"

vm_fix_cert_perms() {
  local d="$1"
  if chmod 644 "${d}/cert.pem" "${d}/root_ca.crt" "${d}/intermediate_ca.crt" "${d}/fullchain.pem" 2>/dev/null \
    && chmod 600 "${d}/key.pem" 2>/dev/null; then
    return 0
  fi
  vm_sudo chown "${USER}:${USER}" "${d}/cert.pem" "${d}/key.pem" "${d}/root_ca.crt" "${d}/intermediate_ca.crt" "${d}/fullchain.pem" 2>/dev/null || true
  chmod 644 "${d}/cert.pem" "${d}/root_ca.crt" "${d}/intermediate_ca.crt" "${d}/fullchain.pem"
  chmod 600 "${d}/key.pem"
}

vm_fix_cert_perms "${CERT_DIR}"

echo "==> Starting nginx (web) with TLS certs"
vm_compose up -d web
for _ in $(seq 1 30); do
  if curl -sf --max-time 5 "http://127.0.0.1:18080/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Waiting for HTTPS endpoint"
for _ in $(seq 1 20); do
  if curl -sf --max-time 5 --cacert "${CERT_DIR}/root_ca.crt" \
    --resolve "www.lab.3ss.local:18443:127.0.0.1" \
    "https://www.lab.3ss.local:18443/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "OK: certificates provisioned in ${CERT_DIR}"
