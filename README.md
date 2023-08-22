# V2ray for Doprax
Create By ifeng<br>
Web Site: https://www.hicairo.com <br>
Telegram: https://t.me/HiaiFeng <br>

# 简介：
本项目用于在 Doprax.com 免费服务上部署 V2ray ，采用的方案为 Nginx + WebSocket + VMess/VLess + TLS。速度与 Replit 相比较慢，但是官方宣传不限流量，服务启动后永不停机。

# 服务端快速启动
1、购买云服务器（海外region）
  - 我用的是aliyun 日本区域，AWS（AWS有免费24个月试用）、Azure（访问openAI可以在azure上开通服务器）都可以；
  - OS选择：Centos、ubuntu 都可以，我用Centos习惯了；
  - 不需要购买数据盘，系统盘一般20G足够用了；
  - 使用aliyun服务器，可以使用"实例启动模版"功能非常好用（IP被封重新拉起instance非常快），另外借助"发送命令/文件(云助手)"将编排的code作为初始化工具也不错；

2、修改UUID
  - UUID 是v2ray访问过程中身份认证KEY，初始化之前最好修改下，不要使用默认值（被试出来浪费钱）；

3、启动方法（以aliyun 云助手为例，不需要登录服务器）
  服务器执行
  - 第一步：
  - 第二步：


# 客户端配置方式

<p>2、客户端配置</p>
<p>节点客户端配置需要手动进行，下面以 V2rayN 为例。
<p>下图为 VMess 配置示意图，请修改标示内容，其他设置与图片中显示一致。</p>
<img src="https://www.hicairo.com/zb_users/upload/2022/12/202212291672276258394161.webp">
<p>下图为 VLess 配置示意图，请修改标示内容，其他设置与图片中显示一致。</p>
<img src="https://www.hicairo.com/zb_users/upload/2022/12/202212291672276274474231.webp">

# 反馈与交流：
<p>在使用过程中，如果遇到问题，请使用Telegram与我联系。（ https://t.me/HiaiFeng ）</p>
<p>大家好，Doprax 非常关注用户使用体验。Hemen 先生及他的团队，为 Doprax 社区创建了 Discord 服务，如果您在使用过程中，遇到 Doprax 平台的相关问题或对平台有一些建议，请使用如下链接与官方联系。

Hello everyone! Doprax pays great attention to user experience. Mr. Hemen and his team have created a Discord service for the Doprax community. If you encounter any problems or have any suggestions related to the Doprax platform during use, please contact the official using the link below.

https://discord.gg/pFnGwTuXjk</p>

