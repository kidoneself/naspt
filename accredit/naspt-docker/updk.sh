#!/bin/bash

# 颜色配置
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

# 输出函数
header() { echo -e "${COLOR_BLUE}==========================================================${COLOR_RESET}"; }
info() { echo -e "${COLOR_CYAN}[信息] $*${COLOR_RESET}"; }
success() { echo -e "${COLOR_GREEN}[成功] $*${COLOR_RESET}"; }
warning() { echo -e "${COLOR_YELLOW}[警告] $*${COLOR_RESET}"; }
error() { echo -e "${COLOR_RED}[错误] $*${COLOR_RESET}" >&2; }

# 加载配置文件
CONFIG_FILE="/root/.naspt/naspt.conf"

# 初始化默认配置
DOCKER_ROOT=""
CHECK_INTERVAL="10800"
AUTO_CLEANUP="true"
WATCHTOWER_IMAGE="ccr.ccs.tencentyun.com/naspt/watchtower:latest"
CONTAINER_NAME="naspt-dkup"

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
  
  # 如果文件不存在，创建文件和section
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo "[$section]" > "$file"
  fi
  
  # 如果section不存在，添加section
  if ! grep -q "^\[$section\]" "$file"; then
    echo -e "\n[$section]" >> "$file"
  fi
  
  # 在section中查找并替换key的值，如果不存在则添加
  if grep -q "^$key=" "$file"; then
    sed -i "/^\[$section\]/,/^\[/s|^$key=.*|$key=$value|" "$file"
  else
    sed -i "/^\[$section\]/a $key=$value" "$file"
  fi
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # 从[watchtower]部分读取所有配置
    DOCKER_ROOT=$(get_ini_value "$CONFIG_FILE" "watchtower" "DOCKER_ROOT")
    CHECK_INTERVAL=$(get_ini_value "$CONFIG_FILE" "watchtower" "CHECK_INTERVAL")
    AUTO_CLEANUP=$(get_ini_value "$CONFIG_FILE" "watchtower" "AUTO_CLEANUP")
    CONTAINER_NAME=$(get_ini_value "$CONFIG_FILE" "watchtower" "CONTAINER_NAME")
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

  # 保存所有配置到[watchtower]部分
  set_ini_value "$CONFIG_FILE" "watchtower" "DOCKER_ROOT" "$DOCKER_ROOT"
  set_ini_value "$CONFIG_FILE" "watchtower" "CHECK_INTERVAL" "$CHECK_INTERVAL"
  set_ini_value "$CONFIG_FILE" "watchtower" "AUTO_CLEANUP" "$AUTO_CLEANUP"
  set_ini_value "$CONFIG_FILE" "watchtower" "CONTAINER_NAME" "$CONTAINER_NAME"
  
  [[ $? -eq 0 ]] && info "配置已保存" || error "配置保存失败"
}

# 系统检查
check_dependencies() {
  if ! command -v docker &>/dev/null; then
    error "Docker 未安装"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    error "Docker 服务未运行"
    exit 1
  fi
}

# 输入验证
safe_input() {
  local var_name="$1" prompt="$2" default="$3" validator="$4"

  while :; do
    read -rp "$(echo -e "${COLOR_CYAN}${prompt} (默认: ${default}): ${COLOR_RESET}")" input
    input=${input:-$default}

    case "$validator" in
      "number")
        if ! [[ "$input" =~ ^[0-9]+$ ]]; then
          error "必须输入数字"
          continue
        fi
        ;;
      "boolean")
        if ! [[ "$input" =~ ^[YyNn]$ ]]; then
          error "请输入 y 或 n"
          continue
        fi
        input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
        ;;
    esac

    eval "$var_name='$input'"
    break
  done
}

# 容器管理
clean_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warning "发现残留容器: ${CONTAINER_NAME}"
    if docker rm -f "$CONTAINER_NAME" &>/dev/null; then
      info "已移除旧容器"
    else
      error "容器移除失败"
      exit 1
    fi
  fi
}

# 服务部署
setup_service() {
  info "正在配置自动更新服务"

  safe_input "CHECK_INTERVAL" "检测间隔时间（秒）" "$CHECK_INTERVAL" "number"
  safe_input "AUTO_CLEANUP" "自动清理旧镜像？(y/n)" "$([[ $AUTO_CLEANUP == "true" ]] && echo "y" || echo "n")" "boolean"

  local cleanup_flag=""
  [[ ${AUTO_CLEANUP,,} == "y" ]] && {
    AUTO_CLEANUP="true"
    cleanup_flag="--cleanup"
  }

  info "启动容器..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e TZ=Asia/Shanghai \
    "$WATCHTOWER_IMAGE" \
    --interval "$CHECK_INTERVAL" \
    $cleanup_flag || {
    error "服务启动失败"
    exit 1
  }

  save_config
  success "服务已启动"
  info "检测间隔: $((CHECK_INTERVAL / 3600)) 小时"
  info "自动清理: ${AUTO_CLEANUP}"
}
#docker run --rm   --name watchtower   -e TZ=Asia/Shanghai   -v /var/run/docker.sock:/var/run/docker.sock   ccr.ccs.tencentyun.com/naspt/watchtower  --run-once   --cleanup
# 立即更新
run_update() {

  info "执行立即更新..."
  docker login ccr.ccs.tencentyun.com --username=100005757274 -p naspt1995
  docker run --rm \
    -e TZ=Asia/Shanghai \
    -v ~/.docker/config.json:/config.json \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$WATCHTOWER_IMAGE" \
    --run-once --cleanup || {
    error "更新执行失败"
    exit 1
  }
  success "容器更新完成"
}

# 服务状态
show_status() {
  header
  echo -e "${COLOR_CYAN}容器状态:"
  docker ps -a --filter "name=$CONTAINER_NAME" \
    --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
  header
}

# 菜单显示
show_menu() {
  clear
  header
  echo -e "${COLOR_GREEN} Docker 更新服务管理 v2.0"
  header
  echo -e " 1. 安装/配置自动更新"
  echo -e " 2. 立即更新所有容器"
  echo -e " 3. 查看服务状态"
  echo -e " 4. 卸载服务"
  echo -e " 0. 退出脚本"
  header
}

# 主流程
main() {
  check_dependencies
  load_config

  while :; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    case $choice in
      1)
        clean_container
        setup_service
        ;;
      2)
        run_update
        ;;
      3)
        show_status
        ;;
      4)
        clean_container
        success "服务已卸载"
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