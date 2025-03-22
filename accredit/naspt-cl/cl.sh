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
CONFIG_FILE="/root/.naspt/.naspt-clash.conf"

# 初始化默认配置
DOCKER_ROOT=""
HOST_IP=""

CLASH_CONTAINER="naspt-clash"
CLASH_VOLUME="naspt-clash"
WEB_PORT="8081"
PROXY_PORT="7890"
CLASH_CONFIG_URL="https://alist.naspt.vip/d/shell/naspt-cl/naspt-cl.tgz"

# 配置管理
load_config() {
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || warning "使用默认配置"
}

save_config() {
  local config_dir="$(dirname "$CONFIG_FILE")"
  mkdir -p "$config_dir" || {
    error "无法创建配置目录: $config_dir"
    return 1
  }

  cat > "$CONFIG_FILE" <<EOF
DOCKER_ROOT="$DOCKER_ROOT"
HOST_IP="$HOST_IP"
CLASH_CONTAINER="$CLASH_CONTAINER"
CLASH_VOLUME="$CLASH_VOLUME"
WEB_PORT="$WEB_PORT"
PROXY_PORT="$PROXY_PORT"
EOF
  [[ $? -eq 0 ]] && info "配置已保存到 $CONFIG_FILE" || error "配置保存失败"
}



safe_input() {
  local var_name="$1" prompt="$2" default="$3" validator="$4"
  local input
  local cancelled=false

  # 设置Ctrl+C信号处理
  trap 'echo -e "\n${COLOR_YELLOW}已取消当前输入${COLOR_RESET}"; cancelled=true; break' INT

  while ! $cancelled; do
    read -rp "$(echo -e "${COLOR_CYAN}${prompt} (默认: ${default}): ${COLOR_RESET}")" input
    input=${input:-$default}

    case "$validator" in
      "path")
        if [[ ! "$input" =~ ^/ ]]; then
          error "必须使用绝对路径"
          continue
        fi
        if [[ ! -d "$input" ]]; then
          error "路径不存在 $input"
          continue
        fi
        ;;
      "ip")
        if ! [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          error "无效IP格式"
          continue
        fi
        if ! ping -c1 -W2 "$input" &>/dev/null; then
          warning "IP地址 $input 无法ping通，请确认网络配置"
        fi
        ;;
      "port")
        if ! [[ "$input" =~ ^[0-9]+$ ]] || (( "$input" < 1 || "$input" > 65535 )); then
          error "无效端口号"
          continue
        fi
        ;;
    esac

    eval "$var_name='$input'"
    cancelled=false
    break
  done

  # 重置信号处理
  trap - INT
  return $cancelled
}

configure_essential() {
  while :; do
    header
    info "开始初始配置（首次运行必需）"

    # 设置Ctrl+C信号处理
    trap 'echo -e "\n${COLOR_YELLOW}返回主菜单${COLOR_RESET}"; return 1' INT

    local input_cancelled=false
    while :; do
      if safe_input "DOCKER_ROOT" "Docker数据存储路径" "${DOCKER_ROOT:-}" "path"; then
        if safe_input "HOST_IP" "服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"; then
          if safe_input "WEB_PORT" "控制面板端口" "${WEB_PORT:-8081}" "port"; then
            if safe_input "PROXY_PORT" "代理服务端口" "${PROXY_PORT:-7890}" "port"; then
              input_cancelled=false
              break
            fi
          fi
        fi
      fi
      info "重新开始配置..."
    done

    header
    echo -e "${COLOR_BLUE}当前配置预览："
    echo -e "▷ Docker根目录: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_BLUE}"
    echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}${COLOR_BLUE}"
    echo -e "▷ 控制面板端口: ${COLOR_CYAN}${WEB_PORT}${COLOR_BLUE}"
    echo -e "▷ 代理服务端口: ${COLOR_CYAN}${PROXY_PORT}${COLOR_BLUE}"
    header

    read -rp "$(echo -e "${COLOR_YELLOW}是否确认保存以上配置？(Y/n) ${COLOR_RESET}")" confirm
    if [[ "${confirm:-Y}" =~ ^[Yy]$ ]]; then
      save_config
      success "配置已保存！"
      # 重置信号处理
      trap - INT
      return 0
    else
      info "重新输入配置..."
      DOCKER_ROOT=""
      HOST_IP=""
      WEB_PORT="8081"
      PROXY_PORT="7890"
    fi
  done
}

clean_container() {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    warning "发现残留容器: ${name}"
    if docker inspect "$name" --format '{{.State.Status}}' | grep -q "running"; then
      info "正在停止运行中的容器..."
      docker stop "$name" &>/dev/null
    fi
    if docker rm -f "$name" &>/dev/null; then
      info "已移除容器: ${name}"
    else
      error "容器移除失败"
      exit 1
    fi
  fi
}

check_deploy_params() {
  [[ -z "$DOCKER_ROOT" || -z "$HOST_IP" ]] && {
    error "关键参数未配置！请先运行配置"
    return 1
  }
  return 0
}

download_clash_config() {
  local dest="${DOCKER_ROOT}/naspt-clash.tgz"
  [[ -f "$dest" ]] && return

  info "下载Clash配置文件..."
  for i in {1..3}; do
    if curl -L "$CLASH_CONFIG_URL" -o "$dest" --progress-bar; then
      success "下载成功"
      return
    else
      warning "下载失败，重试第 $i 次..."
      sleep 2
    fi
  done
  error "多次下载失败，请检查网络或代理设置"
  rm -f "$dest"
  exit 1
}

init_clash() {
  check_deploy_params || exit 1

  local config_dir="${DOCKER_ROOT}/${CLASH_VOLUME}"
  mkdir -p "${config_dir}"

  clean_container "$CLASH_CONTAINER"

  if netstat -tuln | grep -Eq ":${WEB_PORT}|:${PROXY_PORT}"; then
      error "端口 ${WEB_PORT} 或 ${PROXY_PORT} 已被占用"
      exit 1
  fi


  info "解压配置文件..."
  tar -zxf "${DOCKER_ROOT}/naspt-clash.tgz" -C "${config_dir}" --strip-components=1 || {
    error "文件解压失败，可能下载损坏"
    rm -rf "$config_dir"
    exit 1
  }

  info "启动Clash容器..."
  docker run -d --restart always \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    --network bridge \
    -v "${config_dir}:/root/.config/clash" \
    -p "${WEB_PORT}:8081" \
    -p "${PROXY_PORT}:7890" \
    --name "$CLASH_CONTAINER" \
    "ccr.ccs.tencentyun.com/naspt/clash-and-dashboard:latest" || {
    error "Clash启动失败，查看日志：docker logs $CLASH_CONTAINER"
    exit 1
  }

  success "Clash 已启动"
  info "控制面板: ${COLOR_YELLOW}http://${HOST_IP}:${WEB_PORT}${COLOR_RESET}"
  info "代理地址: ${COLOR_YELLOW}http://${HOST_IP}:${PROXY_PORT}${COLOR_RESET}"
}

uninstall_services() {
  header
  warning "此操作将永久删除所有容器及数据！"
  read -rp "$(echo -e "${COLOR_RED}确认要卸载服务吗？(输入Y确认): ${COLOR_RESET}")" confirm
  [[ "$confirm" != "Y" ]] && { info "已取消卸载"; return; }

  clean_container "$CLASH_CONTAINER"
  rm -rf "${DOCKER_ROOT}/${CLASH_VOLUME}"
  success "所有服务及数据已移除"
}

configure_essential() {
  while :; do
    header
    info "开始初始配置（首次运行必需）"

    safe_input "DOCKER_ROOT" "Docker数据存储路径" "${DOCKER_ROOT:-}" "path"
    safe_input "HOST_IP" "服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"
    safe_input "WEB_PORT" "控制面板端口" "${WEB_PORT:-8081}" "port"
    safe_input "PROXY_PORT" "代理服务端口" "${PROXY_PORT:-7890}" "port"

    header
    echo -e "${COLOR_BLUE}当前配置预览："
    echo -e "▷ Docker根目录: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_BLUE}"
    echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}${COLOR_BLUE}"
    echo -e "▷ 控制面板端口: ${COLOR_CYAN}${WEB_PORT}${COLOR_BLUE}"
    echo -e "▷ 代理服务端口: ${COLOR_CYAN}${PROXY_PORT}${COLOR_BLUE}"
    header

    read -rp "$(echo -e "${COLOR_YELLOW}是否确认保存以上配置？(Y/n) ${COLOR_RESET}")" confirm
    if [[ "${confirm:-Y}" =~ ^[Yy]$ ]]; then
      save_config
      success "配置已保存！"
      return 0
    else
      info "重新输入配置..."
      DOCKER_ROOT=""
      HOST_IP=""
      WEB_PORT="8081"
      PROXY_PORT="7890"
    fi
  done
}

update_clash() {
  check_deploy_params || exit 1
  
  info "正在更新Clash服务..."
  
  # 拉取最新镜像
  info "拉取最新镜像..."
  if ! docker pull "ccr.ccs.tencentyun.com/naspt/clash-and-dashboard:latest"; then
    error "镜像拉取失败"
    return 1
  fi
  
  # 停止并移除旧容器
  clean_container "$CLASH_CONTAINER"
  
  # 使用最新镜像重新启动容器
  info "使用最新镜像重启服务..."
  docker run -d --restart always \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    --network bridge \
    -v "${DOCKER_ROOT}/${CLASH_VOLUME}:/root/.config/clash" \
    -p "${WEB_PORT}:8081" \
    -p "${PROXY_PORT}:7890" \
    --name "$CLASH_CONTAINER" \
    "ccr.ccs.tencentyun.com/naspt/clash-and-dashboard:latest" || {
    error "Clash更新失败，查看日志：docker logs $CLASH_CONTAINER"
    return 1
  }
  
  success "Clash 已更新到最新版本"
  info "控制面板: ${COLOR_YELLOW}http://${HOST_IP}:${WEB_PORT}${COLOR_RESET}"
  info "代理地址: ${COLOR_YELLOW}http://${HOST_IP}:${PROXY_PORT}${COLOR_RESET}"
}

show_menu() {
  clear
  header
  echo -e "${COLOR_GREEN} naspt-Clash服务部署管理脚本"
  header
  echo -e " 1. 完整部署"
  echo -e " 2. 修改配置"
  echo -e " 3. 完全卸载"
  echo -e " 4. 服务状态"
  echo -e " 5. 更新服务"
  echo -e " 0. 退出脚本"
  header
}

main() {
#  check_dependencies
  clear
  load_config

  if [[ -z "$DOCKER_ROOT" || -z "$HOST_IP" ]]; then
    warning "检测到未完成初始配置！"
    configure_essential
  fi

  while :; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    case $choice in
      1)
        header
        if [[ -n "$DOCKER_ROOT" && -n "$HOST_IP" ]]; then
          info "检测到当前配置："
          echo -e "▷ Docker存储: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_RESET}"
          echo -e "▷ 服务器地址: ${COLOR_CYAN}${HOST_IP}${COLOR_RESET}"
          echo -e "▷ 控制面板端口: ${COLOR_CYAN}${WEB_PORT}${COLOR_RESET}"
          echo -e "▷ 代理服务端口: ${COLOR_CYAN}${PROXY_PORT}${COLOR_RESET}"
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

        download_clash_config
        init_clash
        ;;
      2) configure_essential ;;
      3) uninstall_services ;;
      4)
        header
        echo -e "${COLOR_CYAN}容器状态:"
        docker ps -a --filter "name=${CLASH_CONTAINER}" \
          --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
        header
        ;;
      5) update_clash ;;
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