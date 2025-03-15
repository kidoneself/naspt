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

# 服务配置（示例）
declare -A CONFIG_URLS=(
    ["service1"]="https://example.com/service1.tgz"
    ["service2"]="https://example.com/service2.tgz"
)

# 初始化默认配置
DOCKER_ROOT=""
DATA_ROOT=""
HOST_IP=""
declare -A SERVICE_PORTS=(
    ["service1"]="8081"
    ["service2"]="8082"
)
CONFIG_FILE="/root/.naspt/template.conf"

# 配置管理
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
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

  # 动态生成配置文件内容
  local config_content=""
  config_content+="DOCKER_ROOT=\"$DOCKER_ROOT\"\n"
  config_content+="DATA_ROOT=\"$DATA_ROOT\"\n"
  config_content+="HOST_IP=\"$HOST_IP\"\n"
  
  # 保存服务端口配置
  for service in "${!SERVICE_PORTS[@]}"; do
    config_content+="${service}_PORT=\"${SERVICE_PORTS[$service]}\"\n"
  done

  echo -e "$config_content" > "$CONFIG_FILE"
  [[ $? -eq 0 ]] && info "配置已保存到 $CONFIG_FILE" || error "配置保存失败"
}

# 系统检查
check_dependencies() {
  local deps=("docker" "curl" "tar" "netstat")
  local missing=()

  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "缺少依赖: ${missing[*]}"
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
      "path")
        if [[ ! "$input" =~ ^/ ]]; then
          error "必须使用绝对路径"
          continue
        fi
        mkdir -p "$input" || {
          error "目录创建失败"
          continue
        }
        ;;
      "ip")
        if ! [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          error "无效IP格式"
          continue
        fi
        ;;
      "port")
        if ! [[ "$input" =~ ^[0-9]+$ ]] || (( input < 1 || input > 65535 )); then
          error "无效端口号"
          continue
        fi
        ;;
    esac

    eval "$var_name='$input'"
    break
  done
}

# 容器管理
clean_container() {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    warning "发现残留容器: ${name}"
    if docker rm -f "$name" &>/dev/null; then
      info "已移除容器: ${name}"
    else
      error "容器移除失败"
      exit 1
    fi
  fi
}

check_port() {
  if netstat -tuln | grep -Eq ":$1"; then
      error "端口 $1 已被占用"
      exit 1
  fi
}

# 配置文件下载解压
download_config() {
  local service="$1"
  local dest_dir="$2"
  local url="${CONFIG_URLS[$service]}"
  local temp_file="${dest_dir}.tgz"

  info "正在下载 ${service} 配置文件..."
  for i in {1..3}; do
    if curl -L "$url" -o "$temp_file" --progress-bar; then
      success "下载成功"
      break
    else
      warning "下载失败，第${i}次重试..."
      sleep 2
    fi
  done || {
    error "多次下载失败: $service"
    rm -f "$temp_file"
    return 1
  }

  info "解压配置文件..."
  mkdir -p "$dest_dir" || return 1
  if ! tar -zxf "$temp_file" -C "$dest_dir" --strip-components=1; then
    error "解压失败: $service"
    rm -rf "$dest_dir" "$temp_file"
    return 1
  fi
}

# 服务初始化示例
init_service() {
  local service_name="$1"
  local port="${SERVICE_PORTS[$service_name]}"
  local data_dir="${DOCKER_ROOT}/${service_name}"

  check_port "$port" || return 1
  clean_container "$service_name"
  download_config "$service_name" "$data_dir" || return 1

  info "正在启动 ${service_name}..."
  # 在这里添加具体的docker run命令
  # 示例：
  # docker run -d --name "$service_name" \
  #   --restart always \
  #   --network bridge \
  #   -p "$port":8080 \
  #   -v "${data_dir}/config:/config" \
  #   -v "${DATA_ROOT}:/data" \
  #   your-image-name:tag
}

# 配置向导
configure_essential() {
  while :; do
    header
    info "开始初始配置"

    safe_input "DOCKER_ROOT" "Docker数据路径" "$DOCKER_ROOT" "path"
    safe_input "DATA_ROOT" "数据存储路径" "$DATA_ROOT" "path"
    safe_input "HOST_IP" "服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"

    # 配置各服务端口
    for service in "${!SERVICE_PORTS[@]}"; do
      safe_input "SERVICE_PORTS[$service]" "${service}服务端口" "${SERVICE_PORTS[$service]}" "port"
    done

    header
    echo -e "${COLOR_BLUE}配置预览："
    echo -e "▷ Docker目录: ${COLOR_CYAN}${DOCKER_ROOT}"
    echo -e "▷ 数据目录: ${COLOR_CYAN}${DATA_ROOT}"
    echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}"
    echo -e "▷ 服务端口列表:"
    for service in "${!SERVICE_PORTS[@]}"; do
      echo -e "  - ${service}: ${SERVICE_PORTS[$service]}"
    done
    header

    read -rp "$(echo -e "${COLOR_YELLOW}是否确认配置？(Y/n) ${COLOR_RESET}")" confirm
    [[ "${confirm:-Y}" =~ ^[Yy]$ ]] && break
  done

  save_config
}

# 服务管理菜单
show_menu() {
  clear
  header
  echo -e "${COLOR_GREEN} 服务管理脚本模板 v1.0"
  header
  echo -e " 1. 完整部署所有服务"
  echo -e " 2. 配置参数设置"
  echo -e " 3. 单独部署服务"
  echo -e " 4. 查看服务状态"
  echo -e " 5. 完全卸载"
  echo -e " 0. 退出脚本"
  header
}

# 主流程
main() {
  check_dependencies
  load_config

  if [[ -z "$DOCKER_ROOT" || -z "$DATA_ROOT" || -z "$HOST_IP" ]]; then
    warning "检测到未完成初始配置！"
    configure_essential
  fi

  while :; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    case $choice in
      1)
        # 部署所有服务
        for service in "${!CONFIG_URLS[@]}"; do
          init_service "$service"
        done
        success "所有服务部署完成"
        info "访问地址:"
        for service in "${!SERVICE_PORTS[@]}"; do
          echo -e "${service}: http://${HOST_IP}:${SERVICE_PORTS[$service]}"
        done
        ;;
      2)
        configure_essential
        ;;
      3)
        header
        echo -e "请选择要部署的服务："
        local i=1
        declare -A service_map
        for service in "${!CONFIG_URLS[@]}"; do
          echo -e " $i. $service"
          service_map[$i]=$service
          ((i++))
        done
        read -p "请输入编号: " service_choice
        if [[ -n "${service_map[$service_choice]}" ]]; then
          init_service "${service_map[$service_choice]}"
        else
          error "无效选择"
        fi
        ;;
      4)
        header
        echo -e "${COLOR_CYAN}运行中的容器："
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        header
        ;;
      5)
        header
        warning "此操作将删除所有服务容器！"
        read -rp "$(echo -e "${COLOR_RED}确认要卸载吗？(输入YES确认): ${COLOR_RESET}")" confirm
        if [[ "$confirm" == "YES" ]]; then
          for service in "${!CONFIG_URLS[@]}"; do
            clean_container "$service"
          done
          success "所有服务已卸载"
        else
          info "已取消卸载"
        fi
        ;;
      0)
        rm -rf *.tgz
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