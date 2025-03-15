#!/bin/bash

HOST_IP=""
# 获取用户输入
get_input() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    local value
    while true; do
        read -p "$prompt_message $default_value: " value
        value="${value:-$default_value}"
        eval "$var_name='$value'"
        break
    done
}

# 获取 Docker 根路径和视频根路径
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"

# 导出环境变量
export HOST_IP

# 显示设置的配置信息
echo -e "最终的主机 IP 地址是: $HOST_IP"


# 启动每个服务的函数
init_allinone() {
     echo "初始化 allinone"
      docker run -d \
        --name allinone \
        --privileged \
        --restart unless-stopped \
        --network host \
        ccr.ccs.tencentyun.com/naspt/allinone \
        -tv=true \
        -aesKey=swj6pnb4h6xyvhpq69fgae2bbpjlb8y2 \
        -userid=5892131247 \
        -token=9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137
}
init_allinone_format() {
     echo "初始化 allinone_format"
      docker run -d \
        --name allinone_format \
        --restart always \
        --network host \
        ccr.ccs.tencentyun.com/naspt/allinone_format:latest
}

init_awatchtower() {
     echo "初始化 awatchtower"
        docker run -d \
          --name watchtower \
          --restart always \
          --network host \
          -v /var/run/docker.sock:/var/run/docker.sock \
          ccr.ccs.tencentyun.com/naspt/watchtower
}




      # 配置输入完成后直接开始安装所有服务
      echo "正在开始安装所有服务..."
      init_allinone
      init_allinone_format
      init_awatchtower
      # 输出每个服务的配置信息
      echo "服务安装已完成，以下是每个服务的访问信息："
      echo "1. IPTV源地址:"
      echo "   地址: http://$HOST_IP:35455/tv.m3u"
      echo "2. IPTV整理地址:"
      echo "   地址: http://$HOST_IP:35456"
      # 结束脚本
      history -c
      echo "安装流程结束！"
      exit 0

