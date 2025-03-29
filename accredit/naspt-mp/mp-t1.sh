#!/bin/bash

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



# 服务配置
declare -A CONFIG_URLS=(
    ["tr"]="https://alist.naspt.vip/d/123pan/shell/tgz/naspt-tr.tgz"
    ["emby"]="https://alist.naspt.vip/d/123pan/shell/tgz/naspt-emby.tgz"
    ["qb"]="https://alist.naspt.vip/d/123pan/shell/tgz/naspt-qb.tgz"
    ["csf"]="https://alist.naspt.vip/d/123pan/shell/tgz/naspt-csf.tgz"
    ["mp"]="https://alist.naspt.vip/d/123pan/shell/tgz/naspt-mpv2.tgz"
)

# 镜像源配置
IMAGE_SOURCE="official"  # 默认使用官方镜像

# 私有镜像配置
declare -A DOCKER_IMAGES=(
    ["tr"]="ccr.ccs.tencentyun.com/naspt/transmission:4.0.5"
    ["emby"]="ccr.ccs.tencentyun.com/naspt/embyserver:latest"
    ["qb"]="ccr.ccs.tencentyun.com/naspt/qbittorrent:4.6.4"
    ["csf"]="ccr.ccs.tencentyun.com/naspt/chinesesubfinder:latest"
    ["mp"]="ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest"
)

# 官方镜像配置
declare -A OFFICIAL_DOCKER_IMAGES=(
    ["tr"]="linuxserver/transmission:4.0.5"
    ["emby"]="amilys/embyserver:latest"
    ["qb"]="linuxserver/qbittorrent:4.6.4"
    ["csf"]="allanpk716/chinesesubfinder:latest"
    ["mp"]="jxxghp/moviepilot-v2:latest"
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

# 初始化默认配置
DOCKER_ROOT=""
MEDIA_ROOT=""
HOST_IP=""
TR_PORT="9091"
EMBY_PORT="8096"
QB_PORT="9000"
CSF_PORT="19035"
MP_PORT="3000"
CRON_SCHEDULE="0 3 * * *"
CONFIG_FILE="/root/.naspt/naspt.conf"

## 配置管理
#load_config() {
#  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || warning "使用默认配置"
#}

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
    # 从[mp]部分读取所有配置
    DOCKER_ROOT=$(get_ini_value "$CONFIG_FILE" "mp" "DOCKER_ROOT")
    MEDIA_ROOT=$(get_ini_value "$CONFIG_FILE" "mp" "MEDIA_ROOT")
    HOST_IP=$(get_ini_value "$CONFIG_FILE" "mp" "HOST_IP")
    TR_PORT=$(get_ini_value "$CONFIG_FILE" "mp" "TR_PORT")
    EMBY_PORT=$(get_ini_value "$CONFIG_FILE" "mp" "EMBY_PORT")
    QB_PORT=$(get_ini_value "$CONFIG_FILE" "mp" "QB_PORT")
    CSF_PORT=$(get_ini_value "$CONFIG_FILE" "mp" "CSF_PORT")
    MP_PORT=$(get_ini_value "$CONFIG_FILE" "mp" "MP_PORT")
    IMAGE_SOURCE=$(get_ini_value "$CONFIG_FILE" "mp" "IMAGE_SOURCE")
    IMAGE_SOURCE=${IMAGE_SOURCE:-official}
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

  # 保存所有配置到[mp]部分
  set_ini_value "$CONFIG_FILE" "mp" "DOCKER_ROOT" "$DOCKER_ROOT"
  set_ini_value "$CONFIG_FILE" "mp" "MEDIA_ROOT" "$MEDIA_ROOT"
  set_ini_value "$CONFIG_FILE" "mp" "HOST_IP" "$HOST_IP"
  set_ini_value "$CONFIG_FILE" "mp" "TR_PORT" "$TR_PORT"
  set_ini_value "$CONFIG_FILE" "mp" "EMBY_PORT" "$EMBY_PORT"
  set_ini_value "$CONFIG_FILE" "mp" "QB_PORT" "$QB_PORT"
  set_ini_value "$CONFIG_FILE" "mp" "IMAGE_SOURCE" "$IMAGE_SOURCE"
  set_ini_value "$CONFIG_FILE" "mp" "CSF_PORT" "$CSF_PORT"
  set_ini_value "$CONFIG_FILE" "mp" "MP_PORT" "$MP_PORT"
  
  [[ $? -eq 0 ]] && info "配置已保存" || error "配置保存失败"
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
      "credential")
        if [[ -z "$input" ]]; then
          error "凭证不能为空"
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
      error "端口 $1  已被占用"
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

# 服务初始化
init_tr() {
  check_port "$TR_PORT" || return 1
  local data_dir="${DOCKER_ROOT}/naspt-tr"

  clean_container naspt-tr
  download_config "tr" "$data_dir" || return 1

  info "正在启动 Transmission..."
  docker run -d --name naspt-tr \
    --restart always \
    --privileged=true \
    --network bridge \
    -p "$TR_PORT":9091 \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    -e USER=admin -e PASS=a123456!@ \
    -e 'TRANSMISSION_WEB_HOME'='/config/2/src' \
    -v "${data_dir}/config:/config" \
    -v "${MEDIA_ROOT}:/media" \
    $(get_current_image "tr") || {
    error "Transmission 启动失败"
    return 1
  }
}




init_emby() {
  check_port "$EMBY_PORT" || return 1
  local data_dir="${DOCKER_ROOT}/naspt-emby"

  clean_container naspt-emby
  download_config "emby" "$data_dir" || return 1

  info "正在启动 Emby..."
  docker run -d --name naspt-emby \
    --privileged \
    --restart always \
    --network bridge \
    -p "$EMBY_PORT":8096 \
    --device /dev/dri:/dev/dri \
    -e UID=0 -e GID=0 -e UMASK=022 \
    -v "${data_dir}/config:/config" \
    -v "${MEDIA_ROOT}:/media" \
    $(get_current_image "emby") || {
    error "Emby 启动失败"
    return 1
  }
}

init_qb() {
  check_port "$QB_PORT" || return 1
  local data_dir="${DOCKER_ROOT}/naspt-qb"

  clean_container naspt-qb
  download_config "qb" "$data_dir" || return 1

  info "正在启动 qBittorrent..."
  docker run -d --name naspt-qb \
    --restart always \
    --network bridge \
    -p "$QB_PORT":9000 \
    -e WEBUI_PORT=9000 \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    -e SavePatch="/media/downloads" \
    -e TempPatch="/media/downloads" \
    -v "${data_dir}/config:/config" \
    -v "${MEDIA_ROOT}:/media" \
    $(get_current_image "qb") || {
    error "qBittorrent 启动失败"
    return 1
  }
}

init_csf() {
  check_port "$CSF_PORT" || return 1
  local data_dir="${DOCKER_ROOT}/naspt-csf"

  clean_container naspt-csf
  download_config "csf" "$data_dir" || return 1

  info "正在启动 ChineseSubFinder..."
  docker run -d --name naspt-csf \
    --restart always \
    --network bridge \
    --privileged \
    -p "$CSF_PORT":19035 \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    -v "${data_dir}/config:/config" \
     -v "${data_dir}/cache:/app/cache" \
    -v "${MEDIA_ROOT}:/media" \
    $(get_current_image "csf") || {
    error "ChineseSubFinder 启动失败"
    return 1
  }
}

init_mp() {
  check_port "$MP_PORT" || return 1
  local data_dir="${DOCKER_ROOT}/naspt-mpv2"

  clean_container naspt-mpv2
  download_config "mp" "$data_dir" || return 1

  info "正在下载最新HOST"
  curl -Ls  https://pan.naspt.vip/d/123pan/shell/tgz/hosts_new.txt >> ${data_dir}/hosts_new.txt
  info "下载成功"
  info "配置自动更新HOST"
  CRON_COMMAND="curl -Ls https://pan.naspt.vip/d/123pan/shell/tgz/hosts_new.txt >> ${data_dir}/hosts_new.txt"
  CRON_JOB="${CRON_SCHEDULE} ${CRON_COMMAND}"
  # 检查 cron 任务是否存在
  if crontab -l 2>/dev/null | grep -F --quiet "$CRON_COMMAND"; then
      echo "Cron 任务已存在，无需重复添加。"
  else
      # 在这里添加你的 cron 任务（如果需要）
      (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  fi


  # 创建媒体目录结构
  declare -A categories=(
    ["剧集"]="国产剧集 日韩剧集 欧美剧集 综艺节目 纪录片 儿童剧集 纪录影片 港台剧集 南亚剧集"
    ["动漫"]="国产动漫 欧美动漫 日本番剧"
    ["电影"]="儿童电影 动画电影 国产电影 日韩电影 欧美电影 歌舞电影 港台电影 南亚电影"
  )

  info "创建媒体目录结构..."
  for category in "${!categories[@]}"; do
    for subcategory in ${categories[$category]}; do
      mkdir -p "${MEDIA_ROOT}/downloads/${category}/${subcategory}"
      mkdir -p "${MEDIA_ROOT}/links/${category}/${subcategory}"
    done
  done

  info "正在启动 MoviePilot..."
  docker run -d --name naspt-mpv2 \
    --restart always \
    --privileged \
    --network bridge \
    -p "$MP_PORT":3000 \
    -p 3001:3001 \
    -e TZ=Asia/Shanghai \
    -e SUPERUSER=admin \
    -e API_TOKEN=nasptnasptnasptnasptnaspt \
    -e AUTO_UPDATE_RESOURCE=true\
    -e MOVIEPILOT_AUTO_UPDATE=release\
    -e AUTH_SITE=icc2022,leaves \
    -e ICC2022_UID="24730" \
    -e ICC2022_PASSKEY="49c421073514d4d981a0cbc4174f4b23" \
    -e LEAVES_UID="10971" \
    -e LEAVES_PASSKEY="e0405a9d0de9e3b112ef78ac3d9c7975" \
    -e SUPERUSER="admin" \
    -v "${data_dir}/config:/config" \
    -v "${MEDIA_ROOT}:/media" \
    -v "${DOCKER_ROOT}/naspt-qb/config/qBittorrent/BT_backup:/qbtr" \
    -v "${data_dir}/core:/moviepilot/.cache/ms-playwright" \
    -v "${data_dir}/hosts_new.txt:/etc/hosts:ro" \
    $(get_current_image "mp") || {
    error "MoviePilot 启动失败"
    return 1
  }
}
uninstall_services() {
  header
  warning "此操作将永久删除所有容器及数据！"
  read -rp "$(echo -e "${COLOR_RED}确认要卸载服务吗？(输入Y确认): ${COLOR_RESET}")" confirm
  [[ "$confirm" != "Y" ]] && { info "已取消卸载"; return; }
  clean_container naspt-tr
  clean_container naspt-emby
  clean_container naspt-qb
  clean_container naspt-csf
  clean_container naspt-mpv2
  rm -rf "${DOCKER_ROOT}/naspt-tr"
  rm -rf "${DOCKER_ROOT}/naspt-emby"
  rm -rf "${DOCKER_ROOT}/naspt-qb"
  rm -rf "${DOCKER_ROOT}/naspt-csf"
  rm -rf "${DOCKER_ROOT}/naspt-mpv2"
  success "所有服务及数据已移除"
}

# 更新服务
update_services() {
  header
  warning "此操作将更新所有服务到最新版本！"
  read -rp "$(echo -e "${COLOR_YELLOW}确认要更新服务吗？(输入Y确认): ${COLOR_RESET}")" confirm
  [[ "$confirm" != "Y" ]] && { info "已取消更新"; return; }

  # 更新Transmission
  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-tr$"; then
    info "更新 Transmission..."
    docker pull ${DOCKER_IMAGES["tr"]} && {
      clean_container naspt-tr
      docker run -d --name naspt-tr \
        --restart always \
        --privileged=true \
        --network bridge \
        -p "$TR_PORT":9091 \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -e TZ=Asia/Shanghai \
        -e USER=admin -e PASS=a123456!@ \
        -e 'TRANSMISSION_WEB_HOME'='/config/2/src' \
        -v "${DOCKER_ROOT}/naspt-tr/config:/config" \
        -v "${MEDIA_ROOT}:/media" \
        ${DOCKER_IMAGES["tr"]}
    }
  fi

  # 更新Emby
  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-emby$"; then
    info "更新 Emby..."
    docker pull ${DOCKER_IMAGES["emby"]} && {
      clean_container naspt-emby
      docker run -d --name naspt-emby \
        --privileged \
        --restart always \
        --network bridge \
        -p "$EMBY_PORT":8096 \
        --device /dev/dri:/dev/dri \
        -e UID=0 -e GID=0 -e UMASK=022 \
        -v "${DOCKER_ROOT}/naspt-emby/config:/config" \
        -v "${MEDIA_ROOT}:/media" \
        ${DOCKER_IMAGES["emby"]}
    }
  fi

  # 更新qBittorrent
  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-qb$"; then
    info "更新 qBittorrent..."
    docker pull ${DOCKER_IMAGES["qb"]} && {
      clean_container naspt-qb
      docker run -d --name naspt-qb \
        --restart always \
        --network bridge \
        -p "$QB_PORT":9000 \
        -e WEBUI_PORT=9000 \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -e TZ=Asia/Shanghai \
        -e SavePatch="/media/downloads" \
        -e TempPatch="/media/downloads" \
        -v "${DOCKER_ROOT}/naspt-qb/config:/config" \
        -v "${MEDIA_ROOT}:/media" \
        ${DOCKER_IMAGES["qb"]}
    }
  fi

  # 更新ChineseSubFinder
  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-csf$"; then
    info "更新 ChineseSubFinder..."
    docker pull ${DOCKER_IMAGES["csf"]} && {
      clean_container naspt-csf
      docker run -d --name naspt-csf \
        --restart always \
        --network bridge \
        --privileged \
        -p "$CSF_PORT":19035 \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -v "${DOCKER_ROOT}/naspt-csf/config:/config" \
        -v "${DOCKER_ROOT}/naspt-csf/cache:/app/cache" \
        -v "${MEDIA_ROOT}:/media" \
        ${DOCKER_IMAGES["csf"]}
    }
  fi

  # 更新MoviePilot
  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-mpv2$"; then
    info "更新 MoviePilot..."
    docker pull ${DOCKER_IMAGES["mp"]} && {
      clean_container naspt-mpv2
      docker run -d --name naspt-mpv2 \
        --restart always \
        --privileged \
        --network bridge \
        -p "$MP_PORT":3000 \
        -p 3001:3001 \
        -e TZ=Asia/Shanghai \
        -e SUPERUSER=admin \
        -e API_TOKEN=nasptnasptnasptnasptnaspt \
        -e AUTO_UPDATE_RESOURCE=false \
        -e MOVIEPILOT_AUTO_UPDATE=false \
        -e AUTH_SITE=icc2022,leaves \
        -e ICC2022_UID="24730" \
        -e ICC2022_PASSKEY="49c421073514d4d981a0cbc4174f4b23" \
        -e LEAVES_UID="10971" \
        -e LEAVES_PASSKEY="e0405a9d0de9e3b112ef78ac3d9c7975" \
        -e SUPERUSER="admin" \
        -v "${DOCKER_ROOT}/naspt-mpv2/config:/config" \
        -v "${MEDIA_ROOT}:/media" \
        -v "${DOCKER_ROOT}/naspt-qb/config/qBittorrent/BT_backup:/qbtr" \
        -v "${DOCKER_ROOT}/naspt-mpv2/core:/moviepilot/.cache/ms-playwright" \
        -v "${DOCKER_ROOT}/naspt-mpv2/hosts_new.txt:/etc/hosts:ro" \
        ${DOCKER_IMAGES["mp"]}
    }
  fi

  success "所有服务更新完成"
  info "访问地址:"
  echo -e "Transmission: http://${HOST_IP}:${TR_PORT}"
  echo -e "Emby: http://${HOST_IP}:${EMBY_PORT}"
  echo -e "qBittorrent: http://${HOST_IP}:${QB_PORT}"
  echo -e "MoviePilot: http://${HOST_IP}:${MP_PORT}"
  echo -e "ChineseSubFinder: http://${HOST_IP}:${CSF_PORT}"
  echo -e "所有站点账号密码都是admin  a123456!@"
}


# 配置向导
configure_essential() {
  while :; do
    header
    info "开始初始配置"

    safe_input "DOCKER_ROOT" "Docker数据路径" "$DOCKER_ROOT" "path"
    safe_input "MEDIA_ROOT" "Media媒体库路径" "$MEDIA_ROOT" "path"
    safe_input "HOST_IP" "NAS IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"
    safe_input "TR_PORT" "Transmission端口" "$TR_PORT" "port"
    safe_input "EMBY_PORT" "Emby端口" "$EMBY_PORT" "port"
    safe_input "QB_PORT" "qBittorrent端口" "$QB_PORT" "port"
    safe_input "CSF_PORT" "ChineseSubFinder端口" "$CSF_PORT" "port"
    safe_input "MP_PORT" "MoviePilot端口" "$MP_PORT" "port"

    header
    echo -e "请选择镜像源:"
    echo -e "1. 官方镜像 (默认)"
    echo -e "2. 私有镜像"
    read -rp "$(echo -e "${COLOR_CYAN}请选择 (1/2): ${COLOR_RESET}")" image_choice
    case "$image_choice" in
      2) IMAGE_SOURCE="private" ;;
      *) IMAGE_SOURCE="official" ;;
    esac

    header
    echo -e "${COLOR_BLUE}配置预览："
    echo -e "▷ Docker目录: ${COLOR_CYAN}${DOCKER_ROOT}"
    echo -e "▷ 媒体库路径: ${COLOR_CYAN}${MEDIA_ROOT}"
    echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}"
    echo -e "▷ 服务端口列表:"
    echo -e "  - Transmission: ${TR_PORT}"
    echo -e "  - Emby: ${EMBY_PORT}"
    echo -e "  - qBittorrent: ${QB_PORT}"
    echo -e "  - ChineseSubFinder: ${CSF_PORT}"
    echo -e "  - MoviePilot: ${MP_PORT}"
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
  echo -e "${COLOR_GREEN} 媒体服务管理脚本 v2.0"
  header
  echo -e " 1. 完整部署所有服务"
  echo -e " 2. 配置参数设置"
  echo -e " 3. 单独部署服务"
  echo -e " 4. 查看服务状态"
  echo -e " 5. 完全卸载"
  echo -e " 6. 更新服务"
  echo -e " 0. 退出脚本"
  header
}

# 主流程
main() {
  check_dependencies
  load_config

  if [[ -z "$DOCKER_ROOT" || -z "$MEDIA_ROOT" || -z "$HOST_IP" ]]; then
    warning "检测到未完成初始配置！"
    configure_essential
  fi

  while :; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    case $choice in
      1)
        init_tr && init_emby && init_qb && init_csf && init_mp
        success "所有服务部署完成"
        info "访问地址:"
        echo -e "Transmission: http://${HOST_IP}:${TR_PORT}"
        echo -e "Emby: http://${HOST_IP}:${EMBY_PORT}"
        echo -e "qBittorrent: http://${HOST_IP}:${QB_PORT}"
        echo -e "MoviePilot: http://${HOST_IP}:${MP_PORT}"
        echo -e "ChineseSubFinder: http://${HOST_IP}:${CSF_PORT}"
        echo -e "所有站点账号密码都是admin  a123456!@"
        ;;
      2)
        configure_essential
        ;;
      3)
        header
        echo -e "请选择要部署的服务："
        echo -e " 1. Transmission"
        echo -e " 2. Emby"
        echo -e " 3. qBittorrent"
        echo -e " 4. ChineseSubFinder"
        echo -e " 5. MoviePilot"
        read -p "请输入编号: " service_choice
        case $service_choice in
          1) init_tr ;;
          2) init_emby ;;
          3) init_qb ;;
          4) init_csf ;;
          5) init_mp ;;
          *) error "无效选择" ;;
        esac
        ;;
      4)
        header
        echo -e "${COLOR_CYAN}运行中的容器："
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        header
        ;;
      5)
        header
        uninstall_services
        success "所有服务已卸载"
        ;;
      6)
        header
        update_services
        success "所有服务已更新"
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