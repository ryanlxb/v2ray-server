#!/usr/bin/env bash
# =============================================================================
# v2ray-server one-click setup for Ubuntu 22/24/26
#
# What this script does:
#   1. Validates OS (Ubuntu 22-26)
#   2. Installs x-ui-yg directly (no interactive menu)
#   3. Sets panel port to 13579
#   4. Pre-seeds a VLESS+Reality inbound on port 24680 via x-ui API
#   5. Opens UFW ports if active
#   6. Prints the connection summary + client config
#
# Autostart: x-ui registers a systemd service (x-ui.service) on install.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ryanlxb/v2ray-server/main/server_init.sh \
#     -o /tmp/server_init.sh && sudo bash /tmp/server_init.sh
# =============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── constants ────────────────────────────────────────────────────────────────
XRAY_PORT=24680
UI_PORT=13579
UI_USER="admin"
UI_PASS="admin"

REALITY_SERVER_NAME="www.yahoo.com"
REALITY_FINGERPRINT="firefox"

XUI_RELEASE_URL="https://github.com/yonggekkk/x-ui-yg/releases/download/xui_yg"
XUI_INSTALL_SH="https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/install.sh"
XUI_BIN="/usr/local/x-ui/x-ui"
XUI_DIR="/usr/local/x-ui"
XRAY_BIN=""   # resolved after install

# ── helpers ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || error "Run as root: sudo bash $0"
}

check_ubuntu() {
    local ver id
    ver=$(. /etc/os-release && echo "$VERSION_ID")
    id=$(. /etc/os-release && echo "$ID")
    local major="${ver%%.*}"
    [[ "$id" == "ubuntu" ]] || error "This script only supports Ubuntu."
    [[ $major -ge 22 && $major -le 26 ]] || \
        error "Supported Ubuntu versions: 22-26. Detected: $ver"
    info "OS: Ubuntu $ver — OK"
}

# ── detect CPU arch ───────────────────────────────────────────────────────────
detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64)  CPU="amd64" ;;
        aarch64) CPU="arm64" ;;
        armv7*)  CPU="armv7" ;;
        *)       error "Unsupported architecture: $machine" ;;
    esac
    info "Architecture: ${machine} → ${CPU}"
}

# ── install dependencies ──────────────────────────────────────────────────────
install_deps() {
    info "Installing dependencies ..."
    apt-get update -qq
    apt-get install -y -qq curl wget tar jq cron socat iptables-persistent 2>/dev/null || \
    apt-get install -y -qq curl wget tar jq cron socat 2>/dev/null || true
}

# ── install x-ui-yg ──────────────────────────────────────────────────────────
install_xui() {
    if [[ -f "${XUI_BIN}" ]]; then
        info "x-ui already installed — skipping download."
    else
        info "Downloading x-ui-yg (${CPU}) ..."
        cd /usr/local/
        curl -L --retry 3 --insecure -# \
            -o "/usr/local/x-ui-linux-${CPU}.tar.gz" \
            "${XUI_RELEASE_URL}/x-ui-linux-${CPU}.tar.gz"

        info "Extracting ..."
        tar zxf "/usr/local/x-ui-linux-${CPU}.tar.gz" -C /usr/local/ >/dev/null 2>&1
        rm -f "/usr/local/x-ui-linux-${CPU}.tar.gz"

        cd "${XUI_DIR}"
        chmod +x x-ui "bin/xray-linux-${CPU}"
        cp -f x-ui.service /etc/systemd/system/ >/dev/null 2>&1
        cd /

        # install x-ui shortcut (same as official script)
        curl -L --retry 2 --insecure -o /usr/bin/x-ui -s "${XUI_INSTALL_SH}"
        chmod +x /usr/bin/x-ui

        [[ -f "${XUI_BIN}" ]] || error "x-ui binary not found after install."
        info "x-ui-yg installed successfully"
    fi

    # resolve xray binary path
    if [[ -f "${XUI_DIR}/bin/xray-linux-${CPU}" ]]; then
        XRAY_BIN="${XUI_DIR}/bin/xray-linux-${CPU}"
    elif [[ -f "${XUI_DIR}/bin/xray" ]]; then
        XRAY_BIN="${XUI_DIR}/bin/xray"
    else
        error "xray binary not found under ${XUI_DIR}/bin/"
    fi
    info "xray binary: ${XRAY_BIN}"
}

# ── configure panel port ─────────────────────────────────────────────────────
configure_xui_port() {
    info "Setting x-ui panel port to ${UI_PORT} ..."
    "${XUI_BIN}" setting -port "${UI_PORT}" >/dev/null 2>&1
}

# ── start x-ui service ────────────────────────────────────────────────────────
start_xui() {
    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
    systemctl restart x-ui
    info "x-ui service started (systemctl enable x-ui — survives reboots)"
}

# ── wait for API ──────────────────────────────────────────────────────────────
wait_for_api() {
    info "Waiting for x-ui API on port ${UI_PORT} ..."
    local i=0
    while [[ $i -lt 30 ]]; do
        if curl -s --max-time 3 "http://127.0.0.1:${UI_PORT}/" -o /dev/null 2>/dev/null; then
            info "x-ui API is up"
            return 0
        fi
        i=$((i + 1))
        sleep 2
    done
    error "x-ui did not start within 60s. Check: journalctl -u x-ui -n 50"
}

# ── login → session cookie ────────────────────────────────────────────────────
xui_login() {
    COOKIE_FILE=$(mktemp)
    local resp
    resp=$(curl -sf -c "${COOKIE_FILE}" \
        -X POST "http://127.0.0.1:${UI_PORT}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${UI_USER}&password=${UI_PASS}")
    echo "${resp}" | grep -q '"success":true' || \
        error "x-ui login failed. Response: ${resp}"
    info "Logged in to x-ui as '${UI_USER}'"
}

# ── generate Reality keys ─────────────────────────────────────────────────────
generate_reality_keys() {
    info "Generating Reality keypair ..."
    local output
    output=$("${XRAY_BIN}" x25519 2>/dev/null) || \
        error "xray x25519 failed — check binary at ${XRAY_BIN}"
    # xray-core format:    "Private key: xxx"  / "Public key: xxx"
    # x-ui-yg xray format: "PrivateKey: xxx"   / "Password (PublicKey): xxx"
    PRIVATE_KEY=$(echo "$output" | grep -i "private" | awk '{print $NF}')
    PUBLIC_KEY=$(echo  "$output" | grep -i "public"  | awk '{print $NF}')
    [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || error "Failed to parse Reality keypair from: $output"
    info "Reality public key: ${PUBLIC_KEY}"
}

generate_short_id() {
    SHORT_ID=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
}

generate_uuid() {
    UUID=$(cat /proc/sys/kernel/random/uuid)
    info "UUID: ${UUID}"
}

# ── add inbound via API ───────────────────────────────────────────────────────
add_inbound() {
    local payload resp

    # x-ui-yg API expects settings/streamSettings/sniffing as JSON-encoded strings
    # Use jq to properly escape nested JSON into strings
    local settings stream sniff
    settings=$(jq -nc \
        --arg uuid "${UUID}" \
        '{"clients":[{"id":$uuid,"flow":"xtls-rprx-vision","level":0,"email":"default@xui"}],"decryption":"none","fallbacks":[]}')
    stream=$(jq -nc \
        --arg dest "${REALITY_SERVER_NAME}:443" \
        --arg sni  "${REALITY_SERVER_NAME}" \
        --arg priv "${PRIVATE_KEY}" \
        --arg sid  "${SHORT_ID}" \
        '{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":$dest,"xver":0,"serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]},"tcpSettings":{"header":{"type":"none"}}}')
    sniff='{"enabled":true,"destOverride":["http","tls","quic"],"metadataOnly":false}'

    payload=$(jq -nc \
        --arg  remark "vless-reality-${XRAY_PORT}" \
        --argjson port   "${XRAY_PORT}" \
        --arg  settings  "${settings}" \
        --arg  stream    "${stream}" \
        --arg  sniff     "${sniff}" \
        '{"remark":$remark,"enable":true,"protocol":"vless","listen":"","port":$port,"settings":$settings,"streamSettings":$stream,"sniffing":$sniff}')

    resp=$(curl -sf -b "${COOKIE_FILE}" \
        -X POST "http://127.0.0.1:${UI_PORT}/xui/inbound/add" \
        -H "Content-Type: application/json" \
        -d "${payload}")

    if echo "${resp}" | grep -q '"success":true'; then
        info "VLESS+Reality inbound created on port ${XRAY_PORT}"
    else
        warn "API add-inbound response: ${resp}"
        warn "Inbound may already exist — verify via Web UI"
    fi
    rm -f "${COOKIE_FILE}"
}

# ── firewall ──────────────────────────────────────────────────────────────────
configure_ufw() {
    if ! command -v ufw &>/dev/null; then
        warn "ufw not found — skipping firewall configuration"
        return
    fi
    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        warn "ufw is inactive — skipping (enable manually: ufw enable)"
        return
    fi
    ufw allow "${UI_PORT}/tcp"   comment "x-ui web UI"
    ufw allow "${XRAY_PORT}/tcp" comment "VLESS+Reality proxy"
    ufw reload
    info "UFW: opened ports ${UI_PORT}/tcp and ${XRAY_PORT}/tcp"
}

# ── summary ───────────────────────────────────────────────────────────────────
print_summary() {
    local server_ip
    server_ip=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -sf --max-time 5 https://ifconfig.me 2>/dev/null || \
                hostname -I | awk '{print $1}')

    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Setup complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  Web UI:      http://${server_ip}:${UI_PORT}"
    echo -e "  UI Login:    ${UI_USER} / ${UI_PASS}  ← change immediately!"
    echo
    echo -e "  Protocol:    VLESS + Reality (TCP)"
    echo -e "  Server IP:   ${server_ip}"
    echo -e "  Port:        ${XRAY_PORT}"
    echo -e "  UUID:        ${UUID}"
    echo -e "  Public Key:  ${PUBLIC_KEY}"
    echo -e "  Short ID:    ${SHORT_ID}"
    echo -e "  Server SNI:  ${REALITY_SERVER_NAME}"
    echo -e "  Fingerprint: ${REALITY_FINGERPRINT}"
    echo -e "  Flow:        xtls-rprx-vision"
    echo
    local vless_url="vless://${UUID}@${server_ip}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=${REALITY_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#vless-reality-${server_ip}"
    echo -e "  Import URL (paste into v2rayN / v2rayNG / V2rayU):"
    echo
    echo -e "  ${vless_url}"
    echo
    echo -e "  Client config (paste as outbounds[0] in config.json):"
    echo
    cat <<CLIENT
{
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "${server_ip}",
      "port": ${XRAY_PORT},
      "users": [{
        "id": "${UUID}",
        "flow": "xtls-rprx-vision",
        "level": 0,
        "encryption": "none"
      }]
    }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "serverName": "${REALITY_SERVER_NAME}",
      "fingerprint": "${REALITY_FINGERPRINT}",
      "publicKey": "${PUBLIC_KEY}",
      "shortId": "${SHORT_ID}",
      "spiderX": ""
    }
  },
  "tag": "proxy"
}
CLIENT
    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  Autostart:   systemctl enable x-ui (already configured)"
    echo -e "  Logs:        journalctl -u x-ui -f"
    echo -e "  Restart:     systemctl restart x-ui"
    echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    require_root
    check_ubuntu
    detect_arch
    install_deps
    install_xui
    configure_xui_port
    start_xui
    wait_for_api
    xui_login
    generate_reality_keys
    generate_short_id
    generate_uuid
    add_inbound
    configure_ufw
    print_summary
}

main "$@"
