#!/bin/bash

# 上传功能函数
upload_file() {
    local file_path="$1"
    local target_path="/123pan/shell/tgz/$(basename "$file_path")"
    local authorization="alist-24b56f2d-c57e-4a3a-ae55-29ef0d460f56AfVH68IQaNGk6UcwQV5iThwovcDlxD36BrDB0hieeR5qJcz4ewqGdpR8LxKmtdLt"
    local api_url="https://alist.naspt.vip/api/fs/put"

    if [ ! -f "$file_path" ]; then
        echo "错误：文件不存在 - $file_path"
        return 1
    fi

    echo "正在上传: $file_path → 云端路径: $target_path"

    response=$(curl --silent --location --request PUT "$api_url" \
        --header "Authorization: $authorization" \
        --header "File-Path: $target_path" \
        --header "overwrite: true" \
        --header "Content-Type: application/octet-stream" \
        --data-binary @"$file_path" \
        --max-time 300 \
        --connect-timeout 30 \
        --retry 3 \
        --retry-delay 5 \
        --retry-max-time 60)

    if [[ $? -eq 0 ]]; then
        echo "上传成功！响应: $response"
    else
        echo "上传失败: $file_path"
        return 1
    fi
}

# 定义相关变量
HOSTS_FILE="$(pwd)/hosts_new.txt"
PROXY="http://47.239.17.34:7890"
TMP_DIR="/tmp/hosts_update"

# 创建临时目录
mkdir -p "$TMP_DIR"

echo "开始下载 hosts 文件..."

# 使用代理下载 hosts 文件
curl -sSL -x "$PROXY" -o "$TMP_DIR/hosts1.txt" "https://raw.githubusercontent.com/cnwikee/CheckTMDB/main/Tmdb_host_ipv4"
curl -sSL -x "$PROXY" -o "$TMP_DIR/hosts2.txt" "https://hosts.gitcdn.top/hosts.txt"

echo "合并并处理下载的 hosts 文件..."

# 合并两个文件，过滤掉注释和空行，并去重，同时在文件顶部加入更新时间
{
    echo "# Updated at $(date)"
    cat "$TMP_DIR/hosts1.txt" "$TMP_DIR/hosts2.txt" | \
        grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s" | \
        sort | uniq
} > "$HOSTS_FILE"

# 清理临时目录
rm -rf "$TMP_DIR"

echo "Hosts 文件已更新: $HOSTS_FILE"

# 上传更新后的 hosts 文件到云端
upload_file "$HOSTS_FILE"