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
    ["naspt-watchtower"]="ccr.ccs.tencentyun.com/naspt/watchtower:latest"
)

# 初始化默认配置
DOCKER_ROOT="/opt/docker"
declare -A SERVICE_CONFIG=(
    ["check_interval"]="10800"
    ["auto_cleanup"]="true"
    ["container_name"]="naspt-dkup"
)
CONFIG_FILE="/root/.naspt/.naspt-watchtower.conf"

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

    echo -e "$config_content" > "$CONFIG_FILE" || {
        error "配置保存失败"
        return 1
    }
    info "配置已保存到 $CONFIG_FILE"
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
    if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_CONFIG[container_name]}$"; then
        warning "发现残留容器: ${SERVICE_CONFIG[container_name]}"
        if docker rm -f "${SERVICE_CONFIG[container_name]}" &>/dev/null; then
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

    safe_input "SERVICE_CONFIG[check_interval]" "检测间隔时间（秒）" "${SERVICE_CONFIG[check_interval]}" "number"
    safe_input "cleanup_choice" "自动清理旧镜像？(y/n)" "$([[ ${SERVICE_CONFIG[auto_cleanup]} == "true" ]] && echo "y" || echo "n")" "boolean"

    local cleanup_flag=""
    [[ ${cleanup_choice,,} == "y" ]] && {
        SERVICE_CONFIG[auto_cleanup]="true"
        cleanup_flag="--cleanup"
    }

    info "启动容器..."
    docker run -d \
        --name "${SERVICE_CONFIG[container_name]}" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e TZ=Asia/Shanghai \
        "${CONFIG_URLS[naspt-watchtower]}" \
        --interval "${SERVICE_CONFIG[check_interval]}" \
        $cleanup_flag || {
        error "服务启动失败"
        exit 1
    }

    save_config
    success "服务已启动"
    info "检测间隔: $((SERVICE_CONFIG[check_interval] / 3600)) 小时"
    info "自动清理: ${SERVICE_CONFIG[auto_cleanup]}"
}

# 立即更新
run_update() {
    info "执行立即更新..."
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "${CONFIG_URLS[naspt-watchtower]}" \
        --run-once || {
        error "更新执行失败"
        exit 1
    }
    success "容器更新完成"
}

# 服务状态
show_status() {
    header
    echo -e "${COLOR_CYAN}容器状态:"
    docker ps -a --filter "name=${SERVICE_CONFIG[container_name]}" \
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