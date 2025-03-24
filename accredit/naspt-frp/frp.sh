#!/bin/bash

# 配置颜色输出
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"
COLOR_YELLOW="\033[33m"

# 定义输出函数
info() { echo -e "${COLOR_CYAN}[信息] $*${COLOR_RESET}"; }
success() { echo -e "${COLOR_GREEN}[成功] $*${COLOR_RESET}"; }
error() { echo -e "${COLOR_RED}[错误] $*${COLOR_RESET}" >&2; }
header() { echo -e "${COLOR_BLUE}==========================================${COLOR_RESET}"; }

# 配置文件路径
CONFIG_DIR="/root/.naspt"
CONFIG_FILE="/root/.naspt/naspt.conf"

# 默认配置
SERVER_ID=""
HOST_NAME=""
FRP_SERVER="91.132.146.106"
FRP_AUTH_KEY="9b83aed0cf81aef6d1c5fdb6274b4cb8"

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
  
  # 在section中查找并替换key的值，如果不存在则添加
  if grep -q "^$key=" "$file"; then
    sed -i "/^\[$section\]/,/^\[/s|^$key=.*|$key=$value|" "$file"
  else
    sed -i "/^\[$section\]/a $key=$value" "$file"
  fi
}

# 加载配置
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # 从[frp]部分读取所有配置
    SERVER_ID=$(get_ini_value "$CONFIG_FILE" "frp" "SERVER_ID")
    HOST_NAME=$(get_ini_value "$CONFIG_FILE" "frp" "HOST_NAME")
    FRP_SERVER=$(get_ini_value "$CONFIG_FILE" "frp" "FRP_SERVER")
    FRP_AUTH_KEY=$(get_ini_value "$CONFIG_FILE" "frp" "FRP_AUTH_KEY")
    success "加载历史配置成功"
    return 0
  fi
  return 1
}

# 保存配置
save_config() {
  mkdir -p "$CONFIG_DIR"
  
  # 保存所有配置到[frp]部分
  set_ini_value "$CONFIG_FILE" "frp" "SERVER_ID" "$SERVER_ID"
  set_ini_value "$CONFIG_FILE" "frp" "HOST_NAME" "$HOST_NAME"
  set_ini_value "$CONFIG_FILE" "frp" "FRP_SERVER" "$FRP_SERVER"
  set_ini_value "$CONFIG_FILE" "frp" "FRP_AUTH_KEY" "$FRP_AUTH_KEY"
}

# 参数解析
parse_command() {
  local input=$1
  SERVER_ID=$(grep -oP -- '-s\s+\K\S+' <<< "$input" | tr -d '"')
  HOST_NAME=$(grep -oP -- '-i\s+\K\S+' <<< "$input" | sed 's/naspt.c.//;s/"//g')
  FRP_SERVER=$(grep -oP -- '-r\s+\K\S+' <<< "$input" | tr -d '"')
  FRP_AUTH_KEY=$(grep -oP -- '-a\s+\K\S+' <<< "$input" | tr -d '"')

  [[ "$SERVER_ID" =~ ^[a-f0-9]{8}- ]] || return 1
  [[ -n "$HOST_NAME" ]] || return 1
  return 0
}

# 部署服务
deploy_frp() {
  header
  info "启动FRP客户端容器..."

  # 清理旧容器
  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-frp$"; then
    info "发现已有容器，正在清理..."
    if docker rm -f naspt-frp &>/dev/null; then
      success "旧容器已清除"
    else
      error "容器清理失败，请手动检查"
      exit 1
    fi
  fi

  # 启动新容器
  info "正在创建新容器..."
  if docker run -d \
    --network=host \
    --restart=unless-stopped \
    --name naspt-frp \
    "ccr.ccs.tencentyun.com/naspt/frp-panel" client \
    -s "$SERVER_ID" \
    -i "naspt.c.$HOST_NAME" \
    -a "$FRP_AUTH_KEY" \
    -r "$FRP_SERVER" \
    -c 9001 \
    -p 9000 \
    -e http; then

    success "部署完成"
    info "api回调地址: http://${HOST_NAME}.8768611.xyz:8888/api/v1/message/?token=nasptnasptnasptnaspt"
  else
    error "容器启动失败"
    exit 1
  fi
}

# 卸载服务
uninstall() {
  header
  info "开始卸载 FRP 服务"

  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-frp$"; then
    info "正在停止并删除容器..."
    if docker rm -f naspt-frp &>/dev/null; then
      success "容器删除成功"
    else
      error "容器删除失败"
    fi
  else
    info "未找到运行中的容器"
  fi

  info "配置文件保留在: ${COLOR_YELLOW}${CONFIG_FILE}${COLOR_RESET}"
}

# 查看配置
view_config() {
  header
  info "当前配置信息："

  if [[ -f "$CONFIG_FILE" ]]; then
    success "配置文件路径: ${COLOR_YELLOW}${CONFIG_FILE}${COLOR_RESET}"
    echo -e " 服务ID\t: ${COLOR_YELLOW}$SERVER_ID${COLOR_RESET}"
    echo -e " 主机名称\t: ${COLOR_YELLOW}$HOST_NAME${COLOR_RESET}"
    echo -e " FRP服务器\t: ${COLOR_YELLOW}$FRP_SERVER${COLOR_RESET}"
    echo -e " 认证密钥\t: ${COLOR_YELLOW}$FRP_AUTH_KEY${COLOR_RESET}"
  else
    error "未找到配置文件"
  fi
}

# 修改配置
modify_config() {
  header
  info "请粘贴新的 FRP 命令（示例格式如下）"
  echo -e "${COLOR_YELLOW}frp-panel client -s 新服务ID -i naspt.c.新主机名 -a 新认证密钥...${COLOR_RESET}"
  read -rp "$(echo -e "${COLOR_CYAN}输入新命令: ${COLOR_RESET}")" new_cmd

  if parse_command "$new_cmd"; then
    save_config
    success "配置更新成功！"
    return 0
  else
    error "新命令解析失败，配置未更新"
    return 1
  fi
}

# 服务状态
check_status() {
  header
  info "服务状态检查"

  if docker ps -a --format '{{.Names}}' | grep -q "^naspt-frp$"; then
    echo -e " FRP 状态: ${COLOR_GREEN}已部署${COLOR_RESET}"
    echo -e " 容器名称: naspt-frp"
    echo -e " API地址: http://${HOST_NAME}.8768611.xyz:8888/api/v1/message/?token=nasptnasptnasptnaspt"
  else
    echo -e " FRP 状态: ${COLOR_RED}未部署${COLOR_RESET}"
  fi
}

# 主菜单
show_menu() {
  clear
  header
  echo -e " ${COLOR_GREEN}FRP 服务管理脚本"
  header
  echo -e " 1. 安装/更新服务"
  echo -e " 2. 查看服务状态"
  echo -e " 3. 查看配置信息"
  echo -e " 4. 修改配置信息"
  echo -e " 5. 卸载服务"
  echo -e " 0. 退出脚本"
  header
}

# 主流程
main() {
  load_config

  while true; do
    show_menu
    read -rp "$(echo -e "${COLOR_CYAN}请选择操作 [0-5]: ${COLOR_RESET}")" choice

    case $choice in
      1)
        if [[ -f "$CONFIG_FILE" ]]; then
          read -rp "$(echo -e "${COLOR_YELLOW}检测到现有配置，是否更新？(y/N): ${COLOR_RESET}")" update_choice
          if [[ "$update_choice" == "y" || "$update_choice" == "Y" ]]; then
            modify_config
          fi
          deploy_frp
        else
          while true; do
            header
            info "请粘贴FRP部署命令（示例格式如下）"
            echo -e "frp-panel client -s xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -i naspt.c.主机名 -a xxxx..."
            read -rp "$(echo -e "${COLOR_CYAN}输入命令: ${COLOR_RESET}")" cmd

            if parse_command "$cmd"; then
              save_config
              deploy_frp
              break
            fi
            error "命令解析失败，请检查格式"
          done
        fi
        ;;
      2)
        check_status
        ;;
      3)
        view_config
        ;;
      4)
        if [[ -f "$CONFIG_FILE" ]]; then
          modify_config
          read -rp "$(echo -e "${COLOR_YELLOW}是否立即部署新配置？(Y/n): ${COLOR_RESET}")" deploy_choice
          if [[ "$deploy_choice" != "n" ]]; then
            deploy_frp
          fi
        else
          error "没有可修改的配置"
        fi
        ;;
      5)
        uninstall
        ;;
      0)
        info "感谢使用，再见！"
        exit 0
        ;;
      *)
        error "无效选项"
        ;;
    esac

    read -rp "$(echo -e "${COLOR_CYAN}按 Enter 返回主菜单...${COLOR_RESET}")" _
  done
}

# 执行主程序
main