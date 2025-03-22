#!/bin/bash

# 公共函数部分
# ==============================================

# 颜色定义
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

# 基础输出函数
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

# 通用服务初始化函数（带配置文件下载）
init_service_with_config() {
    local name="$1"
    local container_name="$2"
    local image="$3"
    local port="$4"
    local docker_opts="$5"

    check_port "$port" "$name" || return 1
    local config_path="${DOCKER_ROOT}"
#    local config_path="${DOCKER_ROOT}/${container_name}/config"
#    local data_path="${DOCKER_ROOT}/${container_name}/data"

    clean_container "$container_name"
    mkdir -p "$config_path"  || {
        error "无法创建${name}目录"
        return 1
    }

    # 下载配置文件
    if [[ -n "${CONFIG_URLS[$name]}" ]]; then
        download_config "$name" "$config_path"
    fi

    info "正在启动 ${name}..."
    eval "docker run -d --name ${name} \
        --restart always \
        --network bridge \
        ${docker_opts} \
        ${image}" || {
        error "${name} 启动失败"
        return 1
    }

    check_service_health "$container_name"
}

# 通用服务初始化函数
init_service() {
    local name="$1"
    local container_name="$2"
    local image="$3"
    local port="$4"
    local config_url="$5"
    local docker_opts="$6"

    check_port "$port" "$name" || return 1
    local config_path="${DOCKER_ROOT}"
#    local data_path="${DOCKER_ROOT}/${container_name}/data"

    clean_container "$container_name"
    mkdir -p "$config_path"  || {
        error "无法创建${name}目录"
        return 1
    }

#    # 如果有配置文件需要下载
#    if [[ -n "$config_url" ]]; then
#        info "下载${name}配置文件..."
#        curl -Ls "$config_url" -o "${config_path}/config.json" || {
#            error "${name}配置文件下载失败"
#            return 1
#        }
#    fi

    info "正在启动 ${name}..."
    eval "docker run -d --name ${container_name} \
        --restart always \
        --network bridge \
        ${docker_opts} \
        ${image}" || {
        error "${name} 启动失败"
        return 1
    }

    check_service_health "$container_name"
}

# 通用服务状态检查
check_service_status() {
    local service_pattern="$1"
    header
    echo -e "${COLOR_CYAN}服务状态："
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$service_pattern"
    header
}

# 通用服务卸载
uninstall_services() {
    local services=("$@")
    for service in "${services[@]}"; do
        clean_container "$service"
    done
    success "服务已卸载"
}

# 通用菜单处理
handle_menu_choice() {
    local choice="$1"
    local menu_title="$2"
    shift 2
    local -a options=("$@")

    header
    echo -e "${COLOR_GREEN} ${menu_title}"
    header

    for i in "${!options[@]}"; do
        echo -e " $((i+1)). ${options[i]}"
    done
    echo -e " 0. 返回主菜单"
    header

    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

    echo "$choice"
}

# 配置文件管理
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        success "已加载配置文件"
    else
        warning "使用默认配置"
    fi
}

# 修改 save_config 函数
save_config() {
    mkdir -p "$CONFIG_DIR" || handle_error "无法创建配置目录"

    # 基础配置
    cat > "$CONFIG_FILE" <<EOF
DOCKER_ROOT="$DOCKER_ROOT"
MEDIA_ROOT="$MEDIA_ROOT"
MUSIC_ROOT="$MUSIC_ROOT"
HOST_IP="$HOST_IP"
EOF

    # 端口配置，使用更安全的方式保存
    for service in "${!DEFAULT_PORTS[@]}"; do
        # 将破折号替换为下划线
        local var_name="${service//-/_}_port"
        # 使用默认端口，如果自定义端口存在则使用自定义端口
        local port_value="${!var_name:-${DEFAULT_PORTS[$service]}}"
        echo "${var_name}=\"${port_value}\"" >> "$CONFIG_FILE"
    done

    success "配置已保存"
    backup_config
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

# 端口检查
check_port() {
    local port="$1"
    local service="$2"
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

    handle_error "端口 $port 已被占用，请为 $service 选择其他端口"
}

# 清理函数
cleanup() {
    info "执行清理..."
    rm -f *.tgz
    docker system prune -f >/dev/null 2>&1
    success "清理完成"
}

# 配置文件下载解压
download_config() {
    local service="$1"
    local dest_dir="$2"
    local url="${CONFIG_URLS[$service]}"

    if [[ -z "$url" ]]; then
        info "服务 ${service} 无需下载配置文件"
        return 0
    fi

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

# 创建目录结构
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

create_music_structure() {
    info "创建音乐目录结构..."
    mkdir -p "${MUSIC_ROOT}/"{downloads,links,cache}
    success "音乐目录结构创建完成"
}

# 配置向导
config_wizard() {
    header
    info "欢迎使用NASPT配置向导"

    # 设置Docker根目录
    while true; do
        read -rp "$(echo -e "${COLOR_CYAN}请输入Docker数据存储路径: ${COLOR_RESET}")" DOCKER_ROOT
        if [[ -z "$DOCKER_ROOT" ]]; then
            warning "路径不能为空"
            continue
        fi
        
        if ! mkdir -p "$DOCKER_ROOT" 2>/dev/null; then
            error "无法创建目录: $DOCKER_ROOT"
            continue
        fi
        break
    done

    # 设置媒体库路径
    while true; do
        read -rp "$(echo -e "${COLOR_CYAN}请输入媒体库路径: ${COLOR_RESET}")" MEDIA_ROOT
        if [[ -z "$MEDIA_ROOT" ]]; then
            warning "路径不能为空"
            continue
        fi
        
        if ! mkdir -p "$MEDIA_ROOT" 2>/dev/null; then
            error "无法创建目录: $MEDIA_ROOT"
            continue
        fi
        break
    done

    # 设置音乐库路径
    while true; do
        read -rp "$(echo -e "${COLOR_CYAN}请输入音乐库路径: ${COLOR_RESET}")" MUSIC_ROOT
        if [[ -z "$MUSIC_ROOT" ]]; then
            warning "路径不能为空"
            continue
        fi
        
        if ! mkdir -p "$MUSIC_ROOT" 2>/dev/null; then
            error "无法创建目录: $MUSIC_ROOT"
            continue
        fi
        break
    done

    # 设置服务器IP
    if [[ -z "$HOST_IP" ]]; then
        HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)
    fi
    read -rp "$(echo -e "${COLOR_CYAN}请输入服务器IP (默认: $HOST_IP): ${COLOR_RESET}")" input
    HOST_IP=${input:-$HOST_IP}

    # 创建目录结构
    create_media_structure
    create_music_structure

    # 保存配置
    save_config

    success "配置向导完成"
    header
}

# 菜单函数
media_menu() {
    while true; do
        header
        info "媒体服务管理菜单"
        echo "1. 部署所有媒体服务"
        echo "2. 部署Transmission"
        echo "3. 部署Emby"
        echo "4. 部署qBittorrent"
        echo "5. 部署ChineseSubFinder"
        echo "6. 部署MoviePilot"
        echo "7. 检查服务状态"
        echo "8. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-8]: " choice

        case $choice in
            1)
                init_tr
                init_emby
                init_qb
                init_csf
                init_mp
                show_media_info
                ;;
            2) init_tr && show_media_info ;;
            3) init_emby && show_media_info ;;
            4) init_qb && show_media_info ;;
            5) init_csf && show_media_info ;;
            6) init_mp && show_media_info ;;
            7) check_service_status "naspt-tr|naspt-emby|naspt-qb|naspt-csf|naspt-mpv2" ;;
            8) uninstall_services "naspt-tr|naspt-emby|naspt-qb|naspt-csf|naspt-mpv2" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

music_menu() {
    while true; do
        header
        info "音乐服务管理菜单"
        echo "1. 部署所有音乐服务"
        echo "2. 部署Navidrome"
        echo "3. 部署MusicTag"
        echo "4. 部署LyricAPI"
        echo "5. 检查服务状态"
        echo "6. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1)
                init_navidrome
                init_musictag
                init_lyricapi
                show_music_info
                ;;
            2) init_navidrome && show_music_info ;;
            3) init_musictag && show_music_info ;;
            4) init_lyricapi && show_music_info ;;
            5) check_service_status "naspt-navidrome|naspt-musictag|naspt-lyricapi" ;;
            6) uninstall_services "naspt-navidrome|naspt-musictag|naspt-lyricapi" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

jellyfin_menu() {
    while true; do
        header
        info "Jellyfin服务管理菜单"
        echo "1. 部署所有Jellyfin服务"
        echo "2. 部署Jellyfin"
        echo "3. 部署MetaTube"
        echo "4. 检查服务状态"
        echo "5. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1)
                init_jellyfin
                init_metatube
                show_jellyfin_info
                ;;
            2) init_jellyfin && show_jellyfin_info ;;
            3) init_metatube && show_jellyfin_info ;;
            4) check_service_status "naspt-jl|metatube" ;;
            5) uninstall_services "naspt-jl|metatube" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

iptv_menu() {
    while true; do
        header
        info "IPTV服务管理菜单"
        echo "1. 部署IPTV服务"
        echo "2. 更新EPG数据"
        echo "3. 检查服务状态"
        echo "4. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1)
                init_iptv
                init_epg
                show_iptv_info
                ;;
            2) init_epg ;;
            3) check_service_status "naspt-iptv" ;;
            4) uninstall_services "naspt-iptv" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

live_menu() {
    while true; do
        header
        info "直播录制服务管理菜单"
        echo "1. 部署BiliLive"
        echo "2. 检查服务状态"
        echo "3. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-3]: " choice

        case $choice in
            1) init_bililive && show_live_info ;;
            2) check_service_status "naspt-bililive" ;;
            3) uninstall_services "naspt-bililive" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

cms_menu() {
    while true; do
        header
        info "115直连服务管理菜单"
        echo "1. 部署所有115服务"
        echo "2. 部署115 Emby"
        echo "3. 部署115 CMS"
        echo "4. 检查服务状态"
        echo "5. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1)
                init_115_emby
                init_115_cms
                show_115_info
                ;;
            2) init_115_emby && show_115_info ;;
            3) init_115_cms && show_115_info ;;
            4) check_service_status "naspt-115-emby|naspt-115-cms" ;;
            5) uninstall_services "naspt-115-emby|naspt-115-cms" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

proxy_menu() {
    while true; do
        header
        info "代理服务管理菜单"
        echo "1. 部署所有代理服务"
        echo "2. 部署FRP"
        echo "3. 部署Laddy"
        echo "4. 检查服务状态"
        echo "5. 完全卸载"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1)
                init_frp
                init_laddy
                show_proxy_info
                ;;
            2) init_frp && show_proxy_info ;;
            3) init_laddy && show_proxy_info ;;
            4) check_service_status "naspt-frp|naspt-laddy" ;;
            5) uninstall_services "naspt-frp|naspt-laddy" ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

tools_menu() {
    while true; do
        header
        info "系统工具菜单"
        echo "1. 显示系统信息"
        echo "2. 检查服务端口"
        echo "3. 清理Docker系统"
        echo "4. 备份配置"
        echo "5. 恢复配置"
        echo "0. 返回主菜单"
        header

        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) show_system_info ;;
            2) check_all_ports ;;
            3) docker system prune -f ;;
            4) backup_config ;;
            5) restore_config ;;
            0) return ;;
            *) warning "无效的选择" ;;
        esac

        read -p "按Enter键继续..."
    done
}

show_main_menu() {
    while true; do
        header
        info "NASPT一键安装脚本"
        echo "1. 媒体服务"
        echo "2. 音乐服务"
        echo "3. Jellyfin服务"
        echo "4. IPTV服务"
        echo "5. 直播录制服务"
        echo "6. 115直连服务"
        echo "7. 代理服务"
        echo "8. 系统工具"
        echo "0. 退出"
        header

        read -p "请选择服务类型 [0-8]: " choice

        case $choice in
            1) media_menu ;;
            2) music_menu ;;
            3) jellyfin_menu ;;
            4) iptv_menu ;;
            5) live_menu ;;
            6) cms_menu ;;
            7) proxy_menu ;;
            8) tools_menu ;;
            0)
                info "感谢使用NASPT一键安装脚本"
                exit 0
                ;;
            *) warning "无效的选择" ;;
        esac
    done
}

# 主函数
main() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        handle_error "请使用root用户运行此脚本"
    fi

    # 检查依赖
    check_dependencies

    # 检查网络连接
    check_network

    # 加载配置
    load_config

    # 如果配置文件不存在，运行配置向导
    if [[ ! -f "$CONFIG_FILE" ]]; then
        config_wizard
    fi

    # 显示主菜单
    show_main_menu
}

# 配置文件路径
CONFIG_DIR="/root/.naspt"
CONFIG_FILE="${CONFIG_DIR}/naspt-all.conf"

# 服务配置
declare -A CONFIG_URLS=(
    # 媒体服务
    ["tr"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-tr.tgz"
    ["emby"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-emby.tgz"
    ["qb"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-qb.tgz"
    ["csf"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-csf.tgz"
    ["mp"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-mpv2.tgz"
    # 音乐服务
    ["navidrome"]="https://pan.naspt.vip/d/123pan/shell/naspt-music/naspt-navidrome.tgz"
    ["musictag"]="https://pan.naspt.vip/d/123pan/shell/naspt-music/naspt-musictag.tgz"
)

# 默认端口配置
declare -A DEFAULT_PORTS=(
    # 媒体服务端口
    ["tr"]="9091"
    ["emby"]="8096"
    ["qb"]="9000"
    ["csf"]="19035"
    ["mp"]="3000"
    # 音乐服务端口
    ["navidrome"]="4533"
    ["musictag"]="8002"
    ["lyricapi"]="28883"
    # Jellyfin服务端口
    ["jellyfin"]="8097"
    ["metatube"]="8900"
    # IPTV服务端口
    ["iptv"]="35455"
    ["iptv_format"]="35456"
    # 直播录制端口
    ["bililive"]="9595"
    # 115服务端口
    ["115_emby"]="38096"
    ["115_cms"]="9527"
)

# 镜像配置
declare -A DEFAULT_IMAGE=(
    # 媒体服务镜像
    ["tr"]="ccr.ccs.tencentyun.com/naspt/transmission:4.0.5"
    ["emby"]="ccr.ccs.tencentyun.com/naspt/embyserver:latest"
    ["qb"]="ccr.ccs.tencentyun.com/naspt/qbittorrent:4.6.4"
    ["csf"]="ccr.ccs.tencentyun.com/naspt/chinesesubfinder:latest"
    ["mp"]="ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest"
    # 音乐服务镜像
    ["navidrome"]="ccr.ccs.tencentyun.com/naspt/navidrome:latest"
    ["musictag"]="ccr.ccs.tencentyun.com/naspt/music_tag_web:latest"
    ["lyricapi"]="ccr.ccs.tencentyun.com/naspt/lyricapi:latest"
    # Jellyfin服务镜像
    ["jellyfin"]="ccr.ccs.tencentyun.com/naspt/jellyfin:latest"
    ["metatube"]="ccr.ccs.tencentyun.com/naspt/metatube-server:latest"
    # IPTV服务镜像
    ["iptv"]="ccr.ccs.tencentyun.com/naspt/iptv:latest"
    # 直播录制镜像
    ["bililive"]="ccr.ccs.tencentyun.com/naspt/bililive:latest"
    # 115服务镜像
    ["115_cms"]="ccr.ccs.tencentyun.com/naspt/115-cms:latest"
    # 代理服务镜像
    ["frp"]="ccr.ccs.tencentyun.com/naspt/frpc:latest"
    ["laddy"]="ccr.ccs.tencentyun.com/naspt/laddy:latest"
)

# 初始化默认配置
DOCKER_ROOT=""
MEDIA_ROOT=""
MUSIC_ROOT=""
HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)

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

# 网络检查
check_network() {
    info "检查网络连接..."
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        warning "网络连接不稳定，请检查网络设置"
    fi
}

# 配置备份
backup_config() {
    local backup_dir="${CONFIG_DIR}/backup"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    mkdir -p "$backup_dir"
    tar -czf "$backup_dir/config_$timestamp.tar.gz" -C "$(dirname $CONFIG_FILE)" "$(basename $CONFIG_FILE)"
    success "配置已备份到 $backup_dir/config_$timestamp.tar.gz"
}

# 系统工具函数
show_system_info() {
    header
    info "系统信息"

    # CPU信息
    echo -e "${COLOR_CYAN}CPU信息:"
    echo -e "型号: $(cat /proc/cpuinfo | grep 'model name' | head -n1 | cut -d':' -f2 | xargs)"
    echo -e "核心数: $(nproc)"
    echo -e "使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"

    # 内存信息
    echo -e "\n${COLOR_CYAN}内存信息:"
    free -h | grep -v + | sed 's/^/  /'

    # 磁盘信息
    echo -e "\n${COLOR_CYAN}磁盘使用情况:"
    df -h | grep -v "tmpfs" | grep -v "udev" | sed 's/^/  /'

    # Docker信息
    echo -e "\n${COLOR_CYAN}Docker信息:"
    docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Total Memory|OS Type" | sed 's/^/  /'

    # 运行容器
    echo -e "\n${COLOR_CYAN}运行中的容器:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed 's/^/  /'

    header
}

check_all_ports() {
    header
    info "服务端口检查"

    for service in "${!DEFAULT_PORTS[@]}"; do
        local port="${DEFAULT_PORTS[$service]}"
        if netstat -tuln | grep -q ":$port "; then
            local pid=$(lsof -i :$port -t)
            local process=""
            if [ -n "$pid" ]; then
                process=$(ps -p $pid -o comm=)
            fi
            echo -e "${COLOR_YELLOW}端口 $port ($service) 被占用 - PID: $pid, 进程: $process"
        else
            echo -e "${COLOR_GREEN}端口 $port ($service) 可用"
        fi
    done

    header
}

restore_config() {
    header
    info "可用的配置备份:"

    local backup_dir="${CONFIG_DIR}/backup"
    local backups=($(ls -t "${backup_dir}"/*.tar.gz 2>/dev/null))

    if [ ${#backups[@]} -eq 0 ]; then
        error "没有找到可用的配置备份"
        return 1
    fi

    for i in "${!backups[@]}"; do
        echo "$((i+1)). $(basename "${backups[$i]}")"
    done

    header
    read -rp "$(echo -e "${COLOR_CYAN}请选择要恢复的备份编号 (0退出): ${COLOR_RESET}")" choice

    if [[ "$choice" == "0" ]]; then
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        error "无效选择"
        return 1
    fi

    local selected_backup="${backups[$((choice-1))]}"
    local temp_dir="/tmp/naspt_restore_$$"

    mkdir -p "$temp_dir"
    tar -xzf "$selected_backup" -C "$temp_dir"

    # 恢复主配置文件
    if [[ -f "${temp_dir}/naspt-all.conf" ]]; then
        cp "${temp_dir}/naspt-all.conf" "$CONFIG_FILE"
    fi

    # 恢复各服务配置
    for service_dir in "${temp_dir}"/*; do
        if [[ -d "$service_dir" ]]; then
            local service_name=$(basename "$service_dir")
            local target_dir="${DOCKER_ROOT}/${service_name}"
            mkdir -p "$target_dir"
            cp -r "${service_dir}"/* "$target_dir/"
            success "已恢复 ${service_name} 配置"
        fi
    done

    rm -rf "$temp_dir"
    success "配置恢复完成"
    header
}

# 媒体服务初始化函数
init_tr() {
    init_service_with_config "tr" "naspt-tr" "${DEFAULT_IMAGE[tr]}" "${DEFAULT_PORTS[tr]}" \
        "-p ${DEFAULT_PORTS[tr]}:9091 \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -e TZ=Asia/Shanghai \
        -e USER=admin -e PASS=a123456!@ \
        -e 'TRANSMISSION_WEB_HOME'='/config/2/src' \
        -v '${DOCKER_ROOT}/naspt-tr/config:/config' \
        -v '${MEDIA_ROOT}:/media'"
}

init_emby() {
    init_service_with_config "emby" "naspt-emby" "${DEFAULT_IMAGE[emby]}" "${DEFAULT_PORTS[emby]}" \
        "--privileged \
        -p ${DEFAULT_PORTS[emby]}:8096 \
        --device /dev/dri:/dev/dri \
        -e UID=0 -e GID=0 -e UMASK=022 \
        -v '${DOCKER_ROOT}/naspt-emby/config:/config' \
        -v '${MEDIA_ROOT}:/media'"
}

init_qb() {
    init_service_with_config "qb" "naspt-qb" "${DEFAULT_IMAGE[qb]}" "${DEFAULT_PORTS[qb]}" \
        "-p ${DEFAULT_PORTS[qb]}:9000 \
        -e WEBUI_PORT=9000 \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -e TZ=Asia/Shanghai \
        -e SavePatch='/media/downloads' \
        -e TempPatch='/media/downloads' \
        -v '${DOCKER_ROOT}/naspt-qb/config:/config' \
        -v '${MEDIA_ROOT}:/media'"
}

init_csf() {
    init_service_with_config "csf" "naspt-csf" "${DEFAULT_IMAGE[csf]}" "${DEFAULT_PORTS[csf]}" \
        "--privileged \
        -p ${DEFAULT_PORTS[csf]}:19035 \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -v '${DOCKER_ROOT}/naspt-csf/config:/config' \
        -v '${DOCKER_ROOT}/naspt-csf/cache:/app/cache' \
        -v '${MEDIA_ROOT}:/media'"
}

init_mp() {
    init_service_with_config "mp" "naspt-mpv2" "${DEFAULT_IMAGE[mp]}" "${DEFAULT_PORTS[mp]}" \
        "--privileged \
        -p ${DEFAULT_PORTS[mp]}:3000 \
        -p 3001:3001 \
        -e TZ=Asia/Shanghai \
        -e SUPERUSER=admin \
        -e API_TOKEN=nasptnasptnasptnaspt \
        -e AUTO_UPDATE_RESOURCE=false \
        -e MOVIEPILOT_AUTO_UPDATE=false \
        -e AUTH_SITE=icc2022,leaves \
        -e ICC2022_UID='24730' \
        -e ICC2022_PASSKEY='49c421073514d4d981a0cbc4174f4b23' \
        -e LEAVES_UID='10971' \
        -e LEAVES_PASSKEY='e0405a9d0de9e3b112ef78ac3d9c7975' \
        -v '${DOCKER_ROOT}/naspt-mpv2/config:/config' \
        -v '${MEDIA_ROOT}:/media' \
        -v '${DOCKER_ROOT}/naspt-qb/config/qBittorrent/BT_backup:/qbtr' \
        -v '${DOCKER_ROOT}/naspt-mpv2/core:/moviepilot/.cache/ms-playwright' \
        -v '${DOCKER_ROOT}/naspt-mpv2/hosts_new.txt:/etc/hosts:ro'"
}

# 音乐服务初始化函数
init_navidrome() {
    init_service_with_config "navidrome" "naspt-navidrome" "${DEFAULT_IMAGE[navidrome]}" "${DEFAULT_PORTS[navidrome]}" \
        "-p ${DEFAULT_PORTS[navidrome]}:4533 \
        -e ND_SCANSCHEDULE=1h \
        -e ND_LOGLEVEL=info \
        -v '${DOCKER_ROOT}/naspt-navidrome/data:/data' \
        -v '${MUSIC_ROOT}/links:/music'"
}

init_musictag() {
    init_service_with_config "musictag" "naspt-musictag" "${DEFAULT_IMAGE[musictag]}" "${DEFAULT_PORTS[musictag]}" \
        "-p ${DEFAULT_PORTS[musictag]}:8002 \
        -v '${MUSIC_ROOT}:/app/media' \
        -v '${DOCKER_ROOT}/naspt-musictag:/app/data'"
}

init_lyricapi() {
    init_service "LyricAPI" "naspt-lyricapi" "${DEFAULT_IMAGE[lyricapi]}" "${DEFAULT_PORTS[lyricapi]}" \
        "-p ${DEFAULT_PORTS[lyricapi]}:28883 \
        -v '${MUSIC_ROOT}/links:/music'"
}

# Jellyfin服务初始化函数
init_jellyfin() {
    init_service "Jellyfin" "naspt-jl" "${DEFAULT_IMAGE[jellyfin]}" "${DEFAULT_PORTS[jellyfin]}" "" \
        "--privileged \
        -p ${DEFAULT_PORTS[jellyfin]}:8096 \
        --device /dev/dri:/dev/dri \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=Asia/Shanghai \
        -e JELLYFIN_PublishedServerUrl=${HOST_IP} \
        -v '${DOCKER_ROOT}/jellyfin/config:/config' \
        -v '${DOCKER_ROOT}/jellyfin/cache:/cache' \
        -v '${MEDIA_ROOT}:/media'"
}

init_metatube() {
    init_service "MetaTube" "metatube" "${DEFAULT_IMAGE[metatube]}" "${DEFAULT_PORTS[metatube]}" "" \
        "-p ${DEFAULT_PORTS[metatube]}:8080 \
        -v '${DOCKER_ROOT}/metatube/config:/config' \
        -dsn /config/metatube.db"
}

# IPTV服务初始化函数
init_iptv() {
    init_service "IPTV" "naspt-iptv" "${DEFAULT_IMAGE[iptv]}" "${DEFAULT_PORTS[iptv]}" \
        "https://alist.naspt.vip/d/123pan/shell/naspt-iptv/config.json" \
        "-p ${DEFAULT_PORTS[iptv]}:35455 \
        -p ${DEFAULT_PORTS[iptv_format]}:35456 \
        -v '${DOCKER_ROOT}/naspt-iptv/config:/root/.iptv' \
        -v '${DOCKER_ROOT}/naspt-iptv/cache:/root/.cache'"
}

init_epg() {
    local epg_path="${DOCKER_ROOT}/naspt-iptv/epg"
    mkdir -p "$epg_path" || {
        error "无法创建EPG目录"
        return 1
    }

    info "下载EPG数据..."
    curl -Ls "https://alist.naspt.vip/d/123pan/shell/naspt-iptv/epg.xml.gz" -o "${epg_path}/epg.xml.gz" || {
        error "EPG数据下载失败"
        return 1
    }

    info "解压EPG数据..."
    gunzip -f "${epg_path}/epg.xml.gz" || {
        error "EPG数据解压失败"
        return 1
    }

    success "EPG数据更新成功"

    # 设置每日自动更新EPG
    local cron_schedule="0 4 * * *"
    local cron_command="curl -Ls https://alist.naspt.vip/d/123pan/shell/naspt-iptv/epg.xml.gz | gunzip > ${epg_path}/epg.xml"
    local cron_job="${cron_schedule} ${cron_command}"

    if ! crontab -l 2>/dev/null | grep -F --quiet "$cron_command"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        success "已添加EPG自动更新任务"
    fi
}

# 直播录制服务初始化函数
init_bililive() {
    init_service "BiliLive" "naspt-bililive" "${DEFAULT_IMAGE[bililive]}" "${DEFAULT_PORTS[bililive]}" \
        "https://alist.naspt.vip/d/123pan/shell/naspt-live/config.json" \
        "-p ${DEFAULT_PORTS[bililive]}:9595 \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=Asia/Shanghai \
        -v '${DOCKER_ROOT}/naspt-bililive/config:/config' \
        -v '${DOCKER_ROOT}/naspt-bililive/data:/data' \
        -v '${MEDIA_ROOT}/直播录制:/recordings'"
}

# 115直连服务初始化函数
init_115_emby() {
    init_service "115 Emby" "naspt-115-emby" "${DEFAULT_IMAGE[jellyfin]}" "${DEFAULT_PORTS[115_emby]}" "" \
        "--privileged \
        -p ${DEFAULT_PORTS[115_emby]}:8096 \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=Asia/Shanghai \
        -e JELLYFIN_PublishedServerUrl=${HOST_IP} \
        -v '${DOCKER_ROOT}/naspt-115/emby/config:/config' \
        -v '${DOCKER_ROOT}/naspt-115/emby/cache:/cache'"
}

init_115_cms() {
    init_service "115 CMS" "naspt-115-cms" "${DEFAULT_IMAGE[115_cms]}" "${DEFAULT_PORTS[115_cms]}" \
        "https://alist.naspt.vip/d/123pan/shell/naspt-115/config.json" \
        "-p ${DEFAULT_PORTS[115_cms]}:9527 \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=Asia/Shanghai \
        -v '${DOCKER_ROOT}/naspt-115/cms/config:/config' \
        -v '${DOCKER_ROOT}/naspt-115/cms/data:/data'"
}

# 代理服务初始化函数
init_frp() {
    init_service "FRP" "naspt-frp" "${DEFAULT_IMAGE[frp]}" "" \
        "https://alist.naspt.vip/d/123pan/shell/naspt-frp/frpc.ini" \
        "--network host \
        -e TZ=Asia/Shanghai \
        -v '${DOCKER_ROOT}/naspt-frp/config/frpc.ini:/etc/frp/frpc.ini'"
}

init_laddy() {
    init_service "Laddy" "naspt-laddy" "${DEFAULT_IMAGE[laddy]}" "" \
        "https://alist.naspt.vip/d/123pan/shell/naspt-laddy/config.json" \
        "--network host \
        -e TZ=Asia/Shanghai \
        -v '${DOCKER_ROOT}/naspt-laddy/config:/config' \
        -v '${DOCKER_ROOT}/naspt-laddy/data:/data'"
}

# 显示服务信息函数
show_media_info() {
    header
    info "媒体服务访问地址:"
    echo -e "Transmission: http://${HOST_IP}:${DEFAULT_PORTS[tr]}"
    echo -e "Emby: http://${HOST_IP}:${DEFAULT_PORTS[emby]}"
    echo -e "qBittorrent: http://${HOST_IP}:${DEFAULT_PORTS[qb]}"
    echo -e "MoviePilot: http://${HOST_IP}:${DEFAULT_PORTS[mp]}"
    echo -e "ChineseSubFinder: http://${HOST_IP}:${DEFAULT_PORTS[csf]}"
    echo -e "所有站点账号密码都是admin  a123456!@"
    header
}

show_music_info() {
    header
    info "音乐服务访问地址:"
    echo -e "Navidrome: http://${HOST_IP}:${DEFAULT_PORTS[navidrome]}"
    echo -e "MusicTag: http://${HOST_IP}:${DEFAULT_PORTS[musictag]}"
    echo -e "LyricAPI: http://${HOST_IP}:${DEFAULT_PORTS[lyricapi]}"
    echo -e "Navidrome 默认账号密码: admin/a123456!@"
    header
}

show_jellyfin_info() {
    header
    info "Jellyfin 服务访问地址:"
    echo -e "Jellyfin: http://${HOST_IP}:${DEFAULT_PORTS[jellyfin]}"
    echo -e "MetaTube: http://${HOST_IP}:${DEFAULT_PORTS[metatube]}"
    header
}

show_iptv_info() {
    header
    info "IPTV 服务访问地址:"
    echo -e "IPTV代理: http://${HOST_IP}:${DEFAULT_PORTS[iptv]}"
    echo -e "IPTV格式转换: http://${HOST_IP}:${DEFAULT_PORTS[iptv_format]}"
    header
}

show_live_info() {
    header
    info "直播录制服务访问地址:"
    echo -e "BiliLive: http://${HOST_IP}:${DEFAULT_PORTS[bililive]}"
    header
}

show_115_info() {
    header
    info "115直连服务访问地址:"
    echo -e "115 Emby: http://${HOST_IP}:${DEFAULT_PORTS[115_emby]}"
    echo -e "115 CMS: http://${HOST_IP}:${DEFAULT_PORTS[115_cms]}"
    header
}

show_proxy_info() {
    header
    info "代理服务已启动"
    echo -e "FRP和Laddy服务使用host网络模式，无需端口映射"
    header
}

# 启动脚本
main "$@"