#!/bin/bash

# 颜色定义
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

# 错误处理函数
handle_error() {
    error "$1"
    cleanup
    exit 1
}

# 服务配置
declare -A CONFIG_URLS=(
    ["navidrome"]="https://pan.naspt.vip/d/123pan/shell/tgz/naspt-navidrome.tgz"
    ["musictag"]="https://pan.naspt.vip/d/123pan/shell/tgz/naspt-musictag.tgz"
)

declare -A SERVICES=(
    ["navidrome"]="4533"
    ["musictag"]="8002"
    ["lyricapi"]="28883"
)

# 定义私有镜像
declare -A DOCKER_IMAGES=(
    ["navidrome"]="ccr.ccs.tencentyun.com/naspt/navidrome:latest"
    ["musictag"]="ccr.ccs.tencentyun.com/naspt/music_tag_web:latest"
    ["lyricapi"]="ccr.ccs.tencentyun.com/naspt/lyricapi:latest"
)

# 定义官方镜像
declare -A OFFICIAL_DOCKER_IMAGES=(
    ["navidrome"]="deluan/navidrome:latest"
    ["musictag"]="xhongc/music_tag_web:latest"
    ["lyricapi"]="hisatri/lyricapi:latest"
)

# 初始化默认配置
DOCKER_ROOT=""
MUSIC_ROOT=""
HOST_IP=""
CONFIG_FILE="/root/.naspt/naspt.conf"
IMAGE_SOURCE="official"  # 新增：镜像源选择

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

# 网络检查函数
check_network() {
  info "检查网络连接..."
  if ! curl -Is https://pan.naspt.vip --connect-timeout 3 &>/dev/null; then
    warning "外网连接异常，可能影响配置文件下载"
  else
    success "网络连接正常"
  fi
}

# 配置管理
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # 从[music]部分读取所有配置
        DOCKER_ROOT=$(get_ini_value "$CONFIG_FILE" "music" "DOCKER_ROOT")
        MUSIC_ROOT=$(get_ini_value "$CONFIG_FILE" "music" "MUSIC_ROOT")
        HOST_IP=$(get_ini_value "$CONFIG_FILE" "music" "HOST_IP")
        IMAGE_SOURCE=$(get_ini_value "$CONFIG_FILE" "music" "IMAGE_SOURCE")
        # 如果IMAGE_SOURCE为空，设置默认值
        [[ -z "$IMAGE_SOURCE" ]] && IMAGE_SOURCE="official"
        success "已加载配置文件"
    else
        warning "使用默认配置"
    fi
}

save_config() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    mkdir -p "$config_dir" || handle_error "无法创建配置目录"

    # 保存所有配置到[music]部分
    set_ini_value "$CONFIG_FILE" "music" "DOCKER_ROOT" "$DOCKER_ROOT"
    set_ini_value "$CONFIG_FILE" "music" "MUSIC_ROOT" "$MUSIC_ROOT"
    set_ini_value "$CONFIG_FILE" "music" "HOST_IP" "$HOST_IP"
    set_ini_value "$CONFIG_FILE" "music" "IMAGE_SOURCE" "$IMAGE_SOURCE"

    success "配置已保存"
    backup_config
}

# 配置备份
backup_config() {
    local backup_dir="/root/.naspt/backup"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/music_config_$timestamp.ini"

    mkdir -p "$backup_dir"
    cp "$CONFIG_FILE" "$backup_file"
    success "配置已备份到 $backup_file"
}

# 安全输入函数
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
      "image_source")
        if [[ ! "$input" =~ ^(private|official)$ ]]; then
          error "镜像源只能是 private 或 official"
          continue
        fi
        ;;
    esac

    eval "$var_name='$input'"
    break
  done
}

# 进度显示
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))

    printf "\r[%${completed}s%${remaining}s] %d%%" \
           "$(printf '#%.0s' $(seq 1 $completed))" \
           "$(printf ' %.0s' $(seq 1 $remaining))" \
           "$percentage"
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
        handle_error "缺少依赖: ${missing[*]}"
    fi

    if ! docker info &>/dev/null; then
        handle_error "Docker 服务未运行"
    fi
}

# 服务健康检查
check_service_health() {
    local service_name="$1"
    local max_retries=5
    local count=0

    while [ $count -lt $max_retries ]; do
        if docker ps | grep -q "$service_name"; then
            success "$service_name 服务启动成功"
            return 0
        fi
        count=$((count + 1))
        sleep 5
    done

    handle_error "$service_name 服务启动失败"
}

# 容器管理
clean_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        warning "发现残留容器: ${name}"
        if docker rm -f "$name" &>/dev/null; then
            info "已移除容器: ${name}"
        else
            handle_error "容器移除失败: ${name}"
        fi
    fi
}

# 端口检查
check_port() {
    local port="$1"
    local retries=3
    local wait_time=5

    for ((i=1; i<=retries; i++)); do
        if ! netstat -tuln | grep -q ":$port "; then
            return 0
        fi
        if [ $i -lt $retries ]; then
            warning "端口 $port 被占用，等待 ${wait_time} 秒后重试..."
            sleep $wait_time
        fi
    done

    handle_error "端口 $port 已被占用，请选择其他端口"
}

# 配置文件下载解压
download_config() {
    local service="$1"
    local dest_dir="$2"
    local url="${CONFIG_URLS[$service]}"
    local temp_file="${dest_dir}.tgz"

    if [[ -z "$url" ]]; then
        info "服务 ${service} 无需下载配置文件"
        return 0
    fi

    info "正在下载 ${service} 配置文件..."
    for i in {1..3}; do
        if curl -L "$url" -o "$temp_file" --progress-bar; then
            success "下载成功"
            break
        else
            warning "下载失败，第${i}次重试..."
            sleep 2
        fi
    done || handle_error "多次下载失败: $service"

    info "解压配置文件..."
    mkdir -p "$dest_dir" || handle_error "创建目录失败: $dest_dir"
    if ! tar -zxf "$temp_file" -C "$dest_dir" --strip-components=1; then
        handle_error "解压失败: $service"
    fi
    rm -f "$temp_file"
}
# 快速安装模式
quick_install() {
    info "开始快速安装..."

    # 创建必要目录
    mkdir -p "$DOCKER_ROOT" "$MUSIC_ROOT" || handle_error "目录创建失败"
    create_music_structure

    # 依次启动服务
    local total_services=3
    local current_service=0

    init_navidrome
    show_progress $((++current_service)) $total_services

    init_musictag
    show_progress $((++current_service)) $total_services

    init_lyricapi
    show_progress $((++current_service)) $total_services

    show_service_info
}


# 服务初始化函数
init_navidrome() {
    check_port "${SERVICES[navidrome]}"
    local data_dir="${DOCKER_ROOT}/naspt-navidrome"

    clean_container naspt-navidrome
    download_config "navidrome" "$data_dir"

    info "正在启动 Navidrome..."
    docker run -d --name naspt-navidrome \
        --restart always \
        -p "${SERVICES[navidrome]}":4533 \
        -e ND_SCANSCHEDULE=1h \
        -e ND_LOGLEVEL=info \
        -v "${data_dir}/data:/data" \
        -v "${MUSIC_ROOT}/links:/music" \
        "$(get_current_image navidrome)"

    check_service_health naspt-navidrome
}

init_musictag() {
    check_port "${SERVICES[musictag]}"
    local data_dir="${DOCKER_ROOT}/naspt-musictag"

    clean_container naspt-musictag
    download_config "musictag" "$data_dir"

    info "正在启动 MusicTag..."
    docker run -d --name naspt-musictag \
        --restart always \
        -p "${SERVICES[musictag]}":8002 \
        -v "${MUSIC_ROOT}:/app/media" \
        -v "${data_dir}:/app/data" \
        "$(get_current_image musictag)"

    check_service_health naspt-musictag
}

init_lyricapi() {
    check_port "${SERVICES[lyricapi]}"
    local data_dir="${DOCKER_ROOT}/naspt-lyricapi"

    clean_container naspt-lyricapi

    info "正在启动 LyricAPI..."
    docker run -d --name naspt-lyricapi \
        --restart always \
        -p "${SERVICES[lyricapi]}":28883 \
        -v "${MUSIC_ROOT}/links:/music" \
        "$(get_current_image lyricapi)"

    check_service_health naspt-lyricapi
}

# 创建音乐目录结构
create_music_structure() {
    info "创建音乐目录结构..."
    mkdir -p "${MUSIC_ROOT}/"{downloads,links,cache}
    success "音乐目录结构创建完成"
}



# 显示服务信息
show_service_info() {
    header
    success "所有服务部署完成"
    info "访问地址:"
    echo -e "Navidrome: http://${HOST_IP}:${SERVICES[navidrome]}"
    echo -e "MusicTag: http://${HOST_IP}:${SERVICES[musictag]}"
    echo -e "LyricAPI: http://${HOST_IP}:${SERVICES[lyricapi]}"
    echo -e "Navidrome 默认账号密码: admin/a123456!@"
    header
}

# 清理函数
cleanup() {
    info "执行清理..."
    rm -f *.tgz
    docker system prune -f >/dev/null 2>&1
    success "清理完成"
}

# 配置向导
configure_essential() {
    header
    info "开始初始配置"

    safe_input "DOCKER_ROOT" "Docker数据存储路径" "${DOCKER_ROOT:-}" "path"
    safe_input "MUSIC_ROOT" "音乐库根路径" "${MUSIC_ROOT:-}" "path"
    safe_input "HOST_IP" "服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"
    safe_input "IMAGE_SOURCE" "镜像源选择(private/official)" "${IMAGE_SOURCE:-official}" "image_source"

    header
    echo -e "${COLOR_BLUE}当前配置预览："
    echo -e "▷ Docker根目录: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_BLUE}"
    echo -e "▷ 音乐库路径: ${COLOR_CYAN}${MUSIC_ROOT}${COLOR_BLUE}"
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
    fi
}

# 检查部署参数
check_deploy_params() {
  [[ -z "$DOCKER_ROOT" || -z "$MUSIC_ROOT" || -z "$HOST_IP" ]] && {
    error "关键参数未配置！请先运行配置向导"
    return 1
  }
  return 0
}

# 卸载服务
uninstall_services() {
  header
  warning "此操作将永久删除所有容器及数据！"
  read -rp "$(echo -e "${COLOR_RED}确认要卸载服务吗？(输入YES确认): ${COLOR_RESET}")" confirm
  [[ "$confirm" != "YES" ]] && { info "已取消卸载"; return; }

  clean_container naspt-navidrome
  clean_container naspt-musictag
  clean_container naspt-lyricapi
  rm -rf "${DOCKER_ROOT}"/naspt-{navidrome,musictag,lyricapi}
  success "所有服务及数据已移除"
}

# 主菜单
show_menu() {
    clear
    header
    echo -e "${COLOR_GREEN} NASPT 音乐服务管理脚本 v2.0"
    header
    echo -e " 1. 完整部署"
    echo -e " 2. 修改配置"
    echo -e " 3. 单独部署服务"
    echo -e " 4. 查看服务状态"
    echo -e " 5. 完全卸载"
    echo -e " 0. 退出脚本"
    header
}

# 主函数
main() {
    check_dependencies
    check_network
    load_config

    if [[ -z "$DOCKER_ROOT" || -z "$MUSIC_ROOT" || -z "$HOST_IP" ]]; then
        warning "检测到未完成初始配置！"
        configure_essential
    fi

    while :; do
        show_menu
        read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

        case $choice in
            1)
                header
                if [[ -n "$DOCKER_ROOT" && -n "$MUSIC_ROOT" && -n "$HOST_IP" ]]; then
                    info "检测到当前配置："
                    echo -e "▷ Docker存储: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_RESET}"
                    echo -e "▷ 音乐库路径: ${COLOR_CYAN}${MUSIC_ROOT}${COLOR_RESET}"
                    echo -e "▷ 服务器地址: ${COLOR_CYAN}${HOST_IP}${COLOR_RESET}"
                    echo -e "▷ 镜像源: ${COLOR_CYAN}${IMAGE_SOURCE}${COLOR_RESET}"
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

                quick_install
                ;;
            2) 
                configure_essential 
                ;;
            3)
                header
                echo -e "请选择要部署的服务："
                echo -e " 1. Navidrome"
                echo -e " 2. MusicTag"
                echo -e " 3. LyricAPI"
                read -rp "$(echo -e "${COLOR_CYAN}请输入编号: ${COLOR_RESET}")" service_choice
                case $service_choice in
                    1) 
                        check_deploy_params && init_navidrome 
                        ;;
                    2) 
                        check_deploy_params && init_musictag 
                        ;;
                    3) 
                        check_deploy_params && init_lyricapi 
                        ;;
                    *) 
                        error "无效选择" 
                        ;;
                esac
                ;;
            4)
                header
                echo -e "${COLOR_CYAN}运行中的容器："
                docker ps --filter "name=naspt-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                header
                ;;
            5)
                uninstall_services
                ;;
            0)
                cleanup
                success "感谢使用，再见！"
                exit 0
                ;;
            *)
                error "无效选项"
                ;;
        esac

        read -rp "$(echo -e "${COLOR_CYAN}按 Enter 继续...${COLOR_RESET}")"
    done
}

# 启动脚本
main