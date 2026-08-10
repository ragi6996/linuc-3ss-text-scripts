#!/usr/bin/env bash
# Stop lab-net and remove containers, networks, volumes, and orphan services.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
LAB_DIR="$(lab_dir_from_script "$0")"
cd "$LAB_DIR"
# shellcheck source=../lib/guest-lib.sh
source "${SCRIPT_DIR}/../lib/guest-lib.sh"

PROFILES=(--profile smoke --profile ch04 --profile ch05 --profile ch06)

echo "==> Stopping lab (${PROFILES[*]})"
vm_compose "${PROFILES[@]}" down -v --remove-orphans

# Belt-and-suspenders: report anything left that still looks like this project
left="$(vm_docker ps -aq --filter "label=com.docker.compose.project=lab" 2>/dev/null || true)"
if [[ -n "${left}" ]]; then
  echo "WARN: removing leftover containers: ${left}"
  vm_docker rm -f ${left} 2>/dev/null || true
fi

vols="$(vm_docker volume ls -q --filter "name=^lab_" 2>/dev/null || true)"
if [[ -n "${vols}" ]]; then
  echo "WARN: removing leftover volumes: ${vols}"
  vm_docker volume rm ${vols} 2>/dev/null || true
fi

nets="$(vm_docker network ls -q --filter "name=lab_" 2>/dev/null || true)"
if [[ -n "${nets}" ]]; then
  for n in ${nets}; do
    if vm_docker network inspect "${n}" --format '{{len .Containers}}' 2>/dev/null | grep -q '^0$'; then
      vm_docker network rm "${n}" 2>/dev/null || true
    fi
  done
fi

echo "OK: lab stopped"
