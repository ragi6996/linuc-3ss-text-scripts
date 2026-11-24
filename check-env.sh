#!/usr/bin/env bash
# 実習環境が、本書が想定する状態になっているかを確認する（読み取り専用。何も変更しない）。
# Debian・AlmaLinux のどちらのゲストでも、SETUP の完了後に実行する。
#   ./check-env.sh            # OS を自動判定
#   ./check-env.sh --no-net   # インターネット・相手ゲストへの疎通確認を省く
# 終了コード: FAIL が 1 つでもあれば 1、そうでなければ 0（WARN は 0）。
set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

CHECK_NET=1
[ "${1:-}" = "--no-net" ] && CHECK_NET=0

EXPECT_DEBIAN_IP="192.168.56.21"
EXPECT_ALMA_IP="192.168.56.11"

n_fail=0
n_warn=0
ok()   { echo "OK:   $*"; }
warn() { echo "WARN: $*"; n_warn=$((n_warn + 1)); }
fail() { echo "FAIL: $*"; n_fail=$((n_fail + 1)); }
note() { echo "      $*"; }

[ "$(id -u)" -eq 0 ] || { echo "FAIL: root で実行してください（sshd -T などの確認に必要）" >&2; exit 1; }
[ -r /etc/os-release ] || { echo "FAIL: /etc/os-release がありません" >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
  debian) ROLE=debian; PEER=alma;   MY_IP="$EXPECT_DEBIAN_IP"; PEER_IP="$EXPECT_ALMA_IP" ;;
  almalinux|rocky|rhel|centos) ROLE=alma; PEER=debian; MY_IP="$EXPECT_ALMA_IP"; PEER_IP="$EXPECT_DEBIAN_IP" ;;
  *) echo "FAIL: 想定外の OS です: ${PRETTY_NAME:-unknown}（Debian 13 または AlmaLinux のゲストで実行してください）" >&2; exit 1 ;;
esac

echo "== 実習環境チェック（${ROLE}: ${PRETTY_NAME:-}） =="

echo "-- OS・リソース"
case "$ROLE:${VERSION_ID%%.*}" in
  debian:13) ok "OS: ${PRETTY_NAME}" ;;
  alma:10)   ok "OS: ${PRETTY_NAME}" ;;
  alma:9)    warn "OS: ${PRETTY_NAME}。本書の検証は AlmaLinux 10 です。FreeIPA コンテナ自体は動きますが、手順や出力が異なる場合があります" ;;
  *)         warn "OS: ${PRETTY_NAME}。本書の検証は Debian 13 / AlmaLinux 10 です" ;;
esac

cpus="$(nproc)"
[ "$cpus" -ge 2 ] && ok "vCPU: ${cpus}" || fail "vCPU が ${cpus} です。2 以上を割り当ててください"

mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
if [ "$mem_mb" -ge 3500 ]; then
  ok "メモリ: ${mem_mb}MB"
else
  fail "メモリが ${mem_mb}MB です。4GB 以上を割り当ててください（第 4 章以降のコンテナ、FreeIPA の構築に必要）"
fi

root_free_gb="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
[ "${root_free_gb:-0}" -ge 15 ] && ok "/ の空き: ${root_free_gb}GB" || fail "/ の空きが ${root_free_gb}GB です。ディスクは 30GB 以上にしてください"

if [ "$ROLE" = alma ]; then
  flags="$(grep -m1 '^flags' /proc/cpuinfo || true)"
  missing=""
  for f in avx2 bmi2 fma movbe; do
    echo "$flags" | grep -qw "$f" || missing="$missing $f"
  done
  if [ -z "$missing" ]; then
    ok "CPU: x86-64-v3 相当（FreeIPA の AlmaLinux 10 コンテナに必要）"
  else
    fail "CPU に${missing} がありません。AlmaLinux 10 の FreeIPA コンテナが起動できません"
    note "VirtualBox: 設定 → システム → プロセッサー で、可能なら「ネストされた VT-x/AMD-V」や、KVM なら CPU を host-passthrough にしてください"
  fi
fi

echo "-- ホスト名・ネットワーク"
want_host="$([ "$ROLE" = debian ] && echo debian || echo alma)"
cur_host="$(hostname -s)"
[ "$cur_host" = "$want_host" ] && ok "ホスト名: ${cur_host}" || warn "ホスト名が ${cur_host} です（本書は ${want_host}。プロンプト表示が本文と異なります）"

if ip -4 -o addr show | awk '{print $4}' | grep -q '^192\.168\.56\.'; then
  my_ip="$(ip -4 -o addr show | awk '{print $4}' | grep '^192\.168\.56\.' | head -1 | cut -d/ -f1)"
  if [ "$my_ip" = "$MY_IP" ]; then
    ok "ホストオンリー側のアドレス: ${my_ip}"
  else
    warn "ホストオンリー側のアドレスは ${my_ip} です（本書は ${MY_IP}）。/etc/hosts の例は、ご自身のアドレスに読み替えてください"
  fi
else
  warn "192.168.56.0/24 のアドレスが見つかりません。2 台が相互に接続できる IP を、ゲスト間で通信できる NIC に設定してください"
  note "ip -4 -o addr で確認できます。VirtualBox ならホストオンリーアダプターを 2 枚目の NIC として有効にします"
fi

nics_up="$(ip -4 -o addr show up scope global | awk '$2 !~ /^(docker|br-|veth|virbr|cni|podman)/ {print $2}' | sort -u | wc -l)"
[ "$nics_up" -ge 2 ] && ok "IPv4 アドレスを持つ有効な NIC: ${nics_up} 枚（NAT とホストオンリー）" \
  || warn "IPv4 アドレスを持つ有効な NIC が ${nics_up} 枚です。NAT のみだと 2 台が相互に接続できません"

peer_line="$(grep -E "(^|[[:space:]])${PEER}([[:space:]]|\$)" /etc/hosts | head -1 || true)"
if [ -n "$peer_line" ]; then
  ok "/etc/hosts に ${PEER} があります: ${peer_line}"
else
  fail "/etc/hosts に ${PEER} がありません（SETUP の「ゲスト間の名前解決」を実施してください）"
fi
if [ "$ROLE" = alma ]; then
  ipa_line="$(grep -E '(^|[[:space:]])ipa\.lab\.3ss\.local' /etc/hosts | head -1 || true)"
  if [ -n "$ipa_line" ]; then
    ipa_ip="${ipa_line%%[[:space:]]*}"
    nat_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    n_addrs="$(ip -4 -o addr show scope global | wc -l)"
    if ! ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -qx "$ipa_ip"; then
      fail "/etc/hosts の ipa.lab.3ss.local は ${ipa_ip} ですが、このゲストのアドレスではありません（ホストオンリー側のアドレスを書いてください）"
    elif [ "$n_addrs" -ge 2 ] && [ "$ipa_ip" = "$nat_ip" ]; then
      fail "/etc/hosts の ipa.lab.3ss.local が NAT 側のアドレス(${ipa_ip})です。Debian から届かないので、ホストオンリー側のアドレスにしてください"
    else
      ok "/etc/hosts の ipa.lab.3ss.local はこのゲスト自身のアドレス(${ipa_ip})です"
    fi
  else
    fail "/etc/hosts に ipa.lab.3ss.local がありません（SETUP の「ゲスト間の名前解決」を実施してください）"
  fi
else
  grep -qE '(^|[[:space:]])ipa\.lab\.3ss\.local' /etc/hosts \
    && ok "/etc/hosts に ipa.lab.3ss.local があります" \
    || fail "/etc/hosts に ipa.lab.3ss.local がありません（SETUP の「ゲスト間の名前解決」を実施してください）"
fi

if [ "$CHECK_NET" -eq 1 ]; then
  peer_ip_now="$(awk -v p="$PEER" '$0 !~ /^#/ { for (i=2;i<=NF;i++) if ($i==p) { print $1; exit } }' /etc/hosts)"
  peer_ip_now="${peer_ip_now:-$PEER_IP}"
  if ping -c1 -W2 "$peer_ip_now" >/dev/null 2>&1; then
    ok "相手ゲスト(${PEER}, ${peer_ip_now})へ ping が通ります"
  else
    warn "相手ゲスト(${PEER}, ${peer_ip_now})へ ping が通りません（相手が起動していない、または相互接続の設定を確認してください）"
  fi
  url="$([ "$ROLE" = debian ] && echo https://deb.debian.org/ || echo https://repo.almalinux.org/)"
  if curl -fsS -o /dev/null --max-time 10 "$url"; then
    ok "インターネットへ接続できます(${url})"
  else
    fail "インターネットへ接続できません(${url})。パッケージの導入ができません"
  fi
fi

echo "-- ログイン・SSH"
if [ -d /etc/cloud ] || command -v cloud-init >/dev/null 2>&1; then
  warn "cloud-init が入っています（クラウドイメージ由来の VM）。本書はインストーラ（ISO）で作成した VM が前提です"
fi

if command -v sshd >/dev/null 2>&1; then
  pw="$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication" {print $2}')"
  if [ "$pw" = yes ]; then
    ok "sshd: PasswordAuthentication yes"
  else
    warn "sshd: PasswordAuthentication が ${pw:-不明} です。パスワードで ssh ログインする実習（5.1 PAM の faillock など）が再現できません"
    note "/etc/ssh/sshd_config.d/ 内の PasswordAuthentication no を確認してください"
  fi
else
  fail "sshd が入っていません（OS インストール時に「SSH server」を選択、または openssh-server を導入してください）"
fi

[ -n "$(getent passwd testuser)" ] && ok "一般ユーザー testuser があります" \
  || warn "一般ユーザー testuser がありません（SETUP の「ゲスト VM の作成」の要件）"

echo "-- SETUP で導入するパッケージ"
need_cmds=()
if [ "$ROLE" = debian ]; then
  need_cmds=(docker named dig ldapsearch auditctl nft tcpdump git setfacl aa-status)
  if ! { command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; }; then
    fail "docker compose / docker-compose がありません"
  fi
  if dpkg -s libpam-pwquality >/dev/null 2>&1; then ok "libpam-pwquality"; else fail "libpam-pwquality が入っていません"; fi
  if [ -d /etc/apt/sources.list.d ] && ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1 && [ ! -s /etc/apt/sources.list ]; then
    ok "apt: deb822 形式（debian.sources）"
  elif [ -s /etc/apt/sources.list ]; then
    ok "apt: sources.list"
  fi
else
  need_cmds=(podman curl ldapsearch git getenforce)
  command -v nfs4_getfacl >/dev/null 2>&1 && ok "nfs4-acl-tools" || fail "nfs4-acl-tools が入っていません"
  [ "$(getenforce 2>/dev/null)" = Enforcing ] && ok "SELinux: Enforcing" \
    || warn "SELinux が $(getenforce 2>/dev/null || echo 不明) です（第 1.2 章は Enforcing 前提）"
  if systemctl is-active --quiet firewalld; then ok "firewalld: active"; else warn "firewalld が動いていません（インストーラ由来の AlmaLinux は既定で有効です）"; fi
fi
for c in "${need_cmds[@]}"; do
  command -v "$c" >/dev/null 2>&1 && ok "コマンド: ${c}" || fail "コマンドがありません: ${c}（SETUP のパッケージ導入を確認してください）"
done

echo "-- 動作確認用スクリプト"
scripts_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -d "${scripts_dir}/ch05" ] && [ -d "${scripts_dir}/lib" ]; then
  ok "スクリプトの場所: ${scripts_dir}"
else
  fail "スクリプトの構成が想定と異なります: ${scripts_dir}"
fi
n_nonexec="$(find "$scripts_dir" -name '*.sh' ! -perm -u+x -not -path '*/.git/*' | wc -l)"
if [ "$n_nonexec" -eq 0 ]; then
  ok "*.sh に実行権があります"
else
  warn "実行権のない *.sh が ${n_nonexec} 本あります（bash <ファイル> で実行するか、find ${scripts_dir} -name '*.sh' -exec chmod +x {} + を実行してください）"
fi

echo
echo "== 結果: FAIL ${n_fail} / WARN ${n_warn} =="
[ "$n_fail" -eq 0 ]
