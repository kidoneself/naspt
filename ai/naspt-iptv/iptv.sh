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
    ["naspt-allinone"]="ccr.ccs.tencentyun.com/naspt/allinone:latest"
    ["naspt-allinone-format"]="ccr.ccs.tencentyun.com/naspt/allinone_format:latest"
)

declare -A SERVICE_PORTS=(
    ["naspt-allinone"]="35455"
    ["naspt-allinone-format"]="35456"
)

# 初始化默认配置
DOCKER_ROOT="/opt/docker"
declare -A SERVICE_CONFIG=(
    ["host_ip"]=""
    ["aes_key"]="swj6pnb4h6xyvhpq69fgae2bbpjlb8y2"
    ["user_id"]="5892131247"
    ["token"]="9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137"
)
CONFIG_FILE="/root/.naspt/.naspt-iptv.conf"

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
    success "配置已保存到 $CONFIG_FILE"
}

# 检查依赖项
check_dependencies() {
    if ! command -v docker &>/dev/null; then
        error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        error "Docker 服务未运行"
        exit 1
    fi
}

# 安全输入验证
safe_input() {
    local var_name="$1"
    local prompt="$2"
    local default="$3"

    while true; do
        read -rp "$(echo -e "${COLOR_CYAN}${prompt} (默认: ${default}): ${COLOR_RESET}")" value
        value="${value:-$default}"

        if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            error "无效的IP地址格式"
            continue
        fi

        SERVICE_CONFIG["host_ip"]="$value"
        break
    done
}

# 清理残留容器
clean_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        warning "发现已存在的容器: ${name}"
        if docker rm -f "$name" &>/dev/null; then
            info "已成功移除旧容器: ${name}"
        else
            error "无法移除容器: ${name}"
            return 1
        fi
    fi
}

# 初始化服务
init_service() {
    local name="$1"
    local image="${CONFIG_URLS[$name]}"
    local port="${SERVICE_PORTS[$name]}"

    header
    info "正在初始化 ${name} 服务"
    clean_container "$name" || return 1

    info "正在启动容器..."
    if [[ "$name" == "naspt-allinone" ]]; then
        docker run -d \
            --name "$name" \
            --restart always \
            --network host \
            --privileged \
            "$image" \
            -aesKey="${SERVICE_CONFIG[aes_key]}" \
            -userid="${SERVICE_CONFIG[user_id]}" \
            -token="${SERVICE_CONFIG[token]}" || {
            error "容器启动失败"
            return 1
        }
    else
        docker run -d \
            --name "$name" \
            --restart always \
            --network host \
            "$image" || {
            error "容器启动失败"
            return 1
        }
    fi

    success "${name} 服务启动成功"
}

# 主程序流程
main() {
    clear
    check_dependencies
    load_config

    # 获取配置信息
    header
    safe_input "host_ip" "请输入 NAS IP 地址" "$(ip route get 1 | awk '{print $7}' | head -1)"

    # 显示配置确认
    header
    info "配置信息确认"
    echo -e "主机 IP 地址: ${COLOR_YELLOW}${SERVICE_CONFIG[host_ip]}${COLOR_RESET}"

    read -rp "$(echo -e "${COLOR_CYAN}是否继续安装？(y/N): ${COLOR_RESET}")" confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

    # 安装服务
    for name in "${!CONFIG_URLS[@]}"; do
        init_service "$name" || exit 1
    done

    # 保存配置
    save_config

    # 输出访问信息
    header
    success "服务部署完成！"
    echo -e "${COLOR_YELLOW}=== 访问地址 ===${COLOR_RESET}"
    echo -e "IPTV 源地址:   http://${SERVICE_CONFIG[host_ip]}:${SERVICE_PORTS[naspt-allinone]}/tv.m3u"
    echo -e "IPTV 整理地址: http://${SERVICE_CONFIG[host_ip]}:${SERVICE_PORTS[naspt-allinone-format]}"
    echo -e "\n${COLOR_YELLOW}请确保防火墙已开放以下端口：${COLOR_RESET}"
    for name in "${!SERVICE_PORTS[@]}"; do
        echo -e " - ${SERVICE_PORTS[$name]}/TCP"
    done

}

# 执行主程序
main