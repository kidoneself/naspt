#!/bin/bash

DEFAULT_DOCKER_PATH=""
DEFAULT_VIDEO_PATH=""
HOST_IP=""
PROXY_HOST="http://188.68.50.187:7890"

# 设置颜色常量
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

##echo -e "${COLOR_GREEN}=== 优化CMS网络 ===${COLOR_RESET}"
#curl -s -x  http://188.68.50.187:7890 https://raw.githubusercontent.com/cnwikee/CheckTMDB/refs/heads/main/Tmdb_host_ipv4 >> /etc/hosts
#curl -s -x  http://188.68.50.187:7890 https://hosts.gitcdn.top/hosts.txt >> /etc/hosts

# 获取用户输入
get_input() {
  local var_name="$1"
  local prompt_message="$2"
  local default_value="$3"
  local value

  while true; do
    echo -e "\033[36m$prompt_message ===> \033[0m"  # 用 echo 显示带颜色的提示
    read -r value  # 读取输入
    value="${value:-$default_value}"
    eval "$var_name='$value'"
    break
  done
}

# 检查端口是否被占用的函数
check_ports() {
  if [ -z "$1" ]; then
    echo -e "${COLOR_RED}错误: 请提供要检查的端口号${COLOR_RESET}"
    return 1
  fi

  for PORT in "$@"; do
    if lsof -i :$PORT >/dev/null 2>&1; then
      echo -e "${COLOR_YELLOW}端口 $PORT 已被占用${COLOR_RESET}"
    else
      echo -e "${COLOR_GREEN}端口 $PORT 没有被占用${COLOR_RESET}"
    fi
  done
}

# 通用的下载和解压函数
download_and_extract() {
  local url="$1"
  local output_file="$2"
  local extract_path="$3"
  local strip_components="${4:-1}"

  if [ -f "$output_file" ]; then
    echo -e "${COLOR_YELLOW}文件 $output_file 已存在，跳过下载.${COLOR_RESET}"
  else
    echo -e "${COLOR_CYAN}正在下载文件: $url${COLOR_RESET}"
    if ! curl -L "$url" -o "$output_file"; then
      echo -e "${COLOR_RED}错误: 无法下载文件 $url，请检查网络连接或 URL 是否正确。${COLOR_RESET}"
      exit 1
    fi
  fi

  echo -e "${COLOR_CYAN}正在解压文件到: $extract_path${COLOR_RESET}"
  mkdir -p "$extract_path"
  if ! tar --strip-components="$strip_components" -zxvf "$output_file" -C "$extract_path"; then
    echo -e "${COLOR_RED}错误: 解压文件 $output_file 失败，请检查文件内容是否正确。${COLOR_RESET}"
    exit 1
  fi
}

#############################
# 获取全局输入
#############################
get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DEFAULT_DOCKER_PATH"
get_input "VIDEO_ROOT_PATH" "请输入视频文件根路径" "$DEFAULT_VIDEO_PATH"
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"

# 导出环境变量
export USER_ID GROUP_ID DOCKER_ROOT_PATH VIDEO_ROOT_PATH HOST_IP

# 初始化服务函数
init_qbittorrent() {
  echo -e "${COLOR_BLUE}=== 初始化 qBittorrent ===${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}=== 检测端口是否占用 ===${COLOR_RESET}"
  check_ports "9000"
  mkdir -p "$DOCKER_ROOT_PATH/naspt-qb"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-qb.tgz" \
    "$DOCKER_ROOT_PATH/naspt-qb.tgz" \
    "$DOCKER_ROOT_PATH/naspt-qb/"

  docker run -d --name naspt-qb --restart always --privileged \
      -v "$DOCKER_ROOT_PATH/naspt-qb/config:/config" \
      -v "$VIDEO_ROOT_PATH:/media" \
      -e PUID=0 \
      -e PGID=0 \
      -e UMASK=022 \
      -e TZ=Asia/Shanghai \
      -e WEBUI_PORT=9000 \
      -e SavePatch="/media/downloads" \
      -e TempPatch="/media/downloads" \
      --network bridge \
      -p 9000:9000 \
      "ccr.ccs.tencentyun.com/naspt/qbittorrent:4.6.4"
}

init_transmission() {
  echo -e "${COLOR_BLUE}=== 初始化 Transmission ===${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}=== 检测端口是否占用 ===${COLOR_RESET}"
  check_ports "9091"

  mkdir -p "$DOCKER_ROOT_PATH/naspt-tr"
  mkdir -p "$VIDEO_ROOT_PATH/站点刷流"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-tr.tgz" \
    "$DOCKER_ROOT_PATH/naspt-tr.tgz" \
    "$DOCKER_ROOT_PATH/naspt-tr/"

  docker run -d --name='naspt-tr' --restart always --privileged=true \
      --network bridge \
      -e PUID=0 -e PGID=0 -e UMASK=022 \
      -e TZ="Asia/Shanghai" \
      -e 'USER'='admin' \
      -e 'PASS'='a123456!@' \
      -e 'TRANSMISSION_WEB_HOME'='/config/2/src' \
      -v "$VIDEO_ROOT_PATH:/media" \
      -v "$DOCKER_ROOT_PATH/naspt-tr/config:/config" \
      -p 9091:9091 \
      'ccr.ccs.tencentyun.com/naspt/transmission:4.0.5'
}

init_emby() {
  echo -e "${COLOR_BLUE}=== 初始化 Emby ===${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}=== 检测端口是否占用 ===${COLOR_RESET}"
  check_ports "8096"
  mkdir -p "$DOCKER_ROOT_PATH/naspt-emby"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-emby.tgz" \
    "$DOCKER_ROOT_PATH/naspt-emby.tgz" \
    "$DOCKER_ROOT_PATH/naspt-emby/"
  docker run -d --name naspt-emby --restart always \
    -v "$DOCKER_ROOT_PATH/naspt-emby/config:/config" \
    -v "$VIDEO_ROOT_PATH:/media" \
    -e UID=0 \
    -e GID=0 \
    -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    --device /dev/dri:/dev/dri \
    --network bridge \
    --privileged \
    -p 8096:8096 \
    "ccr.ccs.tencentyun.com/naspt/embyserver:beta"
}

init_chinese_sub_finder() {
  echo -e "${COLOR_BLUE}=== 初始化 Chinese-Sub-Finder ===${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}=== 检测端口是否占用 ===${COLOR_RESET}"
  check_ports "19035"
  mkdir -p "$DOCKER_ROOT_PATH/naspt-csf"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-csf.tgz" \
    "$DOCKER_ROOT_PATH/naspt-csf.tgz" \
    "$DOCKER_ROOT_PATH/naspt-csf/"

  docker run -d --name naspt-csf --restart always \
     -v "$DOCKER_ROOT_PATH/naspt-csf/config:/config" \
     -v "$DOCKER_ROOT_PATH/naspt-csf/cache:/app/cache" \
     -v "$VIDEO_ROOT_PATH:/media" \
     -e PUID=0 \
     -e PGID=0 \
     -e UMASK=022 \
     -e TZ=Asia/Shanghai \
     --network bridge \
     --privileged \
     -p 19035:19035 \
     "ccr.ccs.tencentyun.com/naspt/chinesesubfinder:latest"
}

init_moviepilot() {
  echo -e "${COLOR_BLUE}=== 初始化 MoviePilot ===${COLOR_RESET}"
  mkdir -p "$DOCKER_ROOT_PATH/naspt-mpv2/"{config,core}
  mkdir -p "$VIDEO_ROOT_PATH/downloads" "$VIDEO_ROOT_PATH/links"

  local categories=("剧集" "动漫" "电影")
  local subcategories_juji=("国产剧集" "日韩剧集" "欧美剧集" "综艺节目" "纪录片" "儿童剧集" "纪录影片" "港台剧集" "南亚剧集")
  local subcategories_dongman=("国产动漫" "欧美动漫" "日本番剧")
  local subcategories_dianying=("儿童电影" "动画电影" "国产电影" "日韩电影" "欧美电影" "歌舞电影" "港台电影" "南亚电影")

  for category in "${categories[@]}"; do
    case "$category" in
    "剧集") subcategories=("${subcategories_juji[@]}") ;;
    "动漫") subcategories=("${subcategories_dongman[@]}") ;;
    "电影") subcategories=("${subcategories_dianying[@]}") ;;
    esac

    for subcategory in "${subcategories[@]}"; do
      mkdir -p \
        "$VIDEO_ROOT_PATH/downloads/$category/$subcategory" \
        "$VIDEO_ROOT_PATH/links/$category/$subcategory"
    done
  done

  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-mpv2.tgz" \
    "$DOCKER_ROOT_PATH/naspt-mpv2.tgz" \
    "$DOCKER_ROOT_PATH/naspt-mpv2/"

  docker run -d \
      --name naspt-mpv2 \
      --restart always \
      --privileged \
      -v "$VIDEO_ROOT_PATH:/media" \
      -v "$DOCKER_ROOT_PATH/naspt-mpv2/config:/config" \
      -v "$DOCKER_ROOT_PATH/naspt-mpv2/core:/moviepilot/.cache/ms-playwright" \
      -v "$DOCKER_ROOT_PATH/naspt-qb/config/qBittorrent/BT_backup:/qbtr" \
      -e PUID=0 \
      -e PGID=0 \
      -e UMASK=022 \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=icc2022 \
      -e ICC2022_UID="24730" \
      -e ICC2022_PASSKEY="49c421073514d4d981a0cbc4174f4b23" \
      -e SUPERUSER="admin" \
      -e API_TOKEN="nasptnasptnasptnaspt" \
      -e AUTO_UPDATE_RESOURCE=false \
      -e MOVIEPILOT_AUTO_UPDATE=false \
      --network bridge \
      -p 3000:3000 \
      -p 3001:3001 \
      "ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest"

  echo -e "${COLOR_GREEN}=== 优化MP网络 ===${COLOR_RESET}"
  docker exec -it naspt-mpv2 sh -c "curl -Ls https://alist.naspt.vip/d/%E5%85%AC%E5%BC%80%E8%B5%84%E6%96%99/hosts.txt >> /etc/hosts"
}

#############################
# 安装服务主逻辑
#############################
install_service() {
  local service_id="$1"
  case "$service_id" in
  1) init_transmission ;;
  2) init_emby ;;
  3) init_qbittorrent ;;
  4) init_chinese_sub_finder ;;
  5) init_moviepilot ;;
  *)
    echo -e "${COLOR_RED}无效选项：$service_id${COLOR_RESET}"
    ;;
  esac
}

#############################
# 主菜单循环
#############################
while true; do
  echo -e "${COLOR_BLUE}=========================================================${COLOR_RESET}"
  echo -e "${COLOR_GREEN}请选择要安装的服务（可输入数字组合，如 '1234' 表示依次安装多个服务）：${COLOR_RESET}"
  echo -e "1. 安装 tr"
  echo -e "2. 安装 emby"
  echo -e "3. 安装 qb"
  echo -e "4. 安装 csf"
  echo -e "5. 安装 mp"
  echo -e "0. 退出"
  echo -e "${COLOR_BLUE}=========================================================${COLOR_RESET}"
  read -r -p "请输入要安装的服务数字组合: " service_choice

  service_choice="${service_choice:-12345}"

  if [[ ! "$service_choice" =~ ^[0-7]+$ ]]; then
    echo -e "${COLOR_RED}输入无效，请仅输入范围 [0-7] 的数字组合。${COLOR_RESET}"
    continue
  fi

  if [[ "$service_choice" == *0* ]]; then
    echo -e "\n${COLOR_YELLOW}准备退出...\n${COLOR_RESET}"
    echo -e "${COLOR_GREEN}以下是每个服务的默认初始访问信息（如有更改请以实际为准）：${COLOR_RESET}"
    echo -e "http://$HOST_IP:3000"
    echo -e "http://$HOST_IP:8096"
    echo -e "http://$HOST_IP:9000"
    echo -e "http://$HOST_IP:19035"
    echo -e "http://$HOST_IP:9091"
    echo -e "${COLOR_GREEN}统一账号：admin   密码：a123456!@${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}安装流程结束，感谢使用！${COLOR_RESET}"
    history -c
    exit 0
  fi

  for ((i = 0; i < ${#service_choice}; i++)); do
    service_id="${service_choice:$i:1}"
    install_service "$service_id"
  done
done