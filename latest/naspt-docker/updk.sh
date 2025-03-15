#!/bin/bash

# 设置颜色常量
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

echo -e "${COLOR_BLUE}=========================================================="
echo -e "${COLOR_GREEN}欢迎使用 Docker 服务安装脚本！${COLOR_RESET}"
echo -e "请选择您要执行的操作："
echo -e "${COLOR_BLUE}=========================================================="
echo -e "${COLOR_GREEN}1. 安装 Docker 自动更新程序 (Watchtower)"
echo -e "2. 执行单次容器更新"
echo -e "3. 退出"
echo -e "${COLOR_BLUE}=========================================================="

get_input() {
  local var_name="$1"
  local prompt_message="$2"
  local default_value="$3"
  local value

  while true; do
    echo -e "\033[36m$prompt_message ===> \033[0m"  # 用 echo 显示带颜色的提示
    read -r value  # 读取输入
    value="${value:-$default_value}"
    eval "$var_name='$value'"
    break
  done
}

get_input "SERVICE_CHOICE" "请输入操作编号（如 '1'）" "1"

# 配置输入完成后，开始执行服务
install_service() {
  local service_id="$1"
  case "$service_id" in
    1)
      echo -e "${COLOR_YELLOW}正在安装 Docker 自动更新程序（Watchtower）...${COLOR_RESET}"
      init_watchtower
      echo -e "${COLOR_GREEN}docker 自动更新程序安装完成！${COLOR_RESET}"
      ;;
    2)
      echo -e "${COLOR_YELLOW}正在执行单次容器更新...${COLOR_RESET}"
      update_watchtower
      echo -e "${COLOR_GREEN}容器更新完成！${COLOR_RESET}"
      ;;
    *)
      echo -e "${COLOR_RED}无效选项，请输入有效的操作编号！${COLOR_RESET}"
      ;;
  esac
}

# 安装 Watchtower 服务
init_watchtower() {
  echo -e "${COLOR_BLUE}初始化 Docker 自动更新程序...${COLOR_RESET}"
  docker run -d \
    --name naspt-dkup \
    -v /var/run/docker.sock:/var/run/docker.sock \
    ccr.ccs.tencentyun.com/naspt/watchtower
}

# 单次更新所有容器
update_watchtower() {
  echo -e "${COLOR_BLUE}执行单次更新所有容器...${COLOR_RESET}"
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    ccr.ccs.tencentyun.com/naspt/watchtower --run-once
}

# 开始执行用户选择的操作
install_service "$SERVICE_CHOICE"

# 结束脚本
echo -e "${COLOR_YELLOW}=================== 操作完成 =====================${COLOR_RESET}"
echo -e "${COLOR_GREEN}感谢使用本脚本！${COLOR_RESET}"
history -c
exit 0