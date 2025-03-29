#!/bin/bash

# 配置颜色输出
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

# 定义输出函数
info() { echo -e "${COLOR_CYAN}[信息] $*${COLOR_RESET}"; }
success() { echo -e "${COLOR_GREEN}[成功] $*${COLOR_RESET}"; }
warning() { echo -e "${COLOR_YELLOW}[警告] $*${COLOR_RESET}"; }
error() { echo -e "${COLOR_RED}[错误] $*${COLOR_RESET}" >&2; }
header() { echo -e "${COLOR_BLUE}==========================================${COLOR_RESET}"; }

# 默认配置
CONFIG_FILE="/root/.naspt/naspt.conf"
DOCKER_ROOT=""
HOST_IP=""
CONTAINER_NAME="naspt-bililive"
PORT=9595
IMAGE_SOURCE="official"  # 新增：镜像源选择

# 定义私有镜像
# 在文件开头的配置部分添加 memos 相关配置
declare -A DOCKER_IMAGES=(
    ["bililive"]="ccr.ccs.tencentyun.com/naspt/bililive-go:latest"
    ["memos"]="neosmemo/memos:stable"
)

declare -A OFFICIAL_DOCKER_IMAGES=(
    ["bililive"]="chigusa/bililive-go:latest"
    ["memos"]="neosmemo/memos:stable"
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

# 配置管理
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # 从[live]部分读取所有配置
        DOCKER_ROOT=$(get_ini_value "$CONFIG_FILE" "live" "DOCKER_ROOT")
        HOST_IP=$(get_ini_value "$CONFIG_FILE" "live" "HOST_IP")
        CONTAINER_NAME=$(get_ini_value "$CONFIG_FILE" "live" "CONTAINER_NAME")
        PORT=$(get_ini_value "$CONFIG_FILE" "live" "PORT")
        IMAGE_SOURCE=$(get_ini_value "$CONFIG_FILE" "live" "IMAGE_SOURCE")
        
        # 如果IMAGE_SOURCE为空，设置默认值
        [[ -z "$IMAGE_SOURCE" ]] && IMAGE_SOURCE="official"
        # 如果CONTAINER_NAME为空，设置默认值
        [[ -z "$CONTAINER_NAME" ]] && CONTAINER_NAME="naspt-bililive"
        # 如果PORT为空，设置默认值
        [[ -z "$PORT" ]] && PORT="9595"
        
        success "已加载配置文件"
    else
        warning "使用默认配置"
        # 设置默认值
#        DOCKER_ROOT="${HOME}/bililive-data"
    fi
}

save_config() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    mkdir -p "$config_dir" || {
        error "无法创建配置目录: $config_dir"
        return 1
    }

    # 保存所有配置到[live]部分
    set_ini_value "$CONFIG_FILE" "live" "DOCKER_ROOT" "$DOCKER_ROOT"
    set_ini_value "$CONFIG_FILE" "live" "HOST_IP" "$HOST_IP"
    set_ini_value "$CONFIG_FILE" "live" "CONTAINER_NAME" "$CONTAINER_NAME"
    set_ini_value "$CONFIG_FILE" "live" "PORT" "$PORT"
    set_ini_value "$CONFIG_FILE" "live" "IMAGE_SOURCE" "$IMAGE_SOURCE"
    
    [[ $? -eq 0 ]] && success "配置已保存" || error "配置保存失败"
}

# 检查依赖项
check_dependencies() {
    local deps=("docker" "curl")
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

# 检查网络连接
check_network() {
    info "检查网络连接..."
    if ! curl -Is https://www.baidu.com --connect-timeout 3 &>/dev/null; then
        warning "外网连接异常，可能影响服务使用"
    else
        success "网络连接正常"
    fi
}

# 安全输入验证
safe_input() {
    local var_name="$1"
    local prompt="$2"
    local default="$3"
    local validator="$4"

    while true; do
        read -rp "$(echo -e "${COLOR_CYAN}${prompt} (默认: ${default}): ${COLOR_RESET}")" value
        value="${value:-$default}"

        case "$validator" in
            "path")
                if [[ ! "$value" =~ ^/ ]]; then
                    error "必须使用绝对路径"
                    continue
                fi
                if [[ ! -d "$value" ]]; then
                    warning "路径不存在，尝试创建: $value"
                    mkdir -p "$value" || {
                        error "目录创建失败"
                        continue
                    }
                fi
                ;;
            "ip")
                if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    error "无效的IP地址格式"
                    continue
                fi
                if ! ping -c1 -W2 "$value" &>/dev/null; then
                    warning "IP地址 $value 无法ping通，请确认网络配置"
                fi
                ;;
            "port")
                if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
                    error "端口必须是1-65535之间的数字"
                    continue
                fi
                ;;
            "image_source")
                if [[ ! "$value" =~ ^(private|official)$ ]]; then
                    error "镜像源只能是 private 或 official"
                    continue
                fi
                ;;
        esac

        eval "$var_name='$value'"
        break
    done
}

# 容器状态管理
manage_container() {
    local action="$1"
    case $action in
        check)
            if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
                return 0
            else
                return 1
            fi
            ;;
        remove)
            if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                warning "发现残留容器: ${CONTAINER_NAME}"
                if docker rm -f "$CONTAINER_NAME" &>/dev/null; then
                    success "已移除旧容器: $CONTAINER_NAME"
                else
                    error "无法移除容器: $CONTAINER_NAME"
                    return 1
                fi
            fi
            ;;
        stop)
            if manage_container check; then
                info "正在停止容器..."
                if docker stop "$CONTAINER_NAME" &>/dev/null; then
                    success "容器已停止"
                else
                    error "停止容器失败"
                    return 1
                fi
            else
                warning "容器未运行"
            fi
            ;;
        start)
            if ! manage_container check; then
                info "正在启动容器..."
                if docker start "$CONTAINER_NAME" &>/dev/null; then
                    success "容器已启动"
                else
                    error "启动容器失败"
                    return 1
                fi
            else
                info "容器已在运行中"
            fi
            ;;
        logs)
            if manage_container check; then
                docker logs "$CONTAINER_NAME"
            else
                error "容器未运行，无法查看日志"
                return 1
            fi
            ;;
    esac
}

# 检查部署参数
check_deploy_params() {
    [[ -z "$DOCKER_ROOT" || -z "$HOST_IP" ]] && {
        error "关键参数未配置！请先运行选项2进行配置"
        return 1
    }
    return 0
}

# 初始化直播录制服务
# 修改 init_service 函数中的服务配置部分
case $service_type in
    "bililive")
        container_name="$CONTAINER_NAME"
        data_dir="$DOCKER_ROOT:/srv/bililive"
        port="$PORT:8080"
        
        # 启动容器
        info "正在启动容器..."
        if docker run -d \
            --name "$container_name" \
            --restart always \
            --network bridge \
            -p "$port" \
            -v "$data_dir" \
            "$(get_current_image $service_type)"; then

            success "服务启动成功"
            info "访问地址: http://${HOST_IP}:${PORT}"
            return 0
        fi
        ;;
    "memos")
        # 启动容器
        info "正在启动容器..."
        if docker run -d \
            --init \
            --name memos \
            --publish 5230:5230 \
            --volume ~/.memos/:/var/opt/memos \
            "$(get_current_image $service_type)"; then

            success "服务启动成功"
            info "访问地址: http://${HOST_IP}:5230"
            return 0
        fi
        ;;
    *)
        error "未知的服务类型"
        return 1
        ;;
esac

error "容器启动失败"
return 1
}

# 配置向导
configure_essential() {
    while :; do
        header
        info "开始初始配置（首次运行必需）"

        safe_input "DOCKER_ROOT" "录制数据存储路径" "${DOCKER_ROOT}" "path"
        safe_input "HOST_IP" "服务器IP地址" "${HOST_IP:-$(ip route get 1 | awk '{print $7}' | head -1)}" "ip"
        safe_input "PORT" "Web界面端口" "${PORT:-9595}" "port"
        safe_input "IMAGE_SOURCE" "镜像源选择(private/official)" "${IMAGE_SOURCE:-official}" "image_source"

        header
        echo -e "${COLOR_BLUE}当前配置预览："
        echo -e "▷ 数据存储路径: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_BLUE}"
        echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}${COLOR_BLUE}"
        echo -e "▷ Web界面端口: ${COLOR_CYAN}${PORT}${COLOR_BLUE}"
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
    done
}

# 卸载服务
uninstall_service() {
    header
    echo -e "${COLOR_GREEN} 选择要卸载的服务"
    header
    echo -e " 1. B站直播录制"
    echo -e " 2. Memos 笔记"
    echo -e " 0. 返回主菜单"
    header

    read -rp "$(echo -e "${COLOR_CYAN}请输入要卸载的服务编号: ${COLOR_RESET}")" choice
    # 修改 uninstall_service 函数中的卸载配置
    case $choice in
        1) do_uninstall "bililive" "$CONTAINER_NAME" "$DOCKER_ROOT" ;;
        2) do_uninstall "memos" "memos" "${HOME}/.memos" ;;
        0) return ;;
        *) error "无效选项" ;;
    esac
}

# 新增 do_uninstall 函数
do_uninstall() {
    local service_type="$1"
    local container_name="$2"
    local data_dir="$3"

    header
    warning "此操作将永久删除 ${service_type} 服务的容器及数据！"
    read -rp "$(echo -e "${COLOR_RED}确认要卸载服务吗？(输入YES确认): ${COLOR_RESET}")" confirm
    [[ "$confirm" != "YES" ]] && { info "已取消卸载"; return; }

    manage_container remove "$container_name"
    read -rp "$(echo -e "${COLOR_YELLOW}是否同时删除数据目录 ${data_dir}？(y/N): ${COLOR_RESET}")" del_data
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        rm -rf "$data_dir"
        success "数据目录已删除"
    fi
    success "${service_type} 服务已卸载"
}

# 显示菜单
show_menu() {
    clear
    header
    echo -e "${COLOR_GREEN} NASPT 直播录制服务管理脚本 v2.0"
    header
    echo -e " 1. 完整部署"
    echo -e " 2. 修改配置"
    echo -e " 3. 管理服务"
    echo -e " 4. 查看日志"
    echo -e " 5. 完全卸载"
    echo -e " 0. 退出脚本"
    header
}

# 服务管理菜单
show_service_menu() {
    header
    echo -e "${COLOR_GREEN} 服务管理"
    header
    echo -e " 1. 启动服务"
    echo -e " 2. 停止服务"
    echo -e " 3. 重启服务"
    echo -e " 4. 查看状态"
    echo -e " 0. 返回主菜单"
    header
}

# 添加服务选择菜单函数
show_deploy_menu() {
    header
    echo -e "${COLOR_GREEN} 选择要部署的服务"
    header
    echo -e " 1. B站直播录制"
    echo -e " 2. Memos 笔记"
    echo -e " 0. 返回主菜单"
    header
}

# 主程序流程
main() {
    check_dependencies
    check_network
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
                while :; do
                    show_deploy_menu
                    read -rp "$(echo -e "${COLOR_CYAN}请输入要部署的服务编号: ${COLOR_RESET}")" deploy_choice
                    
                    case $deploy_choice in
                        1)
                            header
                            if [[ -n "$DOCKER_ROOT" && -n "$HOST_IP" ]]; then
                                info "检测到当前配置："
                                echo -e "▷ 数据存储路径: ${COLOR_CYAN}${DOCKER_ROOT}${COLOR_RESET}"
                                echo -e "▷ 服务器IP: ${COLOR_CYAN}${HOST_IP}${COLOR_RESET}"
                                echo -e "▷ Web界面端口: ${COLOR_CYAN}${PORT}${COLOR_RESET}"
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

                            init_service "bililive"
                            ;;
                        2)
                            init_service "memos"
                            ;;
                        0) break ;;
                        *) error "无效选项" ;;
                    esac
                    
                    [[ "$deploy_choice" != "0" ]] && read -rp "$(echo -e "${COLOR_CYAN}按 Enter 继续...${COLOR_RESET}")"
                done
                ;;
            2) 
                configure_essential 
                ;;
            3)
                while :; do
                    show_service_menu
                    read -rp "$(echo -e "${COLOR_CYAN}请输入操作编号: ${COLOR_RESET}")" service_choice
                    
                    case $service_choice in
                        1) manage_container start ;;
                        2) manage_container stop ;;
                        3) 
                            manage_container stop
                            sleep 2
                            manage_container start
                            ;;
                        4)
                            header
                            echo -e "${COLOR_CYAN}容器状态:"
                            docker ps -a --filter "name=${CONTAINER_NAME}" \
                                --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
                            header
                            ;;
                        0) break ;;
                        *) error "无效选项" ;;
                    esac
                    
                    [[ "$service_choice" != "0" ]] && read -rp "$(echo -e "${COLOR_CYAN}按 Enter 继续...${COLOR_RESET}")"
                done
                continue
                ;;
            4)
                header
                manage_container logs
                header
                ;;
            5)
                uninstall_service
                ;;
            0)
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

# 执行主程序
main