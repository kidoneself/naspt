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
    ["navidrome"]="https://pan.naspt.vip/d/123pan/shell/naspt-music/naspt-navidrome.tgz"
    ["musictag"]="https://pan.naspt.vip/d/123pan/shell/naspt-music/naspt-musictag.tgz"
)

declare -A SERVICES=(
    ["navidrome"]="4533"
    ["musictag"]="8002"
    ["lyricapi"]="28883"
)

# 初始化默认配置
DOCKER_ROOT=""
MUSIC_ROOT=""
HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)
CONFIG_FILE="/root/.naspt/naspt-music.conf"


# 网络检查
check_network() {
    info "检查网络连接..."
    if ! ping -c 1 114.114.114.114 >/dev/null 2>&1; then
        warning "网络连接不稳定，请检查网络设置"
    fi
}

# 配置管理
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        success "已加载配置文件"
    else
        warning "使用默认配置"
    fi
}

save_config() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    mkdir -p "$config_dir" || handle_error "无法创建配置目录"

    cat > "$CONFIG_FILE" <<EOF
DOCKER_ROOT="$DOCKER_ROOT"
MUSIC_ROOT="$MUSIC_ROOT"
HOST_IP="$HOST_IP"
EOF

    success "配置已保存"
    backup_config
}

# 配置备份
backup_config() {
    local backup_dir="/root/.naspt/backup"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    mkdir -p "$backup_dir"
    tar -czf "$backup_dir/music_config_$timestamp.tar.gz" -C "$(dirname $CONFIG_FILE)" "$(basename $CONFIG_FILE)"
    success "配置已备份到 $backup_dir/music_config_$timestamp.tar.gz"
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
        ccr.ccs.tencentyun.com/naspt/navidrome:latest

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
        ccr.ccs.tencentyun.com/naspt/music_tag_web:latest

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
        ccr.ccs.tencentyun.com/naspt/lyricapi:latest

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

    read -rp "$(echo -e "${COLOR_CYAN}Docker数据路径 (默认: $DOCKER_ROOT): ${COLOR_RESET}")" input
    DOCKER_ROOT=${input:-$DOCKER_ROOT}

    read -rp "$(echo -e "${COLOR_CYAN}音乐库路径 (默认: $MUSIC_ROOT): ${COLOR_RESET}")" input
    MUSIC_ROOT=${input:-$MUSIC_ROOT}

    read -rp "$(echo -e "${COLOR_CYAN}服务器IP (默认: $HOST_IP): ${COLOR_RESET}")" input
    HOST_IP=${input:-$HOST_IP}

    save_config
}

# 主菜单
show_menu() {
    clear
    header
    echo -e "${COLOR_GREEN} NASPT 音乐服务管理脚本 v2.0"
    header
    echo -e " 1. 自定义配置部署"
    echo -e " 2. 单独部署服务"
    echo -e " 3. 查看服务状态"
    echo -e " 4. 完全卸载"
    echo -e " 0. 退出脚本"
    header
}

# 主函数
main() {
#    setup_logging
    check_dependencies
    check_network
    load_config

    while :; do
        show_menu
        read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

        case $choice in
            1)
                configure_essential
                quick_install
                ;;
            2)
                header
                echo -e "请选择要部署的服务："
                echo -e " 1. Navidrome"
                echo -e " 2. MusicTag"
                echo -e " 3. LyricAPI"
                read -rp "请输入编号: " service_choice
                case $service_choice in
                    1) init_navidrome ;;
                    2) init_musictag ;;
                    3) init_lyricapi ;;
                    *) error "无效选择" ;;
                esac
                ;;
            3)
                header
                echo -e "${COLOR_CYAN}运行中的容器："
                docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                header
                ;;
            4)
                clean_container naspt-navidrome
                clean_container naspt-musictag
                clean_container naspt-lyricapi
                success "所有服务已卸载"
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