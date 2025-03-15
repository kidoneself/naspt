#!/bin/bash

# 捕获 Ctrl+C 信号并处理
trap 'echo -e "\n检测到 Ctrl+C，使用选项 q 退出程序。" && continue' SIGINT

while true; do
      # 获取系统架构
    ARCH=$(uname -m)
    # 根据架构类型判断
    case "$ARCH" in
        x86_64)
            echo "Architecture: x86_64 (x86 64位)"
            ;;
        i686 | i386)
            echo "Architecture: x86 (x86 32位)"
            ;;
        aarch64)
            echo "Architecture: ARM64 (ARM 64位)"
            ;;
        armv7l | armv6l)
            echo "Architecture: ARM (ARM 32位)"
            ;;
        *)
            echo "Architecture: Unknown (未知：$ARCH)"
            ;;
    esac
    #!/bin/bash

    echo "+----------------------------------------------------------------------"
    echo "| NASPT FOR NAS"
    echo "+----------------------------------------------------------------------"
    echo "| 为了您的正常使用，请确保在安装前确认是否已经安装过，避免端口冲突，安装失败"
    echo "+----------------------------------------------------------------------"
    echo "================================"
    echo "请选择要安装的脚本："
    echo "1) 安装家庭影院"
    echo "2) 安装家庭影院(微信交互)"
    echo "3) 安装音乐服务"
    echo "4) 安装工具类"
    echo "5) 安装直播"
    echo "6) 安装115直连"
    echo "7) 安装代理软件"
    echo "8) 安装IPTV"
    echo "b) 返回上一层"
    echo "q) 退出"
    echo "================================"
    read -p "请输入你的选择：" choice

    case $choice in
        1)
            echo "正在安装 安装家庭影院"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-mp/mp-tr.sh)
            ;;
        2)
            echo "正在安装 安装家庭影院(微信交互)"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-mp/mp-tr.sh)
            ;;
        3)
            echo "正在安装 音乐服务"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-music/music.sh)
            ;;
        4)
            echo "正在安装 工具类"
            bash <(curl -Ls https://naspt.oss-cn-shanghai.aliyuncs.com/tool/tool.sh)
            ;;
        5)
            echo "正在安装 直播录制"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-live/live.sh)
            ;;
        6)
            echo "正在安装 cms"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-cms/cms.sh)
            ;;
        7)
            echo "正在安装 clash"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-cl/cl.sh)
            ;;
        8)
            echo "正在安装 IPTV"
            bash <(curl -Ls https://alist.naspt.vip/d/shell/naspt-iptv/iptv.sh)
            ;;
        b)
            echo "返回上一层。"
            ;;
        q)
            echo "退出程序。"

            exit 0

            ;;
        *)
            echo "无效选择，请重试。"
            ;;
    esac
done
            history -c
