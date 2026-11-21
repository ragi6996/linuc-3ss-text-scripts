#!/usr/bin/env bash
# Chapter 6 lab-net setup: ch06 profile (web, waf/CRS, ca, …) + TLS certificates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
SCRIPTS_DIR="$(scripts_dir_from_script "$0")"
LAB_NET_DIR="$(lab_net_dir_from_script "$0")"
cd "${LAB_NET_DIR}"
# shellcheck source=../lib/guest-lib.sh
source "${SCRIPT_DIR}/../lib/guest-lib.sh"

vm_compose --profile ch06 up -d dns ca
sleep 12
"${SCRIPTS_DIR}/lib/provision-ch04-certs.sh"
vm_compose --profile ch06 up -d
echo "OK: ch06 setup — lab-net ready (web :18080, waf/CRS :18082)"
