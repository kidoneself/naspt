#!/bin/bash

# 全局变量定义
DOCKER_ROOT_PATH=""
VIDEO_ROOT_PATH=""
PROXY_HOST="http://188.68.50.187:7890"
USE_PROXY=true  # 控制是否启用代理
# 设置颜色常量
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_BLUE="\033[34m"

#
#echo -e "${COLOR_GREEN}=== 优化CMS网络 ===${COLOR_RESET}"
curl -s -x  http://188.68.50.187:7890 https://raw.githubusercontent.com/cnwikee/CheckTMDB/refs/heads/main/Tmdb_host_ipv4 >> /etc/hosts
curl -s -x  http://188.68.50.187:7890 https://hosts.gitcdn.top/hosts.txt >> /etc/hosts

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



get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DOCKER_ROOT_PATH"
get_input "VIDEO_ROOT_PATH" "请输入115媒体库根路径" "$VIDEO_ROOT_PATH"
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"
        # 代理设置
    if [ "$USE_PROXY" == true ]; then
        PROXY_VARS="-e NO_PROXY=172.17.0.1,127.0.0.1,localhost -e ALL_PROXY=$PROXY_HOST -e HTTP_PROXY=$PROXY_HOST"
    else
        PROXY_VARS=""
    fi

# 导出环境变量
export DOCKER_ROOT_PATH VIDEO_ROOT_PATH  HOST_IP

# 启动每个服务的函数
init_cms_auto() {
  echo "初始化 naspt-115-emby"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-emby"
    if [ ! -f "$DOCKER_ROOT_PATH/115-emby.tgz" ]; then
    echo "文件不存在，开始下载..."
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/cms/115-emby.tgz > "$DOCKER_ROOT_PATH/115-emby.tgz"
    else
        echo "文件已存在，跳过下载。"
    fi
    tar --strip-components=1 -zxf "$DOCKER_ROOT_PATH/115-emby.tgz" -C "$DOCKER_ROOT_PATH/naspt-115-emby/"
      docker run -d  --restart  always\
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        $PROXY_VARS \
        --network bridge \
        -v "$VIDEO_ROOT_PATH:/media" \
        -v "$DOCKER_ROOT_PATH/naspt-115-emby/config:/config" \
        -v /etc/hosts:/etc/hosts \
        -p 18096:8096 \
        -p 18920:8920 \
        --name=naspt-115-emby \
        ccr.ccs.tencentyun.com/naspt/emby_unlockd:latest

    echo "初始化 cms"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms/config/"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/logs"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/cache"
    docker run -d \
      --privileged \
      --name naspt-115-cms \
      --restart always \
      --network bridge \
      -p 9527:9527 \
      -p 9096:9096 \
      -v "$DOCKER_ROOT_PATH/naspt-115-cms/config:/config" \
      -v "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/logs:/logs" \
      -v "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/cache:/var/cache/nginx/emby" \
      -v "$VIDEO_ROOT_PATH:/media" \
      -v /etc/hosts:/etc/hosts \
      -e PUID=0 -e PGID=0 -e UMASK=022 \
      -e TZ=Asia/Shanghai \
      -e RUN_ENV=online \
      -e ADMIN_USERNAME=admin \
      -e ADMIN_PASSWORD=a123456!@ \
      -e EMBY_HOST_PORT=http://$HOST_IP:18096 \
      -e EMBY_API_KEY=40b107b7417f4a04b0180fd67a90dd79 \
      -e IMAGE_CACHE_POLICY=2 \
      -e DONATE_CODE=CMS_HQFO2BSD_EE104D0293B84F668F7CC0B518F3AAD2 \
      ccr.ccs.tencentyun.com/naspt/cloud-media-sync:latest

      cat <<EOF > "$DOCKER_ROOT_PATH/naspt-115-cms/config/category.yaml"
# 配置电影的分类策略
movie:
  # 分类名仅为标识 不起任何作用
  动画电影:
    ###### cid为115文件夹的cid 必须有 ######
    cid: 3108164003358778166
    # 匹配 genre_ids 内容类型，16是动漫
    genre_ids: '16'
  华语电影:
    cid: 3108164004407354169
    # 匹配语种
    original_language: 'zh,cn,bo,za'
  # 未匹配以上条件时，返回最后一个
  外语电影:
    cid: 3108164003929203511

# 配置电视剧的分类策略
tv:
  国漫:
    cid: 3108164001572004657
    genre_ids: '16'
    # 匹配 origin_country 国家，CN是中国大陆，TW是中国台湾，HK是中国香港
    origin_country: 'CN,TW,HK'
  日番:
    cid: 3108163998325613354
    genre_ids: '16'
    # 匹配 origin_country 国家，JP是日本
    origin_country: 'JP'
  纪录片:
    cid: 3108163998828929835
    # 匹配 genre_ids 内容类型，99是纪录片
    genre_ids: '99'
  儿童:
    cid: 3108163999852340013
    # 匹配 genre_ids 内容类型，10762是儿童
    genre_ids: '10762'
  综艺:
    cid: 3108164002117264179
    # 匹配 genre_ids 内容类型，10764 10767都是综艺
    genre_ids: '10764,10767'
  国产剧:
    cid: 3108164002712855348
    # 匹配 origin_country 国家，CN是中国大陆，TW是中国台湾，HK是中国香港
    origin_country: 'CN,TW,HK'
  欧美剧:
    cid: 3108164000330490670
    # 匹配 origin_country 国家，主要欧美国家列表
    origin_country: 'US,FR,GB,DE,ES,IT,NL,PT,RU,UK'
  日韩剧:
    cid: 3108163999332246316
    # 匹配 origin_country 国家，主要亚洲国家列表
    origin_country: 'JP,KP,KR,TH,IN,SG'
  未分类:
    cid: 3108164000934470447
EOF
}


init_cms_manually() {
 echo "初始化 naspt-115-emby"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-emby"
    if [ ! -f "$DOCKER_ROOT_PATH/115-emby.tgz" ]; then
    echo "文件不存在，开始下载..."
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/cms/115-emby.tgz > "$DOCKER_ROOT_PATH/115-emby.tgz"
    else
        echo "文件已存在，跳过下载。"
    fi
    tar --strip-components=1 -zxf "$DOCKER_ROOT_PATH/115-emby.tgz" -C "$DOCKER_ROOT_PATH/naspt-115-emby/"
      docker run -d  --restart  always\
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        $PROXY_VARS \
         --network bridge \
        -v "$VIDEO_ROOT_PATH:/media" \
        -v "$DOCKER_ROOT_PATH/naspt-115-emby/config:/config" \
        -v /etc/hosts:/etc/hosts \
        -p 18096:8096 \
        -p 18920:8920 \
        --name=naspt-115-emby \
        ccr.ccs.tencentyun.com/naspt/emby_unlockd:latest

    echo "初始化 cms"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms/config/"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/logs"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/cache"
    docker run -d \
      --privileged \
      --name naspt-115-cms \
      --restart always \
      --network bridge \
      -p 9527:9527 \
      -p 9096:9096 \
      -v "$DOCKER_ROOT_PATH/naspt-115-cms/config:/config" \
      -v "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/logs:/logs" \
      -v "$DOCKER_ROOT_PATH/naspt-115-cms/nginx/cache:/var/cache/nginx/emby" \
      -v "$VIDEO_ROOT_PATH:/media" \
      -v /etc/hosts:/etc/hosts \
      -e PUID=0 -e PGID=0 -e UMASK=022 \
      -e TZ=Asia/Shanghai \
      -e RUN_ENV=online \
      -e ADMIN_USERNAME=admin \
      -e ADMIN_PASSWORD=a123456!@ \
      -e EMBY_HOST_PORT=http://$HOST_IP:18096 \
      -e EMBY_API_KEY=40b107b7417f4a04b0180fd67a90dd79 \
      -e IMAGE_CACHE_POLICY=2 \
      -e DONATE_CODE=CMS_HQFO2BSD_EE104D0293B84F668F7CC0B518F3AAD2 \
      ccr.ccs.tencentyun.com/naspt/cloud-media-sync:latest

}
#############################
# 安装服务主逻辑
#############################
install_service() {
  local service_id="$1"
  case "$service_id" in
  1) init_cms_manually ;;
  2) init_cms_auto ;;
  *)
    echo -e "${COLOR_RED}无效选项：$service_id${COLOR_RESET}"
    ;;
  esac
}

# 卸载服务的函数
uninstall_service() {
  local service_id="$1"
  case "$service_id" in
  3)
    echo "停止并删除 cms 容器及文件夹..."
    docker stop naspt-115-cms && docker rm naspt-115-cms
    rm -rf "$DOCKER_ROOT_PATH/naspt-115-cms"
    docker stop naspt-115-emby && docker rm naspt-115-emby
    rm -rf "$DOCKER_ROOT_PATH/naspt-115-emby"
    ;;
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
  echo -e "${COLOR_GREEN}请选择要安装或卸载的服务：${COLOR_RESET}"
  echo -e "1. ${COLOR_GREEN}安装cms自己整理${COLOR_RESET}"
  echo -e "2. ${COLOR_YELLOW}安装cms 程序整理${COLOR_RESET}"
  echo -e "3. ${COLOR_RED}卸载cms${COLOR_RESET}"
  echo -e "0. 退出"
  echo -e "${COLOR_BLUE}=========================================================${COLOR_RESET}"
  read -r -p "请输入要操作的数字组合: " service_choice

  service_choice="${service_choice:-2}"

  if [[ ! "$service_choice" =~ ^[0-3]+$ ]]; then
    echo -e "${COLOR_RED}输入无效，请仅输入范围 [0-3] 的数字组合。${COLOR_RESET}"
    continue
  fi

  if [[ "$service_choice" == *0* ]]; then
    echo -e "\n${COLOR_YELLOW}准备退出...\n${COLOR_RESET}"
    echo -e "${COLOR_GREEN}以下是每个服务的默认初始访问信息（如有更改请以实际为准）：${COLOR_RESET}"
    echo -e "http://$HOST_IP:9527"
    echo -e "http://$HOST_IP:9096"
    echo -e "${COLOR_GREEN}统一账号：admin   密码：a123456!@${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}安装流程结束，感谢使用！${COLOR_RESET}"
    history -c
    exit 0
  fi

  for ((i = 0; i < ${#service_choice}; i++)); do
    service_id="${service_choice:$i:1}"
    if [[ "$service_id" =~ ^[1-2]$ ]]; then
      install_service "$service_id"
    elif [[ "$service_id" =~ ^[3-4]$ ]]; then
      uninstall_service "$service_id"
    fi
  done
done