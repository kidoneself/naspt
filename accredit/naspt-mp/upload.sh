#!/bin/bash

# 定义参数与文件夹的映射关系
declare -A FOLDER_MAP=(
    ["csf"]="naspt-csf"
    ["emby"]="naspt-emby"
    ["mpv2"]="naspt-mpv2"
    ["qb"]="naspt-qb"
    ["tr"]="naspt-tr"
)

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项] [参数...]"
    echo "可用的参数选项:"
    echo "  all         打包并上传所有支持的项目"
    echo "  csf         仅处理 naspt-csf"
    echo "  emby        仅处理 naspt-emby"
    echo "  mpv2        仅处理 naspt-mpv2"
    echo "  qb          仅处理 naspt-qb"
    echo "  tr          仅处理 naspt-tr"
    echo "  help        显示帮助信息"
    exit 1
}

# 处理打包和上传操作
process_upload() {
    local folder=$1
    local tgz_file="${folder}.tgz"

    echo "开始打包文件夹: $folder"
    tar --exclude='*/ipc-socket' -czf "$tgz_file" "$folder" || {
        echo "打包 $folder 失败!"
        return 1
    }
    echo "打包 $folder 完成"

    local api_url="https://alist.naspt.vip/api/fs/put"
    local file_path="/123pan/shell/naspt-mp/$tgz_file"

    echo "开始上传文件: $tgz_file"
    response=$(curl --location --request PUT "$api_url" \
        --header "Authorization: $authorization" \
        --header "File-Path: $file_path" \
        --header "overwrite: true" \
        --header "Content-Type: application/octet-stream" \
        --data-binary @"$tgz_file" \
        --max-time 300 \
        --connect-timeout 30 \
        --retry 3 --retry-delay 5 --retry-max-time 60)

    echo "上传文件: $tgz_file 完成，响应: $response"
}

# 检查参数数量
if [ $# -eq 0 ]; then
    echo "错误：需要至少一个参数！"
    show_help
    exit 1
fi

# 处理帮助参数
for arg in "$@"; do
    if [ "$arg" == "help" ]; then
        show_help
    fi
done
rm -rf *.tgz
# 执行初始化请求（这部分保持不变）
echo "开始发送第一个请求：更新存储配置（/123pan）"
response=$(curl --location --request POST 'https://alist.naspt.vip/api/admin/storage/update' \
  --header 'Authorization: alist-24b56f2d-c57e-4a3a-ae55-29ef0d460f56AfVH68IQaNGk6UcwQV5iThwovcDlxD36BrDB0hieeR5qJcz4ewqGdpR8LxKmtdLt' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "id": 6,
    "mount_path": "/123pan",
    "order": 0,
    "driver": "123Pan",
    "cache_expiration": 30,
    "status": "work",
    "addition": "{\"username\":\"17621047058\",\"password\":\"Lzq951201@\",\"root_folder_id\":\"0\",\"AccessToken\":\"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NDIyNzcyMTgsImlhdCI6MTc0MTY3MjQxOCwiaWQiOjE4Mzg0MDAyNjgsIm1haWwiOiIiLCJuaWNrbmFtZSI6IjE3NjIxMDQ3MDU4Iiwic3VwcGVyIjpmYWxzZSwidXNlcm5hbWUiOjE3NjIxMDQ3MDU4LCJ2IjowfQ.ePVX6ePbioBr5v8ZkJie3XNJWst-TyStQlhyKNb7yxs\"}",
    "remark": "",
    "modified": "2025-02-17T00:55:20.186342738Z",
    "disabled": false,
    "disable_index": false,
    "enable_sign": false,
    "order_by": "",
    "order_direction": "",
    "extract_folder": "",
    "web_proxy": false,
    "webdav_policy": "302_redirect",
    "proxy_range": false,
    "down_proxy_url": ""
  }')
echo "第一个请求完成，响应: $response"

echo "开始发送第二个请求：更新存储配置（/shell）"
response=$(curl --location --request POST 'https://alist.naspt.vip/api/admin/storage/update' \
  --header 'Authorization: alist-24b56f2d-c57e-4a3a-ae55-29ef0d460f56AfVH68IQaNGk6UcwQV5iThwovcDlxD36BrDB0hieeR5qJcz4ewqGdpR8LxKmtdLt' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "id": 10,
    "mount_path": "/shell",
    "order": 0,
    "driver": "189CloudPC",
    "cache_expiration": 30,
    "status": "work",
    "addition": "{\"username\":\"15316787058\",\"password\":\"Lzq951201@\",\"validate_code\":\"\",\"root_folder_id\":\"324021177039391293\",\"order_by\":\"filename\",\"order_direction\":\"asc\",\"type\":\"personal\",\"family_id\":\"716770734\",\"upload_method\":\"stream\",\"upload_thread\":\"3\",\"family_transfer\":false,\"rapid_upload\":false,\"no_use_ocr\":false}",
    "remark": "ref:/naspt",
    "modified": "2025-02-24T06:53:28.422831034Z",
    "disabled": false,
    "disable_index": false,
    "enable_sign": false,
    "order_by": "",
    "order_direction": "",
    "extract_folder": "",
    "web_proxy": false,
    "webdav_policy": "302_redirect",
    "proxy_range": false,
    "down_proxy_url": ""
}')
echo "第二个请求完成，响应: $response"

# 处理打包和上传参数
authorization="alist-24b56f2d-c57e-4a3a-ae55-29ef0d460f56AfVH68IQaNGk6UcwQV5iThwovcDlxD36BrDB0hieeR5qJcz4ewqGdpR8LxKmtdLt"

for arg in "$@"; do
    if [ "$arg" == "all" ]; then
        for key in "${!FOLDER_MAP[@]}"; do
            process_upload "${FOLDER_MAP[$key]}"
        done
        exit 0
    elif [ -n "${FOLDER_MAP[$arg]}" ]; then
        process_upload "${FOLDER_MAP[$arg]}"
    else
        echo "警告：忽略无效参数 '$arg'"
    fi
done

echo "脚本执行完成"