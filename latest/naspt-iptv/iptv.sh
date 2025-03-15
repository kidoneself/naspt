#!/bin/bash

# 颜色设置
COLOR_CYAN="\033[36m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"

# 默认值
HOST_IP=""

# 获取用户输入
get_input() {
    local var_name="$1"
    local prompt_message="$2"
    local default_value="$3"
    local value

    while true; do
        echo -e "${COLOR_CYAN}$prompt_message ===> ${COLOR_YELLOW}$default_value${COLOR_RESET}:"
        read -r value
        value="${value:-$default_value}"
        eval "$var_name='$value'"
        break
    done
}

# 获取用户输入的主机 IP 地址
get_input "HOST_IP" "请输入 NAS IP" "$HOST_IP"

# 导出环境变量
export HOST_IP

# 显示设置的配置信息
echo -e "\n${COLOR_GREEN}=== 配置信息 ===${COLOR_RESET}"
echo -e "${COLOR_CYAN}主机 IP 地址:${COLOR_RESET} $HOST_IP"

# 启动服务函数
init_allinone() {
    echo -e "\n${COLOR_GREEN}=== 初始化 allinone ===${COLOR_RESET}"
    docker run -d \
      --name naspt-allinone \
      --privileged \
      --restart always \
      --network host
      ccr.ccs.tencentyun.com/naspt/allinone \
      -tv=true \
      -aesKey=swj6pnb4h6xyvhpq69fgae2bbpjlb8y2 \
      -userid=5892131247 \
      -token=9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137
}

init_allinone_format() {
    echo -e "\n${COLOR_GREEN}=== 初始化 allinone_format ===${COLOR_RESET}"
    docker run -d \
      --name naspt-allinone-format \
      --restart always \
      --network host \
      ccr.ccs.tencentyun.com/naspt/allinone_format:latest
}

#init_awatchtower() {
#    echo -e "\n${COLOR_GREEN}=== 初始化 awatchtower ===${COLOR_RESET}"
#    docker run -d \
#      --name watchtower \
#      --restart always \
#      --network host \
#      -v /var/run/docker.sock:/var/run/docker.sock \
#      ccr.ccs.tencentyun.com/naspt/watchtower
#}

# 配置输入完成后直接开始安装所有服务
echo -e "\n${COLOR_YELLOW}正在开始安装所有服务...${COLOR_RESET}"

init_allinone
init_allinone_format
#init_awatchtower

# 输出每个服务的配置信息
echo -e "\n${COLOR_GREEN}=== 服务安装完成 ===${COLOR_RESET}"
echo -e "以下是每个服务的访问信息："
echo -e "1. ${COLOR_CYAN}IPTV源地址:${COLOR_RESET}"
echo -e "   地址: http://$HOST_IP:35455/tv.m3u"
echo -e "2. ${COLOR_CYAN}IPTV整理地址:${COLOR_RESET}"
echo -e "   地址: http://$HOST_IP:35456"

# 结束脚本
history -c
echo -e "\n${COLOR_GREEN}安装流程结束！${COLOR_RESET}"
exit 0