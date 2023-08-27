#!/bin/bash
#
yum install -y git docker docker-compose

cd /opt
git clone https://github.com/ryanlxb/v2ray-server.git

service docker restart

systemctl disable firewalld

cd v2ray-server
docker-compose up -d
