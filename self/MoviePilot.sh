#!/bin/bash



CURRENT_DIR="/root/naspt"
# 检查 CURRENT_DIR 是否存在，如果不存在则创建
if [ ! -d "$CURRENT_DIR" ]; then
    mkdir -p "$CURRENT_DIR"
    echo "目录 $CURRENT_DIR 不存在，已创建。"
else
    echo "目录 $CURRENT_DIR 已存在。"
fi
PUID="${PUID:-0}"
PGID="${PGID:-0}"
UMASK="${UMASK:-022}"
DEFAULT_DOCKER_PATH=""
DEFAULT_VIDEO_PATH=""

# 获取用户输入
get_input() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    local value
    while true; do
        read -p "$prompt_message $default_value: " value
        value="${value:-$default_value}"
        eval "$var_name='$value'"
        break
    done
}

# 获取 Docker 根路径和视频根路径
get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DEFAULT_DOCKER_PATH"
get_input "VIDEO_ROOT_PATH" "请输入视频文件根路径" "$DEFAULT_VIDEO_PATH"


while [ -z "$HOST_IP" ]; do
    read -p "请输入主机 IP 地址 [回车使用默认：$HOST_IP]：" input_ip
    HOST_IP="${input_ip:-$HOST_IP}"
    if [ -z "$HOST_IP" ]; then
        echo -e "主机 IP 地址不能为空，请重新输入。"
    fi
done




# 获取用户名并设置 USER_ID 和 GROUP_ID
read -p "请输入nas登录用户名: " USER_NAME
USER_ID=$(id -u "$USER_NAME")
GROUP_ID=$(id -g "$USER_NAME")

# 导出环境变量
export USER_ID
export GROUP_ID
export DOCKER_ROOT_PATH
export VIDEO_ROOT_PATH
export HOST_IP

# 确保目录结构


# 显示设置的配置信息
echo -e "最终的主机 IP 地址是: $HOST_IP"
echo -e "Docker 根路径: $DOCKER_ROOT_PATH"
echo -e "视频文件根路径: $VIDEO_ROOT_PATH"
echo -e "用户信息：PUID=$USER_ID($USER_NAME) PGID=$GROUP_ID UMASK=022"

# 启动每个服务的函数
init_qbittorrent() {
    echo "初始化 qBittorrent"
    mkdir -p "$DOCKER_ROOT_PATH/qb-9000"
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/MoviePilot/naspt-qb.tgz -o "$CURRENT_DIR/naspt-qb.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/naspt-qb.tgz" -C "$DOCKER_ROOT_PATH/qb-9000/"
    docker run -d --name qb-9000 --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/qb-9000/config:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=9000 \
        -e SavePatch="/media/downloads" -e TempPatch="/media/downloads" \
        --network host --privileged \
        "ccr.ccs.tencentyun.com/naspt/qbittorrent:4.6.4"
}

init_emby() {
    echo "初始化 Emby"
    mkdir -p "$DOCKER_ROOT_PATH/emby"
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/MoviePilot/naspt-emby.tgz > "$CURRENT_DIR/naspt-emby.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/naspt-emby.tgz" -C "$DOCKER_ROOT_PATH/emby/"
    docker run -d --name emby --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/emby/config:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e UID="$PUID" -e GID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --device /dev/dri:/dev/dri \
        --network host --privileged \
        "ccr.ccs.tencentyun.com/naspt/embyserver:beta"
}

init_chinese_sub_finder() {
    echo "初始化 Chinese-Sub-Finder"
    mkdir -p "$DOCKER_ROOT_PATH/chinese-sub-finder"
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/MoviePilot/naspt-csf.tgz > "$CURRENT_DIR/naspt-csf.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/naspt-csf.tgz" -C "$DOCKER_ROOT_PATH/chinese-sub-finder/"
    sed -i "s/192.168.2.100/$HOST_IP/g" "$DOCKER_ROOT_PATH/chinese-sub-finder/config/ChineseSubFinderSettings.json"
    docker run -d --name chinese-sub-finder --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/chinese-sub-finder/config:/config" \
        -v "$DOCKER_ROOT_PATH/chinese-sub-finder/cache:/app/cache" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --network host --privileged \
        "ccr.ccs.tencentyun.com/naspt/chinesesubfinder:latest"
}

init_moviepilot() {
    echo "初始化 MoviePilot"
    mkdir -p "$DOCKER_ROOT_PATH/moviepilot-v2/"{main,config,core}
    mkdir -p "$VIDEO_ROOT_PATH/downloads" "$VIDEO_ROOT_PATH/links"
    categories=("剧集" "动漫" "电影")
    subcategories_juji=("国产剧集" "日韩剧集" "欧美剧集" "综艺节目" "纪录片")
    subcategories_dongman=("国产动漫" "欧美动漫")
    subcategories_dianying=("儿童电影" "动画电影" "国产电影" "日韩电影" "欧美电影")
    # 创建文件夹
    for category in "${categories[@]}"; do
      if [ "$category" == "剧集" ]; then
        subcategories=("${subcategories_juji[@]}")
      elif [ "$category" == "动漫" ]; then
        subcategories=("${subcategories_dongman[@]}")
      else
        subcategories=("${subcategories_dianying[@]}")
      fi

      for subcategory in "${subcategories[@]}"; do
        mkdir -p "$VIDEO_ROOT_PATH/downloads/$category/$subcategory" \
                 "$VIDEO_ROOT_PATH/links/$category/$subcategory"
      done
    done

    echo "GITHUB_PROXY='https://mirror.ghproxy.com/'" > "$DOCKER_ROOT_PATH/moviepilot-v2/config/"app.env
    cat <<EOF > "$DOCKER_ROOT_PATH/moviepilot-v2/config/category.yaml"
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
    # 检查 core.tgz 是否已经存在，如果存在则跳过下载
    curl -L https://naspt.oss-cn-shanghai.aliyuncs.com/MoviePilot/naspt-core.tgz -o "$CURRENT_DIR/naspt-core.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/naspt-core.tgz" -C "$DOCKER_ROOT_PATH/moviepilot-v2/core/"
  docker run -d \
      --name moviepilot-v2 \
      --restart always \
      --privileged \
      -v "$VIDEO_ROOT_PATH:/media" \
      -v "$DOCKER_ROOT_PATH/moviepilot-v2/config:/config" \
      -v "$DOCKER_ROOT_PATH/moviepilot-v2/core:/moviepilot/.cache/ms-playwright" \
      -e MOVIEPILOT_AUTO_UPDATE=false \
      -e PUID="$PUID" \
      -e PGID="$PGID" \
      -e UMASK="$UMASK"  \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN="IYUU49479T2263e404ce3e261473472d88f75a55d3d44faad1" \
      -e SUPERUSER="admin" \
      -e API_TOKEN="nasptnasptnasptnaspt" \
      --network host \
      "ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest"
      echo "容器启动完成，开始检测是否生成了 user.db 文件..."
      SECONDS=0
  while true; do
      # 等待容器启动完成并生成文件
      sleep 1  # 每 5 秒检查一次
      # 检查容器内是否存在 user.db 文件
      USER_DB_FILE="/config/user.db"
      FILE_EXISTS=$(docker exec moviepilot-v2 test -f "$USER_DB_FILE" && echo "exists" || echo "not exists")
    # 检查日志文件中是否存在 "所有插件初始化完成"
      if [ "$FILE_EXISTS" == "exists" ]; then
          echo "moviepilot启动成功...."
          break  # 跳出循环，继续后续操作
      else
          # 追加输出，确保前面的信息不变
          echo -ne "正在初始化moviepilot-v2... $SECONDS 秒 \r"
      fi

  done
}


init_owjdxb() {
    echo "初始化 Owjdxb"
    mkdir -p "$DOCKER_ROOT_PATH/store"
    docker run -d --name wx --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/store:/data/store" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}ionewu/owjdxb"
}

init_database() {
echo 'UPDATE user SET hashed_password = "$2b$12$9Lcemwg/PNtVaegry6wY.eZL41dENcX3f9Bt.NdhxMtzAsrhv1Cey" WHERE id = 1;' > "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "INSERT INTO systemconfig (id, key, value) VALUES (5, 'Downloaders', '[{\"name\": \"\\u4e0b\\u8f7d\", \"type\": \"qbittorrent\", \"default\": true, \"enabled\": true, \"config\": {\"host\": \"http://119.3.173.6:9000\", \"username\": \"admin\", \"password\": \"a123456!@\", \"category\": true, \"sequentail\": true}}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "INSERT INTO systemconfig (id, key, value) VALUES (6, 'Directories', '[{\"name\": \"\\u5f71\\u89c6\\u8d44\\u6e90\", \"storage\": \"local\", \"download_path\": \"/media/downloads/\", \"priority\": 0, \"monitor_type\": \"monitor\", \"media_type\": \"\", \"media_category\": \"\", \"download_type_folder\": false, \"monitor_mode\": \"fast\", \"library_path\": \"/media/links/\", \"download_category_folder\": true, \"library_storage\": \"local\", \"transfer_type\": \"link\", \"overwrite_mode\": \"latest\", \"library_category_folder\": true, \"scraping\": true, \"renaming\": true}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "INSERT INTO systemconfig (id, key, value) VALUES (7, 'MediaServers', '[{\"name\": \"emby\", \"type\": \"emby\", \"enabled\": true, \"config\": {\"apikey\": \"4a138e7210704d948dbdd6853e316d9c\", \"host\": \"http://119.3.173.6:8096\"}, \"sync_libraries\": [\"all\"]}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"

    sed -i "s/119.3.173.6/$HOST_IP/g" "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "初始化数据库..."
    # SQL 文件路径
    SQL_FILE="$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    # 确保 SQL 文件存在
    if [ ! -f "$SQL_FILE" ]; then
        echo "错误: SQL 文件 $SQL_FILE 不存在。请确认文件路径是否正确。"
        exit 1
    fi
    # 在容器中通过 Python 执行 SQL 文件
    docker exec -i  -w /config moviepilot-v2 python -c "
import sqlite3

# 连接数据库
conn = sqlite3.connect('user.db')
# 创建游标
cur = conn.cursor()
# 读取 SQL 文件
with open('/config/script.sql', 'r') as file:
    sql_script = file.read()
# 执行 SQL 脚本
cur.executescript(sql_script)
# 提交事务
conn.commit()
# 关闭连接
conn.close()
    "
    echo "SQL 文件已在容器中执行并修改数据库。"
    echo "SQL 脚本已执行完毕"
    echo "数据库初始化完成！"

      # 重启容器
    docker restart moviepilot-v2

    echo "正在检查容器是否成功重启..."
    sleep 1  # 等待容器重新启动
    SECONDS=0
# 持续检查容器状态，直到容器运行或失败
    while true; do
        CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' moviepilot-v2)

        if [ "$CONTAINER_STATUS" == "running" ]; then
            echo "容器 moviepilot-v2 重启成功！"
            break
        elif [ "$CONTAINER_STATUS" == "starting" ]; then
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化moviepilot-v2... $SECONDS 秒 \r"
            sleep 1 # 等待2秒后再次检查
        else
            echo "错误: 容器 moviepilot-v2 重启失败！状态：$CONTAINER_STATUS"
            exit 1
        fi
    done
}

# 安装服务
install_service() {
    local service_id=$1
    case "$service_id" in
        1) init_moviepilot ;;
        2) init_emby ;;
        3) init_qbittorrent ;;
        4) init_chinese_sub_finder ;;
        5) init_database ;;
        *)
            echo -e "无效选项：$service_id"
        ;;
    esac
}

      # 配置输入完成后直接开始安装所有服务
      echo "正在开始安装所有服务..."

      # 安装 MoviePilot
      init_moviepilot

      # 安装 Emby
      init_emby

      # 安装 qBittorrent
      init_qbittorrent

      # 安装 Chinese-Sub-Finder
      init_chinese_sub_finder

      sleep 10
      # 初始化数据库
      init_database

      # 删除 naspt 目录
      rm -rf "$CURRENT_DIR"

      # 输出每个服务的配置信息
      echo "服务安装已完成，以下是每个服务的访问信息："
      echo "1. MoviePilot:"
      echo "   地址: http://$HOST_IP:3000"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo
      echo "2. Emby:"
      echo "   地址: http://$HOST_IP:8096"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo
      echo "3. qBittorrent:"
      echo "   地址: http://$HOST_IP:9000"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo
      echo "4. Chinese-Sub-Finder:"
      echo "   地址: http://$HOST_IP:19035"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo

      # 结束脚本
      history -c
      echo "安装流程结束！"
      exit 0

