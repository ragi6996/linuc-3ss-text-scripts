#!/usr/bin/env bash
# Provision Keycloak realm/client/user for ch05 (Keycloak must be healthy).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/lab-dir.sh
source "${SCRIPT_DIR}/../lib/lab-dir.sh"
LAB_DIR="$(lab_dir_from_script "$0")"
cd "$LAB_DIR"
# shellcheck source=guest-lib.sh
source "${SCRIPT_DIR}/guest-lib.sh"

KC_ADMIN="${KC_ADMIN:-admin}"
KC_PASS="${KC_PASS:-lab-keycloak-password}"
REALM="${REALM:-lab}"
CLIENT_ID="${CLIENT_ID:-grafana}"
CLIENT_SECRET="${CLIENT_SECRET:-lab-grafana-secret}"
LAB_USER="${LAB_USER:-labuser}"
LAB_USER_PASS="${LAB_USER_PASS:-lab-user-password}"
KC_URL_HOST="${KC_URL_HOST:-http://127.0.0.1:18081}"
KC_URL_CONTAINER="${KC_URL_CONTAINER:-http://localhost:8080}"

fail() { echo "FAIL: $*" >&2; exit 1; }

kcadm() {
  vm_compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

echo "==> Waiting for Keycloak health"
for _ in $(seq 1 60); do
  if curl -sf "${KC_URL_HOST}/health/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -sf "${KC_URL_HOST}/health/ready" >/dev/null || fail "keycloak not ready"

echo "==> Keycloak admin login"
kcadm config credentials \
  --server "${KC_URL_CONTAINER}" \
  --realm master \
  --user "${KC_ADMIN}" \
  --password "${KC_PASS}"

echo "==> Realm ${REALM}"
if ! kcadm get "realms/${REALM}" >/dev/null 2>&1; then
  kcadm create realms -s "realm=${REALM}" -s enabled=true
fi

echo "==> OIDC client ${CLIENT_ID}"
existing_id="$(kcadm get clients -r "${REALM}" -q "clientId=${CLIENT_ID}" --fields id --format csv --noquotes 2>/dev/null | tail -n1 || true)"
if [[ -z "${existing_id}" || "${existing_id}" == "id" ]]; then
  kcadm create clients -r "${REALM}" \
    -s "clientId=${CLIENT_ID}" \
    -s enabled=true \
    -s publicClient=false \
    -s secret="${CLIENT_SECRET}" \
    -s directAccessGrantsEnabled=true \
    -s 'redirectUris=["http://127.0.0.1:13000/login/generic_oauth"]' \
    -s 'webOrigins=["http://127.0.0.1:13000"]'
else
  kcadm update "clients/${existing_id}" -r "${REALM}" \
    -s secret="${CLIENT_SECRET}" \
    -s directAccessGrantsEnabled=true \
    -s 'redirectUris=["http://127.0.0.1:13000/login/generic_oauth"]' \
    -s 'webOrigins=["http://127.0.0.1:13000"]'
fi

echo "==> Lab user ${LAB_USER}"
user_id="$(kcadm get users -r "${REALM}" -q "username=${LAB_USER}" --fields id --format csv --noquotes 2>/dev/null | tail -n1 || true)"
if [[ -z "${user_id}" || "${user_id}" == "id" ]]; then
  kcadm create users -r "${REALM}" \
    -s "username=${LAB_USER}" \
    -s "email=${LAB_USER}@lab.3ss.local" \
    -s firstName=Lab \
    -s lastName=User \
    -s emailVerified=true \
    -s enabled=true
  user_id="$(kcadm get users -r "${REALM}" -q "username=${LAB_USER}" --fields id --format csv --noquotes | tail -n1)"
fi
kcadm set-password -r "${REALM}" --username "${LAB_USER}" --new-password "${LAB_USER_PASS}" --temporary=false
kcadm update "users/${user_id}" -r "${REALM}" \
  -s firstName=Lab \
  -s lastName=User \
  -s "email=${LAB_USER}@lab.3ss.local" \
  -s emailVerified=true \
  -s 'requiredActions=[]'

echo "OK: Keycloak provisioned (realm=${REALM}, client=${CLIENT_ID}, user=${LAB_USER})"
