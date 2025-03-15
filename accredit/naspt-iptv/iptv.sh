#!/bin/bash

# 配置颜色输出
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

# 定义输出函数
info() { echo -e "${COLOR_CYAN}[信息] $*${COLOR_RESET}"; }
success() { echo -e "${COLOR_GREEN}[成功] $*${COLOR_RESET}"; }
warning() { echo -e "${COLOR_YELLOW}[警告] $*${COLOR_RESET}"; }
error() { echo -e "${COLOR_RED}[错误] $*${COLOR_RESET}" >&2; }
header() { echo -e "${COLOR_BLUE}==========================================${COLOR_RESET}"; }

# 默认配置
HOST_IP=""
CONTAINER_NAMES=("naspt-allinone" "naspt-allinone-format")

# 检查依赖项
check_dependencies() {
  if ! command -v docker &>/dev/null; then
    error "Docker 未安装，请先安装 Docker"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    error "Docker 服务未运行"
    exit 1
  fi
}

# 安全输入验证
safe_input() {
  local var_name="$1"
  local prompt="$2"
  local default="$3"

  while true; do
    read -rp "$(echo -e "${COLOR_CYAN}${prompt} (默认: ${default}): ${COLOR_RESET}")" value
    value="${value:-$default}"

    if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      error "无效的IP地址格式"
      continue
    fi

    eval "$var_name='$value'"
    break
  done
}

# 清理残留容器
clean_container() {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    warning "发现已存在的容器: ${name}"
    if docker rm -f "$name" &>/dev/null; then
      info "已成功移除旧容器: ${name}"
    else
      error "无法移除容器: ${name}"
      exit 1
    fi
  fi
}

# 初始化服务
init_service() {
  local name="$1"
  local image="$2"
  local cmd="$3"

  header
  info "正在初始化 ${name} 服务"
  clean_container "$name"

  info "正在启动容器..."
  if docker run -d \
    --name "$name" \
    --restart always \
    --network host \
    ${cmd}; then

    success "${name} 服务启动成功"
  else
    error "容器启动失败"
    exit 1
  fi
}

# 主程序流程
main() {
  clear
  check_dependencies

  # 获取配置信息
  header
  safe_input "HOST_IP" "请输入 NAS IP 地址" "$(ip route get 1 | awk '{print $7}' | head -1)"

  # 显示配置确认
  header
  info "配置信息确认"
  echo -e "主机 IP 地址: ${COLOR_YELLOW}${HOST_IP}${COLOR_RESET}"

  read -rp "$(echo -e "${COLOR_CYAN}是否继续安装？(y/N): ${COLOR_RESET}")" confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

  # 安装服务
  init_service "naspt-allinone" \
    "ccr.ccs.tencentyun.com/naspt/allinone" \
    "--privileged -e aesKey=swj6pnb4h6xyvhpq69fgae2bbpjlb8y2 -e userid=5892131247 -e token=9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137"

  init_service "naspt-allinone-format" \
    "ccr.ccs.tencentyun.com/naspt/allinone_format:latest" \
    ""

  # 输出访问信息
  header
  success "服务部署完成！"
  echo -e "${COLOR_YELLOW}=== 访问地址 ===${COLOR_RESET}"
  echo -e "IPTV 源地址:   http://${HOST_IP}:35455/tv.m3u"
  echo -e "IPTV 整理地址: http://${HOST_IP}:35456"
  echo -e "\n${COLOR_YELLOW}请确保防火墙已开放以下端口：${COLOR_RESET}"
  echo -e " - 35455/TCP (原始数据接口)"
  echo -e " - 35456/TCP (整理后数据接口)"

  # 安全建议
  header
  warning "安全提示："
  echo -e "1. 建议定期轮换 AES 加密密钥"
  echo -e "2. 监控容器日志：docker logs naspt-allinone"
  echo -e "3. 建议配置 HTTPS 加密访问"
}

# 执行主程序
main