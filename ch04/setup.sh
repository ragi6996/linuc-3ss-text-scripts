#!/usr/bin/env bash
# Chapter 4 lab-net setup: ch04 profile + TLS certificates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
TEXTBOOK_DIR="$(textbook_dir_from_script "$0")"
LAB_NET_DIR="$(lab_net_dir_from_script "$0")"
cd "${LAB_NET_DIR}"
# shellcheck source=../lib/guest-lib.sh
source "${SCRIPT_DIR}/../lib/guest-lib.sh"

vm_compose --profile ch04 up -d dns ca
sleep 12
"${TEXTBOOK_DIR}/scripts/lib/provision-ch04-certs.sh"
vm_compose --profile ch04 up -d
echo "OK: ch04 setup — lab-net ready"
