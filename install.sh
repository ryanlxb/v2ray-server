#!/bin/bash
#
yum install -y git docker docker-compose

cd /opt & git clone https://github.com/ryanlxb/V2ray.git

service docker restart


