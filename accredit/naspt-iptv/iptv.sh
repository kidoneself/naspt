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

# 加载配置文件
CONFIG_FILE="/root/.naspt/naspt.conf"

# 初始化默认配置
HOST_IP=""
IMAGE_SOURCE="official"  # 镜像源选择

# 定义私有镜像
declare -A DOCKER_IMAGES=(
    ["allinone"]="ccr.ccs.tencentyun.com/naspt/allinone:latest"
    ["allinone_format"]="ccr.ccs.tencentyun.com/naspt/allinone_format:latest"
)

# 定义官方镜像
declare -A OFFICIAL_DOCKER_IMAGES=(
    ["allinone"]="youshandefeiyang/allinone:latest"
    ["allinone_format"]="yuexuangu/allinone_format:latest"
)

# 获取当前使用的镜像
get_current_image() {
    local image_type="$1"
    local image=""
    
    if [[ "$IMAGE_SOURCE" == "official" ]]; then
        image="${OFFICIAL_DOCKER_IMAGES[$image_type]}"
    else
        image="${DOCKER_IMAGES[$image_type]}"
    fi
    
    echo -e "${COLOR_CYAN}[信息] 使用${IMAGE_SOURCE}镜像源: ${image}${COLOR_RESET}" >&2
    printf "%s" "$image"
}

# 配置文件操作函数
get_ini_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value
  
  value=$(sed -n "/^\[$section\]/,/^\[/p" "$file" | grep "^$key=" | cut -d'=' -f2-)
  echo "$value"
}

set_ini_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo "[$section]" > "$file"
  fi
  
  if ! grep -q "^\[$section\]" "$file"; then
    echo -e "\n[$section]" >> "$file"
  fi
  
  if grep -q "^$key=" <(sed -n "/^\[$section\]/,/^\[/p" "$file"); then
    sed -i "/^\[$section\]/,/^\[/s|^$key=.*|$key=$value|" "$file"
  else
    sed -i "/^\[$section\]/a $key=$value" "$file"
  fi
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    HOST_IP=$(get_ini_value "$CONFIG_FILE" "iptv" "HOST_IP")
    IMAGE_SOURCE=$(get_ini_value "$CONFIG_FILE" "iptv" "IMAGE_SOURCE")
    [[ -z "$IMAGE_SOURCE" ]] && IMAGE_SOURCE="official"
  else
    warning "使用默认配置"
  fi
}

save_config() {
  local config_dir="$(dirname "$CONFIG_FILE")"
  mkdir -p "$config_dir" || {
    error "无法创建配置目录: $config_dir"
    return 1
  }

  set_ini_value "$CONFIG_FILE" "iptv" "HOST_IP" "$HOST_IP"
  set_ini_value "$CONFIG_FILE" "iptv" "IMAGE_SOURCE" "$IMAGE_SOURCE"
  
  [[ $? -eq 0 ]] && info "配置已保存" || error "配置保存失败"
}

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

safe_input() {
  local var_name="$1"
  local prompt="$2"
  local default="$3"

  while true; do
    read -rp "$(echo -e "${COLOR_CYAN}${prompt} (默认: ${default}): ${COLOR_RESET}")" value
    value="${value:-$default}"

    case "$4" in
      "ip")
        if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          error "无效的IP地址格式"
          continue
        fi
        ;;
    esac

    eval "$var_name='$value'"
    break
  done
}

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

check_deploy_params() {
  [[ -z "$HOST_IP" ]] && {
    error "关键参数未配置！请先运行选项2进行配置"
    return 1
  }
  return 0
}

init_allinone() {
  check_deploy_params || exit 1

  clean_container "naspt-allinone"

  info "启动 IPTV 源服务..."
  docker run -d \
    --name naspt-allinone \
    --privileged \
    --restart always \
    --network host \
    "$(get_current_image allinone)" \
    -tv=true \
    -aesKey=swj6pnb4h6xyvhpq69fgae2bbpjlb8y2 \
    -userid=5892131247 \
    -token=9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137  || {
    error "IPTV源服务启动失败，查看日志：docker logs naspt-allinone"
    exit 1
  }

  success "IPTV源服务已启动"
  info "访问地址: ${COLOR_YELLOW}http://${HOST_IP}:35455/tv.m3u${COLOR_RESET}"
}

init_allinone_format() {
  check_deploy_params || exit 1

  clean_container "naspt-allinone-format"

  info "启动 IPTV 整理服务..."
  docker run -d \
    --name naspt-allinone-format \
    --restart always \
    --network host \
    "$(get_current_image allinone_format)" || {
    error "IPTV整理服务启动失败，查看日志：docker logs naspt-allinone-format"
    exit 1
  }

  success "IPTV整理服务已启动"
  info "访问地址: ${COLOR_YELLOW}http://${HOST_IP}:35456${COLOR_RESET}"
}

uninstall_services() {
  header
  warning "此操作将永久删除所有容器及数据！"
  read -rp "$(echo -e "${COLOR_RED}确认要卸载服务吗？(输入YES确认): ${COLOR_RESET}")" confirm
  [[ "$confirm" != "YES" ]] && { info "已取消卸载"; return; }

  clean_container "naspt-allinone"
  clean_container "naspt-allinone-format"
  success "所有服务及数据已移除"
}

configure_essential() {
  while :; do
    header
    info "开始初始配置（首次运行必需）"

    safe_input "HOST_IP" "请输入服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"
    safe_input "IMAGE_SOURCE" "镜像源选择(private/official)" "${IMAGE_SOURCE:-official}" "image_source"

    header
    echo -e "${COLOR_BLUE}当前配置预览："
    echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}${COLOR_BLUE}"
    echo -e "▷ 镜像源: ${COLOR_CYAN}${IMAGE_SOURCE}${COLOR_BLUE}"
    header

    read -rp "$(echo -e "${COLOR_YELLOW}是否确认保存以上配置？(Y/n) ${COLOR_RESET}")" confirm
    if [[ "${confirm:-Y}" =~ ^[Yy]$ ]]; then
      save_config
      success "配置已保存！"
      return 0
    else
      info "重新输入配置..."
      HOST_IP=""
    fi
  done
}

show_menu() {
  clear
  header
  echo -e "${COLOR_GREEN} IPTV 服务部署管理脚本 v2.0"
  header
  echo -e " 1. 完整部署"
  echo -e " 2. 修改配置"
  echo -e " 3. 完全卸载"
  echo -e " 4. 服务状态"
  echo -e " 0. 退出脚本"
  header
}

main() {
  check_dependencies
  load_config

  if [[ -z "$HOST_IP" ]]; then
    warning "检测到未完成初始配置！"
    configure_essential
  fi

  while :; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    case $choice in
      1)
        header
        if [[ -n "$HOST_IP" ]]; then
          info "检测到当前配置："
          echo -e "▷ 服务器地址: ${COLOR_CYAN}${HOST_IP}${COLOR_RESET}"
          header
          read -rp "$(echo -e "${COLOR_YELLOW}确认使用以上配置进行部署？(Y/n) ${COLOR_RESET}")" confirm

          if [[ ! "${confirm:-Y}" =~ ^[Yy]$ ]]; then
            warning "已取消部署，请先修改配置"
            continue
          fi
        else
          error "缺少必要配置，请先完成初始配置！"
          continue
        fi

        init_allinone
        init_allinone_format
        ;;
      2) configure_essential ;;
      3) uninstall_services ;;
      4)
        header
        echo -e "${COLOR_CYAN}容器状态:"
        docker ps -a --filter "name=naspt-allinone" --filter "name=naspt-allinone-format" \
          --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
        header
        ;;
      0)
        success "操作结束"
        exit 0
        ;;
      *)
        error "无效选项"
        ;;
    esac

    read -rp "$(echo -e "${COLOR_CYAN}按 Enter 继续...${COLOR_RESET}")"
  done
}

main