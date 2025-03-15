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
    ["tr"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-tr.tgz"
    ["emby"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-emby.tgz"
    ["qb"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-qb.tgz"
    ["csf"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-csf.tgz"
    ["mp"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-mpv2.tgz"
)

# 初始化默认配置
DOCKER_ROOT="/volume1/docker"
MEDIA_ROOT="/volume1/media"
HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)
TR_PORT="9091"
EMBY_PORT="8096"
QB_PORT="9000"
CSF_PORT="19035"
MP_PORT="3000"
PROXY_HOST="http://47.239.17.34:7890"
CRON_SCHEDULE="0 3 * * *"
CONFIG_FILE="/root/.naspt/naspt-t1.conf"
LOG_DIR="/var/log/naspt"

# 设置日志
setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_DIR/install.log")
    exec 2> >(tee -a "$LOG_DIR/error.log")
}

# 系统资源检查
check_system_resources() {
    info "检查系统资源..."
    local min_memory=2048
    local min_disk=10240
    
    local available_memory=$(free -m | awk '/Mem:/ {print $2}')
    if [ "$available_memory" -lt "$min_memory" ]; then
        warning "系统内存不足，建议至少 ${min_memory}MB 内存"
    fi
    
    local available_space=$(df -m "$DOCKER_ROOT" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt "$min_disk" ]; then
        warning "磁盘空间不足，建议至少 ${min_disk}MB 可用空间"
    fi
}

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
MEDIA_ROOT="$MEDIA_ROOT"
HOST_IP="$HOST_IP"
TR_PORT="$TR_PORT"
EMBY_PORT="$EMBY_PORT"
QB_PORT="$QB_PORT"
CSF_PORT="$CSF_PORT"
MP_PORT="$MP_PORT"
EOF
    
    success "配置已保存"
    backup_config
}

# 配置备份
backup_config() {
    local backup_dir="/root/.naspt/backup"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir"
    tar -czf "$backup_dir/config_$timestamp.tar.gz" -C "$(dirname $CONFIG_FILE)" "$(basename $CONFIG_FILE)"
    success "配置已备份到 $backup_dir/config_$timestamp.tar.gz"
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

# 服务初始化函数
init_tr() {
    check_port "$TR_PORT"
    local data_dir="${DOCKER_ROOT}/naspt-tr"

    clean_container naspt-tr
    download_config "tr" "$data_dir"

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
        ccr.ccs.tencentyun.com/naspt/transmission:4.0.5

    check_service_health naspt-tr
}

init_emby() {
    check_port "$EMBY_PORT"
    local data_dir="${DOCKER_ROOT}/naspt-emby"

    clean_container naspt-emby
    download_config "emby" "$data_dir"

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
        ccr.ccs.tencentyun.com/naspt/embyserver:beta

    check_service_health naspt-emby
}

init_qb() {
    check_port "$QB_PORT"
    local data_dir="${DOCKER_ROOT}/naspt-qb"

    clean_container naspt-qb
    download_config "qb" "$data_dir"

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
        ccr.ccs.tencentyun.com/naspt/qbittorrent:4.6.4

    check_service_health naspt-qb
}

init_csf() {
    check_port "$CSF_PORT"
    local data_dir="${DOCKER_ROOT}/naspt-csf"

    clean_container naspt-csf
    download_config "csf" "$data_dir"

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
        ccr.ccs.tencentyun.com/naspt/chinesesubfinder:latest

    check_service_health naspt-csf
}

init_mp() {
    check_port "$MP_PORT"
    local data_dir="${DOCKER_ROOT}/naspt-mpv2"

    clean_container naspt-mpv2
    download_config "mp" "$data_dir"

    info "正在下载最新HOST"
    curl -Ls https://pan.naspt.vip/d/123pan/shell/naspt-mp/hosts_new.txt > "${data_dir}/hosts_new.txt"
    success "HOST下载成功"

    info "配置自动更新HOST"
    setup_cron_job

    create_media_structure

    info "正在启动 MoviePilot..."
    docker run -d --name naspt-mpv2 \
        --restart always \
        --privileged \
        --network bridge \
        -p "$MP_PORT":3000 \
        -p 3001:3001 \
        -e TZ=Asia/Shanghai \
        -e SUPERUSER=admin \
        -e API_TOKEN=nasptnasptnasptnaspt \
        -e AUTO_UPDATE_RESOURCE=false \
        -e MOVIEPILOT_AUTO_UPDATE=false \
        -e AUTH_SITE=icc2022,leaves \
        -e ICC2022_UID="24730" \
        -e ICC2022_PASSKEY="49c421073514d4d981a0cbc4174f4b23" \
        -e LEAVES_UID="10971" \
        -e LEAVES_PASSKEY="e0405a9d0de9e3b112ef78ac3d9c7975" \
        -v "${data_dir}/config:/config" \
        -v "${MEDIA_ROOT}:/media" \
        -v "${DOCKER_ROOT}/naspt-qb/config/qBittorrent/BT_backup:/qbtr" \
        -v "${data_dir}/core:/moviepilot/.cache/ms-playwright" \
        -v "${data_dir}/hosts_new.txt:/etc/hosts:ro" \
        ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest

    check_service_health naspt-mpv2
}

# 创建媒体目录结构
create_media_structure() {
    info "创建媒体目录结构..."
    declare -A categories=(
        ["剧集"]="国产剧集 日韩剧集 欧美剧集 综艺节目 纪录片 儿童剧集 纪录影片 港台剧集 南亚剧集"
        ["动漫"]="国产动漫 欧美动漫 日本番剧"
        ["电影"]="儿童电影 动画电影 国产电影 日韩电影 欧美电影 歌舞电影 港台电影 南亚电影"
    )

    for category in "${!categories[@]}"; do
        for subcategory in ${categories[$category]}; do
            mkdir -p "${MEDIA_ROOT}/downloads/${category}/${subcategory}"
            mkdir -p "${MEDIA_ROOT}/links/${category}/${subcategory}"
        done
    done
    success "媒体目录结构创建完成"
}

# 设置定时任务
setup_cron_job() {
    CRON_COMMAND="curl -Ls https://pan.naspt.vip/d/123pan/shell/naspt-mp/hosts_new.txt > ${DOCKER_ROOT}/naspt-mpv2/hosts_new.txt"
    CRON_JOB="${CRON_SCHEDULE} ${CRON_COMMAND}"
    
    if crontab -l 2>/dev/null | grep -F --quiet "$CRON_COMMAND"; then
        info "Cron 任务已存在"
    else
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        success "已添加自动更新任务"
    fi
}

# 快速安装模式
quick_install() {
    info "开始快速安装..."
    
    # 创建必要目录
    mkdir -p "$DOCKER_ROOT" "$MEDIA_ROOT" || handle_error "目录创建失败"
    
    # 依次启动服务
    local total_services=5
    local current_service=0
    
    init_tr
    show_progress $((++current_service)) $total_services
    
    init_emby
    show_progress $((++current_service)) $total_services
    
    init_qb
    show_progress $((++current_service)) $total_services
    
    init_csf
    show_progress $((++current_service)) $total_services
    
    init_mp
    show_progress $((++current_service)) $total_services
    
    show_service_info
}

# 显示服务信息
show_service_info() {
    header
    success "所有服务部署完成"
    info "访问地址:"
    echo -e "Transmission: http://${HOST_IP}:${TR_PORT}"
    echo -e "Emby: http://${HOST_IP}:${EMBY_PORT}"
    echo -e "qBittorrent: http://${HOST_IP}:${QB_PORT}"
    echo -e "MoviePilot: http://${HOST_IP}:${MP_PORT}"
    echo -e "ChineseSubFinder: http://${HOST_IP}:${CSF_PORT}"
    echo -e "所有站点账号密码都是admin  a123456!@"
    header
}

# 清理函数
cleanup() {
    info "执行清理..."
    rm -f *.tgz
    docker system prune -f >/dev/null 2>&1
    success "清理完成"
}

# 主菜单
show_menu() {
    clear
    header
    echo -e "${COLOR_GREEN} NASPT 媒体服务管理脚本 v2.0"
    header
    echo -e " 1. 一键快速部署"
    echo -e " 2. 自定义配置部署"
    echo -e " 3. 单独部署服务"
    echo -e " 4. 查看服务状态"
    echo -e " 5. 备份当前配置"
    echo -e " 6. 完全卸载"
    echo -e " 0. 退出脚本"
    header
}

# 主函数
main() {
    setup_logging
    check_dependencies
    check_network
#    check_system_resources
    load_config

    while :; do
        show_menu
        read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

        case $choice in
            1)
                quick_install
                ;;
            2)
                configure_essential
                quick_install
                ;;
            3)
                header
                echo -e "请选择要部署的服务："
                echo -e " 1. Transmission"
                echo -e " 2. Emby"
                echo -e " 3. qBittorrent"
                echo -e " 4. ChineseSubFinder"
                echo -e " 5. MoviePilot"
                read -rp "请输入编号: " service_choice
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
                backup_config
                ;;
            6)
                clean_container naspt-tr
                clean_container naspt-emby
                clean_container naspt-qb
                clean_container naspt-csf
                clean_container naspt-mpv2
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