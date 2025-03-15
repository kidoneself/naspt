#!/bin/bash

CURRENT_DIR="/root/naspt"
# 检查 CURRENT_DIR 是否存在，如果不存在则创建
if [ ! -d "$CURRENT_DIR" ]; then
    mkdir -p "$CURRENT_DIR"
    echo "目录 $CURRENT_DIR 不存在，已创建。"
else
    echo "目录 $CURRENT_DIR 已存在。"
fi

DEFAULT_DOCKER_PATH=""

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
get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DEFAULT_DOCKER_PATH"

# 获取 eth0 网卡的 IPv4 地址
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | grep -v 'docker' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
fi

while [ -z "$HOST_IP" ]; do
    read -p "请输入主机 IP 地址 [回车使用默认：$HOST_IP]：" input_ip
    HOST_IP="${input_ip:-$HOST_IP}"
    if [ -z "$HOST_IP" ]; then
        echo -e "主机 IP 地址不能为空，请重新输入。"
    fi
done


# 导出环境变量
export DOCKER_ROOT_PATH
export HOST_IP

# 确保目录结构


# 显示设置的配置信息
echo -e "最终的主机 IP 地址是: $HOST_IP"
echo -e "Docker 根路径: $DOCKER_ROOT_PATH"

echo "开始创建视频目录结构..."
mkdir -p "$MUSIC_ROOT_PATH/downloads" "$MUSIC_ROOT_PATH/links"


# 启动每个服务的函数
init_easynode() {
    echo "初始化 easynode"
    mkdir -p "$DOCKER_ROOT_PATH/easynode"
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/tool/naspt-easynode.tgz -o "$CURRENT_DIR/naspt-easynode.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/naspt-easynode.tgz" -C "$DOCKER_ROOT_PATH/easynode/"
    docker run -d --name easynode --restart unless-stopped \
        -p 58082:8082 \
        -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/easynode/db:/easynode/app/db \
        ccr.ccs.tencentyun.com/naspt/easynode:latest
}

init_photopea() {
    echo "初始化 photopea"
    docker run -d --name photopea --restart unless-stopped --privileged \
        -p 58081:8887 \
        ccr.ccs.tencentyun.com/naspt/photopea:1.0
}
init_myip() {
    echo "初始化 myip "
    docker run -d --name myip --restart unless-stopped \
        --network bridge --privileged \
        -p 58080:18966 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myip:1.0"
}
      # 配置输入完成后直接开始安装所有服务
      echo "正在开始安装所有服务..."
      init_easynode
      init_photopea
      # 删除 naspt 目录
      rm -rf "$CURRENT_DIR"

      # 输出每个服务的配置信息
      echo "服务安装已完成，以下是每个服务的访问信息："
      echo "1. easynode:"
      echo "   地址: http://$HOST_IP:58082"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo
      echo "2. photopea:"
      echo "   地址: http://$HOST_IP:58081"
      echo
      # 结束脚本
      history -c
      echo "安装流程结束！"
      exit 0

