#!/usr/bin/env bash
# =============================================================================
# v2ray-server one-click setup for Ubuntu 22/24/26
#
# What this script does:
#   1. Validates OS (Ubuntu 22-26)
#   2. Installs Docker (official repo) + enables on boot
#   3. Pulls and starts x-ui-yg in Docker (Web UI on port 13579)
#   4. Pre-seeds a VLESS+Reality inbound on port 24680 via x-ui API
#   5. Opens UFW ports (13579 UI, 24680 proxy)
#   6. Prints the connection summary
#
# Usage: bash server_init.sh
# =============================================================================

set -euo pipefail

# ── constants ────────────────────────────────────────────────────────────────
XRAY_PORT=24680
UI_PORT=13579
UI_USER="admin"
UI_PASS="admin"            # change after first login
DOCKER_IMAGE="ygkkk/x-ui:latest"
CONTAINER_NAME="x-ui"
DATA_DIR="/opt/x-ui"

# Reality target site (publicly trusted TLS 1.3 server to mimic)
REALITY_SERVER_NAME="www.yahoo.com"
REALITY_FINGERPRINT="firefox"

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

# ── docker ───────────────────────────────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker already installed: $(docker --version)"
        return
    fi
    info "Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    info "Docker installed: $(docker --version)"
}

enable_docker_autostart() {
    systemctl enable docker
    systemctl start docker
    info "Docker service enabled and started"
}

# ── x-ui container ───────────────────────────────────────────────────────────
start_xui() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "Container '${CONTAINER_NAME}' already exists — removing to redeploy."
        docker rm -f "${CONTAINER_NAME}"
    fi

    mkdir -p "${DATA_DIR}"

    info "Pulling image ${DOCKER_IMAGE} ..."
    docker pull "${DOCKER_IMAGE}"

    info "Starting x-ui container..."
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart=always \
        --network=host \
        -v "${DATA_DIR}:/etc/x-ui" \
        -v /etc/localtime:/etc/localtime:ro \
        -e "XRAY_VMESS_AEAD_FORCED=false" \
        "${DOCKER_IMAGE}"

    info "Container '${CONTAINER_NAME}' started (restart=always → survives reboots)"
}

# ── wait for API ──────────────────────────────────────────────────────────────
wait_for_api() {
    local url="http://127.0.0.1:${UI_PORT}/login"
    info "Waiting for x-ui API on port ${UI_PORT} ..."
    local attempts=0
    until curl -sf --max-time 3 "${url}" -o /dev/null 2>/dev/null; do
        ((attempts++))
        [[ $attempts -ge 30 ]] && error "x-ui did not start within 60s. Check: docker logs ${CONTAINER_NAME}"
        sleep 2
    done
    info "x-ui API is up"
}

# ── login → get session cookie ────────────────────────────────────────────────
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

# ── generate keys ─────────────────────────────────────────────────────────────
generate_reality_keys() {
    info "Generating Reality keypair inside container..."
    # xray x25519 outputs: Private key: ... \n Public key: ...
    local output
    output=$(docker exec "${CONTAINER_NAME}" \
        /usr/local/x-ui/bin/xray x25519 2>/dev/null || \
        docker exec "${CONTAINER_NAME}" \
        /usr/local/xray/xray x25519 2>/dev/null || \
        docker exec "${CONTAINER_NAME}" \
        xray x25519 2>/dev/null || true)

    if [[ -z "$output" ]]; then
        warn "Could not run xray x25519 inside container; generating keys via openssl fallback"
        # Curve25519 private key via openssl
        PRIVATE_KEY=$(openssl genpkey -algorithm X25519 2>/dev/null \
            | openssl pkey -outform DER 2>/dev/null \
            | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=')
        PUBLIC_KEY="(run: docker exec ${CONTAINER_NAME} xray x25519 to get real keypair)"
    else
        PRIVATE_KEY=$(echo "$output" | grep "Private key:" | awk '{print $3}')
        PUBLIC_KEY=$(echo  "$output" | grep "Public key:"  | awk '{print $3}')
    fi
    info "Reality private key: ${PRIVATE_KEY}"
    info "Reality public  key: ${PUBLIC_KEY}"
}

# ── shortId (8 hex chars) ─────────────────────────────────────────────────────
generate_short_id() {
    SHORT_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 8 | head -n 1)
}

# ── UUID ──────────────────────────────────────────────────────────────────────
generate_uuid() {
    UUID=$(cat /proc/sys/kernel/random/uuid)
    info "UUID: ${UUID}"
}

# ── add inbound via API ───────────────────────────────────────────────────────
add_inbound() {
    local settings stream_settings sniff

    settings=$(cat <<JSON
{
  "clients": [{
    "id": "${UUID}",
    "flow": "xtls-rprx-vision",
    "level": 0,
    "email": "default@xui"
  }],
  "decryption": "none",
  "fallbacks": []
}
JSON
)

    stream_settings=$(cat <<JSON
{
  "network": "tcp",
  "security": "reality",
  "realitySettings": {
    "show": false,
    "dest": "${REALITY_SERVER_NAME}:443",
    "xver": 0,
    "serverNames": ["${REALITY_SERVER_NAME}"],
    "privateKey": "${PRIVATE_KEY}",
    "shortIds": ["${SHORT_ID}"]
  },
  "tcpSettings": {
    "header": { "type": "none" }
  }
}
JSON
)

    sniff=$(cat <<JSON
{
  "enabled": true,
  "destOverride": ["http", "tls", "quic"],
  "metadataOnly": false
}
JSON
)

    local payload
    payload=$(cat <<JSON
{
  "remark": "vless-reality-${XRAY_PORT}",
  "enable": true,
  "protocol": "vless",
  "listen": "",
  "port": ${XRAY_PORT},
  "settings": $(echo "$settings" | tr -d '\n'),
  "streamSettings": $(echo "$stream_settings" | tr -d '\n'),
  "sniffing": $(echo "$sniff" | tr -d '\n')
}
JSON
)

    local resp
    resp=$(curl -sf -b "${COOKIE_FILE}" \
        -X POST "http://127.0.0.1:${UI_PORT}/xui/inbound/add" \
        -H "Content-Type: application/json" \
        -d "${payload}")

    if echo "${resp}" | grep -q '"success":true'; then
        info "VLESS+Reality inbound created on port ${XRAY_PORT}"
    else
        warn "API add-inbound response: ${resp}"
        warn "Inbound may already exist, or check x-ui logs: docker logs ${CONTAINER_NAME}"
    fi

    rm -f "${COOKIE_FILE}"
}

# ── firewall ──────────────────────────────────────────────────────────────────
configure_ufw() {
    if ! command -v ufw &>/dev/null; then
        warn "ufw not found — skipping firewall configuration"
        return
    fi
    if ! ufw status | grep -q "Status: active"; then
        warn "ufw is inactive — skipping (enable manually with: ufw enable)"
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
    server_ip=$(curl -sf --max-time 5 https://api.ipify.org || \
                curl -sf --max-time 5 https://ifconfig.me || \
                hostname -I | awk '{print $1}')

    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Setup complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  Web UI:      http://${server_ip}:${UI_PORT}"
    echo -e "  UI Login:    ${UI_USER} / ${UI_PASS}  ← change this immediately!"
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
    echo -e "  Client config (paste into your v2ray/xray config.json):"
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
    echo -e "  Autostart:   docker restart=always + systemctl enable docker"
    echo -e "  Logs:        docker logs ${CONTAINER_NAME} -f"
    echo -e "  Restart:     docker restart ${CONTAINER_NAME}"
    echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    require_root
    check_ubuntu
    install_docker
    enable_docker_autostart
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
