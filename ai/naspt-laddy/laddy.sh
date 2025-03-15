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

# 服务配置
declare -A CONFIG_URLS=(
    ["naspt-jellyfin"]="ccr.ccs.tencentyun.com/naspt/jellyfin:latest"
    ["naspt-metatube"]="ccr.ccs.tencentyun.com/naspt/metatube-server:latest"
)

# 初始化默认配置
DOCKER_ROOT="/opt/docker"
declare -A SERVICE_CONFIG=(
    ["media_root"]=""
    ["host_ip"]=""
    ["enable_hwaccel"]="N"
)

declare -A SERVICE_PORTS=(
    ["naspt-jellyfin"]="8097"
    ["naspt-metatube"]="8900"
)

CONFIG_FILE="/root/.naspt/.naspt-laddy.conf"

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
    
    # 保存服务配置
    for key in "${!SERVICE_CONFIG[@]}"; do
        config_content+="SERVICE_CONFIG[$key]=\"${SERVICE_CONFIG[$key]}\"\n"
    done

    # 保存端口配置
    for service in "${!SERVICE_PORTS[@]}"; do
        config_content+="SERVICE_PORTS[$service]=\"${SERVICE_PORTS[$service]}\"\n"
    done

    echo -e "$config_content" > "$CONFIG_FILE" || {
        error "配置保存失败"
        return 1
    }
    success "配置已保存到 $CONFIG_FILE"
}

# 系统检查
check_dependencies() {
    if ! command -v docker &>/dev/null; then
        error "需要 Docker 但未安装"
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
            "yn")
                if ! [[ "$input" =~ ^[YyNn]$ ]]; then
                    error "请输入 Y/N"
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
        if docker inspect "$name" --format '{{.State.Status}}' | grep -q "running"; then
            info "正在停止容器..."
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

check_port() {
    if netstat -tuln | grep -q ":${1}$"; then
        error "端口 ${1} 已被占用"
        return 1
    fi
}

# 服务初始化函数
init_jellyfin() {
    local port="${SERVICE_PORTS[naspt-jellyfin]}"
    check_port "$port" || return 1
    local config_path="${DOCKER_ROOT}/jellyfin/config"
    local cache_path="${DOCKER_ROOT}/jellyfin/cache"

    clean_container naspt-jl
    mkdir -p "$config_path" "$cache_path" || {
        error "无法创建存储目录"
        return 1
    }

    local docker_cmd="docker run -d --name naspt-jl \
        --restart always \
        --network bridge \
        --privileged \
        -p ${port}:8096 \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=Asia/Shanghai \
        -e JELLYFIN_PublishedServerUrl=${SERVICE_CONFIG[host_ip]} \
        -v ${config_path}:/config \
        -v ${cache_path}:/cache \
        -v ${SERVICE_CONFIG[media_root]}:/media"

    # 硬件加速支持
    if [[ "${SERVICE_CONFIG[enable_hwaccel]}" =~ ^[Yy]$ ]]; then
        if [[ -d "/dev/dri" ]]; then
            docker_cmd+=" --device /dev/dri:/dev/dri"
            info "已启用Intel核显硬件加速"
        else
            warning "未检测到Intel核显设备，跳过硬件加速"
        fi
    fi

    docker_cmd+=" ${CONFIG_URLS[naspt-jellyfin]}"

    eval "$docker_cmd" || {
        error "Jellyfin 启动失败，查看日志：docker logs naspt-jl"
        return 1
    }

    success "Jellyfin 已启动"
    info "访问地址: ${COLOR_YELLOW}http://${SERVICE_CONFIG[host_ip]}:${port}${COLOR_RESET}"
}

init_metatube() {
    local port="${SERVICE_PORTS[naspt-metatube]}"
    check_port "$port" || return 1
    local config_path="${DOCKER_ROOT}/metatube/config"

    clean_container metatube
    mkdir -p "$config_path" || {
        error "无法创建配置目录"
        return 1
    }

    info "初始化数据库..."
    touch "${config_path}/metatube.db" || {
        error "数据库文件创建失败"
        return 1
    }

    docker run -d --name metatube \
        --restart always \
        --network bridge \
        -p ${port}:8080 \
        -v ${config_path}:/config \
        ${CONFIG_URLS[naspt-metatube]} \
        -dsn /config/metatube.db || {
        error "MetaTube 启动失败，查看日志：docker logs metatube"
        return 1
    }

    success "MetaTube 已启动"
    info "访问地址: ${COLOR_YELLOW}http://${SERVICE_CONFIG[host_ip]}:${port}${COLOR_RESET}"
}

# 配置向导
configure_services() {
    while :; do
        header
        info "服务配置向导"

        safe_input "DOCKER_ROOT" "Docker存储路径" "${DOCKER_ROOT}" "path"
        safe_input "SERVICE_CONFIG[media_root]" "媒体库路径" "${SERVICE_CONFIG[media_root]}" "path"
        safe_input "SERVICE_CONFIG[host_ip]" "服务器IP地址" "${SERVICE_CONFIG[host_ip]:-$(hostname -I | awk '{print $1}')}" "ip"
        safe_input "SERVICE_PORTS[naspt-jellyfin]" "Jellyfin端口" "${SERVICE_PORTS[naspt-jellyfin]}" "port"
        safe_input "SERVICE_PORTS[naspt-metatube]" "MetaTube端口" "${SERVICE_PORTS[naspt-metatube]}" "port"
        safe_input "SERVICE_CONFIG[enable_hwaccel]" "启用硬件加速 (Y/N)" "${SERVICE_CONFIG[enable_hwaccel]}" "yn"

        header
        echo -e "${COLOR_BLUE}配置预览："
        echo -e "▷ Docker存储: ${COLOR_CYAN}${DOCKER_ROOT}"
        echo -e "▷ 媒体库路径: ${COLOR_CYAN}${SERVICE_CONFIG[media_root]}"
        echo -e "▷ 服务器IP: ${COLOR_CYAN}${SERVICE_CONFIG[host_ip]}"
        echo -e "▷ Jellyfin端口: ${COLOR_CYAN}${SERVICE_PORTS[naspt-jellyfin]}"
        echo -e "▷ MetaTube端口: ${COLOR_CYAN}${SERVICE_PORTS[naspt-metatube]}"
        echo -e "▷ 硬件加速: ${COLOR_CYAN}${SERVICE_CONFIG[enable_hwaccel]}"
        header

        read -rp "$(echo -e "${COLOR_YELLOW}是否确认配置？(Y/n) ${COLOR_RESET}")" confirm
        [[ "${confirm:-Y}" =~ ^[Yy]$ ]] && break
    done

    save_config
}

# 卸载服务
uninstall_services() {
    header
    warning "此操作将永久删除所有容器及数据！"
    read -rp "$(echo -e "${COLOR_RED}确认要卸载吗？(输入YES确认): ${COLOR_RESET}")" confirm
    [[ "$confirm" != "YES" ]] && { info "已取消卸载"; return; }

    clean_container naspt-jl
    clean_container metatube
    rm -rf "${DOCKER_ROOT}/jellyfin" "${DOCKER_ROOT}/metatube"
    success "所有服务及数据已移除"
}

# 菜单系统
show_menu() {
    clear
    header
    echo -e "${COLOR_GREEN} 媒体服务管理脚本 v3.0"
    header
    echo -e " 1. 完整部署所有服务"
    echo -e " 2. 单独部署服务"
    echo -e " 3. 修改配置"
    echo -e " 4. 查看服务状态"
    echo -e " 5. 完全卸载"
    echo -e " 0. 退出脚本"
    header
}

main() {
    check_dependencies
    load_config

    if [[ -z "$DOCKER_ROOT" || -z "${SERVICE_CONFIG[media_root]}" ]]; then
        warning "检测到未完成初始配置！"
        configure_services
    fi

    while :; do
        show_menu
        read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" choice

        case $choice in
            1)
                init_jellyfin && init_metatube
                success "所有服务部署完成"
                ;;
            2)
                header
                echo -e "请选择要部署的服务："
                echo -e " 1. Jellyfin"
                echo -e " 2. MetaTube"
                read -rp "请输入编号: " service_choice
                case $service_choice in
                    1) init_jellyfin ;;
                    2) init_metatube ;;
                    *) error "无效选择" ;;
                esac
                ;;
            3) configure_services ;;
            4)
                header
                echo -e "${COLOR_CYAN}运行中的容器："
                docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                header
                ;;
            5) uninstall_services ;;
            0)
                success "操作结束