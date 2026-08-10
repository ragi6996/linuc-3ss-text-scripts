#!/usr/bin/env bash
# Shared helpers for FreeIPA container lab (chapter 5.2, runs on alma via podman).
set -euo pipefail

freeipa_data_dir() {
  echo "/var/lib/linuc3ss-freeipa"
}

freeipa_container_name() {
  echo "linuc3ss-freeipa"
}

freeipa_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker"
  else
    echo "FAIL: podman or docker required" >&2
    return 1
  fi
}

freeipa_cmd() {
  local rt
  rt="$(freeipa_runtime)"
  if [[ "${rt}" == podman && "$(id -u)" -ne 0 ]]; then
    sudo podman "$@"
  elif [[ "${rt}" == docker && "$(id -u)" -ne 0 ]]; then
    sudo docker "$@"
  else
    "${rt}" "$@"
  fi
}

freeipa_prepare_host() {
  sudo dnf install -y podman >/dev/null 2>&1 || true
  sudo setsebool -P container_manage_cgroup 1 2>/dev/null || true
  if ! swapon --show | grep -q swapfile; then
    if [[ ! -f /swapfile ]]; then
      sudo fallocate -l 2G /swapfile 2>/dev/null \
        || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none 2>/dev/null
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile >/dev/null
    fi
    sudo swapon /swapfile 2>/dev/null || true
  fi
}

freeipa_wait_ready() {
  local timeout_sec="${1:-1200}"
  local name elapsed
  name="$(freeipa_container_name)"
  elapsed=0
  echo "==> waiting for FreeIPA container (${timeout_sec}s max)"
  while [[ "${elapsed}" -lt "${timeout_sec}" ]]; do
    if freeipa_cmd inspect -f '{{.State.Running}}' "${name}" 2>/dev/null | grep -q true; then
      if freeipa_cmd exec "${name}" bash -c \
        'echo lab-freeipa-password | kinit admin >/dev/null 2>&1 && ipa config-show >/dev/null' 2>/dev/null; then
        echo "    OK: FreeIPA ready (${elapsed}s)"
        return 0
      fi
    elif freeipa_cmd inspect -f '{{.State.Status}}' "${name}" 2>/dev/null | grep -qE 'exited|stopped'; then
      echo "FAIL: FreeIPA container stopped during install" >&2
      freeipa_cmd logs "${name}" 2>&1 | tail -20 >&2 || true
      sudo tail -20 "$(freeipa_data_dir)/var/log/ipa-server-configure-first.log" 2>/dev/null >&2 || true
      return 1
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "    ... still starting (${elapsed}s)"
  done
  echo "FAIL: FreeIPA not ready within ${timeout_sec}s" >&2
  freeipa_cmd logs "${name}" 2>&1 | tail -30 >&2 || true
  return 1
}

freeipa_ensure_hosts() {
  local ip="$1"
  local line="${ip} ipa.lab.3ss.local"
  if grep -q 'ipa\.lab\.3ss\.local' /etc/hosts 2>/dev/null; then
    return 0
  fi
  echo "${line}" | sudo tee -a /etc/hosts >/dev/null
}

freeipa_start_container_once() {
  local data_dir image name
  data_dir="$(freeipa_data_dir)"
  name="$(freeipa_container_name)"
  image="${FREEIPA_IMAGE:-docker.io/freeipa/freeipa-server:almalinux-10}"

  if freeipa_cmd ps --format '{{.Names}}' | grep -qx "${name}"; then
    freeipa_wait_ready 120
    freeipa_ensure_hosts "$(hostname -I | awk '{print $1}')"
    echo "OK: FreeIPA container already running"
    return 0
  fi

  if freeipa_cmd ps -a --format '{{.Names}}' | grep -qx "${name}"; then
    freeipa_cmd rm -f "${name}" >/dev/null
  fi
  sudo rm -rf "${data_dir}"
  sudo mkdir -p "${data_dir}"

  echo "==> pulling FreeIPA image (first run may take several minutes)"
  freeipa_cmd pull "${image}"
  freeipa_cmd run -d --name "${name}" \
    --systemd=always \
    -h ipa.lab.3ss.local \
    --read-only \
    --tmpfs /run --tmpfs /tmp \
    --sysctl net.ipv6.conf.lo.disable_ipv6=0 \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    -v "${data_dir}:/data:Z" \
    -p 8443:443 -p 8080:80 \
    -p 8389:389 -p 8636:636 \
    -p 88:88 -p 464:464 \
    -p 88:88/udp -p 464:464/udp \
    -e PASSWORD=lab-freeipa-password \
    -e IPA_SERVER_IP=no-update \
    "${image}" \
    ipa-server-install -U \
    --realm=LAB.3SS.LOCAL \
    --domain=lab.3ss.local \
    --ds-password=lab-freeipa-password \
    --admin-password=lab-freeipa-password \
    --hostname=ipa.lab.3ss.local \
    --no-ntp \
    --no-host-dns

  freeipa_wait_ready 1200
  freeipa_ensure_hosts "$(hostname -I | awk '{print $1}')"
  echo "OK: FreeIPA container started"
}

freeipa_start_container() {
  freeipa_prepare_host
  local attempt
  for attempt in 1 2; do
    if freeipa_start_container_once; then
      return 0
    fi
    if [[ "${attempt}" -lt 2 ]]; then
      echo "WARN: FreeIPA install attempt ${attempt} failed — retrying once" >&2
      freeipa_cmd rm -f "$(freeipa_container_name)" >/dev/null 2>&1 || true
      sudo rm -rf "$(freeipa_data_dir)"
      sleep 15
    fi
  done
  return 1
}
