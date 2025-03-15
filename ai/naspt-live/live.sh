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
DOCKER_ROOT="${HOME}/bililive-data"
HOST_IP=""
CONTAINER_NAME="naspt-bililive"
IMAGE_NAME="ccr.ccs.tencentyun.com/naspt/bililive-go:latest"
PORT=9595

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
        ;;
      "ip")
        if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          error "无效的IP地址格式"
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
      if docker rm -f "$CONTAINER_NAME" &>/dev/null; then
        success "已移除旧容器: $CONTAINER_NAME"
      else
        error "无法移除容器: $CONTAINER_NAME"
        exit 1
      fi
      ;;
  esac
}

# 初始化直播录制服务
init_service() {
  header
  info "正在初始化直播录制服务"

  # 清理旧容器
  if manage_container check; then
    warning "发现已存在的容器: $CONTAINER_NAME"
    read -rp "$(echo -e "${COLOR_CYAN}是否重新创建容器？(y/N): ${COLOR_RESET}")" confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      manage_container remove
    else
      info "保留现有容器"
      return
    fi
  fi

  # 创建数据目录
  if ! mkdir -p "$DOCKER_ROOT"; then
    error "无法创建数据目录: $DOCKER_ROOT"
    exit 1
  fi

  # 启动容器
  info "正在启动容器..."
  if docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    --network bridge \
    -p "$PORT:8080" \
    -v "$DOCKER_ROOT:/srv/bililive" \
    "$IMAGE_NAME"; then

    success "服务启动成功"
    info "访问地址: http://${HOST_IP}:${PORT}"
  else
    error "容器启动失败"
    exit 1
  fi
}

# 主程序流程
main() {
  clear
  check_dependencies

  # 获取配置信息
  header
  safe_input "DOCKER_ROOT" "请输入录制数据存储路径" "$DOCKER_ROOT" "path"
  safe_input "HOST_IP" "请输入服务器IP地址" "$(ip route get 1 | awk '{print $7}' | head -1)" "ip"

  # 显示配置确认
  header
  info "配置信息确认"
  echo -e "数据存储路径: ${COLOR_YELLOW}${DOCKER_ROOT}${COLOR_RESET}"
  echo -e "服务器IP地址: ${COLOR_YELLOW}${HOST_IP}${COLOR_RESET}"

  read -rp "$(echo -e "${COLOR_CYAN}是否继续安装？(y/N): ${COLOR_RESET}")" confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

  # 执行安装
  init_service

  # 输出访问信息
  header
  success "服务部署完成！"
  echo -e "${COLOR_YELLOW}=== 重要提示 ===${COLOR_RESET}"
  echo -e "1. 请确保防火墙已开放端口: ${PORT}/TCP"
  echo -e "2. 录制文件将保存至: ${DOCKER_ROOT}"
  echo -e "3. 查看日志命令: docker logs ${CONTAINER_NAME}"
}

# 执行主程序
main