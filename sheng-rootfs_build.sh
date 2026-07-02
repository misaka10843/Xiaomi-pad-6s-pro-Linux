#!/bin/bash
set -euo pipefail

IMAGE_SIZE="${IMAGE_SIZE:-8G}"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

DEBIAN_SUITE="trixie"
DEBOOTSTRAP_MIRROR="http://deb.debian.org/debian"

FINAL_DEBIAN_MIRROR="https://mirrors.ustc.edu.cn/debian"
FINAL_DEBIAN_SECURITY_MIRROR="https://mirrors.ustc.edu.cn/debian-security"

MIPPS_DEB_URL="https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/mipps/xiaomi-mipps-auth_0.11_arm64.deb"

DEFAULT_USER="${ROOTFS_USER:-luser}"
DEFAULT_PASS="${ROOTFS_PASS:-luser}"
ROOT_PASS="${ROOTFS_ROOT_PASS:-1234}"

FIREFOX_CHANNEL="${FIREFOX_CHANNEL:-official}"
INSTALL_FLATPAK="${INSTALL_FLATPAK:-true}"
INSTALL_GPU_DRIVER="${INSTALL_GPU_DRIVER:-false}"

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <distro-variant> <kernel_version> [boot_mode] [desktop_env]"
    echo "示例: $0 debian-desktop 7.1 dual kde"
    echo "示例: $0 debian-desktop 7.1 all all"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

DISTRO="$1"
KERNEL="$2"
TARGET_MODE="${3:-all}"
TARGET_FLAVOUR="${4:-all}"

distro_type="$(echo "$DISTRO" | cut -d'-' -f1)"
distro_variant="$(echo "$DISTRO" | cut -d'-' -f2)"

if [ "$distro_type" != "debian" ]; then
    echo "❌ 目前仅支持 debian 衍生版"
    exit 1
fi

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

if [ "$TARGET_MODE" = "all" ]; then
    BOOTMODES=("dual" "single")
elif [[ "$TARGET_MODE" =~ ^(dual|single)$ ]]; then
    BOOTMODES=("$TARGET_MODE")
else
    echo "❌ 不支持的启动模式: $TARGET_MODE"
    exit 1
fi

if [ "$TARGET_FLAVOUR" = "all" ]; then
    FLAVOURS=("gnome" "kde")
elif [[ "$TARGET_FLAVOUR" =~ ^(gnome|kde)$ ]]; then
    FLAVOURS=("$TARGET_FLAVOUR")
else
    echo "❌ 不支持的桌面环境: $TARGET_FLAVOUR"
    exit 1
fi

bool_is_true() {
    case "${1:-}" in
        true|TRUE|True|1|yes|YES|Yes|on|ON|On)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cleanup_mounts() {
    echo "🧹 正在触发挂载点安全清理机制..."

    if mountpoint -q rootdir/dev/pts 2>/dev/null; then
        umount -l rootdir/dev/pts || true
    fi

    if mountpoint -q rootdir/dev 2>/dev/null; then
        umount -l rootdir/dev || true
    fi

    if mountpoint -q rootdir/proc 2>/dev/null; then
        umount -l rootdir/proc || true
    fi

    if mountpoint -q rootdir/sys 2>/dev/null; then
        umount -l rootdir/sys || true
    fi

    if mountpoint -q rootdir 2>/dev/null; then
        fuser -k -9 -m rootdir 2>/dev/null || true
        sleep 2
        umount -l rootdir || true
    fi

    rm -rf rootdir
}

trap cleanup_mounts EXIT ERR INT TERM

configure_dns() {
    echo "🌐 正在配置构建阶段 DNS..."

    rm -f rootdir/etc/resolv.conf

    cat > rootdir/etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
}

write_build_debian_sources() {
    echo "🪞 正在写入构建阶段 Debian 官方源..."

    mkdir -p rootdir/etc/apt/sources.list.d

    rm -f rootdir/etc/apt/sources.list
    rm -f rootdir/etc/apt/sources.list.d/*.list
    rm -f rootdir/etc/apt/sources.list.d/*.sources

    cat > rootdir/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${DEBIAN_SUITE} ${DEBIAN_SUITE}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: ${DEBIAN_SUITE}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

write_final_debian_sources() {
    echo "🪞 正在写入最终系统 APT 源: USTC HTTPS..."

    mkdir -p rootdir/etc/apt/sources.list.d

    rm -f rootdir/etc/apt/sources.list
    rm -f rootdir/etc/apt/sources.list.d/*.list
    rm -f rootdir/etc/apt/sources.list.d/*.sources

    cat > rootdir/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: ${FINAL_DEBIAN_MIRROR}
Suites: ${DEBIAN_SUITE} ${DEBIAN_SUITE}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${FINAL_DEBIAN_SECURITY_MIRROR}
Suites: ${DEBIAN_SUITE}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

configure_locale_timezone() {
    echo "🌏 正在配置中文语言、时区和输入法环境变量..."

    sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' rootdir/etc/locale.gen
    sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' rootdir/etc/locale.gen
    chroot rootdir locale-gen

    cat > rootdir/etc/default/locale <<EOF
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_MESSAGES=zh_CN.UTF-8
EOF

    cat > rootdir/etc/locale.conf <<EOF
LANG=zh_CN.UTF-8
EOF

    chroot rootdir ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    cat > rootdir/etc/environment <<EOF
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
INPUT_METHOD=fcitx
SDL_IM_MODULE=fcitx
EOF
}

configure_chrony() {
    echo "⏱️ 正在配置 chrony 时间同步..."

    mkdir -p rootdir/etc/chrony

    cat > rootdir/etc/chrony/chrony.conf <<EOF
server ntp.aliyun.com iburst
server time1.cloud.tencent.com iburst
server time2.cloud.tencent.com iburst
server ntp.ntsc.ac.cn iburst
pool cn.pool.ntp.org iburst

driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony/chrony.keys
logdir /var/log/chrony
EOF

    chroot rootdir systemctl disable systemd-timesyncd 2>/dev/null || true
    chroot rootdir systemctl enable chrony || true
}

configure_english_user_dirs() {
    local user_name="$1"

    echo "📁 正在配置英文用户目录: ${user_name}"

    mkdir -p rootdir/etc/xdg
    cat > rootdir/etc/xdg/user-dirs.defaults <<EOF
DESKTOP=Desktop
DOWNLOAD=Downloads
TEMPLATES=Templates
PUBLICSHARE=Public
DOCUMENTS=Documents
MUSIC=Music
PICTURES=Pictures
VIDEOS=Videos
EOF

    mkdir -p "rootdir/home/${user_name}/Desktop"
    mkdir -p "rootdir/home/${user_name}/Downloads"
    mkdir -p "rootdir/home/${user_name}/Templates"
    mkdir -p "rootdir/home/${user_name}/Public"
    mkdir -p "rootdir/home/${user_name}/Documents"
    mkdir -p "rootdir/home/${user_name}/Music"
    mkdir -p "rootdir/home/${user_name}/Pictures"
    mkdir -p "rootdir/home/${user_name}/Videos"
    mkdir -p "rootdir/home/${user_name}/.config"

    cat > "rootdir/home/${user_name}/.config/user-dirs.dirs" <<EOF
XDG_DESKTOP_DIR="\$HOME/Desktop"
XDG_DOWNLOAD_DIR="\$HOME/Downloads"
XDG_TEMPLATES_DIR="\$HOME/Templates"
XDG_PUBLICSHARE_DIR="\$HOME/Public"
XDG_DOCUMENTS_DIR="\$HOME/Documents"
XDG_MUSIC_DIR="\$HOME/Music"
XDG_PICTURES_DIR="\$HOME/Pictures"
XDG_VIDEOS_DIR="\$HOME/Videos"
EOF

    cat > "rootdir/home/${user_name}/.config/user-dirs.locale" <<EOF
en_US
EOF

    chroot rootdir chown -R "${user_name}:${user_name}" "/home/${user_name}"
}

install_base_packages() {
    echo "📦 正在安装基础环境组件..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        sudo \
        vim \
        nano \
        wget \
        curl \
        ca-certificates \
        xz-utils \
        bzip2 \
        file \
        network-manager \
        openssh-server \
        wpasupplicant \
        dbus \
        locales \
        dialog \
        chrony \
        xdg-user-dirs \
        bash-completion \
        pciutils \
        usbutils \
        kmod \
        initramfs-tools \
        qrtr-tools \
        rmtfs \
        tqftpserv \
        protection-domain-mapper \
        bluez \
        pipewire \
        pipewire-audio \
        pipewire-pulse \
        wireplumber \
        alsa-utils \
        pavucontrol \
        upower \
        power-profiles-daemon \
        brightnessctl \
        libdrm2 \
        libglvnd0 \
        libgl1 \
        libegl1 \
        libgles2 \
        libgbm1 \
        libvulkan1 \
        vulkan-tools \
        mesa-utils \
        ffmpeg"

    chroot rootdir systemctl enable NetworkManager || true
    chroot rootdir systemctl enable ssh || true
    chroot rootdir systemctl enable bluetooth || true
    chroot rootdir systemctl enable rmtfs || true
    chroot rootdir systemctl enable qrtr-ns || true
    chroot rootdir systemctl enable pd-mapper || true
    chroot rootdir systemctl enable power-profiles-daemon || true
    chroot rootdir systemctl --global enable pipewire || true
    chroot rootdir systemctl --global enable pipewire-pulse || true
    chroot rootdir systemctl --global enable wireplumber || true
}

install_chinese_fonts_and_fcitx5() {
    echo "⌨️ 正在安装中文字体与 fcitx5-rime..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        fonts-noto-cjk \
        fonts-wqy-microhei \
        fonts-wqy-zenhei \
        fcitx5 \
        fcitx5-chinese-addons \
        fcitx5-frontend-gtk3 \
        fcitx5-frontend-qt5 \
        fcitx5-rime \
        librime-data-pinyin-simp \
        librime-data-double-pinyin \
        librime-data-wubi \
        librime-data-stroke" || {
            echo "⚠️ 部分 Rime 数据包不存在或安装失败，回退安装基础 fcitx5。"
            chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
                fonts-noto-cjk \
                fonts-wqy-microhei \
                fonts-wqy-zenhei \
                fcitx5 \
                fcitx5-chinese-addons \
                fcitx5-frontend-gtk3 \
                fcitx5-frontend-qt5"
        }
}

install_device_debs() {
    echo "📦 正在注入设备专属 .deb 驱动包..."

    mkdir -p rootdir/tmp/debs
    mkdir -p rootdir/tmp/debs-stage

    if ls xiaomi-mipps-auth_*_arm64.deb >/dev/null 2>&1; then
        echo "📥 已检测到工作区 MIPPS deb，跳过 fallback 下载。"
    else
        echo "📥 正在尝试下载 xiaomi-mipps-auth fallback..."
        wget -q -O xiaomi-mipps-auth_0.11_arm64.deb "$MIPPS_DEB_URL" || \
            echo "⚠️ MIPPS fallback 下载失败，继续使用工作区已有 deb。"
    fi

    cp ./*.deb rootdir/tmp/debs/ 2>/dev/null || true

    if ! ls rootdir/tmp/debs/*.deb >/dev/null 2>&1; then
        echo "❌ 没有找到任何 deb 包，无法注入设备驱动。"
        exit 1
    fi

    echo "将安装以下 deb 包："
    ls -lh rootdir/tmp/debs/*.deb

    echo "🔊 正在单独隔离 alsa-xiaomi-sheng，避免与 alsa-ucm-conf 产生 dpkg 文件冲突..."
    if ls rootdir/tmp/debs/alsa-xiaomi-sheng*.deb >/dev/null 2>&1; then
        mv rootdir/tmp/debs/alsa-xiaomi-sheng*.deb rootdir/tmp/debs-stage/
    fi

    echo "📦 正在安装设备 deb 依赖..."
    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libprotobuf-c1 \
        libqmi-glib5 \
        libmbim-glib4 \
        initramfs-tools \
        alsa-ucm-conf"

    echo "📦 正在安装除 alsa-xiaomi-sheng 之外的设备 deb..."

    if ls rootdir/tmp/debs/*.deb >/dev/null 2>&1; then
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/debs/*.deb" || {
            echo "⚠️ 部分设备 .deb 安装失败，尝试修复依赖后继续。"
            chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get --fix-broken install -y" || true
            chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && dpkg --configure -a" || true
            chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/debs/*.deb"
        }
    else
        echo "ℹ️ 没有其他设备 deb 需要安装。"
    fi

    echo "🔊 正在解包 alsa-xiaomi-sheng UCM 文件到系统，不注册 dpkg 包..."

    if ls rootdir/tmp/debs-stage/alsa-xiaomi-sheng*.deb >/dev/null 2>&1; then
        chroot rootdir bash -c '
            set -e
            for deb in /tmp/debs-stage/alsa-xiaomi-sheng*.deb; do
                echo "正在解包 $deb ..."
                dpkg-deb -x "$deb" /
            done
        '

        mkdir -p rootdir/var/lib/xiaomi-sheng
        cat > rootdir/var/lib/xiaomi-sheng/alsa-xiaomi-sheng-overlay.txt <<EOF
alsa-xiaomi-sheng.deb was extracted with dpkg-deb -x during image build.

Reason:
- alsa-xiaomi-sheng contains files also shipped by Debian alsa-ucm-conf.
- alsa-xiaomi-sheng also depends on alsa-ucm-conf.
- Installing it as a normal dpkg package causes overwrite/dependency conflicts.
EOF

        echo "✅ alsa-xiaomi-sheng UCM 文件已覆盖到系统。"
    else
        echo "⚠️ 未找到 alsa-xiaomi-sheng deb，跳过设备 UCM 覆盖。"
    fi

    echo "🔧 正在修复 dpkg 状态..."
    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get --fix-broken install -y" || true
    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && dpkg --configure -a" || true

    echo "🔧 正在启用设备相关服务..."

    for svc in rmtfs qrtr-ns pd-mapper iio-sensor-proxy sheng-sensors sheng-devauth fastrpc; do
        if chroot rootdir systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
            chroot rootdir systemctl enable "${svc}.service" || true
        else
            echo "ℹ️ 未找到 ${svc}.service，跳过 enable。"
        fi
    done
}

install_gpu_driver_deb() {
    if ! bool_is_true "$INSTALL_GPU_DRIVER"; then
        echo "🎮 跳过 Mesa Freedreno/Turnip 显驱注入。"
        return 0
    fi

    echo "🎮 正在尝试注入 Mesa Freedreno/Turnip 显驱 deb..."

    mkdir -p rootdir/tmp/debs

    if ls mesa-freedreno-turnip-opt_*_arm64.deb >/dev/null 2>&1; then
        cp mesa-freedreno-turnip-opt_*_arm64.deb rootdir/tmp/debs/
    else
        echo "⚠️ 当前目录未找到 mesa-freedreno-turnip-opt deb，跳过显驱注入。"
        echo "⚠️ 这不会影响 RootFS 构建，只是使用 Debian 默认 Mesa。"
        return 0
    fi

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/debs/mesa-freedreno-turnip-opt_*_arm64.deb" || {
        echo "⚠️ 显驱 deb 安装失败，尝试修复依赖后继续。"
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get -f install -y" || true
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/debs/mesa-freedreno-turnip-opt_*_arm64.deb" || {
            echo "⚠️ 显驱 deb 最终安装失败，继续构建系统。"
            return 0
        }
    }

    echo "✅ Mesa Freedreno/Turnip 显驱 deb 已注入。"
}

create_default_user() {
    echo "👤 正在创建默认用户..."

    chroot rootdir useradd -m -s /bin/bash "$DEFAULT_USER" || true
    chroot rootdir bash -c "echo '${DEFAULT_USER}:${DEFAULT_PASS}' | chpasswd"
    chroot rootdir bash -c "echo 'root:${ROOT_PASS}' | chpasswd"

    chroot rootdir usermod -aG sudo,audio,video,render,input,netdev,plugdev "$DEFAULT_USER" || true

    mkdir -p "rootdir/home/${DEFAULT_USER}/.config"
    chroot rootdir chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"

    configure_english_user_dirs "$DEFAULT_USER"
}

install_firefox() {
    if [ "$FIREFOX_CHANNEL" = "esr" ]; then
        echo "🦊 正在安装 Debian firefox-esr..."
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends firefox-esr"
        return 0
    fi

    echo "🦊 正在安装 Mozilla 官方 Firefox ARM64 tarball..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends ca-certificates wget xz-utils bzip2"

    chroot rootdir bash -c "mkdir -p /opt /usr/local/bin"
    chroot rootdir bash -c "wget -O /tmp/firefox.tar.xz 'https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=zh-CN'"
    chroot rootdir bash -c "tar -xJf /tmp/firefox.tar.xz -C /opt"
    chroot rootdir bash -c "test -x /opt/firefox/firefox"
    chroot rootdir bash -c "ln -sf /opt/firefox/firefox /usr/local/bin/firefox"
    chroot rootdir bash -c "ln -sf /opt/firefox/firefox /usr/bin/firefox"
    chroot rootdir bash -c "rm -f /tmp/firefox.tar.xz"

    mkdir -p rootdir/usr/share/applications

    cat > rootdir/usr/share/applications/firefox.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=Firefox
Name[zh_CN]=Firefox 浏览器
GenericName=Web Browser
GenericName[zh_CN]=网页浏览器
Comment=Browse the World Wide Web
Comment[zh_CN]=浏览互联网
Exec=/opt/firefox/firefox %u
Terminal=false
Type=Application
Icon=/opt/firefox/browser/chrome/icons/default/default128.png
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

    chroot rootdir bash -c "update-alternatives --install /usr/bin/x-www-browser x-www-browser /opt/firefox/firefox 100 || true"
}

install_flatpak_support() {
    if ! bool_is_true "$INSTALL_FLATPAK"; then
        echo "📦 跳过 Flatpak 安装。"
        return 0
    fi

    echo "📦 正在安装 Flatpak 支持..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        flatpak \
        xdg-desktop-portal \
        xdg-desktop-portal-kde \
        plasma-discover-backend-flatpak"

    chroot rootdir bash -c "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true"
    chroot rootdir bash -c "flatpak remote-modify flathub --url=https://mirrors.ustc.edu.cn/flathub || true"
}

install_gnome_desktop() {
    echo "🖥️ 安装 GNOME 桌面环境..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        gnome-shell \
        gnome-session \
        gnome-terminal \
        gdm3 \
        gnome-tweaks \
        nautilus \
        xdg-user-dirs \
        xdg-user-dirs-gtk"

    chroot rootdir systemctl enable gdm3 || true

    mkdir -p rootdir/etc/gdm3
    cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${DEFAULT_USER}
EOF
}

install_kde_desktop() {
    echo "🖥️ 安装 KDE Plasma 桌面环境..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        kde-plasma-desktop \
        sddm \
        plasma-nm \
        bluedevil \
        powerdevil \
        dolphin \
        konsole \
        systemsettings \
        kde-config-gtk-style \
        xdg-desktop-portal-kde \
        ark \
        gwenview \
        okular \
        xdg-user-dirs"

    echo "📸 正在尝试安装 KDE 截图工具..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        kde-spectacle" || \
        echo "⚠️ kde-spectacle 不存在或安装失败，跳过截图工具。"

    chroot rootdir systemctl enable sddm || true

    mkdir -p rootdir/etc/sddm.conf.d
    cat > rootdir/etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=${DEFAULT_USER}
Session=plasma
EOF
}

configure_hostname() {
    local flavour="$1"
    local mode="$2"

    echo "debian-${flavour}-${mode}" > rootdir/etc/hostname

    cat > rootdir/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 debian-${flavour}-${mode}

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
}

configure_fstab() {
    local mode="$1"

    if [ "$mode" = "dual" ]; then
        echo "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
    else
        echo "PARTLABEL=userdata / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
    fi
}

cleanup_chroot_before_pack() {
    echo "🧹 清理场地准备打包..."

    chroot rootdir apt-get clean || true
    chroot rootdir bash -c "rm -rf /var/lib/apt/lists/*" || true
    chroot rootdir bash -c "rm -rf /tmp/debs /tmp/*.deb /tmp/firefox.tar.xz" || true

    rm -f ./*.deb
}

for FLAVOUR in "${FLAVOURS[@]}"; do
    for MODE in "${BOOTMODES[@]}"; do
        echo ""
        echo "======================================================"
        echo "🔥 开始构建: Debian ${DEBIAN_SUITE} | 桌面: ${FLAVOUR^^} | 模式: ${MODE}"
        echo "======================================================"

        ROOTFS_IMG="${distro_type}_${DEBIAN_SUITE}_${FLAVOUR}_${MODE}_${TIMESTAMP}.img"
        SPARSE_IMG="sparse_${ROOTFS_IMG}"
        ARCHIVE_NAME="${ROOTFS_IMG%.img}.7z"

        cleanup_mounts
        mkdir -p rootdir

        echo "🧱 正在创建 ext4 镜像: ${ROOTFS_IMG}"
        truncate -s "$IMAGE_SIZE" "$ROOTFS_IMG"
        mkfs.ext4 -F -O ^metadata_csum "$ROOTFS_IMG"
        mount -o loop "$ROOTFS_IMG" rootdir

        echo "⬇️ 正在使用 debootstrap 拉取基础系统..."
        debootstrap --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBOOTSTRAP_MIRROR"

        mkdir -p rootdir/dev rootdir/dev/pts rootdir/proc rootdir/sys

        mount --bind /dev rootdir/dev
        mount --bind /dev/pts rootdir/dev/pts
        mount -t proc proc rootdir/proc
        mount -t sysfs sys rootdir/sys

        configure_dns
        write_build_debian_sources
        install_base_packages
        configure_locale_timezone
        configure_chrony
        install_chinese_fonts_and_fcitx5
        install_device_debs
        install_gpu_driver_deb
        create_default_user
        configure_hostname "$FLAVOUR" "$MODE"

        if [ "$distro_variant" = "desktop" ]; then
            if [ "$FLAVOUR" = "gnome" ]; then
                install_gnome_desktop
            elif [ "$FLAVOUR" = "kde" ]; then
                install_kde_desktop
            fi

            install_firefox
            install_flatpak_support

            chroot rootdir systemctl enable NetworkManager || true
            chroot rootdir systemctl set-default graphical.target
        fi

        configure_fstab "$MODE"

        write_final_debian_sources

        cleanup_chroot_before_pack
        cleanup_mounts

        echo "🔧 正在设置文件系统 UUID..."
        tune2fs -U "$FILESYSTEM_UUID" "$ROOTFS_IMG"

        echo "🔄 正在转换 Sparse 镜像并压缩..."
        img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
        7z a "$ARCHIVE_NAME" "$SPARSE_IMG"

        rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

        echo "🎉 [${FLAVOUR^^} - ${MODE}] 版本完成: ${ARCHIVE_NAME}"
    done
done

trap - EXIT ERR INT TERM

echo "✅ Debian 镜像已打包完毕！"