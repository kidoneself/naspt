#!/bin/bash

# 红色文本颜色代码
RED="\033[31m"
GREEN="\033[32m"
RESET="\033[0m"

# 定义全局的最大重试次数
MAX_RETRIES=3

# 定义分割线函数
print_separator() {
    local length=50
    local char="-"
    for ((i = 0; i < length; i++)); do
        printf "%s" "$char"
    done
    printf "\n"
}

# 确保清理操作的 trap
cleanup() {
    rm -rf "$CURRENT_DIR"
    history -c
    history -w
    exit
}
trap cleanup EXIT

CURRENT_DIR="/root/moling"
# 检查 CURRENT_DIR 是否存在，如果不存在则创建
if [ ! -d "$CURRENT_DIR" ]; then
    mkdir -p "$CURRENT_DIR"
fi

# 登录 Docker 仓库，添加重试机制
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
    read -s -p "请输入 Docker 仓库的密码: " PASSWORD
    echo
    echo "$PASSWORD" | docker login --username=aliyun4118146718 --password-stdin crpi-dt5pygtutdf9o78k.cn-shanghai.personal.cr.aliyuncs.com
    if [ $? -eq 0 ]; then
        echo "成功登录 Docker 仓库"
        break
    else
        RETRY=$((RETRY + 1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
            echo "登录 Docker 仓库失败，第 $RETRY 次重试..."
            sleep 2
        else
            echo "登录 Docker 仓库失败，已达到最大重试次数，脚本终止。"
            exit 1
        fi
    fi
done

# 调整系统参数
echo fs.inotify.max_user_watches=5242880 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_instances=5242880 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 获取网关地址
GATEWAY=$(ip route | grep 'default' | awk '{print $3}')
GATEWAY="${GATEWAY:-未获取到网关地址}"

# 检测当前主机架构
ARCHITECTURE=$(uname -m)
ARCHITECTURE="${ARCHITECTURE:-未识别架构}"

# 根据主机架构选择命名空间
case "$ARCHITECTURE" in
    x86_64|i386|i486|i586|i686)
        DOCKER_NAMESPACE="moling7882"
        ;;
    armv7l|aarch64)
        DOCKER_NAMESPACE="moling1992"
        ;;
    *)
        DOCKER_NAMESPACE="moling7882"
        ;;
esac

# 修正这里的空格问题
DOCKER_REGISTRY="crpi-dt5pygtutdf9o78k.cn-shanghai.personal.cr.aliyuncs.com/${DOCKER_NAMESPACE}"

# 定义函数用于判断品牌
check_brand() {
    local info="$1"
    if echo "$info" | grep -q "Synology"; then
        NAS_BRAND="Synology"
        NAS_DEFAULT_PORT="5000"
    elif echo "$info" | grep -q "QNAP"; then
        NAS_BRAND="QNAP"
        NAS_DEFAULT_PORT="8080"
    elif echo "$info" | grep -q "UGREEN"; then
        NAS_BRAND="UGREEN"
        NAS_DEFAULT_PORT="9999"
    elif echo "$info" | grep -q "Zspace"; then
        NAS_BRAND="Zspace"
        NAS_DEFAULT_PORT="5055"
    elif echo "$info" | grep -q "Unraid"; then
        NAS_BRAND="Unraid"
        NAS_DEFAULT_PORT="80"
    elif echo "$info" | grep -q "TrueNAS"; then
        NAS_BRAND="TrueNAS"
        NAS_DEFAULT_PORT="80"
    elif echo "$info" | grep -q "TerraMaster"; then
        NAS_BRAND="TerraMaster"
        NAS_DEFAULT_PORT="8181"
    elif echo "$info" | grep -q "Asus"; then
        NAS_BRAND="Asus"
        NAS_DEFAULT_PORT="5001"
    elif echo "$info" | grep -q "OpenWrt"; then
        NAS_BRAND="OpenWrt"
        NAS_DEFAULT_PORT="80"
    elif echo "$info" | grep -q "Fnos"; then
        NAS_BRAND="Fnos"
        NAS_DEFAULT_PORT="5666"
    fi
}

# 尝试判断 NAS 品牌
NAS_BRAND=""
NAS_DEFAULT_PORT=""

# 群辉可以额外检查端口
if { nc -z -w 1 127.0.0.1 5000 >/dev/null 2>&1; }; then
    NAS_BRAND="Synology"
    NAS_DEFAULT_PORT="5000"
elif [ -f "/etc/defaults/VERSION" ]; then
    if grep -q "Synology" "/etc/defaults/VERSION"; then
        NAS_BRAND="Synology"
        NAS_DEFAULT_PORT="5000"
    fi
elif [ -f "/etc/config/qpkg.conf" ]; then
    NAS_BRAND="QNAP"
    NAS_DEFAULT_PORT="8080"
elif [ -f "/etc/ugreen_nas.conf" ]; then
    NAS_BRAND="UGREEN"
    NAS_DEFAULT_PORT="9999"
elif [ -f "/etc/zspace_version" ]; then
    NAS_BRAND="Zspace"
    NAS_DEFAULT_PORT="5055"
elif [ -f "/etc/unraid-version" ]; then
    NAS_BRAND="Unraid"
    NAS_DEFAULT_PORT="80"
elif [ -d "/opt/istore" ]; then
    NAS_BRAND="iStore"
    NAS_DEFAULT_PORT="80"
# 飞牛（Fnos）优化判断
elif { nc -z -w 1 127.0.0.1 5666 >/dev/null 2>&1; } || { nc -z -w 1 127.0.0.1 8000 >/dev/null 2>&1; }; then
    if [ -f "/etc/fnos_version" ]; then
        NAS_BRAND="Fnos"
        NAS_DEFAULT_PORT="5666"
    fi
elif [ -f "/usr/local/www/freenasUI/templates/base.html" ]; then
    NAS_BRAND="TrueNAS"
    NAS_DEFAULT_PORT="80"
elif [ -f "/etc/terramaster_version" ]; then
    NAS_BRAND="TerraMaster"
    NAS_DEFAULT_PORT="8181"
elif [ -f "/etc/asus_nas_info" ]; then
    NAS_BRAND="Asus"
    NAS_DEFAULT_PORT="5001"
elif [ -f "/etc/openwrt_release" ]; then
    NAS_BRAND="OpenWrt"
    NAS_DEFAULT_PORT="80"
else
    OS_RELEASE=$(cat /etc/os-release 2>/dev/null)
    check_brand "$OS_RELEASE"
    if [ -z "$NAS_BRAND" ]; then
        DMIDECODE_INFO=$(dmidecode 2>/dev/null)
        check_brand "$DMIDECODE_INFO"
    fi
fi

# 随机生成字母加数字的变量
# 修正 tr 命令的参数
RANDOM_VARIABLE=$(openssl rand -base64 10 | tr -dc 'A-Za-z0-9' | head -c 10)
RANDOM_VARIABLE="${RANDOM_VARIABLE:-默认随机变量}"

# 随机生成 10000 - 15000 数字的变量
RANDOM_NUMBER=$((10000 + $RANDOM % 5001))
RANDOM_NUMBER="${RANDOM_NUMBER:-10000}"

# 封装一个函数用于带有重试机制的请求
fetch_info() {
    local url=$1
    local pattern=$2
    local attempt=1
    local result
    while [ $attempt -le $MAX_RETRIES ]; do
        # 修正 curl 命令的空格问题
        result=$(curl -s "$url")
        if [ $? -eq 0 ]; then
            result=$(echo "$result" | grep -oP "$pattern")
            if [ -n "$result" ]; then
                break
            fi
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $MAX_RETRIES ]; then
        result="未获取到信息，多次尝试失败"
    fi
    echo "$result"
}

# 获取公网 IP 所在城市
# 修正 URL 中的空格问题
PUBLIC_IP_CITY=$(fetch_info "http://ip-api.com/json" '"city":"\K[^"]*')

# 获取该城市的经度
# 修正 URL 中的空格问题
LONGITUDE=$(fetch_info "http://ip-api.com/json" '"lon":\K[-+]?[0-9]*\.?[0-9]+')

# 获取该城市的纬度
# 修正 URL 中的空格问题
LATITUDE=$(fetch_info "http://ip-api.com/json" '"lat":\K[-+]?[0-9]*\.?[0-9]+')

# 确保用户输入的变量不为空，否则要求重新输入
get_input() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    local value
    while [ -z "$value" ]; do
        read -p "$prompt_message ($default_value): " value
        value="${value:-$default_value}"
        if [ "$var_name" == "DOCKER_ROOT_PATH" ] || [ "$var_name" == "VIDEO_ROOT_PATH" ]; then
            if [ ! -d "$value" ]; then
                echo -e "${RED}路径无效，请重新输入。${RESET}"
                value=""
            fi
        fi
    done
    eval "$var_name=$value"
}

# 提示并获取 Docker 根路径
if [ -z "$DOCKER_ROOT_PATH" ]; then
    get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "/volume1/docker"
else
    echo -e "${GREEN}当前 Docker 根路径为: $DOCKER_ROOT_PATH${RESET}"
    read -p "是否使用该路径？(y/n): " use_default
    if [ "$use_default" != "y" ]; then
        get_input "DOCKER_ROOT_PATH" "请输入 Docker 根路径" "$DOCKER_ROOT_PATH"
    fi
fi

# 提示并获取视频文件根路径
if [ -z "$VIDEO_ROOT_PATH" ]; then
    get_input "VIDEO_ROOT_PATH" "请输入视频文件根路径" "/volume1/media"
else
    echo -e "${GREEN}当前视频文件根路径为: $VIDEO_ROOT_PATH${RESET}"
    read -p "是否使用该路径？(y/n): " use_default
    if [ "$use_default" != "y" ]; then
        get_input "VIDEO_ROOT_PATH" "请输入视频文件根路径" "$VIDEO_ROOT_PATH"
    fi
fi

# 获取主机 IP 地址
HOST_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | grep -v 'docker' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
HOST_IP="${HOST_IP:-未获取到主机 IP}"
echo -e "${GREEN}当前主机 IP 地址为: $HOST_IP${RESET}"
read -p "是否使用该 IP 地址？(y/n) [默认: y]: " use_default
use_default=${use_default:-y}
if [ "$use_default" != "y" ]; then
    get_input "HOST_IP" "请输入主机 IP 地址" "$HOST_IP"
fi

# 让用户输入用户名
USER_NAME="${USER_NAME:-root}"
read -p "请输入用户名 ($USER_NAME): " input_name
USER_NAME="${input_name:-$USER_NAME}"

# 检查用户是否存在
id "$USER_NAME" &>/dev/null
if [ $? -eq 0 ]; then
    PUID=$(id -u "$USER_NAME")
    PGID=$(id -g "$USER_NAME")
    USER_GROUPS=$(id -G "$USER_NAME" | tr ' ' ',')
else
    PUID=0
    PGID=0
    USER_GROUPS=""
fi

UMASK=$(umask 2>/dev/null)
if [ -z "$UMASK" ]; then
    UMASK=022
fi
UMASK=${UMASK: -3}

# 让用户输入 IYUU KEY
IYUU_TOKEN="${IYUU_TOKEN:-IYUU19953T182d98807dfa49e87579b0487f871a6a74e773fe}"
read -p "请输入 IYUU TOKEN ($IYUU_TOKEN): " input_token
IYUU_TOKEN="${input_token:-$IYUU_TOKEN}"

# 定义捐赠码数组
donate_codes=(
    "CMS_GTIYZECP_E5D4CBB05F3B4755B78D4322FEAE5545"
    "CMS_H8CVTK86_04E199570C634D5CA282666A11EBCAD3"
    "CMS_H8HOCFQI_E6FB7A8D28284F758C45DB619EE0E27B"
    "CMS_IVC4T7TK_9DBED5EC15204740AB2342B4FCDD5FD3"
    "CMS_JF64W92P_686D048D92F04D3582E7A021B72775DC"
    "CMS_JICH8WSU_6380C1CE854E4B1FB35A0C64CDFE6AFE"
)

# 生成随机索引
random_index=$((RANDOM % ${#donate_codes[@]}))

# 获取随机默认捐赠码
default_donate_code=${donate_codes[$random_index]}

# 让用户输入 DONATE_CODE
DONATE_CODE="${DONATE_CODE:-$default_donate_code}"
read -p "请输入 DONATE_CODE ($DONATE_CODE): " input_donate_code
DONATE_CODE="${input_donate_code:-$DONATE_CODE}"

# 让用户输入 VPS_IP
VPS_IP="${VPS_IP:-sblamd2.moling.us.kg}"
read -p "请输入 VPS_IP ($VPS_IP): " input_vps_ip
VPS_IP="${input_vps_ip:-$VPS_IP}"

# 定义默认值
GITHUB_PROXY="${GITHUB_PROXY:-https://git.goling.us.kg/}"
PROXY_HOST="${PROXY_HOST:-$HOST_IP:7890}"

echo "请选择输入代理信息："
echo "1. 输入 GITHUB_PROXY"
echo "2. 输入 PROXY_HOST"
echo "3. 使用默认的 GITHUB_PROXY"
echo "4. 使用默认的 PROXY_HOST"
echo "5. 两个代理都不添加"

while true; do
    read -p "请输入选项编号 (1/2/3/4/5，直接回车默认选 3): " choice
    # 如果用户直接回车，将选择设置为 3
    choice="${choice:-3}"
    case $choice in
        1)
            read -p "请输入 GITHUB_PROXY ($GITHUB_PROXY): " input_github_proxy
            GITHUB_PROXY="${input_github_proxy:-$GITHUB_PROXY}"
            PROXY_HOST=""
            break
            ;;
        2)
            read -p "请输入 PROXY_HOST ($PROXY_HOST): " input_proxy
            PROXY_HOST="${input_proxy:-$PROXY_HOST}"
            GITHUB_PROXY=""
            break
            ;;
        3)
            PROXY_HOST=""
            break
            ;;
        4)
            GITHUB_PROXY=""
            break
            ;;
        5)
            GITHUB_PROXY=""
            PROXY_HOST=""
            break
            ;;
        *)
            echo "无效的选项，请输入 1、2、3、4 或 5。"
            ;;
    esac
done

echo "最终 GITHUB_PROXY: $GITHUB_PROXY"
echo "最终 PROXY_HOST: $PROXY_HOST"

# 提示用户输入是否升级 MPV2
echo "请输入 0 或 1 确认是否升级 MPV2："
TIMEOUT=10
read -t $TIMEOUT -p "（0: 不升级，1: 升级，默认 0）：" input
if [ $? -gt 128 ]; then
    echo "超时，采用默认值 0。"
    input=0
elif [ -z "$input" ]; then
    echo "未输入，采用默认值 0。"
    input=0
fi

if [ "$input" -eq 1 ]; then
    result=release
elif [ "$input" -eq 0 ]; then
    result=false
else
    echo "输入无效，请输入 0 或 1。"
    exit 1
fi

# 定义 TMDB IPv4 和 GitHub 的 hosts 文件链接
TMDB_IPV4_HOSTS_URL="https://git.goling.us.kg/https://raw.githubusercontent.com/cnwikee/CheckTMDB/main/Tmdb_host_ipv4"
GITHUB_HOSTS_URL="https://hosts.gitcdn.top/hosts.txt"

# 函数：获取 hosts 信息
get_hosts_info() {
    local url=$1
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        local response=$(curl -s "$url")
        if [ $? -eq 0 ]; then
            echo "$response"
            return 0
        fi
        retries=$((retries + 1))
        echo "从 $url 获取 hosts 信息失败，第 $retries 次重试..."
        sleep 2
    done
    echo "从 $url 获取 hosts 信息失败，已达到最大重试次数。"
    return 1
}

# 获取 TMDB IPv4 和 GitHub 的 hosts 信息
TMDB_IPV4_HOSTS=$(get_hosts_info "$TMDB_IPV4_HOSTS_URL")
if [ $? -ne 0 ]; then
    echo "获取 TMDB IPv4 hosts 信息失败，脚本终止。"
    exit 1
fi

GITHUB_HOSTS=$(get_hosts_info "$GITHUB_HOSTS_URL")
if [ $? -ne 0 ]; then
    echo "获取 GitHub hosts 信息失败，脚本终止。"
    exit 1
fi

# 整合 hosts 信息并去除重复项
COMBINED_HOSTS=$(echo -e "$TMDB_IPV4_HOSTS\n$GITHUB_HOSTS" | sort -u)

# 确保 $DOCKER_ROOT_PATH/tmp 目录存在
if [ ! -d "$DOCKER_ROOT_PATH/tmp" ]; then
    mkdir -p "$DOCKER_ROOT_PATH/tmp"
    if [ $? -ne 0 ]; then
        echo "创建 $DOCKER_ROOT_PATH/tmp 目录失败，脚本终止。请检查权限或路径设置。"
        exit 1
    fi
fi

# 保存整合后的 hosts 信息到本地临时文件
TEMP_HOSTS_FILE="$DOCKER_ROOT_PATH/tmp/combined_hosts.txt"

# 检查是否有写入权限
if [ ! -w "$DOCKER_ROOT_PATH/tmp" ]; then
    echo "虽然是 root 用户，但 $DOCKER_ROOT_PATH/tmp 目录仍然没有写入权限，脚本终止。请检查系统配置。"
    exit 1
fi

echo "$COMBINED_HOSTS" > "$TEMP_HOSTS_FILE"
if [ $? -eq 0 ]; then
    echo "整合后的 hosts 信息已成功写入 $TEMP_HOSTS_FILE。"
    echo "当前整合后的 hosts 信息如下："
    echo "$COMBINED_HOSTS"
else
    echo "写入 $TEMP_HOSTS_FILE 文件失败，脚本终止。"
    exit 1
fi

# 导出所有可能会用到的变量
export CURRENT_DIR
export GATEWAY
export ARCHITECTURE
export DOCKER_NAMESPACE
export DOCKER_REGISTRY
export MOUNT_POINTS
export PHYSICAL_INTERFACES # 这里之前写的 INTERFACE_NAMES 可能有误，推测是 PHYSICAL_INTERFACES
export RANDOM_VARIABLE
export RANDOM_NUMBER
export PUBLIC_IP_CITY
export LONGITUDE
export LATITUDE
export DOCKER_ROOT_PATH
export VIDEO_ROOT_PATH
export HOST_IP
export USER_NAME
export IYUU_TOKEN
export GITHUB_PROXY
export PROXY_HOST
export DONATE_CODE
export VPS_IP
export result
export PUID
export PGID
export USER_GROUPS
export UMASK
export TEMP_HOSTS_FILE
export NAS_BRAND
export NAS_DEFAULT_PORT

# 集中输出所有重要变量并准备发送到指定 URL
echo "------------------- 脚本运行结果汇总 -------------------"
echo "工作目录: $CURRENT_DIR"
echo "网关地址: $GATEWAY"
echo "主机架构: $ARCHITECTURE"
echo "Docker 命名空间: $DOCKER_NAMESPACE"
echo "Docker 仓库地址: $DOCKER_REGISTRY"
echo "NAS 品牌: $NAS_BRAND"
echo "NAS 默认端口: $NAS_DEFAULT_PORT"
echo "随机字母数字变量: $RANDOM_VARIABLE"
echo "随机数字变量: $RANDOM_NUMBER"
echo "公网 IP 所在城市: $PUBLIC_IP_CITY"
echo "城市经度: $LONGITUDE"
echo "城市纬度: $LATITUDE"
echo "Docker 根路径: $DOCKER_ROOT_PATH"
echo "视频文件根路径: $VIDEO_ROOT_PATH"
echo "主机 IP 地址: $HOST_IP"
echo "用户名: $USER_NAME"
echo "IYUU TOKEN: $IYUU_TOKEN"
echo "GITHUB_PROXY: $GITHUB_PROXY"
echo "PROXY_HOST: $PROXY_HOST"
echo "捐赠码: $DONATE_CODE"
echo "VPS IP: $VPS_IP"
echo "MPV2 升级结果: $result"
echo "用户 PUID: $PUID"
echo "用户 PGID: $PGID"
echo "用户所属组信息: $USER_GROUPS"
echo "umask 值: $UMASK"
echo "临时 hosts 文件路径: $TEMP_HOSTS_FILE"
echo "--------------------------------------------------------"

# ... 前面集中输出重要变量的代码保持不变 ...

# 整理信息为 JSON 格式，使用汉字描述键名
JSON_DATA=$(jq -n \
    --arg current_dir "$CURRENT_DIR" \
    --arg gateway "$GATEWAY" \
    --arg architecture "$ARCHITECTURE" \
    --arg docker_namespace "$DOCKER_NAMESPACE" \
    --arg docker_registry "$DOCKER_REGISTRY" \
    --arg nas_brand "$NAS_BRAND" \
    --arg nas_default_port "$NAS_DEFAULT_PORT" \
    --arg physical_interfaces "$PHYSICAL_INTERFACES" \
    --arg mount_points "$MOUNT_POINTS" \
    --arg random_variable "$RANDOM_VARIABLE" \
    --arg random_number "$RANDOM_NUMBER" \
    --arg public_ip_city "$PUBLIC_IP_CITY" \
    --arg longitude "$LONGITUDE" \
    --arg latitude "$LATITUDE" \
    --arg docker_root_path "$DOCKER_ROOT_PATH" \
    --arg video_root_path "$VIDEO_ROOT_PATH" \
    --arg host_ip "$HOST_IP" \
    --arg user_name "$USER_NAME" \
    --arg iyuu_token "$IYUU_TOKEN" \
    --arg github_proxy "$GITHUB_PROXY" \
    --arg proxy_host "$PROXY_HOST" \
    --arg donate_code "$DONATE_CODE" \
    --arg vps_ip "$VPS_IP" \
    --arg mpv2_result "$result" \
    --arg puid "$PUID" \
    --arg pgid "$PGID" \
    --arg user_groups "$USER_GROUPS" \
    --arg umask "$UMASK" \
    --arg temp_hosts_file "$TEMP_HOSTS_FILE" \
    '{
        "工作目录": $current_dir,
        "网关地址": $gateway,
        "主机架构": $architecture,
        "Docker命名空间": $docker_namespace,
        "Docker仓库地址": $docker_registry,
        "NAS品牌": $nas_brand,
        "NAS默认端口": $nas_default_port,
        "物理网口名称": $physical_interfaces,
        "物理硬盘挂载点": $mount_points,
        "随机字母数字变量": $random_variable,
        "随机数字变量": $random_number,
        "公网IP所在城市": $public_ip_city,
        "城市经度": $longitude,
        "城市纬度": $latitude,
        "Docker根路径": $docker_root_path,
        "视频文件根路径": $video_root_path,
        "主机IP地址": $host_ip,
        "用户名": $user_name,
        "IYUU TOKEN": $iyuu_token,
        "GITHUB_PROXY": $github_proxy,
        "PROXY_HOST": $proxy_host,
        "捐赠码": $donate_code,
        "VPS IP": $vps_ip,
        "MPV2升级结果": $mpv2_result,
        "用户PUID": $puid,
        "用户PGID": $pgid,
        "用户所属组信息": $user_groups,
        "umask值": $umask,
        "临时hosts文件路径": $temp_hosts_file
    }')

# 生成文件名，格式为日期+nas品牌
DATE=$(date +%Y%m%d)
FILE_NAME="${DATE}-${NAS_BRAND}.json"

# 将 JSON 数据保存到以日期和 NAS 品牌命名的文件
echo "$JSON_DATA" > "$FILE_NAME"

# 上传文件到 Alist 的 WebDAV 地址
ALIST_URL="https://pan.naspt.vip/dav/123pan/json/.naspt-t1.conf"
ALIST_USER="qupeng1992"
ALIST_PASS="1992111kL"

UPLOAD_RESULT=$(curl -X PUT -u "naspt:Lzq951201@" -T ".naspt-t1.conf" --insecure "https://pan.naspt.vip/dav/installInfo/.naspt" -w "%{http_code}" -s -o /dev/null)

# 定义成功状态码数组
SUCCESS_CODES=(200 201 204)
# 检查上传结果
is_success=false
for code in "${SUCCESS_CODES[@]}"; do
    if [ "$UPLOAD_RESULT" -eq "$code" ]; then
        is_success=true
        break
    fi
done

if $is_success; then
    echo "信息已成功上传到 Alist: $ALIST_URL"
else
    echo "上传信息到 Alist 失败，HTTP 状态码: $UPLOAD_RESULT"
fi

# 可选：删除临时生成的文件
rm -f "$FILE_NAME"

check_container_status() {
    local container_name=$1
    local status=$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null)
    case "$status" in
        running) echo -e "${GREEN}[✔] $container_name 已启动${RESET}" ;;
        exited) echo -e "${RED}[✘] $container_name 已停止${RESET}" ;;
        *) echo -e "${RED}[✘] $container_name 未安装${RESET}" ;;
    esac
}

# 定义服务序号与完整服务名的映射
declare -A SERVICE_INDEX_MAP=(
    ["1"]="csf_mo"
    ["2"]="qb_mo"
    ["3"]="embypt_mo"
    ["4"]="moviepilot_v2_mo"
    ["5"]="cookiecloud_mo"
    ["6"]="frpc_mo"
    ["7"]="transmission_mo"
    ["8"]="audiobookshelf_mo"
    ["9"]="komga_mo"
    ["10"]="navidrome_mo"
    ["11"]="homepage_mo"
    ["12"]="dockerCopilot_mo"
    ["13"]="memos_mo"
    ["14"]="vertex_mo"
    ["15"]="freshrss_mo"
    ["16"]="rsshub_mo"
    ["17"]="metube_mo"
    ["18"]="filecodebox_mo"
    ["19"]="myip_mo"
    ["20"]="photopea_mo"
    ["21"]="easyimage_mo"
    ["22"]="glances_mo"
    ["23"]="easynode_mo"
    ["24"]="portainer_mo"
    ["25"]="lucky_mo"
    ["26"]="cd2_mo"
    ["27"]="alist_mo"
    ["28"]="aipan_mo"
    ["29"]="allinone_mo"
    ["30"]="allinone_format_mo"
    ["31"]="watchtower_mo"
    ["32"]="cms_mo"
    ["33"]="emby115_mo"
    ["34"]="mp115_mo"
    ["35"]="chromium_mo"
    ["36"]="qb_shua"
    ["37"]="embyptzb_mo"
    ["38"]="emby115zb_mo"
    ["39"]="csf115_mo"
    ["40"]="clash_mo"
    ["41"]="clashok_mo"
    ["42"]="owjdxb_mo"
)

# 更准确地检查容器是否存在
get_service_status() {
    local container_name=$1
    if docker inspect "$container_name" &>/dev/null; then
        echo -e "${GREEN}[✔]${RESET}"
    else
        echo -e "${RED}[✘]${RESET}"
    fi
}

# 卸载服务函数
uninstall_service() {
    local input=$1
    local service_name

    # 检查输入是否为有效的数字序号
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入无效，请输入有效的服务序号。${RESET}"
        return 1
    fi

    service_name="${SERVICE_INDEX_MAP[$input]}"

    # 检查该序号是否对应一个有效的服务名
    if [ -z "$service_name" ]; then
        echo -e "${RED}无效的序号，请输入正确的序号。${RESET}"
        return 1
    fi

    echo "尝试卸载的服务名称: $service_name"

    # 检查服务是否存在
    if [[ "$(get_service_status "$service_name")" == *"[✔]"* ]]; then
        echo "正在卸载 $service_name 服务..."
        if ! docker stop "$service_name"; then
            echo -e "${RED}停止 $service_name 服务失败！${RESET}"
            return 1
        fi
        if ! docker rm "$service_name"; then
            echo -e "${RED}移除 $service_name 容器失败！${RESET}"
            return 1
        fi
        rm -rf "$DOCKER_ROOT_PATH/$service_name"
        echo "$service_name 服务卸载完成。"
    else
        echo "该服务未安装，无法卸载。"
    fi
}


update_service() {
    local service_name=$1
    if [[ -z "${SERVICE_IMAGE_MAP[$service_name]}" ]]; then
        echo -e "${RED}未找到服务 $service_name 对应的 Docker 镜像。${RESET}"
        return 1
    fi
    local image="${SERVICE_IMAGE_MAP[$service_name]}"
    echo "正在更新 $service_name 服务..."
    docker pull "$image"
    if [ $? -ne 0 ]; then
        echo -e "${RED}更新 $service_name 镜像失败！${RESET}"
        return 1
    fi
    docker restart "$service_name"
    if [ $? -ne 0 ]; then
        echo -e "${RED}重启 $service_name 服务失败！${RESET}"
        return 1
    fi
    echo "$service_name 服务更新完成。"
}


echo -e "${GREEN}创建安装环境中...${RESET}"


# 单服务安装函数
install_service() {
    local service_id=$1
    case "$service_id" in
    

        1) init_csf_mo ; check_container_status "csf_mo" ;;
        2) init_qb_mo ; check_container_status "qb_mo" ;;
        3) init_embypt_mo ; check_container_status "embypt_mo" ;;
        4) init_moviepilot_v2_mo ; check_container_status "moviepilot_v2_mo" ;;
        5) init_cookiecloud_mo ; check_container_status "cookiecloud_mo" ;;
        6) init_frpc_mo ; check_container_status "frpc_mo" ;;
        7) init_transmission_mo ; check_container_status "transmission_mo" ;;
        8) init_audiobookshelf_mo ; check_container_status "audiobookshelf_mo" ;;
        9) init_komga_mo ; check_container_status "komga_mo" ;;
        10) init_navidrome_mo ; check_container_status "navidrome_mo" ;;
        11) init_homepage_mo ; check_container_status "homepage_mo" ;;
        12) init_dockerCopilot_mo ; check_container_status "dockerCopilot_mo" ;;
        13) init_memos_mo ; check_container_status "memos_mo" ;;
        14) init_vertex_mo ; check_container_status "vertex_mo" ;;
        15) init_freshrss_mo ; check_container_status "freshrss_mo" ;;
        16) init_rsshub_mo ; check_container_status "rsshub_mo" ;;
        17) init_metube_mo ; check_container_status "metube_mo" ;;
        18) init_filecodebox_mo ; check_container_status "filecodebox_mo" ;;
        19) init_myip_mo ; check_container_status "myip_mo" ;;
        20) init_photopea_mo ; check_container_status "photopea_mo" ;;
        21) init_easyimage_mo ; check_container_status "easyimage_mo" ;;
		22) init_glances_mo ; check_container_status "glances_mo" ;;
		23) init_easynode_mo ; check_container_status "easynode_mo" ;;	
		24) init_portainer_mo ; check_container_status "portainer_mo" ;;
		25) init_lucky_mo ; check_container_status "lucky_mo" ;;
		26) init_cd2_mo ; check_container_status "cd2_mo" ;;
		27) init_alist_mo ; check_container_status "alist_mo" ;;		
		28) init_aipan_mo ; check_container_status "aipan_mo" ;;		
		29) init_allinone_mo ; check_container_status "allinone_mo" ;;	
		30) init_allinone_format_mo ; check_container_status "allinone_format_mo" ;;
		31) init_watchtower_mo ; check_container_status "watchtower_mo" ;;		
        32) init_cms_mo ; check_container_status "cms_mo" ;;
        33) init_emby115_mo ; check_container_status "emby115_mo" ;;
        34) init_mp115_mo ; check_container_status "mp115_mo" ;;	
        35) init_chromium_mo ; check_container_status "chromium_mo" ;;
        36) init_qb_shua ; check_container_status "qb_shua" ;;
		37) init_embyptzb_mo ; check_container_status "embyptzb_mo" ;;
        38) init_emby115zb_mo ; check_container_status "emby115zb_mo" ;;
        39) init_csf115_mo ; check_container_status "csf115_mo" ;;
        40) init_clash_mo ; check_container_status "clash_mo" ;;
		41) init_clashok_mo ; check_container_status "clashok_mo" ;;
        42) init_owjdxb_mo ; check_container_status "owjdxb_mo" ;;
        43) init_database  ;;
        44) init_database115  ;;
        45) view_moviepilot_logs ;;
		
        *)
            echo -e "${RED}无效选项：$service_id${RESET}"
        ;;
    esac
}

# 初始化各个服务
init_clashok_mo() {
    echo "初始化 clashok_mo"
    mkdir -p "$DOCKER_ROOT_PATH/clashok_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/clashok_mo.tgz -o "$CURRENT_DIR/clash_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/clashok_mo.tgz" -C "$DOCKER_ROOT_PATH/clashok_mo/"
    docker run -d --name clashok_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/clashok_mo:/root/.config/clashok_mo" \
		--network bridge --privileged \
        -p 38080:8080 \
        -p 7890:7890 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
}

init_clash_mo() {
    echo "初始化 clash_mo"
    mkdir -p "$DOCKER_ROOT_PATH/clash_mo"
    docker run -d --name clash_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/clash_mo:/root/.config/clash_mo" \
		--network bridge --privileged \
        -p 38080:8080 \
        -p 7890:7890 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
}

init_qb_mo() {
    echo "初始化 qb_mo"
    mkdir -p "$DOCKER_ROOT_PATH/qb_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/qb_mo.tgz -o "$CURRENT_DIR/qb_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/qb_mo.tgz" -C "$DOCKER_ROOT_PATH/qb_mo/"
    docker run -d --name qb_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/qb_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID=$PUID -e PGID=$PGID -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=8080 \
        -e TORRENTING_PORT=6355 \
        -e SavePatch="/media/downloads" -e TempPatch="/media/downloads" \
        --network bridge --privileged \
        -p 58080:8080 \
        -p 6355:6355 \
        -p 6355:6355/udp \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
}

init_qb_shua() {
    echo "初始化 qb_shua"
    mkdir -p "$DOCKER_ROOT_PATH/qb_shua"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/qb_shua.tgz -o "$CURRENT_DIR/qb_shua.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/qb_shua.tgz" -C "$DOCKER_ROOT_PATH/qb_shua/"
    docker run -d --name qb_shua --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/qb_shua:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID=$PUID -e PGID=$PGID -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=8080 \
        -e TORRENTING_PORT=6366 \
        -e SavePatch="/media/downloads" -e TempPatch="/media/downloads" \
        --network bridge --privileged \
        -p 58081:8080 \
        -p 6366:6366 \
        -p 6366:6366/udp \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
}

init_transmission_mo() {
    echo "初始化 transmission_mo"
    mkdir -p "$DOCKER_ROOT_PATH/transmission_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/transmission_mo.tgz -o "$CURRENT_DIR/transmission_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/transmission_mo.tgz" -C "$DOCKER_ROOT_PATH/transmission_mo/"
    docker run -d \
        --name transmission_mo \
        --restart unless-stopped \
        --network bridge \
        --privileged \
        -e PUID=$PUID -e PGID=$PGID -e TZ=Asia/Shanghai \
        -e USER=666666 -e PASS=666666 \
        -e TRANSMISSION_WEB_HOME=/webui \
        -v $DOCKER_ROOT_PATH/transmission_mo:/config \
        -v $DOCKER_ROOT_PATH/transmission_mo/WATCH:/watch \
        -v $DOCKER_ROOT_PATH/transmission_mo/src:/webui \
        -v $VIDEO_ROOT_PATH:/media \
        -p 59091:9091 \
        -p 51788:51788 \
        -p 51788:51788/udp \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}transmission:4.0.5"
}

init_moviepilot_v2_mo() {
    echo "初始化 MoviePilot"
    mkdir -p "$DOCKER_ROOT_PATH/moviepilot_v2_mo/"{main,config,core}
    mkdir -p "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup"
    mkdir -p "$DOCKER_ROOT_PATH/transmission_mo/torrents"
    mkdir -p "$VIDEO_ROOT_PATH/downloads/电影" "$VIDEO_ROOT_PATH/downloads/电视剧" "$VIDEO_ROOT_PATH/links/电影" "$VIDEO_ROOT_PATH/links/电视剧"

    cat <<EOF > "$DOCKER_ROOT_PATH/moviepilot_v2_mo/config/app.env"
GITHUB_PROXY='$GITHUB_PROXY'
cookiecloud_mo_HOST='http://$HOST_IP:58088'
cookiecloud_mo_KEY='666666'
cookiecloud_mo_PASSWORD='666666'
TMDB_API_DOMAIN='api.themoviedb.org'
TMDB_IMAGE_DOMAIN='static-mdb.v.geilijiasu.com'
GLOBAL_IMAGE_CACHE='True'
EOF

    echo "初始化 moviepilot_v2_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/moviepilot_v2_mo.tgz -o "$CURRENT_DIR/moviepilot_v2_mo.tgz"
    if [ $? -ne 0 ]; then
        echo "下载 moviepilot_v2_mo.tgz 文件失败"
        return 1
    fi
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/moviepilot_v2_mo.tgz" -C "$DOCKER_ROOT_PATH/moviepilot_v2_mo/"
    if [ $? -ne 0 ]; then
        echo "解压 moviepilot_v2_mo.tgz 文件失败"
        return 1
    fi
    rm "$CURRENT_DIR/moviepilot_v2_mo.tgz"

    docker run -d \
      --name moviepilot_v2_mo \
      --restart always \
      --privileged \
      --network bridge \
      -v $VIDEO_ROOT_PATH:/media \
      -v $DOCKER_ROOT_PATH/moviepilot_v2_mo/config:/config \
      -v $DOCKER_ROOT_PATH/moviepilot_v2_mo/core:/moviepilot/.cache/ms-playwright \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $DOCKER_ROOT_PATH/transmission_mo/torrents/:/tr \
      -v $DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup/:/qb_mo \
      -v $TEMP_HOSTS_FILE:/etc/hosts:ro \
      -e MOVIEPILOT_AUTO_UPDATE=$result \
      -e NGINX_PORT=3000 \
      -e PORT=3001 \
      -e PUID="$PUID" \
      -e PGID="$PGID" \
      -e UMASK="$UMASK"  \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN=$IYUU_TOKEN \
      -e SUPERUSER="admin" \
      -e API_TOKEN="moling1992moling1992" \
      -e PROXY_HOST="$PROXY_HOST" \
      -e GITHUB_PROXY="$GITHUB_PROXY"\
      -p 53000:3000 \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"

    if [ $? -ne 0 ]; then
        echo "启动 moviepilot_v2_mo 容器失败"
        return 1
    fi

    echo "容器启动完成，开始检测是否生成了 user.db 文件..."
    local TIMEOUT=300  # 设置超时时间为 300 秒（5 分钟）
    local ELAPSED=0    # 已过去的时间
    SECONDS=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        # 等待容器启动完成并生成文件
        sleep 5  # 每 5 秒检查一次
        # 检查容器内是否存在 user.db 文件
        USER_DB_FILE="/config/user.db"
        FILE_EXISTS=$(docker exec moviepilot_v2_mo test -f "$USER_DB_FILE" && echo "exists" || echo "not exists")
        # 检查日志文件中是否存在 "所有插件初始化完成"
        LOG_FILES=$(docker exec moviepilot_v2_mo ls /docker/moviepilot_v2_mo/config/logs/*.log 2>/dev/null)
        LOG_MSG_FOUND=$(docker exec moviepilot_v2_mo grep -l "所有插件初始化完成" $LOG_FILES 2>/dev/null)
        if [ "$FILE_EXISTS" == "exists" ]; then
            echo "user.db 文件已成功生成在 /config 文件夹下。"
            break  # 跳出循环，继续后续操作
        else
            # 追加输出，确保前面的信息不变
            echo -ne "正在初始化 moviepilot_v2_mo... $SECONDS 秒 \r"
            ELAPSED=$SECONDS
        fi
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "超时：在 $TIMEOUT 秒内未检测到 user.db 文件。"
        return 1
    fi

    return 0
}

# 初始化 emby115_mo
init_emby115_mo() {
    echo "初始化 emby115_mo"
    mkdir -p "$DOCKER_ROOT_PATH/emby115_mo"

    # 根据架构选择下载链接和包名
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        PACKAGE_NAME="emby115_mo_arm.tgz"
    else
        PACKAGE_NAME="emby115_mo.tgz"
    fi
    DOWNLOAD_URL="https://moling7882.oss-cn-beijing.aliyuncs.com/999/${PACKAGE_NAME}"

    # 下载文件
    if ! curl -L "$DOWNLOAD_URL" -o "$CURRENT_DIR/${PACKAGE_NAME}"; then
        echo "下载 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 解压文件
    if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${PACKAGE_NAME}" -C "$DOCKER_ROOT_PATH/emby115_mo/"; then
        echo "解压 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 删除临时文件
    rm -f "$CURRENT_DIR/${PACKAGE_NAME}"

    # 根据架构选择镜像名称
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        IMAGE_NAME="embyserver_arm64v8"
    else
        IMAGE_NAME="embyserver"
    fi

    # 运行 Docker 容器
    if ! docker run -d \
        --name emby115_mo \
        --restart unless-stopped \
        --device /dev/dri:/dev/dri \
        --network bridge \
        --privileged \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e UMASK="$UMASK" \
        -e TZ=Asia/Shanghai \
        -v "$DOCKER_ROOT_PATH/emby115_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -p 38096:8096 \
        -p 38920:8920 \
        -e NO_PROXY="172.17.0.1,127.0.0.1,localhost" \
        -e ALL_PROXY="$PROXY_HOST" \
        -e HTTP_PROXY="$PROXY_HOST" \
        "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"; then
        echo "启动 emby115_mo 容器失败"
        return 1
    fi

    echo "emby115_mo 初始化成功"
    return 0
}

# 初始化 embypt_mo
init_embypt_mo() {
    echo "初始化 embypt_mo"
    mkdir -p "$DOCKER_ROOT_PATH/embypt_mo"

    # 根据架构选择下载链接和包名
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        PACKAGE_NAME="embypt_mo_arm.tgz"
    else
        PACKAGE_NAME="embypt_mo.tgz"
    fi
    DOWNLOAD_URL="https://moling7882.oss-cn-beijing.aliyuncs.com/999/${PACKAGE_NAME}"

    # 下载文件
    if ! curl -L "$DOWNLOAD_URL" -o "$CURRENT_DIR/${PACKAGE_NAME}"; then
        echo "下载 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 解压文件
    if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${PACKAGE_NAME}" -C "$DOCKER_ROOT_PATH/embypt_mo/"; then
        echo "解压 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 删除临时文件
    rm -f "$CURRENT_DIR/${PACKAGE_NAME}"

    # 根据架构选择镜像名称
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        IMAGE_NAME="embyserver_arm64v8"
    else
        IMAGE_NAME="embyserver"
    fi

    # 运行 Docker 容器
    if ! docker run -d \
        --name embypt_mo \
        --restart unless-stopped \
        --device /dev/dri:/dev/dri \
        --network bridge \
        --privileged \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e UMASK="$UMASK" \
        -e TZ=Asia/Shanghai \
        -v "$DOCKER_ROOT_PATH/embypt_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -p 58096:8096 \
        -p 58920:8920 \
        -e NO_PROXY="172.17.0.1,127.0.0.1,localhost" \
        -e ALL_PROXY="$PROXY_HOST" \
        -e HTTP_PROXY="$PROXY_HOST" \
        "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"; then
        echo "启动 embypt_mo 容器失败"
        return 1
    fi

    echo "embypt_mo 初始化成功"
    return 0
}
init_embyptzb_mo() {
    echo "初始化 embyptzb_mo"
    mkdir -p "$DOCKER_ROOT_PATH/embyptzb_mo"

    # 根据架构选择下载链接和包名
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        PACKAGE_NAME="embyptzb_mo_arm.tgz"
    else
        PACKAGE_NAME="embyptzb_mo.tgz"
    fi
    DOWNLOAD_URL="https://moling7882.oss-cn-beijing.aliyuncs.com/999/${PACKAGE_NAME}"

    # 下载文件
    if ! curl -L "$DOWNLOAD_URL" -o "$CURRENT_DIR/${PACKAGE_NAME}"; then
        echo "下载 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 解压文件
    if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${PACKAGE_NAME}" -C "$DOCKER_ROOT_PATH/embyptzb_mo/"; then
        echo "解压 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 删除临时文件
    rm -f "$CURRENT_DIR/${PACKAGE_NAME}"

    # 运行 Docker 容器
    if ! docker run -d --name embyptzb_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/embyptzb_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --device /dev/dri:/dev/dri \
        --network bridge --privileged \
        -p 58096:8096 \
        -p 58920:8920 \
        -e NO_PROXY="172.17.0.1,127.0.0.1,localhost" \
        -e ALL_PROXY="$PROXY_HOST" \
        -e HTTP_PROXY="$PROXY_HOST" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}emby:latest"; then
        echo "启动 embyptzb_mo 容器失败"
        return 1
    fi

    echo "embyptzb_mo 初始化成功"
    return 0
}

init_emby115zb_mo() {
    echo "初始化 emby115zb_mo"
    mkdir -p "$DOCKER_ROOT_PATH/emby115zb_mo"

    # 根据架构选择下载链接和包名
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        PACKAGE_NAME="emby115zb_mo_arm.tgz"
    else
        PACKAGE_NAME="emby115zb_mo.tgz"
    fi
    DOWNLOAD_URL="https://moling7882.oss-cn-beijing.aliyuncs.com/999/${PACKAGE_NAME}"

    # 下载文件
    if ! curl -L "$DOWNLOAD_URL" -o "$CURRENT_DIR/${PACKAGE_NAME}"; then
        echo "下载 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 解压文件
    if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${PACKAGE_NAME}" -C "$DOCKER_ROOT_PATH/emby115zb_mo/"; then
        echo "解压 ${PACKAGE_NAME} 失败，但仍尝试继续"
    fi

    # 删除临时文件
    rm -f "$CURRENT_DIR/${PACKAGE_NAME}"

    # 运行 Docker 容器
    if ! docker run -d --name emby115zb_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/emby115zb_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --device /dev/dri:/dev/dri \
        --network bridge --privileged \
        -p 38096:8096 \
        -p 38920:8920 \
        -e NO_PROXY="172.17.0.1,127.0.0.1,localhost" \
        -e ALL_PROXY="$PROXY_HOST" \
        -e HTTP_PROXY="$PROXY_HOST" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}emby:latest"; then
        echo "启动 emby115zb_mo 容器失败"
        return 1
    fi

    echo "emby115zb_mo 初始化成功"
    return 0
}

init_csf_mo() {
    echo "初始化 csf_mo"
    mkdir -p "$DOCKER_ROOT_PATH/csf_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/csf_mo.tgz -o "$CURRENT_DIR/csf_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/csf_mo.tgz" -C "$DOCKER_ROOT_PATH/csf_mo/"
    sed -i "s/192.168.66.220/$HOST_IP/g" "$DOCKER_ROOT_PATH/csf_mo/config/ChineseSubFinderSettings.json"
    docker run -d --name csf_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/csf_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --network bridge --privileged \
        -p 59035:19035 \
        -p 59037:19037 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:latest"
}

init_frpc_mo() {
    echo "初始化 frpc_mo"
    mkdir -p "$DOCKER_ROOT_PATH/frpc_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/frpc_mo.tgz -o "$CURRENT_DIR/frpc_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/frpc_mo.tgz" -C "$DOCKER_ROOT_PATH/frpc_mo/"
    sed -i "s/192.168.66.26/$HOST_IP/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    sed -i "s/130.162.246.23/$VPS_IP/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    sed -i "s/10114/$RANDOM_NUMBER/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    sed -i "s/9999/$RANDOM_VARIABLE/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    docker run -d --name frpc_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml:/etc/frp/frpc.toml" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frpc:latest"
}

init_audiobookshelf_mo() {
    echo "初始化 audiobookshelf_mo"
    mkdir -p "$DOCKER_ROOT_PATH/audiobookshelf_mo"
    mkdir -p "$VIDEO_ROOT_PATH/AD"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/audiobookshelf_mo.tgz -o "$CURRENT_DIR/audiobookshelf_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/audiobookshelf_mo.tgz" -C "$DOCKER_ROOT_PATH/audiobookshelf_mo/"
    docker run -d --name audiobookshelf_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 57758:80 \
        -v $VIDEO_ROOT_PATH:/media \
        -v $DOCKER_ROOT_PATH/audiobookshelf_mo/config:/config \
        -v $DOCKER_ROOT_PATH/audiobookshelf_mo/metadata:/metadata \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}audiobookshelf:latest"
}

init_komga_mo() {
    echo "初始化 komga_mo"
    mkdir -p "$DOCKER_ROOT_PATH/komga_mo"
    mkdir -p "$VIDEO_ROOT_PATH/MH"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/komga_mo.tgz -o "$CURRENT_DIR/komga_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/komga_mo.tgz" -C "$DOCKER_ROOT_PATH/komga_mo/"
    docker run -d --name komga_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55600:25600 \
        -v $VIDEO_ROOT_PATH:/media \
        -v $DOCKER_ROOT_PATH/komga_mo/config:/config \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}komga:latest"
}

init_navidrome_mo() {
    echo "初始化 navidrome_mo"
    mkdir -p "$DOCKER_ROOT_PATH/navidrome_mo"
    mkdir -p "$VIDEO_ROOT_PATH/music"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/navidrome_mo.tgz -o "$CURRENT_DIR/navidrome_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/navidrome_mo.tgz" -C "$DOCKER_ROOT_PATH/navidrome_mo/"
    docker run -d --name navidrome_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 54533:4533 \
        -e ND_SCANSCHEDULE="1h" \
        -e ND_LOGLEVEL="info" \
        -e ND_BASEURL="" \
        -e ND_SPOTIFY_ID="d5fffcb6f90040f2a817430d85694ba7" \
        -e ND_SPOTIFY_SECRET="172ee57bd6aa4b9d9f30f8a9311b91ed" \
        -e ND_LASTFM_APIKEY="842597b59804a3c4eb4f0365db458561" \
        -e ND_LASTFM_SECRET="aee9306d8d005de81405a37ec848983c" \
        -e ND_LASTFM_LANGUAGE="zh" \
        -v $DOCKER_ROOT_PATH/navidrome_mo/data:/data \
        -v $VIDEO_ROOT_PATH/music:/music \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navidrome:latest"
}

init_vertex_mo() {
    echo "初始化 vertex_mo"
    mkdir -p "$DOCKER_ROOT_PATH/vertex_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/vertex_mo.tgz -o "$CURRENT_DIR/vertex_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/vertex_mo.tgz" -C "$DOCKER_ROOT_PATH/vertex_mo/"
    docker run -d --name vertex_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53800:3000 \
        -p 53443:3443 \
        -v $DOCKER_ROOT_PATH/vertex_mo:/vertex_mo \
        -v $VIDEO_ROOT_PATH:/media \
        -e TZ=Asia/Shanghai \
        -e HTTPS_ENABLE=true \
        -e HTTPS_PORT=3443 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}vertex:latest"
}

init_freshrss_mo() {
    echo "初始化 freshrss_mo"
    mkdir -p "$DOCKER_ROOT_PATH/freshrss_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/freshrss_mo.tgz -o "$CURRENT_DIR/freshrss_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/freshrss_mo.tgz" -C "$DOCKER_ROOT_PATH/freshrss_mo/"
    docker run -d --name freshrss_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/freshrss_mo/config:/config \
        -p 58350:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}freshrss:latest"
}

init_easyimage_mo() {
    echo "初始化 easyimage_mo"
    mkdir -p "$DOCKER_ROOT_PATH/easyimage_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/easyimage_mo.tgz -o "$CURRENT_DIR/easyimage_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/easyimage_mo.tgz" -C "$DOCKER_ROOT_PATH/easyimage_mo/"
    docker run -d --name easyimage_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58631:80 \
        -e DEBUG=false \
        -v $DOCKER_ROOT_PATH/easyimage_mo/config:/app/web/config \
        -v $DOCKER_ROOT_PATH/easyimage_mo/i:/app/web/i \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyimage:latest"
}

init_homepage_mo() {
    echo "初始化 homepage_mo"
    mkdir -p "$DOCKER_ROOT_PATH/homepage_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/homepage_mo.tgz -o "$CURRENT_DIR/homepage_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/homepage_mo.tgz" -C "$DOCKER_ROOT_PATH/homepage_mo/"
    sed -i "s/192.168.66.31/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage_mo/config/services.yaml"
    sed -i "s/192.168.66.5/$GATEWAY/g" "$DOCKER_ROOT_PATH/homepage_mo/config/services.yaml"
    sed -i "s/192.168.66.31/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage_mo/config/settings.yaml"
    sed -i "s/8000/$NAS_DEFAULT_PORT/g" "$DOCKER_ROOT_PATH/homepage_mo/config/services.yaml"
    sed -i "s/NAS服务器/$NAS_BRAND/g" "$DOCKER_ROOT_PATH/homepage_mo/config/services.yaml"
    sed -i "s/192.168.66.26/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"	
    sed -i "s/Shenyang/$PUBLIC_IP_CITY/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"
    sed -i "s/41.8048/$LATITUDE/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"  
    sed -i "s/123.433/$LONGITUDE/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"  
    docker run -d --name homepage_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53010:3000 \
        -v $DOCKER_ROOT_PATH/homepage_mo/config:/app/config \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}homepage:latest"
}

init_dockerCopilot_mo() {
    echo "初始化 dockerCopilot_mo"
    mkdir -p "$DOCKER_ROOT_PATH/dockerCopilot_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/dockerCopilot_mo.tgz -o "$CURRENT_DIR/dockerCopilot_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/dockerCopilot_mo.tgz" -C "$DOCKER_ROOT_PATH/dockerCopilot_mo/"
    docker run -d --name dockerCopilot_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 52712:12712 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $DOCKER_ROOT_PATH/dockerCopilot_mo/data:/data \
        -e secretKey=666666mmm \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        -e hubURL=$DOCKER_REGISTRY \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockerCopilot:1.0"
}

init_memos_mo() {
    echo "初始化 memos_mo"
    mkdir -p "$DOCKER_ROOT_PATH/memos_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/memos_mo.tgz -o "$CURRENT_DIR/memos_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/memos_mo.tgz" -C "$DOCKER_ROOT_PATH/memos_mo/"
    docker run -d --name memos_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55230:5230 \
        -v $DOCKER_ROOT_PATH/memos_mo/:/var/opt/memos_mo \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}memos:latest"
}

init_owjdxb_mo() {
    echo "初始化 owjdxb_mo"
    mkdir -p "$DOCKER_ROOT_PATH/store"
    docker run -d --name owjdxb_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/store:/data/store" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}owjdxb:latest"
}

init_cookiecloud_mo() {
    echo "初始化 cookiecloud_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cookiecloud_mo"
    docker run -d --name cookiecloud_mo --restart unless-stopped \
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/cookiecloud_mo:/data/api/data" \
        -p 58088:8088 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cookiecloud:latest"
}

init_metube_mo() {
    echo "初始化 metube_mo"
    mkdir -p "$DOCKER_ROOT_PATH/metube_mo"
    mkdir -p "$VIDEO_ROOT_PATH/metube_mo"
    docker run -d --name metube_mo --restart unless-stopped \
        --network bridge --privileged \
        -p 58081:8081 \
        -v $VIDEO_ROOT_PATH/metube_mo:/downloads \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metube:latest"
}

init_filecodebox_mo() {
    echo "初始化 filecodebox_mo "
    mkdir -p "$DOCKER_ROOT_PATH/filecodebox_mo"
    docker run -d --name filecodebox_mo --restart unless-stopped \
        --network bridge --privileged \
        -p 52346:12345 \
        -v $DOCKER_ROOT_PATH/filecodebox_mo/:/app/data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}filecodebox:beta"
}

init_myip_mo() {
    echo "初始化 myip_mo "
    mkdir -p "$DOCKER_ROOT_PATH/myip_mo"
    docker run -d --name myip_mo --restart unless-stopped \
        --network bridge --privileged \
        -p 58966:18966 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myip:latest"
}

init_photopea_mo () {
    echo "初始化 photopea_mo "
    mkdir -p "$DOCKER_ROOT_PATH/photopea_mo "
    docker run -d --name photopea_mo  --restart unless-stopped \
        --network bridge --privileged \
        -p 59997:2887 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}photopea:1.0"
}

init_rsshub_mo () {
    echo "初始化 rsshub_mo "
    mkdir -p "$DOCKER_ROOT_PATH/rsshub_mo "
    docker run -d --name rsshub_mo  --restart unless-stopped \
        --network bridge --privileged \
        -p 51200:1200 \
        -e CACHE_EXPIRE=3600 \
        -e GITHUB_ACCESS_TOKEN=example \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:latest"
}

init_easynode_mo() {
    echo "初始化 easynode_mo"
    mkdir -p "$DOCKER_ROOT_PATH/easynode_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/easynode_mo.tgz -o "$CURRENT_DIR/easynode_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/easynode_mo.tgz" -C "$DOCKER_ROOT_PATH/easynode_mo/"
    docker run -d --name easynode_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58082:8082 \
        -v $DOCKER_ROOT_PATH/easynode_mo/db:/easynode_mo/app/db\
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easynode:latest"
}

init_portainer_mo() {
    echo "初始化 portainer_mo"
    mkdir -p "$DOCKER_ROOT_PATH/portainer_mo"
    docker run -d --name portainer_mo --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 59000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $DOCKER_ROOT_PATH/portainer_mo:/data\
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}portainer-ce:latest"
}

init_cd2_mo() {    
	echo "初始化 cd2_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cd2_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/cd2_mo.tgz -o "$CURRENT_DIR/cd2_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/cd2_mo.tgz" -C "$DOCKER_ROOT_PATH/cd2_mo/"    
    docker run -d \
        --name cd2_mo \
        --restart unless-stopped \
        --env CLOUDDRIVE_HOME=/Config \
        -v $DOCKER_ROOT_PATH/cd2_mo:/Config \
        -v $VIDEO_ROOT_PATH:/media:shared \
        --network host \
        --pid host \
        --privileged \
        --device /dev/fuse:/dev/fuse \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clouddrive2:latest"
}

init_lucky_mo() {
    echo "初始化 lucky_mo"
    mkdir -p "$DOCKER_ROOT_PATH/lucky_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/lucky_mo.tgz -o "$CURRENT_DIR/lucky_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/lucky_mo.tgz" -C "$DOCKER_ROOT_PATH/lucky_mo/"    
    docker run -d \
        --name lucky_mo \
        --restart=always \
        --net=host \
        -v $DOCKER_ROOT_PATH/lucky_mo:/goodluck \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}lucky:latest"
}

init_alist_mo() {
    echo "初始化 alist_mo"
    mkdir -p "$DOCKER_ROOT_PATH/alist_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/alist_mo.tgz -o "$CURRENT_DIR/alist_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/alist_mo.tgz" -C "$DOCKER_ROOT_PATH/alist_mo/"    
    docker run -d \
        --restart=unless-stopped \
        -v $DOCKER_ROOT_PATH/alist_mo:/opt/alist_mo/data \
        -p 55244:5244 \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --name="alist_mo" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}alist:latest"
}

init_glances_mo() {
    docker run -d \
        --restart="always" \
        --name "glances_mo" \
        -p 61208-61209:61208-61209 \
        -e glances_mo_OPT="-w" \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v /run/user/1000/podman/podman.sock:/run/user/1000/podman/podman.sock:ro \
        --pid host \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}glances:latest"
}

init_aipan_mo() {  
    docker run -d \
        --restart="always" \
        --name "aipan_mo" \
        -p 23565:3000 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}aipan-netdisk-search:latest"
}


init_allinone_mo() {
    docker run -d \
        --name allinone_mo \
        --privileged \
        --restart=unless-stopped \
        -p 55101:35455 \
        --network bridge \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone:latest" \
        -tv=true \
        -aesKey=swj6pnb4h6xyvhpq69fgae2bbpjlb8y2 \
        -userid=5892131247 \
        -token=9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137		
}

init_allinone_format_mo() {
    docker run -d \
        --name allinone_format_mo \
        --restart=always \
        -p 55102:35456 \
        --network bridge \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone_format:latest"		
}

init_watchtower_mo() {
    docker run -d \
        --name watchtower_mo \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e TZ=Asia/Shanghai \
        --restart=unless-stopped \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}watchtower:latest" \
        --schedule "0 3 * * *"
} 

init_cms_mo() {
    echo "初始化 cms_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cms_mo/"{cache,config,logs}
    docker run -d --name cms_mo --restart unless-stopped \
      -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
      -p 9527:9527 \
      -p 9096:9096 \
      -v $DOCKER_ROOT_PATH/cms_mo/config:/config \
      -v $DOCKER_ROOT_PATH/cms_mo/logs:/logs \
      -v $DOCKER_ROOT_PATH/cms_mo/cache:/var/cache/nginx/emby \
      -v $VIDEO_ROOT_PATH:/media \
      -e RUN_ENV=online \
      -e ADMIN_USERNAME=666666 \
      -e ADMIN_PASSWORD=666666 \
      -e EMBY_HOST_PORT=http://$HOST_IP:38096 \
      -e EMBY_API_KEY=da40f811ae1040e6b653cc8a35f1af72 \
      -e IMAGE_CACHE_POLICY=3 \
      -e DONATE_CODE=$DONATE_CODE \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloud-media-sync:latest"
}

init_mp115_mo() {
    echo "初始化 MoviePilot"
    mkdir -p "$DOCKER_ROOT_PATH/mp115_mo/"{main,config,core}
    mkdir -p "$VIDEO_ROOT_PATH/原始库" "$VIDEO_ROOT_PATH/整理库/电影" "$VIDEO_ROOT_PATH/整理库/电视剧" "$VIDEO_ROOT_PATH/整理库/媒体信息"

    cat <<EOF > "$DOCKER_ROOT_PATH/mp115_mo/config/app.env"
GITHUB_PROXY='$GITHUB_PROXY'
TMDB_API_DOMAIN='api.themoviedb.org'
TMDB_IMAGE_DOMAIN='static-mdb.v.geilijiasu.com'
GLOBAL_IMAGE_CACHE='True'
EOF

    echo "初始化 mp115_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/mp115_mo.tgz -o "$CURRENT_DIR/mp115_mo.tgz"
    if [ $? -ne 0 ]; then
        echo "下载 mp115_mo.tgz 文件失败"
        return 1
    fi
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/mp115_mo.tgz" -C "$DOCKER_ROOT_PATH/mp115_mo/"
    if [ $? -ne 0 ]; then
        echo "解压 mp115_mo.tgz 文件失败"
        return 1
    fi
    rm "$CURRENT_DIR/mp115_mo.tgz"

    docker run -d \
      --name mp115_mo \
      --restart always \
      --privileged \
      --network bridge \
      -v $VIDEO_ROOT_PATH:/media \
      -v $DOCKER_ROOT_PATH/mp115_mo/config:/config \
      -v $DOCKER_ROOT_PATH/mp115_mo/core:/moviepilot/.cache/ms-playwright \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $TEMP_HOSTS_FILE:/etc/hosts:ro \
      -e MOVIEPILOT_AUTO_UPDATE=$result \
      -e NGINX_PORT=3000 \
      -e PORT=3001 \
      -e PUID="$PUID" \
      -e PGID="$PGID" \
      -e UMASK="$UMASK"  \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN=$IYUU_TOKEN \
      -e SUPERUSER="admin" \
      -e API_TOKEN="moling1992moling1992" \
      -e PROXY_HOST="$PROXY_HOST" \
      -e GITHUB_PROXY="$GITHUB_PROXY"\
      -p 52000:3000 \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"

    if [ $? -ne 0 ]; then
        echo "启动 mp115_mo 容器失败"
        return 1
    fi

    echo "容器启动完成，开始检测是否生成了 user.db 文件..."
    local TIMEOUT=300  # 设置超时时间为 300 秒（5 分钟）
    local ELAPSED=0    # 已过去的时间
    SECONDS=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        # 等待容器启动完成并生成文件
        sleep 5  # 每 5 秒检查一次
        # 检查容器内是否存在 user.db 文件
        USER_DB_FILE="/config/user.db"
        FILE_EXISTS=$(docker exec mp115_mo test -f "$USER_DB_FILE" && echo "exists" || echo "not exists")
        # 检查日志文件中是否存在 "所有插件初始化完成"
        LOG_FILES=$(docker exec mp115_mo ls /docker/mp115_mo/config/logs/*.log 2>/dev/null)
        LOG_MSG_FOUND=$(docker exec mp115_mo grep -l "所有插件初始化完成" $LOG_FILES 2>/dev/null)
        if [ "$FILE_EXISTS" == "exists" ]; then
            echo "user.db 文件已成功生成在 /config 文件夹下。"
            break  # 跳出循环，继续后续操作
        else
            # 追加输出，确保前面的信息不变
            echo -ne "正在初始化 mp115_mo... $SECONDS 秒 \r"
            ELAPSED=$SECONDS
        fi
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "超时：在 $TIMEOUT 秒内未检测到 user.db 文件。"
        return 1
    fi

    return 0
}

init_csf115_mo() {
    echo "初始化 csf115_mo"
    mkdir -p "$DOCKER_ROOT_PATH/csf115_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/csf115_mo.tgz -o "$CURRENT_DIR/csf115_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/csf115_mo.tgz" -C "$DOCKER_ROOT_PATH/csf115_mo/"
    sed -i "s/192.168.66.30/$HOST_IP/g" "$DOCKER_ROOT_PATH/csf115_mo/config/ChineseSubFinderSettings.json"
    docker run -d --name csf115_mo --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/csf115_mo:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --network bridge --privileged \
        -p 39035:19035 \
        -p 39037:19037 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:latest"
}

init_chromium_mo() {
    echo "初始化 chromium_mo"
    mkdir -p "$DOCKER_ROOT_PATH/chromium_mo"
    docker run -d \
        --name chromium_mo \
        --shm-size=1gb \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 56901:6901 \
        -e VNC_PW=666666 \
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/chromium_mo:/home/kasm-user/Desktop" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chrome:latest"
}


init_database() {
    echo "UPDATE systemconfig SET value = REPLACE(value, '192.168.66.31', '$HOST_IP') WHERE value LIKE '%192.168.66.31%';" >> "$DOCKER_ROOT_PATH/moviepilot_v2_mo/config/script.sql"
    echo "初始化数据库..."
    # SQL 文件路径
    SQL_FILE="$DOCKER_ROOT_PATH/moviepilot_v2_mo/config/script.sql"
    # 确保 SQL 文件存在
    if [ ! -f "$SQL_FILE" ]; then
        echo "错误: SQL 文件 $SQL_FILE 不存在。请确认文件路径是否正确。"
        exit 1
    fi
    # 在容器中通过 Python 执行 SQL 文件
    docker exec -i  -w /config moviepilot_v2_mo python -c "
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
    docker restart moviepilot_v2_mo

    echo "正在检查容器是否成功重启..."
    sleep 1  # 等待容器重新启动
    SECONDS=0
# 持续检查容器状态，直到容器运行或失败
    while true; do
        CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' moviepilot_v2_mo)

        if [ "$CONTAINER_STATUS" == "running" ]; then
            echo "容器 moviepilot_v2_mo 重启成功！"
            break
        elif [ "$CONTAINER_STATUS" == "starting" ]; then
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化moviepilot_v2_mo... $SECONDS 秒 \r"
            sleep 1 # 等待2秒后再次检查
        else
            echo "错误: 容器 moviepilot_v2_mo 重启失败！状态：$CONTAINER_STATUS"
            exit 1
        fi
    done
}

init_database115() {
    echo "UPDATE systemconfig SET value = REPLACE(value, '192.168.66.31', '$HOST_IP') WHERE value LIKE '%192.168.66.31%';" >> "$DOCKER_ROOT_PATH/mp115_mo/config/script.sql"
    echo "初始化数据库..."
    # SQL 文件路径
    SQL_FILE="$DOCKER_ROOT_PATH/mp115_mo/config/script.sql"
    # 确保 SQL 文件存在
    if [ ! -f "$SQL_FILE" ]; then
        echo "错误: SQL 文件 $SQL_FILE 不存在。请确认文件路径是否正确。"
        exit 1
    fi
    # 在容器中通过 Python 执行 SQL 文件
    docker exec -i  -w /config mp115_mo python -c "
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
    docker restart mp115_mo

    echo "正在检查容器是否成功重启..."
    sleep 1  # 等待容器重新启动
    SECONDS=0
# 持续检查容器状态，直到容器运行或失败
    while true; do
        CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' mp115_mo)

        if [ "$CONTAINER_STATUS" == "running" ]; then
            echo "容器 mp115_mo 重启成功！"
            break
        elif [ "$CONTAINER_STATUS" == "starting" ]; then
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化mp115_mo... $SECONDS 秒 \r"
            sleep 1 # 等待2秒后再次检查
        else
            echo "错误: 容器 mp115_mo 重启失败！状态：$CONTAINER_STATUS"
            exit 1
        fi
    done
}

view_moviepilot_logs() {
    echo "查看 moviepilot_v2_mo 容器日志..."
    docker logs -f moviepilot_v2_mo
}

# 定义服务和 Docker 镜像的对应数组
declare -A SERVICE_IMAGE_MAP=(
    ["csf_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:latest"
    ["qb_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
    ["qb_shua"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
    ["embypt_mo"]="${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
    ["moviepilot_v2_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"
    ["cookiecloud_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cookiecloud:latest"
    ["frpc_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frpc:latest"
    ["transmission_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}transmission:4.0.5"
    ["audiobookshelf_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}audiobookshelf:latest"
    ["komga_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}komga:latest"
    ["navidrome_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navidrome:latest"
    ["vertex_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}vertex:latest"
    ["freshrss_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}freshrss:latest"
    ["easyimage_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyimage:latest"
    ["homepage_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}homepage:latest"
    ["dockerCopilot_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockerCopilot:1.0"
    ["memos_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}memos:latest"
    ["owjdxb_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}owjdxb:latest"
    ["metube_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metube:latest"
    ["filecodebox_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}filecodebox:beta"
    ["myip_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myip:latest"
    ["photopea_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}photopea:1.0"
    ["rsshub_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:latest"
    ["easynode_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easynode:latest"
    ["portainer_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}portainer-ce:latest"
    ["lucky_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}lucky:latest"
    ["cd2_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clouddrive2:latest"
    ["alist_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}alist:latest"
    ["glances_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}glances:latest"
    ["aipan_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}aipan-netdisk-search:latest"
    ["allinone_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone:latest"
    ["allinone_format_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone_format:latest"
    ["watchtower_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}watchtower:latest"
    ["cms_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloud-media-sync:latest"
    ["emby115_mo"]="${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
    ["mp115_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"
    ["chromium_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chrome:latest"
    ["embyptzb_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}emby:latest"
    ["emby115zb_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}emby:latest"
    ["csf115_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:latest"
    ["clash_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
    ["clashok_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
)

# 定义列数
columns=3

while true; do
    # 获取各服务的安装状态，按 install_service 里的顺序
    csf_mo_status=$(get_service_status "csf_mo")
    qb_mo_status=$(get_service_status "qb_mo")
    embypt_mo_status=$(get_service_status "embypt_mo")
    moviepilot_v2_mo_status=$(get_service_status "moviepilot_v2_mo")
    cookiecloud_mo_status=$(get_service_status "cookiecloud_mo")
    frpc_mo_status=$(get_service_status "frpc_mo")
    transmission_mo_status=$(get_service_status "transmission_mo")
    audiobookshelf_mo_status=$(get_service_status "audiobookshelf_mo")
    komga_mo_status=$(get_service_status "komga_mo")
    navidrome_mo_status=$(get_service_status "navidrome_mo")
    homepage_mo_status=$(get_service_status "homepage_mo")
    dockerCopilot_mo_status=$(get_service_status "dockerCopilot_mo")
    memos_mo_status=$(get_service_status "memos_mo")
    vertex_mo_status=$(get_service_status "vertex_mo")
    freshrss_mo_status=$(get_service_status "freshrss_mo")
    rsshub_mo_status=$(get_service_status "rsshub_mo")
    metube_mo_status=$(get_service_status "metube_mo")
    filecodebox_mo_status=$(get_service_status "filecodebox_mo")
    myip_mo_status=$(get_service_status "myip_mo")
    photopea_mo_status=$(get_service_status "photopea_mo")
    easyimage_mo_status=$(get_service_status "easyimage_mo")
    glances_mo_status=$(get_service_status "glances_mo")
    easynode_mo_status=$(get_service_status "easynode_mo")
    portainer_mo_status=$(get_service_status "portainer_mo")
    lucky_mo_status=$(get_service_status "lucky_mo")
    cd2_mo_status=$(get_service_status "cd2_mo")
    alist_mo_status=$(get_service_status "alist_mo")
    aipan_mo_status=$(get_service_status "aipan_mo")
    allinone_mo_status=$(get_service_status "allinone_mo")
    allinone_format_mo_status=$(get_service_status "allinone_format_mo")
    watchtower_mo_status=$(get_service_status "watchtower_mo")
    cms_mo_status=$(get_service_status "cms_mo")
    emby115_mo_status=$(get_service_status "emby115_mo")
    mp115_mo_status=$(get_service_status "mp115_mo")
    chromium_mo_status=$(get_service_status "chromium_mo")
    qb_shua_status=$(get_service_status "qb_shua")
    embyptzb_mo_status=$(get_service_status "embyptzb_mo")
    emby115zb_mo_status=$(get_service_status "emby115zb_mo")
    csf115_mo_status=$(get_service_status "csf115_mo")
    clash_mo_status=$(get_service_status "clash_mo")
    clashok_mo_status=$(get_service_status "clashok_mo")
    owjdxb_mo_status=$(get_service_status "owjdxb_mo")

    echo "请选择要安装的服务（输入数字，多个数字用空格分隔）："

# 前面获取服务状态、提示选择服务等代码保持不变

# 构建隐藏 _mo 后缀的服务列表
service_list=(
    "1. csf $csf_mo_status"
    "2. qb $qb_mo_status"
    "3. embypt $embypt_mo_status"
    "4. moviepilot_v2 $moviepilot_v2_mo_status"
    "5. cookiecloud $cookiecloud_mo_status"
    "6. frpc $frpc_mo_status"
    "7. transmission $transmission_mo_status"
    "8. audiobookshelf $audiobookshelf_mo_status"
    "9. komga $komga_mo_status"
    "10. navidrome $navidrome_mo_status"
    "11. homepage $homepage_mo_status"
    "12. dockerCopilot $dockerCopilot_mo_status"
    "13. memos $memos_mo_status"
    "14. vertex $vertex_mo_status"
    "15. freshrss $freshrss_mo_status"
    "16. rsshub $rsshub_mo_status"
    "17. metube $metube_mo_status"
    "18. filecodebox $filecodebox_mo_status"
    "19. myip $myip_mo_status"
    "20. photopea $photopea_mo_status"
    "21. easyimage $easyimage_mo_status"
    "22. glances $glances_mo_status"
    "23. easynode $easynode_mo_status"
    "24. portainer $portainer_mo_status"
    "25. lucky $lucky_mo_status"
    "26. cd2 $cd2_mo_status"
    "27. alist $alist_mo_status"
    "28. aipan $aipan_mo_status"
    "29. allinone $allinone_mo_status"
    "30. allinone_format $allinone_format_mo_status"
    "31. watchtower $watchtower_mo_status"
    "32. cms $cms_mo_status"
    "33. emby115 $emby115_mo_status"
    "34. mp115 $mp115_mo_status"
    "35. chromium $chromium_mo_status"
    "36. qb_shua $qb_shua_status"
    "37. embyptzb $embyptzb_mo_status"
    "38. emby115zb $emby115zb_mo_status"
    "39. csf115 $csf115_mo_status"
    "40. clash $clash_mo_status"
    "41. clashok $clashok_mo_status"
    "42. owjdxb $owjdxb_mo_status"
    "43. 初始化数据库"
    "44. 初始化115数据库"
    "45. 查看 MoviePilot 日志"
    "46. 更新所有已安装服务"
    "47. 卸载指定服务（输入服务名称）"
    "0. 退出"
)

# 定义列数
columns=3

# 找出每列最长元素的长度
max_lengths=()
for ((i = 0; i < columns; i++)); do
    max_length=0
    for ((j = i; j < ${#service_list[@]}; j += columns)); do
        item="${service_list[$j]}"
        length=${#item}
        if (( length > max_length )); then
            max_length=$length
        fi
    done
    max_lengths[$i]=$max_length
done

# 计算行数
rows=$(( (${#service_list[@]} + columns - 1) / columns ))

# 循环打印多列，确保左对齐
for ((i = 0; i < rows; i++)); do
    for ((j = 0; j < columns; j++)); do
        index=$(( i + j * rows ))
        if [ $index -lt ${#service_list[@]} ]; then
            item="${service_list[$index]}"
            printf "%-${max_lengths[$j]}s  " "$item"
        fi
    done
    echo
done

# 后续读取用户输入等代码保持不变
read -p "请输入选择的服务数字： " service_choices

    for service_choice in $service_choices; do
        if [[ "$service_choice" == "0" ]]; then
            OUTPUT_FILE="$DOCKER_ROOT_PATH/安装信息.txt"
            : > "$OUTPUT_FILE"
            echo "服务安装已完成，以下是每个服务的访问信息：" | tee -a "$OUTPUT_FILE"

            # 定义服务名称和对应的配置信息数组，修改分隔符为 |
            declare -A service_info=(
                ["csf_mo"]="http://$HOST_IP:59035|666666|666666"
                ["qb_mo"]="http://$HOST_IP:58080|666666|666666"
                ["qb_shua"]="http://$HOST_IP:58081|666666|666666"
                ["embypt_mo"]="http://$HOST_IP:58096|666666|666666"
                ["moviepilot_v2_mo"]="http://$HOST_IP:53000|admin|666666m"
                ["cookiecloud_mo"]="http://$HOST_IP:58088|666666|666666"
                ["frpc_mo"]="无|无|无"
                ["transmission_mo"]="http://$HOST_IP:59091|无|无"
                ["owjdxb_mo"]="http://$HOST_IP:9118|无|无"
                ["audiobookshelf_mo"]="http://$HOST_IP:57758|root|666666"
                ["komga_mo"]="http://$HOST_IP:55600|666666@qq.com|666666"
                ["navidrome_mo"]="http://$HOST_IP:54533|666666|666666"
                ["dockerCopilot_mo"]="http://$HOST_IP:52172|无|666666mmm"
                ["memos_mo"]="http://$HOST_IP:55230|666666|666666"
                ["homepage_mo"]="http://$HOST_IP:53010|无|无"
                ["vertex_mo"]="http://$HOST_IP:53800|666666|666666"
                ["freshrss_mo"]="http://$HOST_IP:58350|666666|666666m"
                ["rsshub_mo"]="http://$HOST_IP:51200|无|无"
                ["metube_mo"]="http://$HOST_IP:58081|无|无"
                ["filecodebox_mo"]="http://$HOST_IP:52346|无|无"
                ["myip_mo"]="http://$HOST_IP:58966|无|无"
                ["photopea_mo"]="http://$HOST_IP:59997|无|无"
                ["easyimage_mo"]="http://$HOST_IP:58631|无|无"
                ["clash_mo"]="http://$HOST_IP:38080|无|无"
                ["easynode_mo"]="http://$HOST_IP:58082|666666|666666"
                ["portainer_mo"]="http://$HOST_IP:59000|admin|666666666666"
                ["lucky_mo"]="http://$HOST_IP:16601|666666|666666"
                ["cd2_mo"]="http://$HOST_IP:19798|无|无"
                ["alist_mo"]="http://$HOST_IP:55244|666666|666666"
                ["glances_mo"]="http://$HOST_IP:61208|无|无"
                ["aipan_mo"]="http://$HOST_IP:23565|无|无"
                ["allinone_mo"]="http://$HOST_IP:55101|无|无"
                ["allinone_format_mo"]="http://$HOST_IP:55102|无|无"
                ["watchtower_mo"]="无|无|无"
                ["csf115_mo"]="http://$HOST_IP:39035|666666|666666"
                ["cms_mo"]="http://$HOST_IP:9527|666666|666666"
                ["emby115_mo"]="http://$HOST_IP:38096|666666|666666"
                ["mp115_mo"]="http://$HOST_IP:52000|admin|666666m"
                ["chromium_mo"]="http://$HOST_IP:56901|kasm_user|666666"
                ["embyptzb_mo"]="http://$HOST_IP:58096|666666|666666"
                ["emby115zb_mo"]="http://$HOST_IP:38096|666666|666666"
            )

            # 遍历服务信息数组，根据安装状态输出
            for service in "${!service_info[@]}"; do
                if [[ "$(get_service_status "$service")" == *"[✔]"* ]]; then
                    echo "服务名称：$service" | tee -a "$OUTPUT_FILE"
                    IFS='|' read -ra parts <<< "${service_info[$service]}"
                    echo "  地址：${parts[0]}" | tee -a "$OUTPUT_FILE"
                    echo "  账号：${parts[1]}" | tee -a "$OUTPUT_FILE"
                    echo "  密码：${parts[2]}" | tee -a "$OUTPUT_FILE"
                    echo "" | tee -a "$OUTPUT_FILE"
                fi
            done

            echo | tee -a "$OUTPUT_FILE"
            history -c
            echo "安装流程结束！配置信息已保存到 $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
            exit 0
        elif [[ "$service_choice" == "47" ]]; then
            read -p "请输入要卸载的服务序号或不包含 _mo 后缀的服务名称： " service_name_input
            # 检查输入是否为数字（序号）
            if [[ "$service_name_input" =~ ^[0-9]+$ ]]; then
                service_name="${SERVICE_INDEX_MAP[$service_name_input]}"
                if [ -z "$service_name" ]; then
                    echo "无效的序号，请输入正确的序号。"
                    continue
                fi
            else
                service_name="${service_name_input}_mo"
            fi

            if [[ "$(get_service_status "$service_name")" == *"[✔]"* ]]; then
                uninstall_service "$service_name"
            else
                echo "该服务未安装，无法卸载。"
            fi
        else
            install_service "$service_choice"
        fi
    done
done
