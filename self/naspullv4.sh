#!/bin/bash

# 红色文本颜色代码
RED="\033[31m"
GREEN="\033[32m"
RESET="\033[0m"

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
    echo "目录 $CURRENT_DIR 不存在，已创建。"
else
    echo "目录 $CURRENT_DIR 已存在。"
fi
ENV_FILE="$CURRENT_DIR/.env"

docker login --username=aliyun4118146718 crpi-dt5pygtutdf9o78k.cn-shanghai.personal.cr.aliyuncs.com

# 设定环境变量 PUID、PGID 和 UMASK
PUID="${PUID:-0}"  # 默认为0，如果环境变量已设置，则使用环境变量的值
PGID="${PGID:-0}"  # 默认为0
UMASK="${UMASK:-022}"  # 默认为000
DOCKER_REGISTRY="crpi-dt5pygtutdf9o78k.cn-shanghai.personal.cr.aliyuncs.com/moling7882"

# 新增获取网关地址变量
# 使用ip route命令获取网关地址
GATEWAY=$(ip route | grep 'default' | awk '{print $3}')
if [ -z "$GATEWAY" ]; then
    echo "未能获取到网关地址。"
else
    echo "网关地址: $GATEWAY"
fi

# 新增随机生成字母加数字的变量
RANDOM_VARIABLE=$(openssl rand -base64 10 | tr -dc 'A-Za-z0-9' | head -c 10)

# 随机生成10000 - 15000数字的变量
RANDOM_NUMBER=$((10000 + $RANDOM % 5001))

# 获取公网IP所在城市
PUBLIC_IP_CITY=$(curl -s "http://ip-api.com/json" | grep -oP '"city":"\K[^"]*')
echo "公网IP所在城市: $PUBLIC_IP_CITY"

# 获取该城市的经度
LONGITUDE=$(curl -s "http://ip-api.com/json" | grep -oP '"lon":\K[-+]?[0-9]*\.?[0-9]+')

# 获取该城市的纬度
LATITUDE=$(curl -s "http://ip-api.com/json" | grep -oP '"lat":\K[-+]?[0-9]*\.?[0-9]+')

# 定义链接
GITHUB_HOSTS_URL="https://hosts.gitcdn.top/hosts.txt"

# 获取链接内容并赋值给变量
GITHUB_HOSTS_CONTENT=$(curl -s "$GITHUB_HOSTS_URL")

# 定义各品牌常用端口
SYNOLOGY_PORTS=(5000 5001)
GREENLINK_PORTS=(9999)
ZSPACE_PORTS=(5056)
FEINIU_PORTS=(8000 8001 5666 5667)

# 获取系统正在使用的端口
USED_PORTS=$(ss -ltn | awk '{print $4}' | cut -d: -f2 | sort -u)

# 初始化变量
WEB_PORT=""
BRAND=""

# 检查群晖
for port in "${SYNOLOGY_PORTS[@]}"; do
    if echo "$USED_PORTS" | grep -q "$port"; then
        WEB_PORT="$port"
        BRAND="群晖"
        break
    fi
done

# 检查绿联
if [ -z "$BRAND" ]; then
    for port in "${GREENLINK_PORTS[@]}"; do
        if echo "$USED_PORTS" | grep -q "$port"; then
            WEB_PORT="$port"
            BRAND="绿联"
            break
        fi
    done
fi

# 检查极空间
if [ -z "$BRAND" ]; then
    for port in "${ZSPACE_PORTS[@]}"; do
        if echo "$USED_PORTS" | grep -q "$port"; then
            WEB_PORT="$port"
            BRAND="极空间"
            break
        fi
    done
fi

# 检查飞牛
if [ -z "$BRAND" ]; then
    for port in "${FEINIU_PORTS[@]}"; do
        if echo "$USED_PORTS" | grep -q "$port"; then
            WEB_PORT="$port"
            BRAND="飞牛"
            break
        fi
    done
fi

# 导出变量，以便后续脚本引用
export WEB_ACCESS_PORT="$WEB_PORT"
export NAS_BRAND="$BRAND"

# 输出结果
echo "网页访问端口号: $WEB_ACCESS_PORT"
echo "品牌名: $NAS_BRAND"

LOG_FILE="$CURRENT_DIR/install.log"
log() {
    local message=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}
log "脚本开始运行"

# 从环境变量文件加载已有的环境变量
load_env_vars() {
       if [ -f "$ENV_FILE" ]; then
        # 加载文件中的环境变量
        source "$ENV_FILE"
        echo "环境变量已成功加载。"
    else
        echo "环境变量文件 ($ENV_FILE) 不存在。"
    fi

    # 输出当前所有的环境变量
    # 只输出脚本中定义的环境变量
    echo -e "\n脚本定义的环境变量如下："
    echo "DOCKER_ROOT_PATH=$DOCKER_ROOT_PATH"
    echo "VIDEO_ROOT_PATH=$VIDEO_ROOT_PATH"
    echo "HOST_IP=$HOST_IP"
    echo "DOCKER_REGISTRY=$DOCKER_REGISTRY"
    echo "USER_ID=$USER_ID"
    echo "GROUP_ID=$GROUP_ID"
    echo "USER_GROUPS=$USER_GROUPS"
    echo "GATEWAY=$GATEWAY"
    echo "RANDOM_VARIABLE=$RANDOM_VARIABLE"
    echo "RANDOM_NUMBER=$RANDOM_NUMBER"
    echo "PUBLIC_IP_CITY=$PUBLIC_IP_CITY" # 新增输出公网IP所在城市变量
    echo "LONGITUDE=$LONGITUDE" # 新增输出经度变量
    echo "LATITUDE=$LATITUDE" # 新增输出纬度变量
    echo "WEB_ACCESS_PORT=$WEB_ACCESS_PORT"
    echo "NAS_BRAND=$NAS_BRAND"
    echo "IYUU_TOEKN=$IYUU_TOEKN"
}
load_env_vars

# 写入环境变量到文件
save_env_vars() {
    # 备份现有的 .env 文件
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${ENV_FILE}.bak"
        echo "已备份环境变量文件为 ${ENV_FILE}.bak"
    fi

    # 使用 `>` 覆盖写入而非 `>>` 追加
    {
        echo "USER_ID=$USER_ID"
        echo "GROUP_ID=$GROUP_ID"
        echo "USER_GROUPS=$USER_GROUPS"
        echo "DOCKER_ROOT_PATH=$DOCKER_ROOT_PATH"
        echo "VIDEO_ROOT_PATH=$VIDEO_ROOT_PATH"
        echo "HOST_IP=$HOST_IP"
        echo "DOCKER_REGISTRY=$DOCKER_REGISTRY"
        echo "GATEWAY=$GATEWAY"
        echo "RANDOM_VARIABLE=$RANDOM_VARIABLE"
        echo "RANDOM_NUMBER=$RANDOM_NUMBER"
        echo "PUBLIC_IP_CITY=$PUBLIC_IP_CITY" # 新增输出公网IP所在城市变量
        echo "LONGITUDE=$LONGITUDE" # 新增输出经度变量
        echo "LATITUDE=$LATITUDE" # 新增输出纬度变量
        echo "WEB_ACCESS_PORT=$WEB_ACCESS_PORT"
        echo "NAS_BRAND=$NAS_BRAND"
        echo "IYUU_TOEKN=$IYUU_TOEKN"
    } > "$ENV_FILE"
}

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
            # 检查路径是否有效
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

# 获取 eth0 网卡的 IPv4 地址，过滤掉回环地址、Docker 地址和私有网段 172.x.x.x
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | grep -v 'docker' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
fi

if [ -z "$HOST_IP" ]; then
    while [ -z "$HOST_IP" ]; do
        read -p "请输入主机 IP 地址 [默认：$HOST_IP]：" input_ip
        HOST_IP="${input_ip:-$HOST_IP}"  # 如果用户输入为空，则使用默认值
        if [ -z "$HOST_IP" ]; then
            echo -e "${RED}主机 IP 地址不能为空，请重新输入。${RESET}"
        fi
    done
else
    echo -e "${GREEN}当前主机 IP 地址为: $HOST_IP${RESET}"
    read -p "是否使用该 IP 地址？(y/n): " use_default
    if [ "$use_default" != "y" ]; then
        get_input "HOST_IP" "请输入主机 IP 地址" "$HOST_IP"
    fi
fi



#!/bin/bash

# 让用户输入用户名
read -p "请输入用户名: " USER_NAME
# 让用户输入IYUU KEY
read -p "请输入IYUU TOKEN: " IYUU_TOEKN

# 获取当前用户的信息
USER_ID=$(id -u "$USER_NAME")
GROUP_ID=$(id -g "$USER_NAME")
USER_GROUPS=$(id -G "$USER_NAME" | tr ' ' ',')

# 检查用户是否存在
if [ $? -eq 0 ]; then
    # 格式化并输出
    echo "uid=$USER_ID($USER_NAME) gid=$GROUP_ID(groups) groups=$USER_GROUPS"
else
    echo "错误：用户 '$USER_NAME' 不存在！"
fi

export USER_ID
export GROUP_ID
export USER_GROUPS
export DOCKER_ROOT_PATH
export VIDEO_ROOT_PATH
export HOST_IP
export DOCKER_REGISTRY
export GATEWAY
export RANDOM_VARIABLE
export RANDOM_NUMBER
export PUBLIC_IP_CITY # 新增导出公网IP所在城市变量
export LONGITUDE # 新增导出经度变量
export LATITUDE # 新增导出纬度变量
export WEB_ACCESS_PORT
export NAS_BRAND
export IYUU_TOEKN

# 保存环境变量到文件
save_env_vars

echo -e "${GREEN}最终的主机 IP 地址是: $HOST_IP${RESET}"
if [ -z "$DOCKER_REGISTRY" ]; then
    echo -e "${GREEN}有梯子所以不选择镜像加速${RESET}"
else
    echo -e "${GREEN}Docker 镜像源: $DOCKER_REGISTRY${RESET}"
fi
echo -e "${GREEN}Docker 根路径: $DOCKER_ROOT_PATH${RESET}"
echo -e "${GREEN}Midea 根路径: $VIDEO_ROOT_PATH${RESET}"
echo -e "${GREEN}用户信息：PUID=$USER_ID($USER_NAME) PGID=$GROUP_ID UMASK=022"
echo -e "${GREEN}Docker根路径: $DOCKER_ROOT_PATH${RESET}"
echo -e "${GREEN}Midea根路径: $VIDEO_ROOT_PATH${RESET}"
echo -e "${GREEN}用户信息：PUID=$USER_ID($USER_NAME) PGID=$GROUP_ID UMASK=022"
echo -e "${GREEN}网关地址: $GATEWAY${RESET}"
echo -e "${GREEN}随机变量: $RANDOM_VARIABLE${RESET}"
echo -e "${GREEN}随机数字: $RANDOM_NUMBER${RESET}"
echo -e "${GREEN}公网IP所在城市: $PUBLIC_IP_CITY${RESET}" # 新增输出公网IP所在城市
echo -e "${GREEN}该城市经度: $LONGITUDE${RESET}" # 新增输出经度
echo -e "${GREEN}该城市纬度: $LATITUDE${RESET}" # 新增输出纬度
echo -e "${GREEN}网页访问端口号: $WEB_ACCESS_PORT${RESET}"
echo -e "${GREEN}品牌名: $NAS_BRAND${RESET}"
echo -e "${GREEN}IYUU: $IYUU_TOEKN${RESET}"


check_container_status() {
    local container_name=$1
    local status=$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null)
    case "$status" in
        running) echo -e "${GREEN}[✔] $container_name 已启动${RESET}" ;;
        exited) echo -e "${RED}[✘] $container_name 已停止${RESET}" ;;
        *) echo -e "${RED}[✘] $container_name 未安装${RESET}" ;;
    esac
}


# 定义一个函数来获取服务的安装状态，并根据状态显示颜色
get_service_status() {
    local container_name=$1
    if docker ps -a --format "{{.Names}}" | grep -q "$container_name"; then
        echo -e "${GREEN}[✔] $container_name 已安装${RESET}"
    else
        echo -e "${RED}[✘] $container_name 未安装${RESET}"
    fi
}

echo -e "${GREEN}创建安装环境中...${RESET}"
echo "正在创建所需文件夹..."
# 创建 Docker 根路径下的文件夹
# 定义大类
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

# 单服务安装函数
install_service() {
    local service_id=$1
    case "$service_id" in
    

        1) init_csf ; check_container_status "csf" ;;
        2) init_qbittorrent ; check_container_status "qb" ;;
        3) init_emby ; check_container_status "emby" ;;
        4) init_moviepilot ; check_container_status "moviepilot-v2" ;;
        5) init_moviepilot-clash ; check_container_status "moviepilot-v2" ;;
        6) init_cookiecloud ; check_container_status "cookiecloud" ;;
        7) init_frpc ; check_container_status "frpc" ;;
        8) init_transmission ; check_container_status "transmission" ;;
        9) init_owjdxb ; check_container_status "wx" ;;
        10) init_audiobookshelf ; check_container_status "audiobookshelf" ;;
        11) init_komga ; check_container_status "komga" ;;
        12) init_navidrome ; check_container_status "navidrome" ;;
        13) init_dockerCopilot ; check_container_status "dockerCopilot" ;;
        14) init_memos ; check_container_status "memos" ;;
        15) init_homepage ; check_container_status "homepage" ;;
        16) init_vertex ; check_container_status "vertex" ;;
        17) init_freshrss ; check_container_status "freshrss" ;;
        18) init_rsshub ; check_container_status "rsshub" ;;
        19) init_metube ; check_container_status "metube" ;;
        20) init_filecodebox ; check_container_status "filecodebox" ;;
        21) init_myip ; check_container_status "myip" ;;
        22) init_photopea ; check_container_status "photopea" ;;
        23) init_easyimage ; check_container_status "easyimage" ;;
        24) init_clash ; check_container_status "clash" ;;
		25) init_clashok ; check_container_status "clash" ;;
		26) init_easynode ; check_container_status "easynode" ;;
        27) init_database  ;;
		28) output_address_password  ;;
        29) view_moviepilot_logs ;;
        *)
            echo -e "${RED}无效选项：$service_id${RESET}"
        ;;
    esac
}
# 初始化各个服务
init_clashok() {
    echo "初始化 Clash"
    mkdir -p "$DOCKER_ROOT_PATH/clash"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/clash.tgz -o "$CURRENT_DIR/clash.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/clash.tgz" -C "$DOCKER_ROOT_PATH/clash/"
    docker run -d --name clash --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/clash:/root/.config/clash" \
		--network bridge --privileged \
        -p 38080:8080 \
        -p 7890:7890 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash:1.0"
}

init_clash() {
    echo "初始化 Clash"
    mkdir -p "$DOCKER_ROOT_PATH/clash"
    docker run -d --name clash --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/clash:/root/.config/clash" \
		--network bridge --privileged \
        -p 38080:8080 \
        -p 7890:7890 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash:1.0"
}

init_qbittorrent() {
    echo "初始化 qBittorrent"
    mkdir -p "$DOCKER_ROOT_PATH/qb"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/qb.tgz -o "$CURRENT_DIR/qb.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/qb.tgz" -C "$DOCKER_ROOT_PATH/qb/"
    docker run -d --name qb --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/qb:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID=0 -e PGID=0 -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=8080 \
        -e TORRENTING_PORT=6355 \
        -e SavePatch="/media/downloads" -e TempPatch="/media/downloads" \
        --network bridge --privileged \
        -p 58080:8080 \
        -p 6355:6355 \
        -p 6355:6355/udp \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
}

init_transmission() {
    echo "初始化 transmission"
    mkdir -p "$DOCKER_ROOT_PATH/transmission"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/transmission.tgz -o "$CURRENT_DIR/transmission.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/transmission.tgz" -C "$DOCKER_ROOT_PATH/transmission/"
    docker run -d --name transmission --restart unless-stopped \
        -e PUID=0 -e PGID=0 -e TZ=Asia/Shanghai \
        -e TRANSMISSION_WEB_HOME=/webui \
        -v $DOCKER_ROOT_PATH/transmission:/config \
        -v $DOCKER_ROOT_PATH/transmission/WATCH:/watch \
        -v $DOCKER_ROOT_PATH/transmission/src:/webui \
        -v $VIDEO_ROOT_PATH:/media \
        --network bridge --privileged \
        -p 59091:9091 \
        -p 51788:51788 \
        -p 51788:51788/udp \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}transmission:4.0.5"
}

init_moviepilot() {
    echo "初始化 MoviePilot"
    mkdir -p "$DOCKER_ROOT_PATH/moviepilot-v2/"{main,config,core}
    mkdir -p "$DOCKER_ROOT_PATH/qb/qBittorrent/BT_backup"
    mkdir -p "$DOCKER_ROOT_PATH/transmission/torrents"
    mkdir -p "$VIDEO_ROOT_PATH/downloads" "$VIDEO_ROOT_PATH/links" "$VIDEO_ROOT_PATH/sl"
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

    cat <<EOF > "$DOCKER_ROOT_PATH/moviepilot-v2/config/app.env"
GITHUB_PROXY='https://ghgo.xyz/'
COOKIECLOUD_HOST='http://$HOST_IP:58088'
COOKIECLOUD_KEY='666666'
COOKIECLOUD_PASSWORD='666666'
QB_HOST='http://192.168.66.26:58080'
QB_USER='666666'
QB_PASSWORD='666666'
TR_HOST='http://$HOST_IP:59091'
MEDIASERVER='emby'
EMBY_HOST='http://$HOST_IP:58096'
EMBY_API_KEY='e2f69e117d0b40c89802ef0bcaee8676'	
EOF
	
	
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

# 检查文件是否已成功创建并写入
if [ -f "$DOCKER_ROOT_PATH/moviepilot-v2/config/category.yaml" ]; then
    echo "category.yaml 文件已成功创建并写入内容："
    cat "$DOCKER_ROOT_PATH/moviepilot-v2/config/category.yaml"  # 显示文件内容确认
else
    echo "创建 category.yaml 文件失败！"
fi
    echo "初始化 moviepilot-v2"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/moviepilot-v2.tgz -o "$CURRENT_DIR/moviepilot-v2.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/moviepilot-v2.tgz" -C "$DOCKER_ROOT_PATH/moviepilot-v2/"

    docker run -d \
      --name moviepilot-v2 \
      --restart always \
      --privileged \
      --network bridge \
      -v $VIDEO_ROOT_PATH:/media \
      -v $DOCKER_ROOT_PATH/moviepilot-v2/config:/config \
      -v $DOCKER_ROOT_PATH/moviepilot-v2/core:/moviepilot/.cache/ms-playwright \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $DOCKER_ROOT_PATH/transmission/torrents/:/tr \
      -v $DOCKER_ROOT_PATH/qb/qBittorrent/BT_backup/:/qb \
      -e MOVIEPILOT_AUTO_UPDATE=false \
      -e NGINX_PORT=3000 \
      -e PORT=3001 \
      -e PUID="$PUID" \
      -e PGID="$PGID" \
      -e UMASK="$UMASK"  \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN=$IYUU_TOEKN \
      -e SUPERUSER="admin" \
      -e API_TOKEN="moling1992moling1992" \
      -p 53000:3000 \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:2.1.5"

      echo "容器启动完成，开始检测是否生成了 user.db 文件..."
      SECONDS=0
while true; do
    # 等待容器启动完成并生成文件
    sleep 1  # 每 5 秒检查一次
    # 检查容器内是否存在 user.db 文件
    USER_DB_FILE="/config/user.db"
    FILE_EXISTS=$(docker exec moviepilot-v2 test -f "$USER_DB_FILE" && echo "exists" || echo "not exists")
  # 检查日志文件中是否存在 "所有插件初始化完成"
    LOG_FILES=$(docker exec moviepilot-v2 ls /docker/moviepilot-v2/config/logs/*.log 2>/dev/null)
    LOG_MSG_FOUND=$(docker exec moviepilot-v2 grep -l "所有插件初始化完成" $LOG_FILES 2>/dev/null)
    if [ "$FILE_EXISTS" == "exists" ]; then
        echo "user.db 文件已成功生成在 /config 文件夹下。"
        break  # 跳出循环，继续后续操作
    else
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化moviepilot-v2... $SECONDS 秒 \r"

    fi
done
}

init_moviepilot-clash() {
    echo "初始化 MoviePilot"
    mkdir -p "$DOCKER_ROOT_PATH/moviepilot-v2/"{main,config,core}
    mkdir -p "$VIDEO_ROOT_PATH/downloads" "$VIDEO_ROOT_PATH/links" "$VIDEO_ROOT_PATH/sl"
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

    echo "GITHUB_PROXY='https://ghgo.xyz/'" > "$DOCKER_ROOT_PATH/moviepilot-v2/config/"app.env
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
	
    # 下载并解压文件
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/core.tgz -o "$CURRENT_DIR/core.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/core.tgz" -C "$DOCKER_ROOT_PATH/moviepilot-v2/core/"
    docker run -d \
      --name moviepilot-v2 \
      --restart always \
      --privileged \
      --network bridge \
      -v $VIDEO_ROOT_PATH:/media \
      -v $DOCKER_ROOT_PATH/moviepilot-v2/config:/config \
      -v $DOCKER_ROOT_PATH/moviepilot-v2/core:/moviepilot/.cache/ms-playwright \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $DOCKER_ROOT_PATH/transmission/torrents/:/tr \
      -v $DOCKER_ROOT_PATH/qb/qBittorrent/BT_backup/:/qb \
      -e MOVIEPILOT_AUTO_UPDATE=release \
      -e NGINX_PORT=3000 \
      -e PORT=3001 \
      -e PUID="$PUID" \
      -e PGID="$PGID" \
      -e UMASK="$UMASK"  \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN=$IYUU_TOEKN \
      -e SUPERUSER="admin" \
      -e API_TOKEN="moling1992moling1992" \
      -e PROXY_HOST="http://$HOST_IP:7890" \
      -p 53000:3000 \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:2.1.5"

      echo "容器启动完成，开始检测是否生成了 user.db 文件..."
      SECONDS=0
while true; do
    # 等待容器启动完成并生成文件
    sleep 1  # 每 5 秒检查一次
    # 检查容器内是否存在 user.db 文件
    USER_DB_FILE="/config/user.db"
    FILE_EXISTS=$(docker exec moviepilot-v2 test -f "$USER_DB_FILE" && echo "exists" || echo "not exists")
  # 检查日志文件中是否存在 "所有插件初始化完成"
    LOG_FILES=$(docker exec moviepilot-v2 ls /docker/moviepilot-v2/config/logs/*.log 2>/dev/null)
    LOG_MSG_FOUND=$(docker exec moviepilot-v2 grep -l "所有插件初始化完成" $LOG_FILES 2>/dev/null)
    if [ "$FILE_EXISTS" == "exists" ]; then
        echo "user.db 文件已成功生成在 /config 文件夹下。"
        break  # 跳出循环，继续后续操作
    else
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化moviepilot-v2... $SECONDS 秒 \r"

    fi
done
}

init_emby() {
    echo "初始化 Emby"
    mkdir -p "$DOCKER_ROOT_PATH/emby"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/emby.tgz -o "$CURRENT_DIR/emby.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/emby.tgz" -C "$DOCKER_ROOT_PATH/emby/"
    docker run -d --name emby --restart unless-stopped \
        -v $DOCKER_ROOT_PATH/emby:/config \
        -v $VIDEO_ROOT_PATH:/media \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        --device /dev/dri:/dev/dri \
        --network bridge --privileged \
        -p 58096:8096 \
        -p 58920:8920 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}embyserver:kxb"
}

init_csf() {
    echo "初始化 csf"
    mkdir -p "$DOCKER_ROOT_PATH/csf"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/csf.tgz -o "$CURRENT_DIR/csf.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/csf.tgz" -C "$DOCKER_ROOT_PATH/csf/"
    sed -i "s/192.168.66.220/$HOST_IP/g" "$DOCKER_ROOT_PATH/csf/config/ChineseSubFinderSettings.json"
    docker run -d --name csf --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/csf:/config" \
        -v "$VIDEO_ROOT_PATH:/media" \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --network bridge --privileged \
        -p 59035:19035 \
        -p 59037:19037 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:1.0"
}

init_frpc() {
    echo "初始化 frpc"
    mkdir -p "$DOCKER_ROOT_PATH/frpc"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/frpc.tgz -o "$CURRENT_DIR/frpc.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/frpc.tgz" -C "$DOCKER_ROOT_PATH/frpc/"
    sed -i "s/192.168.66.26/$HOST_IP/g" "$DOCKER_ROOT_PATH/frpc/frpc.toml"
    sed -i "s/10114/$RANDOM_NUMBER/g" "$DOCKER_ROOT_PATH/frpc/frpc.toml"
    sed -i "s/9999/$RANDOM_VARIABLE/g" "$DOCKER_ROOT_PATH/frpc/frpc.toml"
    docker run -d --name frpc --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/frpc/frpc.toml:/etc/frp/frpc.toml" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frc:1.0"
}

init_audiobookshelf() {
    echo "初始化 audiobookshelf"
    mkdir -p "$DOCKER_ROOT_PATH/audiobookshelf"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/audiobookshelf.tgz -o "$CURRENT_DIR/audiobookshelf.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/audiobookshelf.tgz" -C "$DOCKER_ROOT_PATH/audiobookshelf/"
    docker run -d --name audiobookshelf --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 57758:80 \
        -v $VIDEO_ROOT_PATH:/media \
        -v $DOCKER_ROOT_PATH/audiobookshelf/config:/config \
        -v $DOCKER_ROOT_PATH/audiobookshelf/metadata:/metadata \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}audiobookshelf:1.0"
}

init_komga() {
    echo "初始化 komga"
    mkdir -p "$DOCKER_ROOT_PATH/komga"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/komga.tgz -o "$CURRENT_DIR/komga.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/komga.tgz" -C "$DOCKER_ROOT_PATH/komga/"
    docker run -d --name komga --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55600:25600 \
        -v $VIDEO_ROOT_PATH:/media \
        -v $DOCKER_ROOT_PATH/komga/config:/config \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}komga:1.0"
}

init_navidrome() {
    echo "初始化 navidrome"
    mkdir -p "$DOCKER_ROOT_PATH/navidrome"
    mkdir -p "$VIDEO_ROOT_PATH/music"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/navidrome.tgz -o "$CURRENT_DIR/navidrome.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/navidrome.tgz" -C "$DOCKER_ROOT_PATH/navidrome/"
    docker run -d --name navidrome --restart unless-stopped \
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
        -v $DOCKER_ROOT_PATH/navidrome/data:/data \
        -v $VIDEO_ROOT_PATH/music:/music \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navidrome:1.0"
}

init_vertex() {
    echo "初始化 vertex"
    mkdir -p "$DOCKER_ROOT_PATH/vertex"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/vertex.tgz -o "$CURRENT_DIR/vertex.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/vertex.tgz" -C "$DOCKER_ROOT_PATH/vertex/"
    docker run -d --name vertex --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53800:3000 \
        -p 53443:3443 \
        -v $DOCKER_ROOT_PATH/vertex:/vertex \
        -v $VIDEO_ROOT_PATH:/media \
        -e TZ=Asia/Shanghai \
        -e HTTPS_ENABLE=true \
        -e HTTPS_PORT=3443 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}vertex:1.0"
}

init_freshrss() {
    echo "初始化 freshrss"
    mkdir -p "$DOCKER_ROOT_PATH/freshrss"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/freshrss.tgz -o "$CURRENT_DIR/freshrss.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/freshrss.tgz" -C "$DOCKER_ROOT_PATH/freshrss/"
    docker run -d --name freshrss --restart unless-stopped \
        --network bridge --privileged \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/freshrss/config:/config \
        -p 58350:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}freshrss:1.0"
}

init_easyimage() {
    echo "初始化 easyimage"
    mkdir -p "$DOCKER_ROOT_PATH/easyimage"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/easyimage.tgz -o "$CURRENT_DIR/easyimage.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/easyimage.tgz" -C "$DOCKER_ROOT_PATH/easyimage/"
    docker run -d --name easyimage --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58631:80 \
        -e DEBUG=false \
        -v $DOCKER_ROOT_PATH/easyimage/config:/app/web/config \
        -v $DOCKER_ROOT_PATH/easyimage/i:/app/web/i \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyimage:1.0"
}

init_homepage() {
    echo "初始化 homepage"
    mkdir -p "$DOCKER_ROOT_PATH/homepage"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/homepage.tgz -o "$CURRENT_DIR/homepage.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/homepage.tgz" -C "$DOCKER_ROOT_PATH/homepage/"
    sed -i "s/192.168.66.220/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage/config/services.yaml"
    sed -i "s/192.168.66.1/$GATEWAY/g" "$DOCKER_ROOT_PATH/homepage/config/services.yaml"
    sed -i "s/8000/$WEB_ACCESS_PORT/g" "$DOCKER_ROOT_PATH/homepage/config/services.yaml"
    sed -i "s/NAS服务器/$NAS_BRAND/g" "$DOCKER_ROOT_PATH/homepage/config/services.yaml"
    sed -i "s/192.168.66.26/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage/config/widgets.yaml"	
    sed -i "s/丹东/$PUBLIC_IP_CITY/g" "$DOCKER_ROOT_PATH/homepage/config/widgets.yaml"
    sed -i "s/40.1292/$LATITUDE/g" "$DOCKER_ROOT_PATH/homepage/config/widgets.yaml"  
    sed -i "s/124.3947/$LONGITUDE/g" "$DOCKER_ROOT_PATH/homepage/config/widgets.yaml"  
    docker run -d --name homepage --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53010:3000 \
        -v $DOCKER_ROOT_PATH/homepage/config:/app/config \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}gethomepage:1.0"
}

init_dockerCopilot() {
    echo "初始化 dockerCopilot"
    mkdir -p "$DOCKER_ROOT_PATH/dockerCopilot"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/dockerCopilot.tgz -o "$CURRENT_DIR/dockerCopilot.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/dockerCopilot.tgz" -C "$DOCKER_ROOT_PATH/dockerCopilot/"
    docker run -d --name dockerCopilot --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 52712:12712 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $DOCKER_ROOT_PATH/dockerCopilot/data:/data \
        -e secretKey=666666mmm \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        -e hubURL=$DOCKER_REGISTRY \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockercopilot:1.0"
}

init_memos() {
    echo "初始化 memos"
    mkdir -p "$DOCKER_ROOT_PATH/memos"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/memos.tgz -o "$CURRENT_DIR/memos.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/memos.tgz" -C "$DOCKER_ROOT_PATH/memos/"
    docker run -d --name memos --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55230:5230 \
        -v $DOCKER_ROOT_PATH/memos/:/var/opt/memos \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}memos:1.0"
}

init_owjdxb() {
    echo "初始化 Owjdxb"
    mkdir -p "$DOCKER_ROOT_PATH/store"
    docker run -d --name wx --restart unless-stopped \
        -v "$DOCKER_ROOT_PATH/store:/data/store" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}wxchat:1.0"
}

init_cookiecloud() {
    echo "初始化 cookiecloud"
    mkdir -p "$DOCKER_ROOT_PATH/cookiecloud"
    docker run -d --name cookiecloud --restart unless-stopped \
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/cookiecloud:/data/api/data" \
        -p 58088:8088 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cookiecloud:1.0"
}

init_metube() {
    echo "初始化 metube"
    mkdir -p "$DOCKER_ROOT_PATH/metube"
    mkdir -p "$VIDEO_ROOT_PATH/metube"
    docker run -d --name metube --restart unless-stopped \
        --network bridge --privileged \
        -p 58081:8081 \
        -v $VIDEO_ROOT_PATH/metube:/downloads \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metube:1.0"
}

init_filecodebox() {
    echo "初始化 filecodebox "
    mkdir -p "$DOCKER_ROOT_PATH/FileCodeBox"
    docker run -d --name filecodebox --restart unless-stopped \
        --network bridge --privileged \
        -p 52346:12345 \
        -v $DOCKER_ROOT_PATH/FileCodeBox/:/app/data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}filecodebox:1.0"
}

init_myip() {#todo
    echo "初始化 myip "
    mkdir -p "$DOCKER_ROOT_PATH/myip"
    docker run -d --name myip --restart unless-stopped \
        --network bridge --privileged \
        -p 58966:18966 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myip:1.0"
}

init_photopea () {#todo
    echo "初始化 photopea "
    mkdir -p "$DOCKER_ROOT_PATH/photopea "
    docker run -d --name photopea  --restart unless-stopped \
        --network bridge --privileged \
        -p 59997:8887 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}photopea:1.0"
}

init_rsshub () {
    echo "初始化 rsshub "
    mkdir -p "$DOCKER_ROOT_PATH/rsshub "
    docker run -d --name rsshub  --restart unless-stopped \
        --network bridge --privileged \
        -p 51200:1200 \
        -e CACHE_EXPIRE=3600 \
        -e GITHUB_ACCESS_TOKEN=example \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:1.0"
}

init_easynode() {#todo
    echo "初始化 easynode"
    mkdir -p "$DOCKER_ROOT_PATH/easynode"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/easynode.tgz -o "$CURRENT_DIR/easynode.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/easynode.tgz" -C "$DOCKER_ROOT_PATH/easynode/"
    docker run -d --name easynode --restart unless-stopped \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58082:8082 \
        -v $DOCKER_ROOT_PATH/easynode/db:/easynode/app/db\
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easynode:1.0"
}


# 新增函数：输出全部地址密码到文件
output_address_password() {
    FILE_PATH="$DOCKER_ROOT_PATH/address_password.txt"
    echo "正在生成地址密码文件到 $FILE_PATH"
    {
        # 获取当前日期时间
        current_datetime=$(date '+%Y-%m-%d %H:%M:%S')
        echo "生成日期时间：$current_datetime"
        echo "主机 IP 地址: $HOST_IP"
        echo "网关地址: $GATEWAY"
        echo "网页访问端口号: $WEB_ACCESS_PORT"
        echo "品牌名: $NAS_BRAND"
        echo ""

        # 添加服务的地址、账号和端口信息
        csf_status=$(get_service_status "csf")
        if [ "$csf_status" == "${GREEN}[✔] csf 已安装${RESET}" ]; then
            echo "CSF："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:59035"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        frpc_status=$(get_service_status "frpc")
        if [ "$frpc_status" == "${GREEN}[✔] frpc 已安装${RESET}" ]; then
            echo "FRPC："
            echo "    已安装成功。"
            echo "    此应用无地址。"
            echo "    此应用无账号密码。"
            echo ""
        fi

        audiobookshelf_status=$(get_service_status "audiobookshelf")
        if [ "$audiobookshelf_status" == "${GREEN}[✔] audiobookshelf 已安装${RESET}" ]; then
            echo "Audiobookshelf："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:57758"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        komga_status=$(get_service_status "komga")
        if [ "$komga_status" == "${GREEN}[✔] komga 已安装${RESET}" ]; then
            echo "Komga："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:55600"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        navidrome_status=$(get_service_status "navidrome")
        if [ "$navidrome_status" == "${GREEN}[✔] navidrome 已安装${RESET}" ]; then
            echo "Navidrome："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:54533"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        vertex_status=$(get_service_status "vertex")
        if [ "$vertex_status" == "${GREEN}[✔] vertex 已安装${RESET}" ]; then
            echo "Vertex："
            echo "    已安装成功。"
            echo "    地址: https://$HOST_IP:53443"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        freshrss_status=$(get_service_status "freshrss")
        if [ "$freshrss_status" == "${GREEN}[✔] freshrss 已安装${RESET}" ]; then
            echo "Freshrss："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:58350"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        easyimage_status=$(get_service_status "easyimage")
        if [ "$easyimage_status" == "${GREEN}[✔] easyimage 已安装${RESET}" ]; then
            echo "EasyImage："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:58631"
            echo "    此应用无账号密码。"
            echo ""
        fi

        homepage_status=$(get_service_status "homepage")
        if [ "$homepage_status" == "${GREEN}[✔] homepage 已安装${RESET}" ]; then
            echo "Homepage："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:53010"
            echo "    此应用无账号密码。"
            echo ""
        fi

        dockerCopilot_status=$(get_service_status "dockerCopilot")
        if [ "$dockerCopilot_status" == "${GREEN}[✔] dockerCopilot 已安装${RESET}" ]; then
            echo "DockerCopilot："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:52712"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: 666666mmm"
            echo ""
        fi

        memos_status=$(get_service_status "memos")
        if [ "$memos_status" == "${GREEN}[✔] memos 已安装${RESET}" ]; then
            echo "Memos："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:55230"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        owjdxb_status=$(get_service_status "owjdxb")
        if [ "$owjdxb_status" == "${GREEN}[✔] owjdxb 已安装${RESET}" ]; then
            echo "Owjdxb："
            echo "    已安装成功。"
            echo "    此应用无地址。"
            echo "    此应用无账号密码。"
            echo ""
        fi

        cookiecloud_status=$(get_service_status "cookiecloud")
        if [ "$cookiecloud_status" == "${GREEN}[✔] cookiecloud 已安装${RESET}" ]; then
            echo "Cookiecloud："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:58088"
            echo "    账号: [你需要填写的账号]"
            echo "    密码: [你需要填写的密码]"
            echo ""
        fi

        metube_status=$(get_service_status "metube")
        if [ "$metube_status" == "${GREEN}[✔] metube 已安装${RESET}" ]; then
            echo "Metube："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:58081"
            echo "    此应用无账号密码。"
            echo ""
        fi

        filecodebox_status=$(get_service_status "filecodebox")
        if [ "$filecodebox_status" == "${GREEN}[✔] filecodebox 已安装${RESET}" ]; then
            echo "Filecodebox："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:52346"
            echo "    此应用无账号密码。"
            echo ""
        fi

        myip_status=$(get_service_status "myip")
        if [ "$myip_status" == "${GREEN}[✔] myip 已安装${RESET}" ]; then
            echo "MyIP："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:58966"
            echo "    此应用无账号密码。"
            echo ""
        fi

        photopea_status=$(get_service_status "photopea")
        if [ "$photopea_status" == "${GREEN}[✔] photopea 已安装${RESET}" ]; then
            echo "Photopea："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:59997"
            echo "    此应用无账号密码。"
            echo ""
        fi

        rsshub_status=$(get_service_status "rsshub")
        if [ "$rsshub_status" == "${GREEN}[✔] rsshub 已安装${RESET}" ]; then
            echo "Rsshub："
            echo "    已安装成功。"
            echo "    地址: http://$HOST_IP:51200"
            echo "    此应用无账号密码。"
            echo ""
        fi
    } > "$FILE_PATH"
    echo "地址密码文件生成完成"
}

init_database() {

    echo 'UPDATE user SET hashed_password = "$2b$12$9Lcemwg/PNtVaegry6wY.eZL41dENcX3f9Bt.NdhxMtzAsrhv1Cey" WHERE id = 1;' > "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "INSERT INTO systemconfig (id, key, value) VALUES (5, 'Downloaders', '[{\"name\": \"\\u4e0b\\u8f7d\", \"type\": \"qbittorrent\", \"default\": true, \"enabled\": true, \"config\": {\"host\": \"http://119.3.173.6:58080\", \"username\": \"666666\", \"password\": \"666666\", \"category\": true, \"sequentail\": true}}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "INSERT INTO systemconfig (id, key, value) VALUES (6, 'Directories', '[{\"name\": \"\\u5f71\\u89c6\\u8d44\\u6e90\", \"storage\": \"local\", \"download_path\": \"/media/downloads/\", \"priority\": 0, \"monitor_type\": \"monitor\", \"media_type\": \"\", \"media_category\": \"\", \"download_type_folder\": false, \"monitor_mode\": \"fast\", \"library_path\": \"/media/links/\", \"download_category_folder\": true, \"library_storage\": \"local\", \"transfer_type\": \"link\", \"overwrite_mode\": \"latest\", \"library_category_folder\": true, \"scraping\": true, \"renaming\": true}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    echo "INSERT INTO systemconfig (id, key, value) VALUES (7, 'MediaServers', '[{\"name\": \"emby\", \"type\": \"emby\", \"enabled\": true, \"config\": {\"apikey\": \"e2f69e117d0b40c89802ef0bcaee8676\", \"host\": \"http://119.3.173.6:58096\"}, \"sync_libraries\": [\"all\"]}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    #echo "INSERT INTO systemconfig (id, key, value) VALUES (8, 'plugin.ChineseSubFinder', '[{\"enabled\": true, \"host\": \"http://119.3.173.6:59035\", \"api_key\": \"\", \"local_path\": \"\", \"remote_path\": \"\", \"undefined\": true}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    #echo "INSERT INTO systemconfig (id, key, value) VALUES (9, 'plugin.CustomHosts', '[{\"hosts\": \"$GITHUB_HOSTS_CONTENT\"}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    #echo "INSERT INTO systemconfig (id, key, value) VALUES (10, 'plugin.MediaServerRefresh', '[{\"enabled\": true, \"delay\": "10", \"undefined\": true, \"mediaservers\": ["emby"]}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
    #echo "INSERT INTO systemconfig (id, key, value) VALUES (11, 'plugin.HomePage', '[{\"enabled\": true, \"undefined\": true}]');" >> "$DOCKER_ROOT_PATH/moviepilot-v2/config/script.sql"
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

# 输出操作完成信息
    echo "SQL 脚本已执行完毕"
    echo "数据库初始化完成！"

      # 重启容器
    docker restart moviepilot-v2

    # 获取容器日志，显示最后 30 秒
 #   echo "获取容器日志..."
  #  docker logs --tail 30 --follow moviepilot-v2

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

view_moviepilot_logs() {
    echo "查看 moviepilot-v2 容器日志..."
    docker logs -f moviepilot-v2
}

# 循环安装服务
while true; do
    # 获取各服务的安装状态
    csf_status=$(get_service_status "csf")
    qbittorrent_status=$(get_service_status "qb")
    emby_status=$(get_service_status "emby")
    moviepilot_status=$(get_service_status "moviepilot-v2")
    cookiecloud_status=$(get_service_status "cookiecloud")
    frpc_status=$(get_service_status "frpc")
    transmission_status=$(get_service_status "transmission")
    owjdxb_status=$(get_service_status "wx")
    audiobookshelf_status=$(get_service_status "audiobookshelf")
    komga_status=$(get_service_status "komga")
    navidrome_status=$(get_service_status "navidrome")
    dockerCopilot_status=$(get_service_status "dockerCopilot")
    memos_status=$(get_service_status "memos")
    homepage_status=$(get_service_status "homepage")
    vertex_status=$(get_service_status "vertex")
    freshrss_status=$(get_service_status "freshrss")
    rsshub_status=$(get_service_status "rsshub")
    metube_status=$(get_service_status "metube")
    filecodebox_status=$(get_service_status "filecodebox")
    myip_status=$(get_service_status "myip")
    photopea_status=$(get_service_status "photopea")
    easyimage_status=$(get_service_status "easyimage")
    clash_status=$(get_service_status "clash")	
    easynode_status=$(get_service_status "easynode")	
    database_status=$(get_service_status "moviepilot-v2")  # 根据需要选择具体容器

    echo "请选择要安装的服务（输入数字）："
    echo "1. csf $csf_status"
    echo "2. qbittorrent $qbittorrent_status"
    echo "3. Emby $emby_status"
	echo "4. moviepilot-v2 $moviepilot_status"
	echo "5. moviepilot-v2-clash $moviepilot_status"
    echo "6. cookiecloud $cookiecloud_status"
    echo "7. frpc $frpc_status"
    echo "8. transmission $transmission_status"
    echo "9. owjdxb $owjdxb_status"
    echo "10. audiobookshelf $audiobookshelf_status"
    echo "11. komga $komga_status"
    echo "12. navidrome $navidrome_status"
    echo "13. dockerCopilot $dockerCopilot_status"
    echo "14. memos $memos_status"
    echo "15. homepage $homepage_status"
    echo "16. vertex $vertex_status"
    echo "17. freshrss $freshrss_status"
    echo "18. rsshub $rsshub_status"
    echo "19. metube $metube_status"
    echo "20. filecodebox $filecodebox_status"
    echo "21. myip $myip_status"
    echo "22. photopea $photopea_status"
    echo "23. easyimage $easyimage_status"	
    echo "24. clash $clash_status"
    echo "25. clashok $clash_status"
    echo "26. easynode $easynode_status"
    echo "27. 初始化数据库 "
    echo "28. 输出全部地址账号密码"
    echo "29. 查看 MoviePilot 日志"
    echo "0. 退出"
    read -p "请输入选择的服务数字： " service_choice

    if [[ "$service_choice" == "0" ]]; then
        # 删除 moling 目录
        rm -rf "$CURRENT_DIR"
        # 确保清理工作完成后立即退出脚本
        echo "安装流程结束！"
        history -c
        exit 0
    fi
    install_service "$service_choice"
	
done
