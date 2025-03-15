#!/bin/bash

DEFAULT_LIVE_PATH=""
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
get_input "DOCKER_ROOT_PATH" "请输入录制视频存放地址根路径" "$DEFAULT_LIVE_PATH"
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"

# 导出环境变量
export DEFAULT_LIVE_PATH
export HOST_IP

# 确保目录结构


# 显示设置的配置信息
echo -e "最终的主机 IP 地址是: $HOST_IP"
echo -e "录制视频存放地址根路径: $DEFAULT_LIVE_PATH"

echo "开始创建视频目录结构..."

# 启动每个服务的函数
init_bililive() {
     echo "初始化 直播录制"
     docker run -it --restart=always \
        --name=bililive \
        -p 9595:8080 \
        -v "$DEFAULT_LIVE_PATH:/srv/bililive" \
        -d ccr.ccs.tencentyun.com/naspt/bililive-go:latest
}


      # 配置输入完成后直接开始安装所有服务
      echo "正在开始安装所有服务..."
      init_bililive
      # 输出每个服务的配置信息
      echo "服务安装已完成，以下是每个服务的访问信息："
      echo "1. 直播录制:"
      echo "   地址: http://$HOST_IP:9595"
      # 结束脚本
      history -c
      echo "安装流程结束！"
      exit 0

