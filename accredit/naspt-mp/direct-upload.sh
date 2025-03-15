#!/bin/bash

# 上传功能函数
upload_file() {
    local file_path="$1"
    local target_path="/123pan/shell/naspt-mp/$(basename "$file_path")"
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

# 主程序
if [ $# -eq 0 ]; then
    echo "用法: $0 <文件路径1> [文件路径2] ..."
    echo "示例:"
    echo "  $0 backup.zip"
    echo "  $0 /path/to/file1.txt /path/to/file2.jpg"
    exit 1
fi

# 遍历所有参数进行上传
for file in "$@"; do
    upload_file "$file"
    echo "-------------------------"
done

echo "所有文件处理完成"