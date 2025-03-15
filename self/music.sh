#!/bin/bash



# 设置当前目录

DEFAULT_DOCKER_PATH=""
DEFAULT_VIDEO_PATH=""
CURRENT_DIR="/root/naspt"
HOST_IP=""


# 检查 CURRENT_DIR 是否存在，如果不存在则创建
if [ ! -d "$CURRENT_DIR" ]; then
    mkdir -p "$CURRENT_DIR"
    echo "目录 $CURRENT_DIR 不存在，已创建。"
else
    echo "目录 $CURRENT_DIR 已存在。"
fi

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
get_input "MUSIC_ROOT_PATH" "请输入音乐文件根路径" "$DEFAULT_VIDEO_PATH"
get_input "HOST_IP" "请输入NAS IP" "$HOST_IP"


# 导出环境变量
export DOCKER_ROOT_PATH
export MUSIC_ROOT_PATH
export HOST_IP

# 确保目录结构


# 显示设置的配置信息
echo -e "最终的主机 IP 地址是: $HOST_IP"
echo -e "Docker 根路径: $DOCKER_ROOT_PATH"
echo -e "音乐文件根路径: $MUSIC_ROOT_PATH"

echo "开始创建视频目录结构..."
mkdir -p "$MUSIC_ROOT_PATH/downloads" "$MUSIC_ROOT_PATH/links"


# 启动每个服务的函数
init_lyricapi() {
    echo "初始化 lyricapi"
    docker run -d \
        --name lyricapi \
        -p 28883:28883 \
        -v "$MUSIC_ROOT_PATH/links:/music" \
        ccr.ccs.tencentyun.com/naspt/lyricapi:latest
}

init_music_tag_web() {
    echo "初始化 musictag2"
    mkdir -p "$DOCKER_ROOT_PATH/musictag2"
    curl -L https://alist.naspt.vip/d/shell/naspt-music/naspt-musictag.tgz > "$CURRENT_DIR/naspt-musictag.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/naspt-musictag.tgz" -C "$DOCKER_ROOT_PATH/musictag2/"
    docker run -d \
            --name music-tag-web \
            -p 8002:8002 \
            -v "$MUSIC_ROOT_PATH:/app/media" \
            -v "$DOCKER_ROOT_PATH/musictag2:/app/data" \
            --restart always \
            ccr.ccs.tencentyun.com/naspt/music_tag_web:latest
}

init_navidrome() {
    echo "初始化 navidrome"
    mkdir -p "$DOCKER_ROOT_PATH/navidrome"
    curl -L https://alist.naspt.vip/d/shell/naspt-music/naspt-navidrome.tgz > "$CURRENT_DIR/naspt-navidrome.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/naspt-navidrome.tgz" -C "$DOCKER_ROOT_PATH/navidrome/"
    docker run -d \
        --name navidrome \
        -p 4533:4533 \
        -e ND_SCANSCHEDULE=1h \
        -e ND_LOGLEVEL=info \
        -e ND_BASEURL="" \
        -e ND_SPOTIFY_ID=d5fffcb6f90040f2a817430d85694ba7 \
        -e ND_SPOTIFY_SECRET=172ee57bd6aa4b9d9f30f8a9311b91ed \
        -e ND_LASTFM_APIKEY=842597b59804a3c4eb4f0365db458561 \
        -e ND_LASTFM_SECRET=aee9306d8d005de81405a37ec848983c \
        -e ND_LASTFM_LANGUAGE=zh \
        -v "$DOCKER_ROOT_PATH/navidrome/data:/data" \
        -v "$MUSIC_ROOT_PATH/links:/music" \
        ccr.ccs.tencentyun.com/naspt/navidrome:latest
}


      # 配置输入完成后直接开始安装所有服务
      echo "正在开始安装所有服务..."
      init_navidrome
      init_music_tag_web
      init_lyricapi
      # 删除 naspt 目录
      rm -rf "$CURRENT_DIR"

      # 输出每个服务的配置信息
      echo "服务安装已完成，以下是每个服务的访问信息："
      echo "1. navidrome:"
      echo "   地址: http://$HOST_IP:4533"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo
      echo "2. musictag2:"
      echo "   地址: http://$HOST_IP:8002"
      echo "   账号: admin"
      echo "   密码: a123456!@"
      echo
      echo "3. lyricapi:"
      echo "   地址: http://$HOST_IP:28883"
      echo "   以下接口是填写到【音流】APP设置内"
      echo "   歌词接口: http://$HOST_IP:28883/jsonapi"
      echo "   歌词确认接口: http://$HOST_IP:28883/jsonapi"
      echo "   封面: http://$HOST_IP:28883/jsonapi"
      # 结束脚本
      history -c
      echo "安装流程结束！"
      exit 0

