# v2ray-server

[中文文档](./README.zh.md) | English

A one-click setup toolkit for self-hosted VLESS + Reality proxy server on Ubuntu, using Docker and [x-ui-yg](https://github.com/yonggekkk/x-ui-yg) as the management panel.

**Why Reality?** The Reality protocol mimics a real TLS 1.3 handshake to a trusted site (e.g. `www.yahoo.com`), making the proxy traffic indistinguishable from normal HTTPS — significantly reducing the risk of port blocking.

---

## Disclaimer

This project is intended **for personal learning, research, and accessing technical resources** (documentation, open-source repositories, academic papers, etc.) only. The open internet is a window to the world's most advanced knowledge — use it to learn, build, and grow.

- For use on your own servers and devices only
- Must comply with the laws and regulations of your country and region
- Must not be used for any illegal activities, commercial resale, or providing proxy services to third parties
- The author assumes no liability for any misuse

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start — Server](#quick-start--server)
- [Client Setup](#client-setup)
  - [Linux](#linux-x64)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Android](#android)
  - [iOS](#ios)
- [Advanced](#advanced)
  - [PAC Rules](#pac-rules)
  - [If the server gets blocked](#if-the-server-gets-blocked)
  - [Changing the TLS Fingerprint](#changing-the-tls-fingerprint)
- [Credits](#credits)

---

## Prerequisites

- An overseas VPS (AWS, DigitalOcean, Vultr, etc.) running **Ubuntu 22 / 24 / 26**
- Root or sudo access
- Ports **24680** (proxy) and **13579** (Web UI) open in your cloud provider's security group / firewall

> AWS Free Tier offers 12 months of t2/t3.micro in overseas regions — sufficient for personal use.

---

## Quick Start — Server

SSH into your server and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ryanlxb/v2ray-server/main/server_init.sh)
```

The script will:

1. Validate Ubuntu version (22–26)
2. Install Docker from the official apt repository
3. Enable Docker on boot (`systemctl enable docker`)
4. Pull and start the **x-ui-yg** container with `--restart=always`
5. Generate a Reality keypair (private key, public key, short ID) and a UUID
6. Pre-seed a **VLESS + Reality** inbound on port **24680** via the x-ui API
7. Open UFW ports 13579 and 24680 (if ufw is active)
8. Print a ready-to-use client config JSON

After the script finishes, access the Web UI at:

```
http://YOUR_SERVER_IP:13579
Default credentials: admin / admin  ← change immediately after first login
```

**Autostart guarantee:** `systemctl enable docker` + `--restart=always` ensures the service survives server reboots without any manual intervention.

---

## Client Setup

The script prints a complete outbound config block at the end. Copy it into your client's `config.json` as the first entry in `outbounds`.

### Client Downloads

| Platform | Client | Reality Support |
|---|---|---|
| Linux | [Xray-core](https://github.com/XTLS/Xray-core) | Yes |
| macOS | [V2rayU](https://github.com/yanue/V2rayU/releases) | Yes |
| Windows | [v2rayN](https://github.com/2dust/v2rayN/releases) | Yes |
| Android | [v2rayNG](https://github.com/2dust/v2rayNG/releases) | Yes |
| iOS | FoXray (App Store — requires overseas Apple ID) | Yes |

---

### Linux x64

```bash
# 1. Download Xray-core
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip

# 2. Paste the client config printed by server_init.sh into config.json

# 3. Run
./xray -c config.json

# 4. Test (default HTTP proxy port 1087)
curl https://www.google.com -x 127.0.0.1:1087
```

---

### macOS

Using **V2rayU**:

1. Run `server_init.sh` on the server and copy the printed config JSON
2. In V2rayU → Preferences → Import config, paste the JSON
3. Or replace `config.json` directly and restart

<img width="575" alt="V2rayU config screenshot" src="https://github.com/user-attachments/assets/1bae534e-0de8-45c6-b0fb-c04d8319d776" />

---

### Windows

Using **v2rayN** — same flow as macOS: import the config JSON from the server output.

---

### Android

Using **v2rayNG** — import via QR code or manual JSON entry.

---

### iOS

**FoXray** (App Store). Requires an overseas Apple ID to download. Import the VLESS+Reality link from the server output.

---

## Advanced

### PAC Rules

PAC (Proxy Auto-Configuration) lets you selectively route specific domains through the proxy.

In V2rayU → Preferences → PAC, add entries like:

```
||example.com        # route all of example.com through proxy
||sub.example.com    # route a specific subdomain
```

Restart V2ray after saving. Recommended PAC list:

- Default GFW list: `https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt`
- Alternative: `https://raw.githubusercontent.com/Loukky/gfwlist-by-loukky/master/gfwlist.txt`

---

### If the server gets blocked

With Reality, outright port blocking is rare. If it does happen:

- Change the `serverName` in the Reality config to another globally trusted TLS 1.3 domain
- Rotate the Reality keypair and short ID via the x-ui Web UI
- As a last resort, use [Tailscale](https://tailscale.com) or another overlay network to bypass the block entirely

---

### Changing the TLS Fingerprint

If you experience connection issues, try changing the `fingerprint` field in the client config (`chrome`, `firefox`, `safari`, `ios`, `android`, `edge`, `360`, `qq`, `random`).

In V2rayU: Preferences → Fingerprint

<img width="823" height="538" alt="V2rayU fingerprint settings" src="https://github.com/user-attachments/assets/a10fea18-1001-4239-b4dd-8eb08a8480a4" />

---

## Credits

This project builds on the work of the following open-source authors:

| Project | Author | Description |
|---|---|---|
| [x-ui-yg](https://github.com/yonggekkk/x-ui-yg) | [@yonggekkk](https://github.com/yonggekkk) | Xray panel with Reality support and Web UI |
| [warp-yg](https://github.com/yonggekkk/warp-yg) | [@yonggekkk](https://github.com/yonggekkk) | WARP + CFwarp one-click deployment |
| [Xray-core](https://github.com/XTLS/Xray-core) | [@XTLS](https://github.com/XTLS) | Core proxy engine with VLESS + Reality |
| [v2fly/v2ray-core](https://github.com/v2fly/v2ray-core) | [@v2fly](https://github.com/v2fly) | Original V2Ray core |
| [gfwlist](https://github.com/gfwlist/gfwlist) | [@gfwlist](https://github.com/gfwlist) | Community-maintained GFW domain list |
| Dockerfile base | [@ifeng / HiaiFeng](https://t.me/HiaiFeng) | Original nginx+v2ray Docker image |
