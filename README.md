# v2ray-server

中文文档 | [English](./README.en.md)

基于 Docker 和 [x-ui-yg](https://github.com/yonggekkk/x-ui-yg) 管理面板，一键在 Ubuntu 上部署 VLESS + Reality 自建代理服务器。

**为什么选择 Reality？** Reality 协议通过模拟对可信站点（如 `www.yahoo.com`）的真实 TLS 1.3 握手，使代理流量与正常 HTTPS 流量无异，大幅降低端口被封的风险。

---

## 免责声明

本项目仅供**个人学习、研究及访问技术资源**（技术文档、开源仓库、学术论文等）使用。互联网是获取全球先进知识的窗口，善加利用，学习先进技术，提升自我。

- 仅限在自己的服务器和设备上使用
- 必须遵守所在国家和地区的法律法规
- 不得用于任何违法活动、商业转售或向第三方提供代理服务
- 因不当使用造成的任何后果由使用者自行承担，作者不负任何责任

---

## 目录

- [前提条件](#前提条件)
- [服务端一键部署](#服务端一键部署)
- [客户端配置](#客户端配置)
  - [Linux](#linux-x64)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Android](#android)
  - [iOS](#ios)
- [进阶使用](#进阶使用)
  - [PAC 分流规则](#pac-分流规则)
  - [服务器被封怎么办](#服务器被封怎么办)
  - [修改 TLS 指纹](#修改-tls-指纹)
- [致谢](#致谢)

---

## 前提条件

- 一台**境外 VPS**（AWS、DigitalOcean、Vultr 等），系统为 **Ubuntu 22 / 24 / 26**
- root 或 sudo 权限
- 在云服务商控制台的安全组 / 防火墙中开放端口 **24680**（代理）和 **13579**（Web UI）

> AWS 海外区域提供 12 个月的 t2/t3.micro 免费套餐，个人使用完全够用。

---

## 服务端一键部署

SSH 登录服务器后执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ryanlxb/v2ray-server/main/server_init.sh)
```

脚本将自动完成以下步骤：

1. 检查 Ubuntu 版本（22–26）
2. 从官方 apt 源安装 Docker
3. 配置 Docker 开机自启（`systemctl enable docker`）
4. 拉取并启动 **x-ui-yg** 容器（`--restart=always`）
5. 生成 Reality 密钥对（私钥、公钥、Short ID）和 UUID
6. 通过 x-ui API 预置一个 **VLESS + Reality** 入站，监听端口 **24680**
7. 开放 UFW 端口 13579 和 24680（如果 ufw 已启用）
8. 打印可直接使用的客户端配置 JSON

脚本执行完成后，访问 Web 管理面板：

```
http://YOUR_SERVER_IP:13579
默认账号密码：admin / admin  ← 首次登录后请立即修改！
```

**自启动保障：** `systemctl enable docker` + `--restart=always` 双重保障，服务器重启后无需任何手动操作，服务自动恢复。

---

## 客户端配置

脚本执行结束时会打印完整的出站配置块，将其复制到客户端 `config.json` 的 `outbounds` 第一项即可。

### 客户端下载

| 平台 | 客户端 | 支持 Reality |
|---|---|---|
| Linux | [Xray-core](https://github.com/XTLS/Xray-core) | 是 |
| macOS | [V2rayU](https://github.com/yanue/V2rayU/releases) | 是 |
| Windows | [v2rayN](https://github.com/2dust/v2rayN/releases) | 是 |
| Android | [v2rayNG](https://github.com/2dust/v2rayNG/releases) | 是 |
| iOS | FoXray（App Store，需境外 Apple ID） | 是 |

---

### Linux x64

```bash
# 1. 下载 Xray-core
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip

# 2. 将 server_init.sh 打印的客户端配置粘贴到 config.json

# 3. 启动
./xray -c config.json

# 4. 测试（默认 HTTP 代理端口 1087）
curl https://www.google.com -x 127.0.0.1:1087
```

---

### macOS

以 **V2rayU** 为例：

1. 在服务器执行 `server_init.sh`，复制末尾打印的配置 JSON
2. V2rayU → 偏好设置 → 导入配置，粘贴 JSON
3. 或直接替换 `config.json` 后重启

<img width="575" alt="V2rayU 配置截图" src="https://github.com/user-attachments/assets/1bae534e-0de8-45c6-b0fb-c04d8319d776" />

---

### Windows

使用 **v2rayN**，操作与 macOS 相同：导入服务器输出的配置 JSON。

---

### Android

使用 **v2rayNG**，通过二维码或手动填写 JSON 导入配置。

---

### iOS

**FoXray**（App Store），需境外 Apple ID 下载。从服务器输出中复制 VLESS+Reality 链接导入。

---

## 进阶使用

### PAC 分流规则

PAC（代理自动配置）可让特定域名走代理，其余流量直连。

在 V2rayU → 偏好设置 → PAC 中添加规则：

```
||example.com        # example.com 全域名走代理
||sub.example.com    # 仅指定子域名走代理
```

保存后重启 V2ray 生效。推荐 PAC 列表：

- 默认 GFW 列表：`https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt`
- 备用列表：`https://raw.githubusercontent.com/Loukky/gfwlist-by-loukky/master/gfwlist.txt`

---

### 服务器被封怎么办

使用 Reality 后被直接封端口的情况很少见。若真的发生：

- 在 x-ui Web UI 中更换 Reality 配置的 `serverName`，换一个全球可信的 TLS 1.3 域名
- 重新生成 Reality 密钥对和 Short ID
- 极端情况下，可使用 [Tailscale](https://tailscale.com) 等内网穿透工具绕过封锁

---

### 修改 TLS 指纹

若遇到连接问题，可尝试修改客户端配置中的 `fingerprint` 字段（可选值：`chrome`、`firefox`、`safari`、`ios`、`android`、`edge`、`360`、`qq`、`random`）。

V2rayU 中：偏好设置 → Fingerprint

<img width="823" height="538" alt="V2rayU 指纹设置" src="https://github.com/user-attachments/assets/a10fea18-1001-4239-b4dd-8eb08a8480a4" />

---

## 致谢

本项目基于以下开源作者的工作构建：

| 项目 | 作者 | 说明 |
|---|---|---|
| [x-ui-yg](https://github.com/yonggekkk/x-ui-yg) | [@yonggekkk](https://github.com/yonggekkk) | 支持 Reality 的 Xray 管理面板 |
| [warp-yg](https://github.com/yonggekkk/warp-yg) | [@yonggekkk](https://github.com/yonggekkk) | WARP + CFwarp 一键部署脚本 |
| [Xray-core](https://github.com/XTLS/Xray-core) | [@XTLS](https://github.com/XTLS) | 支持 VLESS + Reality 的核心代理引擎 |
| [v2fly/v2ray-core](https://github.com/v2fly/v2ray-core) | [@v2fly](https://github.com/v2fly) | V2Ray 原始核心 |
| [gfwlist](https://github.com/gfwlist/gfwlist) | [@gfwlist](https://github.com/gfwlist) | 社区维护的 GFW 域名列表 |
| Dockerfile 基础镜像 | [@ifeng / HiaiFeng](https://t.me/HiaiFeng) | 原始 nginx+v2ray Docker 镜像 |
