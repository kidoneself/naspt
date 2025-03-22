#!/bin/bash

# 捕获 Ctrl+C 信号并处理
trap 'handle_sigint' SIGINT
# 全局变量声明
declare -A SCRIPT_URLS=(
    [1]="https://alist.naspt.vip/d/123pan/shell/naspt-mp/mp-t1.sh"
    [2]="https://alist.naspt.vip/d/123pan/shell/naspt-frp/frp.sh"
    [3]="https://alist.naspt.vip/d/123pan/shell/naspt-music/music.sh"
    [4]="https://naspt.oss-cn-shanghai.aliyuncs.com/tool/tool.sh"
    [5]="https://alist.naspt.vip/d/123pan/shell/naspt-live/live.sh"
    [6]="https://alist.naspt.vip/d/123pan/shell/naspt-cms/cms.sh"
    [7]="https://alist.naspt.vip/d/123pan/shell/naspt-cl/cl.sh"
    [8]="https://alist.naspt.vip/d/123pan/shell/naspt-iptv/iptv.sh"
    [9]="https://alist.naspt.vip/d/123pan/shell/naspt-docker/updk.sh"
    [10]="https://alist.naspt.vip/d/123pan/shell/naspt-laddy/laddy.sh"
)

# 显示系统架构信息（仅在启动时显示一次）
display_architecture() {
    case "$(uname -m)" in
        x86_64)    echo "Architecture: x86_64 (x86 64位)" ;;
        i686|i386) echo "Architecture: x86 (x86 32位)" ;;
        aarch64)   echo "Architecture: ARM64 (ARM 64位)" ;;
        armv7l)    echo "Architecture: ARMv7 (ARM 32位)" ;;
        armv6l)    echo "Architecture: ARMv6 (ARM 32位)" ;;
        *)         echo "Architecture: Unknown (未知架构)" ;;
    esac
}

# 检查 Docker 服务状态并登录腾讯云容器镜像服务
check_docker() {
    if ! docker info &>/dev/null; then
        echo -e "\n====== Docker 未启动，请先启动 Docker 服务 ======"
        return 1
    fi
    
    # 登录腾讯云容器镜像服务
    echo -e "\n正在登录腾讯云容器镜像服务..."
    if ! docker login ccr.ccs.tencentyun.com --username=100005757274 -p naspt1995; then
        echo -e "\n====== 腾讯云容器镜像服务登录失败 ======"
        return 1
    fi
    echo -e "\n✅ 腾讯云容器镜像服务登录成功"
    return 0
}

# 优雅退出处理
clean_exit() {
    echo -e "\n正在清理并退出程序..."
    bash <(curl -Ls https://pan.naspt.vip/d/123pan/shell/sysinfo.sh)
    exit 0
}

# 信号处理函数
handle_sigint() {
    echo -e "\n检测到 Ctrl+C，使用选项 q 退出程序。"
    # 重置信号处理以便后续可以正常捕获
    trap 'handle_sigint' SIGINT
}

# 显示主菜单
show_menu() {
    echo -e "\n+----------------------------------------------------------------------"
    echo "| NASPT FOR NAS 管理面板"
    echo "+----------------------------------------------------------------------"
    echo "| 提示：安装前请确保端口无冲突，建议使用全新环境部署"
    echo "+----------------------------------------------------------------------"
    echo "================================"
    echo "1) 家庭影院系统"
    echo "2) 内网穿透服务"
    echo "3) 音乐管理系统"
    echo "4) 实用工具集合"
    echo "5) 直播录制系统"
    echo "6) 115直连服务"
    echo "7) 代理管理工具"
    echo "8) IPTV 管理系统"
    echo "9) 容器自动更新"
    echo "10) 上车幼儿园"
    echo "q) 安全退出"
    echo "================================"
}

# 执行安装脚本
run_installation() {
    local choice=$1
    echo -e "\n正在启动安装流程..."

    if [[ -n "${SCRIPT_URLS[$choice]}" ]]; then
        if check_docker; then
            echo "正在从以下地址获取安装脚本："
            # echo "${SCRIPT_URLS[$choice]}"
            if bash <(curl -fsSL "${SCRIPT_URLS[$choice]}" 2>/dev/null); then
                echo -e "\n✅ 安装成功完成"
            else
                echo -e "\n❌ 安装过程中出现错误，请检查日志"
            fi
        else
            echo -e "\n⚠️  Docker 服务不可用，安装中止"
        fi
    else
        echo -e "\n❌ 无效的选项编号"
    fi
}

# 主程序逻辑
main() {
    display_architecture

    while true; do
        show_menu
        read -p "请输入操作编号: " choice

        case $choice in
            [1-9]|10) run_installation "$choice" ;;
            q)     clean_exit ;;
            *)     echo -e "\n⚠️  无效选择，请重新输入" ;;
        esac

        # 等待用户确认后清屏
        read -p "按回车键继续..."
        clear
    done
}

# 启动主程序
main