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
VIDEO_ROOT=""
HOST_IP=""
EMBY_CONFIG_URL="https://pan.naspt.vip/d/123pan/shell/tgz/naspt-115-emby.tgz"
IMAGE_SOURCE="official"  # 新增：镜像源选择

# 定义私有镜像
declare -A DOCKER_IMAGES=(
    ["emby"]="ccr.ccs.tencentyun.com/naspt/emby:latest"
    ["cms"]="ccr.ccs.tencentyun.com/naspt/cloud-media-sync:latest"
)

# 定义官方镜像
declare -A OFFICIAL_DOCKER_IMAGES=(
    ["emby"]="linuxserver/emby:latest"
    ["cms"]="imaliang/cloud-media-sync:latest"
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
    
    # 使用stderr输出日志信息，这样不会影响函数返回值
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
  
  # 如果文件不存在，创建文件和section
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo "[$section]" > "$file"
  fi
  
  # 如果section不存在，添加section
  if ! grep -q "^\[$section\]" "$file"; then
    echo -e "\n[$section]" >> "$file"
  fi
  
  # 在指定section中查找并替换key的值，如果不存在则添加
  if grep -q "^$key=" <(sed -n "/^\[$section\]/,/^\[/p" "$file"); then
    sed -i "/^\[$section\]/,/^\[/s|^$key=.*|$key=$value|" "$file"
  else
    sed -i "/^\[$section\]/a $key=$value" "$file"
  fi
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # 从[cms]部分读取所有配置
    DOCKER_ROOT=$(get_ini_value "$CONFIG_FILE" "cms" "DOCKER_ROOT")
    VIDEO_ROOT=$(get_ini_value "$CONFIG_FILE" "cms" "VIDEO_ROOT")
    HOST_IP=$(get_ini_value "$CONFIG_FILE" "cms" "HOST_IP")
    IMAGE_SOURCE=$(get_ini_value "$CONFIG_FILE" "cms" "IMAGE_SOURCE")
    # 如果IMAGE_SOURCE为空，设置默认值
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

  # 保存所有配置到[service]部分
  set_ini_value "$CONFIG_FILE" "cms" "DOCKER_ROOT" "$DOCKER_ROOT"
  set_ini_value "$CONFIG_FILE" "cms" "VIDEO_ROOT" "$VIDEO_ROOT"
  set_ini_value "$CONFIG_FILE" "cms" "HOST_IP" "$HOST_IP"

  [[ $? -eq 0 ]] && info "配置已保存" || error "配置保存失败"
}

check_dependencies() {
  local deps=("docker" "curl" "tar")
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

  if ! curl -Is https://pan.naspt.vip --connect-timeout 3 &>/dev/null; then
    warning "外网连接异常，可能影响配置文件下载"
  fi
}

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
        if [[ ! -d "$input" ]]; then
          warning "路径不存在，尝试创建: $input"
          mkdir -p "$input" || {
            error "目录创建失败"
            continue
          }
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
    esac

    eval "$var_name='$input'"
    break
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
  [[ -z "$DOCKER_ROOT" || -z "$VIDEO_ROOT" || -z "$HOST_IP" ]] && {
    error "关键参数未配置！请先运行选项4进行配置"
    return 1
  }
  return 0
}

download_emby_config() {
  local dest="${DOCKER_ROOT}/naspt-115-emby.tgz"
  [[ -f "$dest" ]] && return

  info "下载Emby配置文件..."
  for i in {1..3}; do
    if curl -L "$EMBY_CONFIG_URL" -o "$dest" --progress-bar; then
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

init_emby() {
  check_deploy_params || exit 1

  local config_dir="${DOCKER_ROOT}/naspt-115-emby"
  mkdir -p "${config_dir}/config"

  if netstat -tuln | grep -Eq ':38096|:38920'; then
      error "端口 38096 或 38920 已被占用，请修改配置"
      exit 1
  fi

  clean_container naspt-115-emby

  info "解压配置文件..."
  tar -zxf "${DOCKER_ROOT}/naspt-115-emby.tgz" -C "${config_dir}" --strip-components=1 || {
    error "文件解压失败，可能下载损坏"
    rm -rf "$config_dir"
    exit 1
  }

  info "启动Emby容器..."
  docker run -d --restart always \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    --network bridge \
    -v "$VIDEO_ROOT:/media" \
    -v "${config_dir}/config:/config" \
    -v /etc/hosts:/etc/hosts \
    -p 38096:8096 \
    -p 38920:8920 \
    --name naspt-115-emby \
    "$(get_current_image emby)" || {
    error "Emby启动失败，查看日志：docker logs naspt-115-emby"
    exit 1
  }

  success "Emby 已启动"
  info "访问地址: ${COLOR_YELLOW}http://${HOST_IP}:38096${COLOR_RESET}"
}

init_cms() {
  check_deploy_params || exit 1

  local config_dir="${DOCKER_ROOT}/naspt-115-cms"
  mkdir -p "${config_dir}"/{config,nginx/logs,nginx/cache}

  if netstat -tuln | grep -Eq ':9527'; then
      error "端口 9527 已被占用，请修改配置"
      exit 1
  fi
  clean_container naspt-115-cms

  info "生成分类配置..."
  cat <<EOF > "${config_dir}/config/category.yaml"
movie:
  动画电影:
    cid: 3108164003358778166
    genre_ids: '16'
  华语电影:
    cid: 3108164004407354169
    original_language: 'zh,cn,bo,za'
  外语电影:
    cid: 3108164003929203511

tv:
  国漫:
    cid: 3108164001572004657
    genre_ids: '16'
    origin_country: 'CN,TW,HK'
  日番:
    cid: 3108163998325613354
    genre_ids: '16'
    origin_country: 'JP'
  纪录片:
    cid: 3108163998828929835
    genre_ids: '99'
  儿童:
    cid: 3108163999852340013
    genre_ids: '10762'
  综艺:
    cid: 3108164002117264179
    genre_ids: '10764,10767'
  国产剧:
    cid: 3108164002712855348
    origin_country: 'CN,TW,HK'
  欧美剧:
    cid: 3108164000330490670
    origin_country: 'US,FR,GB,DE,ES,IT,NL,PT,RU,UK'
  日韩剧:
    cid: 3108163999332246316
    origin_country: 'JP,KP,KR,TH,IN,SG'
  未分类:
    cid: 3108164000934470447
EOF

  info "启动CMS容器..."
  docker run -d --privileged \
    --name naspt-115-cms \
    --restart always \
    --network bridge \
    -p 9527:9527 \
    -p 9096:9096 \
    -v "${config_dir}/config:/config" \
    -v "${config_dir}/nginx/logs:/logs" \
    -v "${config_dir}/nginx/cache:/var/cache/nginx/emby" \
    -v "$VIDEO_ROOT:/media" \
    -v /etc/hosts:/etc/hosts \
    -e TZ=Asia/Shanghai \
    -e RUN_ENV=online \
    -e ADMIN_USERNAME=admin \
    -e ADMIN_PASSWORD='a123456!@' \
    -e EMBY_HOST_PORT="http://$HOST_IP:38096" \
    -e EMBY_API_KEY=d5d013c65e86428ea537006b3926737a \
    -e DONATE_CODE=CMS_HQFO2BSD_EE104D0293B84F668F7CC0B518F3AAD2 \
    "$(get_current_image cms)" || {
    error "CMS启动失败，查看日志：docker logs naspt-115-cms"
    exit 1
  }

  success "CMS 已启动"
  info "管理后台: ${COLOR_YELLOW}http://${HOST_IP}:9527${COLOR_RESET}"
  info "直连播放端: ${COLOR_YELLOW}http://${HOST_IP}:9096${COLOR_RESET}"
}

uninstall_services() {
  header
  warning "此操作将永久删除所有容器及数据！"
  read -rp "$(echo -e "${COLOR_RED}确认要卸载服务吗？(输入YES确认): ${COLOR_RESET}")" confirm
  [[ "$confirm" != "YES" ]] && { info "已取消卸载"; return; }

  clean_container naspt-115-emby
  clean_container naspt-115-cms
  rm -rf "${DOCKER_ROOT}"/naspt-115-{emby,cms}
  success "所有服务及数据已移除"
}

configure_essential() {
  while :; do
    header
    info "开始初始配置（首次运行必需）"

    safe_input "DOCKER_ROOT" "Docker数据存储路径" "${DOCKER_ROOT:-}" "path"
    safe_input "VIDEO_ROOT" "媒体库根路径" "${VIDEO_ROOT:-}" "path"
    safe_input "HOST_IP" "服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"
    safe_input "IMAGE_SOURCE" "镜像源选择(private/official)" "${IMAGE_SOURCE:-official}" "image_source"

    header
    echo -e "${COLOR_BLUE}当前配置预览："
    echo -e "▷ Docker根目录: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_BLUE}"
    echo -e "▷ 媒体库路径: ${COLOR_CYAN}${VIDEO_ROOT}${COLOR_BLUE}"
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
      DOCKER_ROOT=""
      VIDEO_ROOT=""
      HOST_IP=""
    fi
  done
}

show_menu() {
  clear
  header
  echo -e "${COLOR_GREEN} 媒体中心部署管理脚本 v2.0"
  header
  echo -e " 1. 完整部署"
  echo -e " 2. 修改配置"
  echo -e " 3. 完全卸载"
  echo -e " 4. 服务状态"
  echo -e " 0. 退出脚本"
  header
}

main() {
#  check_dependencies
  load_config

  if [[ -z "$DOCKER_ROOT" || -z "$VIDEO_ROOT" || -z "$HOST_IP" ]]; then
    warning "检测到未完成初始配置！"
    configure_essential
  fi

  while :; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    case $choice in
      1)
        header
        if [[ -n "$DOCKER_ROOT" && -n "$VIDEO_ROOT" && -n "$HOST_IP" ]]; then
          info "检测到当前配置："
          echo -e "▷ Docker存储: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_RESET}"
          echo -e "▷ 媒体库路径: ${COLOR_CYAN}${VIDEO_ROOT}${COLOR_RESET}"
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

        download_emby_config
        init_emby
        init_cms
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