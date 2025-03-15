#!/bin/bash

DEFAULT_DOCKER_PATH=""
DEFAULT_VIDEO_PATH=""
HOST_IP=""
GITHUB_PROXY=""

# 获取用户输入
get_input() {
  local var_name="$1"
  local prompt_message="$2"
  local default_value="$3"
  local value

  while true; do
    read -r -p "$prompt_message ---: " value
    value="${value:-$default_value}"
    eval "$var_name='$value'"
    break
  done
}

# 通用的下载和解压函数
download_and_extract() {
  local url="$1"                   # 下载文件的 URL
  local output_file="$2"           # 下载到本地的路径
  local extract_path="$3"          # 解压目标路径
  local strip_components="${4:-1}" # 默认 strip-components 为 1

  # 检查文件是否已存在，如果已存在则跳过下载
  if [ -f "$output_file" ]; then
    echo "文件 $output_file 已存在，跳过下载。"
  else
    echo "正在下载文件: $url"
    if ! curl -L "$url" -o "$output_file"; then
      echo "错误: 无法下载文件 $url，请检查网络连接或 URL 是否正确。"
      exit 1
    fi
  fi

  echo "正在解压文件到: $extract_path"
  mkdir -p "$extract_path"
  if ! tar --strip-components="$strip_components" -zxvf "$output_file" -C "$extract_path"; then
    echo "错误: 解压文件 $output_file 失败，请检查文件内容是否正确。"
    exit 1
  fi
}

#############################
# 获取全局输入
#############################
get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DEFAULT_DOCKER_PATH"
get_input "VIDEO_ROOT_PATH" "请输入视频文件根路径" "$DEFAULT_VIDEO_PATH"
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"
get_input "GITHUB_PROXY" "请输入git加速地址( https://ghproxy.link/ ): " "$GITHUB_PROXY"



# 导出环境变量（看具体镜像需求，如需要则加上）
export USER_ID GROUP_ID DOCKER_ROOT_PATH VIDEO_ROOT_PATH HOST_IP GITHUB_PROXY

echo -e "\n====================================================="
echo "主机 IP 地址: $HOST_IP"
echo "Docker 根路径: $DOCKER_ROOT_PATH"
echo "视频文件根路径: $VIDEO_ROOT_PATH"
echo "GIT加速地址：$GITHUB_PROXY"
echo -e "=====================================================\n"

init_qbittorrent() {
  echo "=== 初始化 qBittorrent ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-qb"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-qb.tgz" \
    "$DOCKER_ROOT_PATH/naspt-qb.tgz" \
    "$DOCKER_ROOT_PATH/naspt-qb/"

  docker run -d --name naspt-qb --restart unless-stopped \
    -v "$DOCKER_ROOT_PATH/naspt-qb/config:/config" \
    -v "$VIDEO_ROOT_PATH:/media" \
    -e PUID=0 \
    -e PGID=0 \
    -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    -e WEBUI_PORT=9000 \
    -e SavePatch="/media/downloads" \
    -e TempPatch="/media/downloads" \
    --network host \
    --privileged \
    "ccr.ccs.tencentyun.com/naspt/qbittorrent:4.6.4"
}

init_transmission() {
  echo "=== 初始化 Transmission ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-tr"
  mkdir -p "$VIDEO_ROOT_PATH/站点刷流"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-tr.tgz" \
    "$DOCKER_ROOT_PATH/naspt-tr.tgz" \
    "$DOCKER_ROOT_PATH/naspt-tr/"
  docker run -d --name='naspt-tr' --restart unless-stopped --privileged=true \
    --network host \
    -e PUID=0 -e PGID=0 -e UMASK=022 \
    -e TZ="Asia/Shanghai" \
    -e 'USER'='admin' \
    -e 'PASS'='a123456!@' \
    -e 'TRANSMISSION_WEB_HOME'='/config/2/src' \
    -v "$VIDEO_ROOT_PATH:/media" \
    -v "$DOCKER_ROOT_PATH/naspt-tr/config:/config" \
    'ccr.ccs.tencentyun.com/naspt/transmission:4.0.5'
}

init_emby() {
  echo "=== 初始化 Emby ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-emby"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-emby.tgz" \
    "$DOCKER_ROOT_PATH/naspt-emby.tgz" \
    "$DOCKER_ROOT_PATH/naspt-emby/"
  docker run -d --name naspt-emby --restart unless-stopped \
    -v "$DOCKER_ROOT_PATH/naspt-emby/config:/config" \
    -v "$VIDEO_ROOT_PATH:/media" \
    -e UID=0 \
    -e GID=0 \
    -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    --device /dev/dri:/dev/dri \
    --network host \
    --privileged \
    "ccr.ccs.tencentyun.com/naspt/embyserver:beta"
}

init_chinese_sub_finder() {
  echo "=== 初始化 Chinese-Sub-Finder ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-csf"
  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-csf.tgz" \
    "$DOCKER_ROOT_PATH/naspt-csf.tgz" \
    "$DOCKER_ROOT_PATH/naspt-csf/"

  # 根据输入 IP 替换配置
  sed -i "s/10.10.10.104/$HOST_IP/g" \
    "$DOCKER_ROOT_PATH/naspt-csf/config/ChineseSubFinderSettings.json"

  docker run -d --name naspt-csf --restart unless-stopped \
    -v "$DOCKER_ROOT_PATH/naspt-csf/config:/config" \
    -v "$DOCKER_ROOT_PATH/naspt-csf/cache:/app/cache" \
    -v "$VIDEO_ROOT_PATH:/media" \
    -e PUID=0 \
    -e PGID=0 \
    -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    --network host \
    --privileged \
    "ccr.ccs.tencentyun.com/naspt/chinesesubfinder:latest"
}

init_moviepilot() {
  echo "=== 初始化 MoviePilot ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-mpv2/"{main,config,core}
  mkdir -p "$VIDEO_ROOT_PATH/downloads" "$VIDEO_ROOT_PATH/links"

  local categories=("剧集" "动漫" "电影")
  local subcategories_juji=("国产剧集" "日韩剧集" "欧美剧集" "综艺节目" "纪录片" "儿童剧集" "纪录影片" "港台剧集" "南亚剧集")
  local subcategories_dongman=("国产动漫" "欧美动漫" "日本番剧")
  local subcategories_dianying=("儿童电影" "动画电影" "国产电影" "日韩电影" "欧美电影" "歌舞电影" "港台电影" "南亚电影")

  # 创建分类文件夹
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

  cat <<EOF >"$DOCKER_ROOT_PATH/naspt-mpv2/config/category.yaml"
movie:
  电影/动画电影:
    genre_ids: '16'
  电影/儿童电影:
    genre_ids: '10762'
  电影/歌舞电影:
    genre_ids: '10402'
  电影/港台电影:
    origin_country: 'TW,HK'
  电影/国产电影:
    origin_country: 'CN'
  电影/日韩电影:
    origin_country: 'JP,KP,KR'
  电影/南亚电影:
    origin_country: 'TH,IN,SG'
  电影/欧美电影:

tv:
  动漫/国产动漫:
    genre_ids: '16'
    origin_country: 'CN,TW,HK'
  动漫/欧美动漫:
    genre_ids: '16'
    origin_country: 'US,FR,GB,DE,ES,IT,NL,PT,RU,UK'
  动漫/日本番剧:
    genre_ids: '16'
    origin_country: 'JP'
  剧集/儿童剧集:
    genre_ids: '10762'
  剧集/纪录影片:
    genre_ids: '99'
  剧集/综艺节目:
    genre_ids: '10764,10767'
  剧集/港台剧集:
    origin_country: 'TW,HK'
  剧集/国产剧集:
    origin_country: 'CN'
  剧集/日韩剧集:
    origin_country: 'JP,KP,KR'
  剧集/南亚剧集:
    origin_country: 'TH,IN,SG'
  剧集/欧美剧集:
EOF

  download_and_extract \
    "https://alist.naspt.vip/d/shell/naspt-mp/naspt-mpv2.tgz" \
    "$DOCKER_ROOT_PATH/naspt-mpv2.tgz" \
    "$DOCKER_ROOT_PATH/naspt-mpv2/"

  docker run -d \
    --name naspt-mpv2 \
    --restart unless-stopped \
    --privileged \
    -v "$VIDEO_ROOT_PATH:/media" \
    -v "$DOCKER_ROOT_PATH/naspt-mpv2/config:/config" \
    -v "$DOCKER_ROOT_PATH/naspt-mpv2/core:/moviepilot/.cache/ms-playwright" \
    -v "$DOCKER_ROOT_PATH/naspt-qb/config/qBittorrent/BT_backup:/qbtr" \
    -e MOVIEPILOT_AUTO_UPDATE=true \
    -e PUID=0 \
    -e PGID=0 \
    -e UMASK=022 \
    -e TZ=Asia/Shanghai \
    -e AUTH_SITE=iyuu \
    -e IYUU_SIGN="IYUU49479T2263e404ce3e261473472d88f75a55d3d44faad1" \
    -e SUPERUSER="admin" \
    -e API_TOKEN="nasptnasptnasptnaspt" \
    -e GITHUB_PROXY="$GITHUB_PROXY" \
    --network host \
    "ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest"

  echo "容器启动完成，开始检测是否生成了 user.db 文件..."
  SECONDS=0
  while true; do
    sleep 1
    USER_DB_FILE="/config/user.db"
    FILE_EXISTS=$(docker exec naspt-mpv2 test -f "$USER_DB_FILE" && echo "exists" || echo "not exists")

    if [[ "$FILE_EXISTS" == "exists" ]]; then
      echo "moviepilot 启动成功！"
      break
    else
      echo -ne "正在初始化 naspt-mpv2... ${SECONDS} 秒 \r"
    fi
  done
  echo
}

init_owjdxb() {
  echo "=== 初始化 Owjdxb (微信通知) ==="
  mkdir -p "$DOCKER_ROOT_PATH/naspt-wx"
  docker run -d --name naspt-wx --restart unless-stopped \
    -v "$DOCKER_ROOT_PATH/naspt-wx:/data/store" \
    --network host \
    --privileged \
    "ccr.ccs.tencentyun.com/naspt/owjdxb:latest"
}

init_database() {
  echo "=== 初始化数据库 (MoviePilot) ==="

  cat <<'EOSQL' >"$DOCKER_ROOT_PATH/naspt-mpv2/config/script.sql"
UPDATE systemconfig SET value = REPLACE(value, '10.10.10.21', '10.10.10.22') WHERE value LIKE '%10.10.10.21%';
EOSQL

  # 替换 IP
  sed -i "s/10.10.10.22/$HOST_IP/g" "$DOCKER_ROOT_PATH/naspt-mpv2/config/script.sql"

  echo "在容器内部执行 SQL 文件修改数据库..."
  docker exec -i -w /config naspt-mpv2 python -c "
import sqlite3

conn = sqlite3.connect('user.db')
cur = conn.cursor()
with open('script.sql', 'r', encoding='utf-8') as f:
    sql_script = f.read()
cur.executescript(sql_script)
conn.commit()
conn.close()
"
  echo "SQL 脚本已执行完毕，数据库初始化完成！"

  echo "重启容器 naspt-mpv2..."
  docker restart naspt-mpv2

  echo "正在检查容器是否成功重启..."
  SECONDS=0
  while true; do
    CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' naspt-mpv2 2>/dev/null || echo "")
    if [[ "$CONTAINER_STATUS" == "running" ]]; then
      echo "容器 naspt-mpv2 重启成功！"
      break
    elif [[ "$CONTAINER_STATUS" == "starting" ]]; then
      echo -ne "正在初始化 naspt-mpv2... ${SECONDS} 秒 \r"
      sleep 1
    else
      echo "错误: 容器 naspt-mpv2 重启失败！状态：$CONTAINER_STATUS"
      exit 1
    fi
  done
  echo
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
  5) init_owjdxb ;;
  6) init_moviepilot ;;
  7) init_database ;;
  *)
    echo "无效选项：$service_id"
    ;;
  esac
}

#############################
# 主菜单循环
#############################
while true; do
  echo "========================================================="
  echo "请选择要安装的服务（可输入数字组合，如 '1234' 表示依次安装多个服务）："
  echo "1. 安装 Transmission"
  echo "2. 安装 Emby"
  echo "3. 安装 qBittorrent"
  echo "4. 安装 Chinese-Sub-Finder"
  echo "5. 安装微信通知（owjdxb）"
  echo "6. 安装 MoviePilot"
  echo "7. 初始化数据库"
  echo "0. 退出"
  echo "========================================================="
  read -r -p "请输入要安装的服务数字组合: " service_choice

  # 默认回车可自定义，如全选或忽略
  service_choice="${service_choice:-654321}"

  # 输入合法性验证：包含 0~7
  if [[ ! "$service_choice" =~ ^[0-7]+$ ]]; then
    echo "输入无效，请仅输入范围 [0-7] 的数字组合。"
    continue
  fi

  # 如果包含 '0'，则执行退出逻辑
  if [[ "$service_choice" == *0* ]]; then
    echo -e "\n准备退出...\n"
    echo "以下是每个服务的默认初始访问信息（如有更改请以实际为准）："
    echo "1. MoviePilot:           http://$HOST_IP:3000    账号: admin   密码: a123456!@"
    echo "2. Emby:                 http://$HOST_IP:8096    账号: admin   密码: a123456!@"
    echo "3. qBittorrent:          http://$HOST_IP:9000    账号: admin   密码: a123456!@"
    echo "4. Chinese-Sub-Finder:   http://$HOST_IP:19035   账号: admin   密码: a123456!@"
    echo "5. 微信通知:             http://$HOST_IP:9118    "
    echo "6. Transmission:         http://$HOST_IP:9091    账号: admin   密码: a123456!@"
    echo
    echo "安装流程结束，感谢使用！"
    # 清理历史命令，如不需要可删除此行
    history -c
    exit 0
  fi

  # 分批安装用户指定的服务
  for ((i = 0; i < ${#service_choice}; i++)); do
    service_id="${service_choice:$i:1}"
    install_service "$service_id"
  done
done
