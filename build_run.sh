#!/bin/bash

docker build . -t v2ray:latest

docker run -it \
--name v2ray \
-p 12345:80 \
--restart=always \
-d v2ray:latest
