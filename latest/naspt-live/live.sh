#!/bin/bash

# 默认值
DEFAULT_LIVE_PATH=""
HOST_IP=""

# 颜色设置
COLOR_CYAN="\033[36m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"

# 获取用户输入
get_input() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    local value
    while true; do
        echo -e "${COLOR_CYAN}$prompt_message ${COLOR_YELLOW}$default_value${COLOR_RESET}:"  # 使用颜色
        read -r value
        value="${value:-$default_value}"
        eval "$var_name='$value'"
        break
    done
}

# 定义公共方法来检查和启动容器
check_container() {
  local container_name=$1
  # 检查容器是否已经启动
  if [ "$(docker ps -q -f name=$container_name)" ]; then
    return 1  # 返回1表示已经在运行，不需要启动
  else
    return 0  # 返回0表示启动了容器，可以继续执行后续代码
  fi
}


# 获取 Docker 根路径和视频根路径
get_input "DOCKER_ROOT_PATH" "请输入录制视频存放地址根路径" "$DEFAULT_LIVE_PATH"
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"

# 导出环境变量
export DEFAULT_LIVE_PATH
export HOST_IP

# 显示设置的配置信息
echo -e "\n${COLOR_GREEN}=== 配置信息 ===${COLOR_RESET}"
echo -e "${COLOR_CYAN}主机 IP 地址:${COLOR_RESET} $HOST_IP"
echo -e "${COLOR_CYAN}录制视频存放地址根路径:${COLOR_RESET} $DEFAULT_LIVE_PATH"

# 创建目录结构
echo -e "\n${COLOR_YELLOW}正在创建视频目录结构...${COLOR_RESET}"

# 启动服务的函数
init_bililive() {

     echo -e "\n${COLOR_GREEN}=== 初始化 直播录制 ===${COLOR_RESET}"
    check_container "naspt-lyricapi"
    if [ $? -eq 0 ]; then
        echo "【提示】未检测到原有容器，启动新的容器..."
        docker run -d -it --restart=always \
        --name=naspt-bililive \
        --network bridge \
        -p 9595:8080 \
        -v "$DEFAULT_LIVE_PATH:/srv/bililive" \
        "ccr.ccs.tencentyun.com/naspt/bililive-go:latest"
    else
        echo "【提示】容器已启动，无需重启"
    fi

}

# 配置输入完成后直接开始安装所有服务
echo -e "\n${COLOR_YELLOW}正在开始安装所有服务...${COLOR_RESET}"
init_bililive

# 输出每个服务的访问信息
echo -e "\n${COLOR_GREEN}=== 服务安装完成 ===${COLOR_RESET}"
echo -e "以下是每个服务的访问信息："
echo -e "1. 直播录制服务:"
echo -e "   ${COLOR_CYAN}地址:${COLOR_RESET} http://$HOST_IP:9595"

# 结束脚本
history -c
echo -e "\n${COLOR_GREEN}安装流程结束！${COLOR_RESET}"
exit 0