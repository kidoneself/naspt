#!/bin/bash

DEFAULT_DOCKER_PATH=""
DEFAULT_VIDEO_PATH=""
HOST_IP=""

# 获取用户输入
get_input() {
  local var_name="$1"
  local prompt_message="$2"
  local default_value="$3"
  local value

  while true; do
    read -r -p "$prompt_message ===> " value
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
    echo "【提示】文件 '$output_file' 已存在，跳过下载。"
  else
    echo "【提示】正在下载文件: $url"
    if ! curl -L "$url" -o "$output_file"; then
      echo "【错误】无法下载文件 '$url'，请检查网络连接或 URL 是否正确。"
      exit 1
    fi
  fi

  echo "【提示】正在解压文件到: $extract_path"
  mkdir -p "$extract_path"
  if ! tar --strip-components="$strip_components" -zxvf "$output_file" -C "$extract_path"; then
    echo "【错误】解压文件 '$output_file' 失败，请检查文件内容是否正确。"
    exit 1
  fi
}


# 检查端口是否被占用的函数
check_ports() {
  # 检查是否有传入端口号
  if [ -z "$1" ]; then
    echo "【错误】请提供要检查的端口号"
    return 1
  fi

  # 遍历所有传入的端口
  for PORT in "$@"; do
    if lsof -i :$PORT >/dev/null 2>&1; then
      echo "【提示】端口 $PORT 已被占用"
    else
      echo "【提示】端口 $PORT 没有被占用"
    fi
  done
}


# 定义公共方法来检查和启动容器
check_container() {
  local container_name=$1
  # 检查容器是否已经启动
  if [ "$(docker ps -q -f name=$container_name)" ]; then
    return 1  # 返回1表示已经在运行，不需要启动
  else
    return 0  # 返回0表示启动了容器，可以继续执行后续代码
  fi
}


# 获取 Docker 根路径和视频根路径
get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DEFAULT_DOCKER_PATH"
get_input "MUSIC_ROOT_PATH" "请输入音乐文件根路径" "$DEFAULT_VIDEO_PATH"
get_input "HOST_IP" "请输入 NAS 的 IP 地址" "$HOST_IP"


# 导出环境变量
export DOCKER_ROOT_PATH MUSIC_ROOT_PATH HOST_IP


echo -e "\n【步骤】开始创建视频目录结构..."
mkdir -p "$MUSIC_ROOT_PATH/downloads" "$MUSIC_ROOT_PATH/links"


# 启动每个服务的函数
init_lyricapi() {
    echo -e "\n=== 初始化 lyricapi 服务 ==="
    echo "【步骤】检测端口是否占用..."
    check_ports "28883"

    check_container "naspt-lyricapi"
    if [ $? -eq 0 ]; then
        echo "【提示】未检测到原有容器，启动新的容器..."
        docker run -d --name naspt-lyricapi --restart always --privileged \
            -p 28883:28883 \
            -e PUID=0 \
            -e PGID=0 \
            -e UMASK=022 \
            -v "$MUSIC_ROOT_PATH/links:/music" \
            --network bridge \
            "ccr.ccs.tencentyun.com/naspt/lyricapi:latest"
    else
        echo "【提示】容器已启动，无需重启"
    fi
}

init_music_tag_web() {
    echo -e "\n=== 初始化 musictag 服务 ==="
    echo "【步骤】检测端口是否占用..."
    check_ports "8002"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-musictag"
    download_and_extract \
    "https://naspt.oss-cn-shanghai.aliyuncs.com/music/naspt-musictag.tgz" \
    "$DOCKER_ROOT_PATH/naspt-musictag.tgz" \
    "$DOCKER_ROOT_PATH/naspt-musictag/"

    check_container "naspt-musictag"
    if [ $? -eq 0 ]; then
        echo "【提示】未检测到原有容器，启动新的容器..."
        docker run -d --name naspt-musictag --restart always\
            -e PUID=0 \
            -e PGID=0 \
            -e UMASK=022 \
            -v "$MUSIC_ROOT_PATH:/app/media" \
            -v "$DOCKER_ROOT_PATH/naspt-musictag:/app/data" \
            --network bridge \
            -p 8002:8002 \
            "ccr.ccs.tencentyun.com/naspt/music_tag_web:latest"
    else
        echo "【提示】容器已启动，无需重启"
    fi
}

init_navidrome() {
    echo -e "\n=== 初始化 navidrome 服务 ==="
    echo "【步骤】检测端口是否占用..."
    check_ports "4533"
    mkdir -p "$DOCKER_ROOT_PATH/naspt-navidrome"
    download_and_extract \
    "https://naspt.oss-cn-shanghai.aliyuncs.com/music/naspt-navidrome.tgz" \
    "$DOCKER_ROOT_PATH/naspt-navidrome.tgz" \
    "$DOCKER_ROOT_PATH/naspt-navidrome/"

    check_container "naspt-navidrome"
    if [ $? -eq 0 ]; then
      echo "【提示】未检测到原有容器，启动新的容器..."
       docker run -d --name naspt-navidrome --restart always --privileged\
        -e PUID=0 \
        -e PGID=0 \
        -e UMASK=022 \
        --network bridge \
        -p 4533:4533 \
        -e ND_SCANSCHEDULE=1h \
        -e ND_LOGLEVEL=info \
        -e ND_BASEURL="" \
        -e ND_SPOTIFY_ID=d5fffcb6f90040f2a817430d85694ba7 \
        -e ND_SPOTIFY_SECRET=172ee57bd6aa4b9d9f30f8a9311b91ed \
        -e ND_LASTFM_APIKEY=842597b59804a3c4eb4f0365db458561 \
        -e ND_LASTFM_SECRET=aee9306d8d005de81405a37ec848983c \
        -e ND_LASTFM_LANGUAGE=zh \
        -v "$DOCKER_ROOT_PATH/naspt-navidrome/data:/data" \
        -v "$MUSIC_ROOT_PATH/links:/music" \
        "ccr.ccs.tencentyun.com/naspt/navidrome:latest"
    else
        echo "【提示】容器已启动，无需重启"
    fi
}

# 配置输入完成后直接开始安装所有服务
echo -e "\n【步骤】开始安装所有服务..."
init_navidrome
init_music_tag_web
init_lyricapi


# 输出每个服务的配置信息
echo -e "\n【安装完成】以下是各服务的访问信息："
echo -e "🎵 Navidrome:     http://$HOST_IP:4533"
echo -e "🎵 Music Tag Web: http://$HOST_IP:8002"
echo -e "🎵 Lyric API:     http://$HOST_IP:28883"
echo -e "\n【统一账号】用户名：admin   密码：a123456!@"

echo -e "\n【音流 APP 配置】请填写以下接口："
echo -e "歌词接口:      http://$HOST_IP:28883/jsonapi"
echo -e "歌词确认接口:  http://$HOST_IP:28883/jsonapi"
echo -e "封面接口:      http://$HOST_IP:28883/jsonapi"

# 结束脚本
echo -e "\n【安装完成】所有服务已成功安装，感谢使用！"
exit 0