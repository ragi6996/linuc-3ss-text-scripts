#!/usr/bin/env bash
# Helpers for scripts run on debian/alma guests.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

vm_fail() { echo "FAIL: $*" >&2; exit 1; }
vm_skip() { echo "SKIP: $*" >&2; }

vm_need_cmd() {
  command -v "$1" >/dev/null || vm_fail "command not found: $1"
}

vm_sudo() {
  sudo -n "$@" 2>/dev/null || sudo "$@"
}

# docker group は usermod 直後も sg 経由なら SSH 1 セッションで使える
vm_docker() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  elif sg docker -c "docker info" >/dev/null 2>&1; then
    sg docker -c "docker $(printf '%q ' "$@")"
  else
    vm_sudo docker "$@"
  fi
}

# lab-net 用 — compose プラグイン未導入時は sudo / sg 経由にフォールバック
vm_compose() {
  if docker compose version --short 2>/dev/null | grep -qE '^v?2\.'; then
    docker compose "$@"
  elif sg docker -c "docker compose version --short" 2>/dev/null | grep -qE '^v?2\.'; then
    sg docker -c "docker compose $(printf '%q ' "$@")"
  else
    vm_sudo docker compose "$@"
  fi
}
