import subprocess
import sys
import os

harbor_addr = 'ccr.ccs.tencentyun.com/naspt'


def check_skopeo():
    """检测Skopeo是否已安装"""
    try:
        subprocess.run(
            ['skopeo', '--version'],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        print("✅ Skopeo 已安装")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def detect_distro():
    """识别Linux发行版"""
    try:
        with open('/etc/os-release', 'r') as f:
            content = f.read()
            if 'ubuntu' in content or 'debian' in content:
                return 'apt'
            elif 'centos' in content or 'rhel' in content:
                return 'yum'
            elif 'fedora' in content:
                return 'dnf'
            elif 'arch' in content:
                return 'pacman'
    except FileNotFoundError:
        pass
    return None


def install_skopeo():
    """跨发行版安装Skopeo"""
    print("🔄 正在尝试安装 Skopeo...")

    distro = detect_distro()
    install_cmd = []

    if distro == 'apt':
        install_cmd = ['sudo', 'apt-get', 'update', '-qq', '&&',
                       'sudo', 'apt-get', 'install', '-y', 'skopeo']
    elif distro == 'yum':
        install_cmd = ['sudo', 'yum', 'install', '-y', 'skopeo']
    elif distro == 'dnf':
        install_cmd = ['sudo', 'dnf', 'install', '-y', 'skopeo']
    elif distro == 'pacman':
        install_cmd = ['sudo', 'pacman', '-Sy', '--noconfirm', 'skopeo']
    else:
        print("❌ 无法自动安装：不支持的Linux发行版")
        print("请手动安装 Skopeo：")
        print("Debian/Ubuntu: sudo apt-get install skopeo")
        print("RHEL/CentOS  : sudo yum install skopeo")
        print("Fedora       : sudo dnf install skopeo")
        print("Arch Linux   : sudo pacman -S skopeo")
        sys.exit(1)

    try:
        subprocess.run(
            ' '.join(install_cmd),
            shell=True,
            check=True,
            executable='/bin/bash'
        )
        print("✅ Skopeo 安装成功")
    except subprocess.CalledProcessError as e:
        print(f"❌ 安装失败，错误代码：{e.returncode}")
        sys.exit(1)


def main():
    # 环境预检
    if os.geteuid() != 0:
        print("⚠️  需要管理员权限，正在尝试自动提权...")
        try:
            subprocess.run(['sudo', '-v'], check=True)
        except:
            print("❌ 需要sudo权限运行此脚本")
            sys.exit(1)

    # 检查并安装Skopeo
    if not check_skopeo():
        install_skopeo()
        # 二次验证安装结果
        if not check_skopeo():
            print("❌ Skopeo 安装后验证失败")
            sys.exit(1)

    # 执行镜像复制
    with open('images.txt', 'r') as f:
        for image in f:
            image_name = image.strip()
            if not image_name:
                continue

            image_path = image_name.split("/")[-1]
            dest_url = f'docker://{harbor_addr}/{image_path}'

            print(f"\n🔄 正在传输镜像: {image_name}")

            try:
                # 关键修改点：将 text=True 改为 universal_newlines=True
                subprocess.run(
                    ['skopeo', 'copy', f'docker://{image_name}', dest_url],
                    check=True,
                    universal_newlines=True  # 这是兼容Python 3.6的写法
                )
                print(f"✅ 成功传输: {image_name}")
            except subprocess.CalledProcessError as e:
                print(f"❌ 传输失败: {image_name}")
                print(f"错误信息: {e.stderr}")
                sys.exit(1)


if __name__ == "__main__":
    main()