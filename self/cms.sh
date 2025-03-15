#!/bin/bash

# 全局变量定义
DOCKER_ROOT_PATH=""
VIDEO_ROOT_PATH=""
GITHUB_PROXY=""

get_input() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    local value
    while true; do
        read -p "$prompt_message [$default_value]: " value
        value="${value:-$default_value}"
        if [ -d "$value" ]; then
            eval "$var_name='$value'"
            break
        else
            echo "路径 $value 不存在，请重新输入。"
        fi
    done
}

show_config() {
    cat <<EOF
配置详情:
- 主机 IP 地址: $HOST_IP
- Docker 根路径: $DOCKER_ROOT_PATH
- 115 根路径: $VIDEO_ROOT_PATH
- github代理地址: $GITHUB_PROXY
EOF
}

# -----------------------------------------------
# 函数：确认用户输入
# 功能：展示当前配置信息并询问用户是否确认
# -----------------------------------------------
confirm_settings() {
    while true; do
        show_config
        read -p "以上配置是否正确？(y/n): " confirm
        case $confirm in
            [Yy]* ) break ;;
            [Nn]* )
                echo "请重新输入配置信息..."
                configure_settings
                ;;
            * ) echo "请输入 y 或 n。" ;;
        esac
    done
}

# -----------------------------------------------
# 函数：配置设置
# 功能：通过用户交互获取 Docker 和 Media 路径、用户名等配置信息
# -----------------------------------------------
configure_settings() {
    get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DOCKER_ROOT_PATH"
    get_input "VIDEO_ROOT_PATH" "请输入 media 根路径" "$VIDEO_ROOT_PATH"
    get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"
    get_input "GITHUB_PROXY" "请输入git加速地址( https://ghproxy.link/ ): " "$GITHUB_PROXY"

}
# 配置安装环境
configure_settings
# 确认安装环境
confirm_settings
# 导出环境变量
export DOCKER_ROOT_PATH VIDEO_ROOT_PATH  HOST_IP

mkdir -p "$VIDEO_ROOT_PATH/媒体库"
mkdir -p  "$VIDEO_ROOT_PATH/115整理/媒体信息"
declare -A categories=(
    ["剧集"]="儿童剧集 国产剧集 日韩剧集 欧美剧集 综艺节目 纪录片 纪录影片 港台剧集 南亚剧集"
    ["动漫"]="国产动漫 欧美动漫 日本番剧"
    ["电影"]="儿童电影 动画电影 国产电影 日韩电影 欧美电影 南亚电影 歌舞电影 港台电影"
)

echo "开始创建视频目录结构..."
for category in "${!categories[@]}"; do
    for subcategory in ${categories[$category]}; do
        mkdir -p "$VIDEO_ROOT_PATH/115整理/$category/$subcategory" \

    done
done
# 启动每个服务的函数
init_cms() {
    echo "初始化 cms"
    mkdir -p "$DOCKER_ROOT_PATH/115-cms"
    mkdir -p "$DOCKER_ROOT_PATH/115-cms/config/"
    mkdir -p "$DOCKER_ROOT_PATH/115-cms/nginx/logs"
    mkdir -p "$DOCKER_ROOT_PATH/115-cms/nginx/cache"
    docker run -d \
      --privileged \
      --name 115-cms \
      --restart always \
      --network bridge \
      -p 9527:9527 \
      -p 9096:9096 \
      -v "$DOCKER_ROOT_PATH/115-cms/config:/config" \
      -v "$DOCKER_ROOT_PATH/115-cms/nginx/logs:/logs" \
      -v "$DOCKER_ROOT_PATH/115-cms/nginx/cache:/var/cache/nginx/emby" \
      -v "$VIDEO_ROOT_PATH:/media" \
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

      cat <<EOF > "$DOCKER_ROOT_PATH/115-cms/config/category.yaml"
movie:
  电影:
    cid: 3070553346589532268

tv:
  电视剧:
    cid: 3070553410535891139

EOF
}

init_emby_115() {
    echo "初始化 115-emby"
    mkdir -p "$DOCKER_ROOT_PATH/115-emby"
    if [ ! -f "$DOCKER_ROOT_PATH/115-emby.tgz" ]; then
    echo "文件不存在，开始下载..."
    curl -L https://alist.naspt.vip/d/shell/naspt-cms/115-emby.tgz > "$DOCKER_ROOT_PATH/115-emby.tgz"
    else
        echo "文件已存在，跳过下载。"
    fi
    tar --strip-components=1 -zxf "$DOCKER_ROOT_PATH/115-emby.tgz" -C "$DOCKER_ROOT_PATH/115-emby/"
    docker run -d --name 115-emby --restart unless-stopped \
        --network bridge \
        -p 18096:8096 \
        -v "$DOCKER_ROOT_PATH/115-emby/config:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID=0 -e PGID=0 -e UMASK=022 \
        -e TZ=Asia/Shanghai \
        --device /dev/dri:/dev/dri \
        --privileged \
        "ccr.ccs.tencentyun.com/naspt/embyserver:beta"

}

init_moviepilot() {
    echo "初始化 MoviePilot"
    mkdir -p "$DOCKER_ROOT_PATH/115-moviepilot2"
        if [ ! -f "$DOCKER_ROOT_PATH/115-moviepilot2.tgz" ]; then
    echo "文件不存在，开始下载..."
    curl -L https://alist.naspt.vip/d/shell/naspt-cms/115-moviepilot2.tgz >  "$DOCKER_ROOT_PATH/115-moviepilot2.tgz"
    else
        echo "文件已存在，跳过下载。"
    fi
    tar  --strip-components=1 -zxf "$DOCKER_ROOT_PATH/115-moviepilot2.tgz" -C "$DOCKER_ROOT_PATH/115-moviepilot2/"
    cat <<EOF > "$DOCKER_ROOT_PATH/115-moviepilot2/config/category.yaml"
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
    # 解压到指定目录
    docker run -d \
      --name 115-moviepilot2 \
      --restart always \
      --privileged \
      --network bridge \
      -p 13000:3000 \
      -p 13001:3001 \
      -v "$VIDEO_ROOT_PATH:/media" \
      -v "$DOCKER_ROOT_PATH/115-moviepilot2/config:/config" \
      -v "$DOCKER_ROOT_PATH/115-moviepilot2/core:/moviepilot/.cache/ms-playwright" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e MOVIEPILOT_AUTO_UPDATE=false \
      -e PUID=0 -e PGID=0 -e UMASK=022 \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN="IYUU49479T2263e404ce3e261473472d88f75a55d3d44faad1" \
      -e SUPERUSER="admin" \
      -e API_TOKEN="nasptnasptnasptnaspt" \
      -e GITHUB_PROXY="$GITHUB_PROXY"\
      ccr.ccs.tencentyun.com/naspt/moviepilot-v2:latest
}


init_owjdxb() {
    echo "初始化 Owjdxb"
    mkdir -p "$DOCKER_ROOT_PATH/store"
    docker run -d --name wx --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/store:/data/store" \
        --network host --privileged \
        "ccr.ccs.tencentyun.com/naspt/owjdxb"
}


init_database() {
    echo "UPDATE systemconfig SET value = REPLACE(value, '10.10.10.105:9096', '$HOST_IP:18096') WHERE value LIKE '%10.10.10.105:8096%';" >> "$DOCKER_ROOT_PATH/115-moviepilot2/config/script.sql"
    echo "初始化数据库..."
    # SQL 文件路径
    SQL_FILE="$DOCKER_ROOT_PATH/115-moviepilot2/config/script.sql"
    # 确保 SQL 文件存在
    if [ ! -f "$SQL_FILE" ]; then
        echo "错误: SQL 文件 $SQL_FILE 不存在。请确认文件路径是否正确。"
        exit 1
    fi
    # 在容器中通过 Python 执行 SQL 文件
    docker exec -i  -w /config 115-moviepilot2 python -c "
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
    docker restart 115-moviepilot2

    echo "正在检查容器是否成功重启..."
    sleep 1  # 等待容器重新启动
    SECONDS=0
# 持续检查容器状态，直到容器运行或失败
    while true; do
        CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' 115-moviepilot2)

        if [ "$CONTAINER_STATUS" == "running" ]; then
            echo "容器 115-moviepilot2 重启成功！"
            break
        elif [ "$CONTAINER_STATUS" == "starting" ]; then
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化115-moviepilot2... $SECONDS 秒 \r"
            sleep 1 # 等待2秒后再次检查
        else
            echo "错误: 容器 115-moviepilot2 重启失败！状态：$CONTAINER_STATUS"
            exit 1
        fi
    done
}
      # 配置输入完成后直接开始安装所有服务
      echo "正在开始安装所有服务..."
      init_emby_115
      init_moviepilot
      init_owjdxb
      init_cms
      init_database

      # 输出每个服务的配置信息到终端和文本文件
      OUTPUT_FILE="$DOCKER_ROOT_PATH/安装信息.txt"

      # 清空或创建输出文件
      : > "$OUTPUT_FILE"

      echo "服务安装已完成，以下是每个服务的访问信息：" | tee -a "$OUTPUT_FILE"
      echo "1. 直连地址:" | tee -a "$OUTPUT_FILE"
      echo "   地址: http://$HOST_IP:9096" | tee -a "$OUTPUT_FILE"
      echo "   账号: admin" | tee -a "$OUTPUT_FILE"
      echo "   密码: a123456!@" | tee -a "$OUTPUT_FILE"
      echo | tee -a "$OUTPUT_FILE"

      echo "2. cms地址:" | tee -a "$OUTPUT_FILE"
      echo "   地址: http://$HOST_IP:9527" | tee -a "$OUTPUT_FILE"
      echo "   账号: admin" | tee -a "$OUTPUT_FILE"
      echo "   密码: a123456!@" | tee -a "$OUTPUT_FILE"
      echo | tee -a "$OUTPUT_FILE"

      echo "3. moviepilot地址:" | tee -a "$OUTPUT_FILE"
      echo "   地址: http://$HOST_IP:13000" | tee -a "$OUTPUT_FILE"
      echo "   账号: admin" | tee -a "$OUTPUT_FILE"
      echo "   密码: a123456!@" | tee -a "$OUTPUT_FILE"
      echo | tee -a "$OUTPUT_FILE"

      echo "4. 节点地址:" | tee -a "$OUTPUT_FILE"
      echo "   地址: http://$HOST_IP:9118" | tee -a "$OUTPUT_FILE"
      echo | tee -a "$OUTPUT_FILE"
      # 结束脚本
      history -c
      echo "安装流程结束！配置信息已保存到 $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
      exit 0

