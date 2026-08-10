#!/usr/bin/env bash
# Guest alma: start FreeIPA server container (chapter 5.2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
TEXTBOOK_DIR="$(textbook_dir_from_script "$0")"
# shellcheck source=../lib/freeipa-lib.sh
source "${TEXTBOOK_DIR}/scripts/lib/freeipa-lib.sh"

freeipa_start_container
