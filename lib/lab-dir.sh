#!/usr/bin/env bash
# Resolve 3_本編執筆 and scripts/lab-net paths from any script under 3_本編執筆/.

resolve_textbook_dir() {
  local d="$1"
  while [[ "${d}" != "/" ]]; do
    if [[ -f "${d}/SETUP.md" ]]; then
      printf '%s\n' "${d}"
      return 0
    fi
    d="$(dirname "${d}")"
  done
  echo "FAIL: textbook root (3_本編執筆) not found from ${1}" >&2
  return 1
}

textbook_dir_from_script() {
  resolve_textbook_dir "$(cd "$(dirname "${1}")" && pwd)"
}

lab_net_dir_from_script() {
  printf '%s\n' "$(textbook_dir_from_script "$1")/scripts/lab-net"
}

# Compose 作業ディレクトリ（第4章以降の lab-net）
lab_dir_from_script() {
  lab_net_dir_from_script "$1"
}
