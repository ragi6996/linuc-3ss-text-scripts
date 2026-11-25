#!/usr/bin/env bash
# Chapter 5 lab-net setup: ch05 profile + TLS + Keycloak realm.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
SCRIPTS_DIR="$(scripts_dir_from_script "$0")"
LAB_NET_DIR="$(lab_net_dir_from_script "$0")"
cd "${LAB_NET_DIR}"
# shellcheck source=../lib/guest-lib.sh
source "${SCRIPT_DIR}/../lib/guest-lib.sh"

vm_compose --profile ch05 up -d dns ca
sleep 12
"${SCRIPTS_DIR}/lib/provision-ch04-certs.sh"
vm_compose --profile ch05 up -d
"${SCRIPTS_DIR}/lib/provision-ch05-keycloak.sh"
echo "OK: ch05 setup — lab-net ready"
