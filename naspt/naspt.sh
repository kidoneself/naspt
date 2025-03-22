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

# 配置文件
CONFIG_FILE="/root/.naspt.env"
# 必须的全局变量
DOCKER_ROOT=""
HOST_IP=""

# 读取配置文件并检查全局变量
ensure_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        warning "配置文件不存在，正在创建..."
        cat <<EOF > "$CONFIG_FILE"
[global]
HOST_IP=
DOCKER_ROOT=
EOF
        success "已创建默认配置文件: $CONFIG_FILE"
    fi

    source "$CONFIG_FILE"

    for var in "${GLOBAL_VARS[@]}"; do
        eval "value=\$$var"
        if [[ -z "$value" ]]; then
            read -p "请输入 ${var} (必填): " input_value
            while [[ -z "$input_value" ]]; do
                read -p "不能为空！请重新输入 ${var}: " input_value
            done
            sed -i "s|^${var}=.*|${var}=${input_value}|" "$CONFIG_FILE"
            export "$var=$input_value"
            success "已设置 ${var}=${input_value}"
        fi
    done
}

# 添加或更新服务配置
add_or_update_service() {
    local service_name="$1"
    local key="$2"
    local value="$3"

    if grep -q "^\[$service_name\]" "$CONFIG_FILE"; then
        if grep -q "^$key=" "$CONFIG_FILE" -A 10 | grep -q "^\[$service_name\]"; then
            sed -i "/^\[$service_name\]/,/^\[/s|^$key=.*|$key=$value|" "$CONFIG_FILE"
            info "更新 $service_name: $key=$value"
        else
            sed -i "/^\[$service_name\]/a $key=$value" "$CONFIG_FILE"
            info "新增 $service_name: $key=$value"
        fi
    else
        echo -e "\n[$service_name]\n$key=$value" >> "$CONFIG_FILE"
        info "新增服务 $service_name 并添加参数: $key=$value"
    fi
}


# 初始化 Clash
init_clash() {
    ensure_config_file  # 确保全局变量已设置

    declare -A local_vars
    local_vars=(
        ["WEB_PORT"]="8081"
        ["PROXY_PORT"]="7890"
        ["IMAGE"]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/naspt-qb.tgz"
        ["CLASH_CONFIG_URL"]="https://alist.naspt.vip/d/shell/naspt-cl/naspt-cl.tgz"
        ["CLASH_VOLUME"]="naspt-clash"
    )

    # 处理局部变量
    for var in "${!local_vars[@]}"; do
        echo "$var=${local_vars[$var]}" >> "$temp_file"
        add_or_update_service "clash" "$var" "${local_vars[$var]}"
    done

    local config_dir="${DOCKER_ROOT}/${CLASH_VOLUME}"
    mkdir -p "${config_dir}"

#    if netstat -tuln | grep -Eq ":"${local_vars[$WEB_PORT]}"|:"${local_vars[$PROXY_PORT]}""; then
#        error "端口 ${local_vars[$WEB_PORT]} 或 ${local_vars[$PROXY_PORT]} 已被占用"
#        exit 1
#    fi

    info "下载配置文件..."
    download_config "clash" "$config_dir" "$CLASH_CONFIG_URL" || return 1
    info "解压配置文件..."
    tar -zxf "${DOCKER_ROOT}/naspt-clash.tgz" -C "${config_dir}" --strip-components=1 || {
        error "文件解压失败，可能下载损坏"
        rm -rf "$config_dir"
        exit 1
    }

    info "启动 Clash 容器..."
    docker run -d --restart always \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        --network bridge \
        -v "${config_dir}:/root/.config/clash" \
        -p "${WEB_PORT}:8080" \
        -p "${PROXY_PORT}:7890" \
        --name "clash_container" \
        "ccr.ccs.tencentyun.com/naspt/clash-and-dashboard:latest" || {
        error "Clash 启动失败，查看日志：docker logs clash_container"
        exit 1
    }

    success "Clash 已启动"
    info "控制面板: ${COLOR_YELLOW}http://${HOST_IP}:${WEB_PORT}${COLOR_RESET}"
    info "代理地址: ${COLOR_YELLOW}http://${HOST_IP}:${PROXY_PORT}${COLOR_RESET}"
}
# 配置文件下载解压
download_config() {
  local service="$1"
  local dest_dir="$2"
  local url="$3"
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
# 主菜单
main_menu() {
    while true; do
        clear
        echo "=========================="
        echo "       主菜单        "
        echo "=========================="
        echo "1) 系统管理"
        echo "2) 网络配置"
        echo "3) 服务管理"
        echo "4) 读取配置文件"
        echo "5) 退出"
        echo "=========================="
        read -p "请选择一个选项: " choice

        case $choice in
            1) system_management_menu ;;
            2) network_config_menu ;;
            3) service_management_menu ;;
            4) read_config_file ;;
            5) exit 0 ;;
            *) echo "无效选项，请重试" ; sleep 1 ;;
        esac
    done
}

# 系统管理子菜单
system_management_menu() {
    while true; do
        clear
        echo "=========================="
        echo "    系统管理菜单        "
        echo "=========================="
        echo "1) init_clash"
        echo "2) 查看内存使用情况"
        echo "3) 返回主菜单"
        echo "=========================="
        read -p "请选择一个选项: " choice

        case $choice in
            1) init_clash; read -p "按回车键返回..." ;;
            2) free -h; read -p "按回车键返回..." ;;
            3) return ;;
            *) echo "无效选项，请重试" ; sleep 1 ;;
        esac
    done
}

# 网络配置子菜单
network_config_menu() {
    while true; do
        clear
        echo "=========================="
        echo "    网络配置菜单        "
        echo "=========================="
        echo "1) 显示当前IP地址"
        echo "2) 测试网络连通性"
        echo "3) 返回主菜单"
        echo "=========================="
        read -p "请选择一个选项: " choice

        case $choice in
            1) ip a; read -p "按回车键返回..." ;;
            2) read -p "请输入目标地址: " target; ping -c 4 "$target"; read -p "按回车键返回..." ;;
            3) return ;;
            *) echo "无效选项，请重试" ; sleep 1 ;;
        esac
    done
}

# 服务管理子菜单
service_management_menu() {
    while true; do
        clear
        echo "=========================="
        echo "    服务管理菜单        "
        echo "=========================="
        echo "1) 查看运行中的服务"
        echo "2) 重启指定服务"
        echo "3) 返回主菜单"
        echo "4) 添加或更新服务配置"
        echo "=========================="
        read -p "请选择一个选项: " choice

        case $choice in
            1) systemctl list-units --type=service --state=running; read -p "按回车键返回..." ;;
            2) read -p "请输入服务名称: " service; systemctl restart "$service"; read -p "服务已重启，按回车键返回..." ;;
            3) return ;;
            4)
                read -p "请输入服务名称: " service_name
                read -p "请输入键: " key
                read -p "请输入值: " value
                add_or_update_service "$service_name" "$key" "$value"
                read -p "按回车键返回..." ;;
            *) echo "无效选项，请重试" ; sleep 1 ;;
        esac
    done
}

main_menu