#!/bin/bash

# 定义保存路径
SYSTEM_ID=$(hostname)
TIMESTAMP=$(date +%Y%m%d%H%M%S)
OUTPUT_FILE="/root/.naspt/${TIMESTAMP}_${SYSTEM_ID}.json"

# WebDAV上传配置
WEBDAV_USER="naspt:Lzq951201@"
WEBDAV_URL="https://pan.naspt.vip/dav/installInfo"

# 添加数组生成函数
generate_json_array() {
    local arr=("$@")
    printf '['
    for i in "${!arr[@]}"; do
        [ $i -ne 0 ] && printf ','
        printf '"%s"' "${arr[$i]}"
    done
    printf ']'
}

# 添加系统信息获取函数
get_system_info() {
    # 基础系统信息
    CURRENT_DIR=$(pwd)
    GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
    ARCHITECTURE=$(uname -m)
    HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)
    USER_NAME=$(whoami)
    UMASK=$(umask)

    # 用户信息
    PUID=$(id -u)
    PGID=$(id -g)
    USER_GROUPS=($(groups))

    # NAS品牌检测
    NAS_BRAND="未知"

    # Docker检测
    DOCKER_ROOT_PATH=$(docker info 2>/dev/null | grep "Docker Root Dir" | cut -d: -f2 | tr -d ' ' || echo "")

    # 视频路径检测
    VIDEO_ROOT_PATH=$(df -h | grep -iE "media|video" | head -1 | awk '{print $NF}' || echo "")

    # 网络信息
    PUBLIC_IP_INFO=$(curl -s https://ipinfo.io/json)
    PUBLIC_IP_CITY=$(echo "$PUBLIC_IP_INFO" | grep -oP '"city":\s*"\K[^"]+' || echo "未知")
    LONGITUDE=$(echo "$PUBLIC_IP_INFO" | grep -oP '"loc":\s*"\K[^"]+' | cut -d',' -f1 || echo "0")
    LATITUDE=$(echo "$PUBLIC_IP_INFO" | grep -oP '"loc":\s*"\K[^"]+' | cut -d',' -f2 || echo "0")
    VPS_IP=$(curl -s ifconfig.me)

    # 代理配置
    PROXY_HOST=${http_proxy:-$https_proxy}
}

generate_json() {
    local groups_json=$(generate_json_array "${USER_GROUPS[@]}")

    cat <<EOF
{
  "记录时间": "$(date '+%Y-%m-%d %H:%M:%S')",
  "系统信息": {
    "基础信息": {
      "系统ID": "$SYSTEM_ID",
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
        201|204) echo "安装记录已经保存" ;;
        401) echo "认证失败：请检查账号密码" >&2 ;;
        403) echo "权限不足：请检查写入权限" >&2 ;;
        *) echo "上传异常，状态码：$http_code" >&2 ;;
    esac
}

main() {
    get_system_info
    # 使用追加模式写入文件
    if [ -f "$OUTPUT_FILE" ]; then
        # 如果文件存在，先删除最后一个大括号，再追加新内容
        sed -i '$ d' "$OUTPUT_FILE"
        echo "," >> "$OUTPUT_FILE"
        generate_json | tail -n +2 >> "$OUTPUT_FILE"
    else
        # 如果文件不存在，创建新文件
        generate_json > "$OUTPUT_FILE"
    fi

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