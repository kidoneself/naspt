#!/bin/bash

# 默认值
DOCKER_ROOT_PATH=""
HOST_IP=""

# 颜色设置
COLOR_CYAN="\033[36m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RESET="\033[0m"

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

# 通用的下载和解压函数
download_and_extract() {
  local url="$1"                   # 下载文件的 URL
  local output_file="$2"           # 下载到本地的路径
  local extract_path="$3"          # 解压目标路径
  local strip_components="${4:-1}" # 默认 strip-components 为 1

  # 检查文件是否已存在，如果已存在则跳过下载
  if [ -f "$output_file" ]; then
    echo -e "${COLOR_GREEN}文件 $output_file 已存在，跳过下载。${COLOR_RESET}"
  else
    echo -e "${COLOR_YELLOW}正在下载文件: $url${COLOR_RESET}"
    if ! curl -L "$url" -o "$output_file"; then
      echo -e "${COLOR_RED}错误: 无法下载文件 $url，请检查网络连接或 URL 是否正确。${COLOR_RESET}"
      exit 1
    fi
  fi

  echo -e "${COLOR_YELLOW}正在解压文件到: $extract_path${COLOR_RESET}"
  mkdir -p "$extract_path"
  if ! tar --strip-components="$strip_components" -zxvf "$output_file" -C "$extract_path"; then
    echo -e "${COLOR_RED}错误: 解压文件 $output_file 失败，请检查文件内容是否正确。${COLOR_RESET}"
    exit 1
  fi
}

# 获取 Docker 根路径和视频根路径
get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DOCKER_ROOT_PATH"
get_input "HOST_IP" "请输入 NAS IP" "$HOST_IP"

# 导出环境变量
export DOCKER_ROOT_PATH HOST_IP

# 显示设置的配置信息
echo -e "\n${COLOR_GREEN}=== 配置信息 ===${COLOR_RESET}"
echo -e "${COLOR_CYAN}主机 IP 地址:${COLOR_RESET} $HOST_IP"
echo -e "${COLOR_CYAN}Docker 根路径:${COLOR_RESET} $DOCKER_ROOT_PATH"

# 初始化 Clash 服务
init_clash() {
    echo -e "\n${COLOR_GREEN}=== 初始化 Clash ===${COLOR_RESET}"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-cl"
    download_and_extract \
      "https://alist.naspt.vip/d/shell/naspt-cl/naspt-cl.tgz" \
      "$DOCKER_ROOT_PATH/naspt-cl.tgz" \
      "$DOCKER_ROOT_PATH/naspt-cl/"

    docker run -d --name naspt-clash --restart unless-stopped \
      -v "$DOCKER_ROOT_PATH/naspt-cl:/root/.config/clash" \
      -p 8080:8080 \
      -p 7890:7890 \
      --privileged \
      "ccr.ccs.tencentyun.com/naspt/clash-and-dashboard:latest"
}

# 配置输入完成后直接开始安装所有服务
echo -e "\n${COLOR_YELLOW}正在开始安装所有服务...${COLOR_RESET}"
init_clash

# 输出每个服务的配置信息
echo -e "\n${COLOR_GREEN}=== 服务安装完成 ===${COLOR_RESET}"
echo -e "以下是每个服务的访问信息："
echo -e "1. ${COLOR_CYAN}Clash:${COLOR_RESET}"
echo -e "   地址: http://$HOST_IP:8080"
echo -e "   HTTP 代理地址: http://$HOST_IP:7890"

# 结束脚本
history -c
echo -e "\n${COLOR_GREEN}安装流程结束！${COLOR_RESET}"
exit 0