#!/usr/bin/env bash
# FreeIPA container lab (chapter 5.2, AlmaLinux, podman only).
# Called from `if`, so set -e does not stop this file. Failures return 1
# before any OK line.
set -euo pipefail

freeipa_data_dir() { echo "/var/lib/linuc3ss-freeipa"; }
freeipa_container_name() { echo "linuc3ss-freeipa"; }

freeipa_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi
  echo "FAIL: podman is not installed. On AlmaLinux run: dnf install -y podman" >&2
  return 1
}

freeipa_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

freeipa_cmd() {
  freeipa_runtime >/dev/null
  if [[ "$(id -u)" -ne 0 ]]; then
    sudo podman "$@"
  else
    podman "$@"
  fi
}

freeipa_fail() {
  echo "FAIL: $*" >&2
  return 1
}

freeipa_major() {
  echo "${1%%.*}"
}

freeipa_prepare_host() {
  freeipa_root setsebool -P container_manage_cgroup 1 2>/dev/null || true
  if ! swapon --show | grep -q .; then
    if [[ ! -f /swapfile ]]; then
      freeipa_root fallocate -l 2G /swapfile 2>/dev/null \
        || freeipa_root dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
      freeipa_root chmod 600 /swapfile
      freeipa_root mkswap /swapfile >/dev/null
    fi
    freeipa_root swapon /swapfile 2>/dev/null || true
  fi
}

freeipa_check_stack() {
  local pver nver pmaj nmaj ldso
  pver="$(podman version -f '{{.Client.Version}}' 2>/dev/null || true)"
  nver=""
  if [[ -x /usr/libexec/podman/netavark ]]; then
    nver="$(/usr/libexec/podman/netavark --version 2>/dev/null | awk '{print $NF}')"
  fi
  echo "podman ${pver:-missing} / netavark ${nver:-missing}"
  [[ -n "${pver}" && -n "${nver}" ]] || { freeipa_fail "podman and netavark are both required"; return 1; }
  pmaj="$(freeipa_major "${pver}")"
  nmaj="$(freeipa_major "${nver}")"
  if [[ "${pmaj}" =~ ^[0-9]+$ && "${nmaj}" =~ ^[0-9]+$ ]]; then
    if { [[ "${pmaj}" -ge 6 && "${nmaj}" -lt 2 ]]; } || { [[ "${pmaj}" -lt 6 && "${nmaj}" -ge 2 ]]; }; then
      freeipa_fail "podman ${pver} and netavark ${nver} do not match (podman 6 needs netavark 2). Run: dnf -y install netavark aardvark-dns"
      return 1
    fi
  fi
  ldso=/lib64/ld-linux-x86-64.so.2
  if [[ -x "${ldso}" ]]; then
    if ! "${ldso}" --help 2>&1 | grep -q 'x86-64-v3 (supported'; then
      freeipa_fail "CPU does not support x86-64-v3. The almalinux-10 FreeIPA image exits at startup on older CPUs."
      return 1
    fi
  elif ! grep -qw avx2 /proc/cpuinfo; then
    freeipa_fail "CPU does not advertise AVX2 (needed for x86-64-v3)."
    return 1
  fi
}

freeipa_preflight() {
  local mem_mb disk_gb ip
  echo "==> preflight"
  if ! freeipa_check_stack; then
    return 1
  fi
  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  echo "RAM ${mem_mb} MiB"
  if [[ "${mem_mb}" -lt 3072 ]]; then
    freeipa_fail "RAM is ${mem_mb} MiB. FreeIPA needs about 4 GiB."
    return 1
  fi
  disk_gb="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
  if [[ -n "${disk_gb}" && "${disk_gb}" -lt 8 ]]; then
    freeipa_fail "less than 8 GiB free on /"
    return 1
  fi

  echo "==> listeners"
  ss -lntup | awk 'NR==1 || $5 ~ /:(80|88|389|443|464|636)$/' || true
  if ss -lntu | awk 'NR>1 {print $5}' | grep -Eq ':(80|88|389|443|464|636)$'; then
    freeipa_fail "a FreeIPA port is already in use (80, 88, 389, 443, 464, or 636). If httpd is running (chapter 1), stop it: systemctl stop httpd"
    return 1
  fi

  if getent ahostsv4 ipa.lab.3ss.local >/dev/null 2>&1; then
    ip="$(getent ahostsv4 ipa.lab.3ss.local | awk '{print $1; exit}')"
    if [[ -n "${ip}" ]] && hostname -I | grep -qw "${ip}"; then
      echo "NOTE: ipa.lab.3ss.local is this host (${ip}). podman run uses --hosts-file=none so the container keeps its own address."
    fi
  fi
}

freeipa_dump() {
  local name
  name="$(freeipa_container_name)"
  freeipa_cmd ps -a --filter "name=^${name}$" >&2 || true
  freeipa_cmd inspect -f 'Status={{.State.Status}} Exit={{.State.ExitCode}} OOM={{.State.OOMKilled}} Error={{.State.Error}}' "${name}" >&2 || true
  echo "==> last logs" >&2
  freeipa_cmd logs --tail 20 "${name}" >&2 || true
  freeipa_root tail -20 "$(freeipa_data_dir)/var/log/ipa-server-configure-first.log" >&2 || true
  free -m >&2 || true
}

freeipa_wait_ready() {
  local timeout_sec="${1:-600}"
  local name elapsed status line prev unchanged
  name="$(freeipa_container_name)"
  elapsed=0
  prev=""
  unchanged=0
  echo "==> waiting for FreeIPA container (${timeout_sec}s max)"
  while [[ "${elapsed}" -lt "${timeout_sec}" ]]; do
    status="$(freeipa_cmd inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || echo missing)"
    case "${status}" in
      created|exited|stopped|dead|missing)
        freeipa_fail "container status is ${status} after ${elapsed}s"
        freeipa_dump
        return 1
        ;;
    esac
    if [[ "${status}" == running ]]; then
      # kinit can succeed while ipa.service is still restarting at the end of the
      # install, so also require the final log line and a container that stays up.
      if freeipa_cmd logs "${name}" 2>&1 | grep -qE 'FreeIPA server (configured|started)\.' \
        && freeipa_cmd exec "${name}" bash -c \
          'echo lab-freeipa-password | kinit admin >/dev/null 2>&1 && ipa config-show >/dev/null' 2>/dev/null; then
        # 成功判定の直後に ipa サービスの再起動が走ってコンテナが落ちる回が、測定中に 1 度あった
        # （kinit が通った数秒後に Exited 123）。落ちないことを 5 秒待って確かめる。
        sleep 5
        if [[ "$(freeipa_cmd inspect -f '{{.State.Status}}' "${name}" 2>/dev/null)" == running ]]; then
          echo "    OK: FreeIPA ready (${elapsed}s)"
          return 0
        fi
      fi
    fi
    line="$(freeipa_cmd logs --tail 1 "${name}" 2>/dev/null | tail -1 | tr '\t' ' ')"
    echo "    ${elapsed}s status=${status} log=${line:-<none>}"
    if [[ "${line}" == "${prev}" ]]; then
      unchanged=$((unchanged + 10))
    else
      unchanged=0
      prev="${line}"
    fi
    # The quietest stretch of a good install was 124-129s (CA [1/33] to [2/33]).
    if [[ "${unchanged}" -ge 240 ]]; then
      freeipa_fail "no new container log for ${unchanged}s (status=${status})"
      freeipa_dump
      return 1
    fi
    # 10 秒おきに確認する。FreeIPA の初回構築（podman run から ready まで）を、KVM（2 vCPU・RAM 4GB）で
    # 複数回測定して正常系の完了時間を調べた。AlmaLinux 10 イメージで 190〜210 秒、9 イメージでも
    # 180〜198 秒で、差はない。これに対して全体の上限 600 秒は約 3 倍、ログ無更新の上限 240 秒は
    # 測定した最長の無更新（124〜129 秒）の約 2 倍にしている。
    sleep 10
    elapsed=$((elapsed + 10))
  done
  freeipa_fail "FreeIPA not ready within ${timeout_sec}s (status=${status:-unknown})"
  freeipa_dump
  return 1
}

# First global IPv4 that is not on the default-route NIC and not a bridge.
# With NAT + host-only, this is the host-only address. hostname -I lists NAT first.
freeipa_hostonly_ip() {
  local defdev
  defdev="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  ip -4 -o addr show scope global 2>/dev/null | awk -v d="${defdev}" '
    $2 == d { next }
    $2 ~ /^(lo|docker.*|br-.*|podman.*|cni.*|veth.*|virbr.*|tun.*|tap.*)$/ { next }
    { split($4, a, "/"); print a[1]; exit }
  '
}

freeipa_ensure_hosts() {
  if grep -q 'ipa\.lab\.3ss\.local' /etc/hosts 2>/dev/null; then
    return 0
  fi
  freeipa_fail "/etc/hosts has no ipa.lab.3ss.local. Add the host-only address guests use, for example: 192.168.56.11 ipa.lab.3ss.local"
  echo "With two NICs, the first address from hostname -I is the NAT NIC. Do not write that address." >&2
  return 1
}

freeipa_check_server_hosts() {
  local resolved nat other
  if ! freeipa_ensure_hosts; then
    return 1
  fi
  resolved="$(getent ahostsv4 ipa.lab.3ss.local 2>/dev/null | awk '{print $1; exit}')"
  nat="$(ip -4 route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") { print $(i+1); exit }}')"
  other="$(freeipa_hostonly_ip)"
  if [[ -n "${other}" && -n "${nat}" && "${resolved}" == "${nat}" ]]; then
    freeipa_fail "ipa.lab.3ss.local resolves to the NAT address ${resolved}. Use the host-only address ${other}."
    return 1
  fi
  if [[ -n "${resolved}" ]] && ! hostname -I | grep -qw "${resolved}"; then
    freeipa_fail "ipa.lab.3ss.local resolves to ${resolved}, which is not an address of this host."
    return 1
  fi
  return 0
}

freeipa_has_data() {
  local data
  data="$(freeipa_data_dir)"
  [[ -d "${data}" ]] && [[ -n "$(ls -A "${data}" 2>/dev/null)" ]]
}

freeipa_start_container_once() {
  local data name image status
  data="$(freeipa_data_dir)"
  name="$(freeipa_container_name)"
  image=docker.io/freeipa/freeipa-server:almalinux-10
  if ! freeipa_check_stack; then
    return 1
  fi
  if ! freeipa_check_server_hosts; then
    return 1
  fi

  if [[ "${FREEIPA_RESET:-}" == 1 ]]; then
    echo "==> FREEIPA_RESET=1: removing ${name} and ${data}"
    freeipa_cmd rm -f "${name}" >/dev/null 2>&1 || true
    freeipa_root rm -rf "${data}"
  elif freeipa_cmd ps --format '{{.Names}}' | grep -qx "${name}"; then
    if freeipa_wait_ready 60; then
      echo "OK: FreeIPA container already running"
      return 0
    fi
    freeipa_fail "container is running but FreeIPA is not ready. Set FREEIPA_RESET=1 to reinstall."
    return 1
  else
    status="$(freeipa_cmd inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || true)"
    if [[ "${status}" == exited || "${status}" == stopped ]]; then
      echo "==> container is ${status}; starting it without deleting ${data}"
      if ! freeipa_cmd start "${name}"; then
        freeipa_fail "podman start ${name} failed"
        return 1
      fi
      if ! freeipa_wait_ready 600; then
        return 1
      fi
      echo "OK: FreeIPA container started"
      return 0
    fi
  fi

  if ! freeipa_preflight; then
    return 1
  fi

  if freeipa_cmd ps -a --format '{{.Names}}' | grep -qx "${name}" || freeipa_has_data; then
    freeipa_fail "FreeIPA container or ${data} already exists. Set FREEIPA_RESET=1 to remove it and install again."
    return 1
  fi

  freeipa_root mkdir -p "${data}"
  echo "==> pulling ${image}"
  if ! freeipa_cmd pull "${image}"; then
    freeipa_fail "podman pull ${image} failed"
    return 1
  fi

  # --hosts-file=none: do not copy the host /etc/hosts line
  # "<this-host-ip> ipa.lab.3ss.local" into the container.
  echo "==> podman run"
  if ! freeipa_cmd run -d --name "${name}" \
    --systemd=always \
    -h ipa.lab.3ss.local \
    --hosts-file=none \
    --read-only \
    --tmpfs /run --tmpfs /tmp \
    --sysctl net.ipv6.conf.lo.disable_ipv6=0 \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    -v "${data}:/data:Z" \
    -p 443:443 -p 80:80 \
    -p 389:389 -p 636:636 \
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
  then
    freeipa_fail "podman run exited non-zero"
    freeipa_dump
    return 1
  fi

  if ! freeipa_wait_ready 600; then
    return 1
  fi
  echo "OK: FreeIPA container started"
  return 0
}

freeipa_start_container() {
  if ! freeipa_runtime >/dev/null; then
    return 1
  fi
  freeipa_prepare_host
  if ! freeipa_start_container_once; then
    return 1
  fi
  return 0
}
