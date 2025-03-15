#!/bin/bash

DOCKER_ROOT_PATH=""
HOST_IP=""
SERVER_ID=${1:-"ce8456bf-508c-4ebf-aa57-91db01114b87"}
HOST_NAME=${2:-"unraid"}

# 获取用户输入
get_input() {
  local var_name="$1"
  local prompt_message="$2"
  local default_value="$3"
  local value

  while true; do
    read -r -p "$prompt_message ---: " value
    value="${value:-$default_value}"
    eval "$var_name='$value'"
    break
  done
}

# 初始化 Owjdxb
init_owjdxb() {
  get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DOCKER_ROOT_PATH"
  get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"
  echo -e "最终的主机 IP 地址是: $HOST_IP"
  echo -e "录制视频存放地址根路径: $DOCKER_ROOT_PATH"
  export DOCKER_ROOT_PATH HOST_IP
  echo "=== 初始化 Owjdxb (节点小宝) ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-wx"
  docker run -d --name naspt-wx --restart unless-stopped \
    -v "$DOCKER_ROOT_PATH/naspt-wx:/data/store" \
    --network host \
    --privileged \
    "ccr.ccs.tencentyun.com/naspt/owjdxb:latest"
}

# 初始化 FRP
init_frp() {
  get_input "SERVER_ID" "请输入FRP ID" "$SERVER_ID"
  get_input "HOST_NAME" "请输入域名前缀" "$HOST_NAME"
  echo -e "最终的主机 IP 地址是: $SERVER_ID"
  echo -e "录制视频存放地址根路径: $HOST_NAME"
  export SERVER_ID HOST_NAME
  echo "=== 初始化 frp (节点小宝) ==="

  docker run -d \
    --network=host \
    --restart=unless-stopped \
    --name naspt-frp \
    ccr.ccs.tencentyun.com/naspt/frp-panel client \
    -s "$SERVER_ID" \
    -i "naspt.c.$HOST_NAME" \
    -a 9b83aed0cf81aef6d1c5fdb6274b4cb8 \
    -r 91.132.146.106 \
    -c 9001 \
    -p 9000 \
    -e http
}

# 显示选择菜单
choose_service() {
  echo "请选择要安装的服务:"
  echo "1) Owjdxb (节点小宝)"
  echo "2) FRP (反向代理)"
  read -r -p "请输入数字 (1 或 2): " choice

  case "$choice" in
  1)
    echo "选择了安装 Owjdxb (节点小宝)。"
    init_owjdxb
    service="Owjdxb (节点小宝)"
    ;;
  2)
    echo "选择了安装 FRP (反向代理)。"
    init_frp
    service="FRP (反向代理)"
    ;;
  *)
    echo "无效选择，默认选择安装  FRP (反向代理)。"
    init_frp
    service="FRP (反向代理)"
    ;;
  esac
}

# 配置输入完成后直接开始安装选定服务
echo "正在开始安装服务..."
choose_service

# 输出每个服务的配置信息
echo "服务安装已完成，以下是每个服务的访问信息："
if [[ "$service" == "Owjdxb (节点小宝)" ]]; then
  echo "1. Owjdxb (节点小宝):"
  echo "   地址: http://$HOST_IP:9118"
elif [[ "$service" == "FRP (反向代理)" ]]; then
  echo "1. FRP (反向代理):"
  echo "   地址: http://$HOST_NAME.8768611.xyz:8888"
  echo "   地址: http://$HOST_NAME.8768611.xyz:8888"

fi

# 结束脚本
history -c
echo "安装流程结束！"
exit 0
