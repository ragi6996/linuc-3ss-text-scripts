#!/usr/bin/env bash
# Resolve the scripts root and lab-net paths for reader-facing scripts.
# Works both in-repo (3_本編執筆/scripts/) and when only the scripts tree is
# deployed elsewhere (e.g. /opt/linuc-3ss-text-scripts/).

_SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

scripts_dir_from_script() {
  printf '%s\n' "${_SCRIPTS_ROOT}"
}

lab_net_dir_from_script() {
  printf '%s\n' "${_SCRIPTS_ROOT}/lab-net"
}

# Compose 作業ディレクトリ（第4章以降の lab-net）
lab_dir_from_script() {
  lab_net_dir_from_script "$@"
}
