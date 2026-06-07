#!/bin/bash
set -euo pipefail

IMAGE_SIZE="12G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

DEBIAN_SUITE="trixie"

# GitHub Actions 构建阶段使用 Debian 官方 HTTP 源
DEBOOTSTRAP_MIRROR="http://deb.debian.org/debian"
BUILD_DEBIAN_MIRROR="http://deb.debian.org/debian"
BUILD_DEBIAN_SECURITY_MIRROR="http://deb.debian.org/debian-security"

# 平板的 apt 源使用中科大 HTTPS 源
FINAL_DEBIAN_MIRROR="https://mirrors.ustc.edu.cn/debian"
FINAL_DEBIAN_SECURITY_MIRROR="https://mirrors.ustc.edu.cn/debian-security"

UPSTREAM_REPO_URL="https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux"
MIPPS_DEB_URL="${UPSTREAM_REPO_URL}/releases/download/mipps/xiaomi-mipps-auth_0.11_arm64.deb"
# WIFI_FIX_DEB_URL="${UPSTREAM_REPO_URL}/releases/download/fix/firmware-sheng-wififix.deb"

DEFAULT_USER="misaka10843"
DEFAULT_PASS="misaka10843"
HOSTNAME_VALUE="debian-mi-pad"

# 正式版默认进入 GUI
DEFAULT_TARGET="graphical.target"

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <distro-variant> <kernel_version> [boot_mode] [desktop_env]"
    echo "示例: $0 debian-desktop 7.1 dual gnome"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

DISTRO="$1"
KERNEL="$2"
TARGET_MODE="${3:-dual}"
TARGET_FLAVOUR="${4:-gnome}"

distro_type="$(echo "$DISTRO" | cut -d'-' -f1)"
distro_variant="$(echo "$DISTRO" | cut -d'-' -f2)"

if [ "$distro_type" != "debian" ]; then
    echo "❌ 目前仅支持 debian 衍生版"
    exit 1
fi

if [ "$distro_variant" != "desktop" ]; then
    echo "❌ 当前脚本仅保留 desktop 构建"
    exit 1
fi

if [ "$TARGET_MODE" != "dual" ]; then
    echo "❌ 当前版本只构建 dual 双系统模式"
    exit 1
fi

if [ "$TARGET_FLAVOUR" != "gnome" ]; then
    echo "❌ 当前版本只支持 GNOME"
    exit 1
fi

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

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

write_build_debian_sources() {
    echo "🪞 正在写入构建阶段 APT 源: Debian 官方 HTTP..."

    mkdir -p rootdir/etc/apt/sources.list.d

    rm -f rootdir/etc/apt/sources.list
    rm -f rootdir/etc/apt/sources.list.d/*.list
    rm -f rootdir/etc/apt/sources.list.d/*.sources

    cat > rootdir/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: ${BUILD_DEBIAN_MIRROR}
Suites: ${DEBIAN_SUITE} ${DEBIAN_SUITE}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${BUILD_DEBIAN_SECURITY_MIRROR}
Suites: ${DEBIAN_SUITE}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

write_final_debian_sources() {
    echo "🪞 正在写入最终系统 APT 源: 中科大 USTC HTTPS..."

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

configure_dns() {
    echo "🌐 正在配置构建阶段 DNS..."

    rm -f rootdir/etc/resolv.conf

    cat > rootdir/etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 1.1.1.1
EOF
}

configure_locale_timezone() {
    echo "🌏 正在配置中文语言、时区和环境变量..."

    sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' rootdir/etc/locale.gen
    sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' rootdir/etc/locale.gen

    chroot rootdir locale-gen

    cat > rootdir/etc/default/locale <<EOF
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
EOF

    cat > rootdir/etc/locale.conf <<EOF
LANG=zh_CN.UTF-8
EOF

    chroot rootdir ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    cat > rootdir/etc/environment <<EOF
LANG=zh_CN.UTF-8
GTK_IM_MODULE=ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
INPUT_METHOD=ibus
SDL_IM_MODULE=ibus
GLFW_IM_MODULE=ibus
EOF
}

configure_system_english_user_dirs() {
    echo "📁 正在配置系统级英文 XDG 用户目录默认值..."

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
    chroot rootdir systemctl enable chrony
}

configure_hostname() {
    echo "🏷️ 正在配置 hostname 和 hosts..."

    echo "${HOSTNAME_VALUE}" > rootdir/etc/hostname

    cat > rootdir/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME_VALUE}

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
}

create_user() {
    echo "👤 正在创建默认用户..."

    chroot rootdir useradd -m -s /bin/bash "$DEFAULT_USER" || true

    chroot rootdir bash -c "echo '${DEFAULT_USER}:${DEFAULT_PASS}' | chpasswd"
    chroot rootdir bash -c "echo 'root:${DEFAULT_PASS}' | chpasswd"

    chroot rootdir usermod -aG sudo,audio,video,render,input,netdev,plugdev "$DEFAULT_USER"

    mkdir -p "rootdir/home/${DEFAULT_USER}/.config"
    chroot rootdir chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"
}

configure_english_user_dirs() {
    echo "📁 正在配置 ${DEFAULT_USER} 的英文用户目录..."

    mkdir -p "rootdir/home/${DEFAULT_USER}/Desktop"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Downloads"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Templates"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Public"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Documents"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Music"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Pictures"
    mkdir -p "rootdir/home/${DEFAULT_USER}/Videos"
    mkdir -p "rootdir/home/${DEFAULT_USER}/.config"

    cat > "rootdir/home/${DEFAULT_USER}/.config/user-dirs.dirs" <<EOF
XDG_DESKTOP_DIR="\$HOME/Desktop"
XDG_DOWNLOAD_DIR="\$HOME/Downloads"
XDG_TEMPLATES_DIR="\$HOME/Templates"
XDG_PUBLICSHARE_DIR="\$HOME/Public"
XDG_DOCUMENTS_DIR="\$HOME/Documents"
XDG_MUSIC_DIR="\$HOME/Music"
XDG_PICTURES_DIR="\$HOME/Pictures"
XDG_VIDEOS_DIR="\$HOME/Videos"
EOF

    cat > "rootdir/home/${DEFAULT_USER}/.config/user-dirs.locale" <<EOF
en_US
EOF

    chroot rootdir chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"
}

install_base_packages() {
    echo "📦 正在安装基础环境组件..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        sudo \
        vim \
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
        blueman \
        pipewire \
        pipewire-audio \
        pipewire-pulse \
        wireplumber \
        alsa-utils \
        alsa-ucm-conf \
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
        ffmpeg \
        libavcodec-extra \
        libavformat61 \
        libavutil59 \
        libswresample5 \
        libavfilter10 \
        libavdevice61"

    chroot rootdir systemctl enable NetworkManager
    chroot rootdir systemctl enable ssh
    chroot rootdir systemctl enable bluetooth || true
    chroot rootdir systemctl enable rmtfs || true
    chroot rootdir systemctl enable qrtr-ns || true
    chroot rootdir systemctl enable pd-mapper || true
    chroot rootdir systemctl enable power-profiles-daemon || true
    chroot rootdir systemctl --global enable pipewire || true
    chroot rootdir systemctl --global enable pipewire-pulse || true
    chroot rootdir systemctl --global enable wireplumber || true
}

install_ibus_rime() {
    echo "⌨️ 正在安装 ibus-rime 输入法..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        ibus \
        ibus-rime \
        fonts-noto-cjk \
        fonts-wqy-microhei \
        fonts-wqy-zenhei"

    echo "⌨️ 正在尝试安装 Rime 附加方案数据包..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        librime-data-pinyin-simp \
        librime-data-double-pinyin \
        librime-data-wubi \
        librime-data-stroke" || echo "⚠️ 部分 Rime 数据包不存在或安装失败，已跳过。"

    mkdir -p "rootdir/home/${DEFAULT_USER}/.config/autostart"

    cat > "rootdir/home/${DEFAULT_USER}/.config/autostart/ibus-daemon.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=IBus
Exec=ibus-daemon -drx
OnlyShowIn=GNOME;
X-GNOME-Autostart-enabled=true
EOF

    chroot rootdir chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}/.config"
}

install_gnome_desktop() {
    echo "🖥️ 正在安装 GNOME 桌面环境..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get \
        -o Dpkg::Options::='--force-confdef' \
        -o Dpkg::Options::='--force-confold' \
        install -y --no-install-recommends \
        gnome-shell \
        gnome-session \
        gnome-session-xsession \
        gnome-terminal \
        gdm3 \
        gnome-control-center \
        gnome-settings-daemon \
        gnome-software \
        gnome-software-plugin-flatpak \
        gnome-system-monitor \
        gnome-tweaks \
        gnome-keyring \
        nautilus \
        gvfs \
        gvfs-backends \
        xdg-user-dirs \
        xdg-user-dirs-gtk \
        xserver-xorg \
        xserver-xorg-core \
        xinit \
        flatpak"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && dpkg --configure -a"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get \
        -o Dpkg::Options::='--force-confdef' \
        -o Dpkg::Options::='--force-confold' \
        -f install -y"

    chroot rootdir systemctl enable gdm3
    chroot rootdir systemctl set-default "${DEFAULT_TARGET}"

    mkdir -p rootdir/etc/gdm3

    # 默认不禁用 Wayland。GDM 会优先提供 GNOME Wayland，同时保留 GNOME on Xorg 回退会话。
    cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${DEFAULT_USER}
EOF
}

install_firefox_official() {
    echo "🦊 正在安装 Mozilla 官方 Firefox ARM64 tarball..."

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        xz-utils \
        bzip2"

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
    chroot rootdir bash -c "update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /opt/firefox/firefox 100 || true"
}

configure_flatpak() {
    echo "📦 正在配置 Flatpak 和中科大 Flathub 镜像..."

    chroot rootdir bash -c "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true"
    chroot rootdir bash -c "flatpak remote-modify flathub --url=https://mirrors.ustc.edu.cn/flathub || true"
}

install_device_debs() {
    echo "📦 正在注入设备专属 .deb 驱动包..."

    mkdir -p rootdir/tmp/debs

    echo "📥 正在从上游仓库下载 xiaomi-mipps-auth..."
    wget -q -O xiaomi-mipps-auth_0.11_arm64.deb "$MIPPS_DEB_URL"

    # echo "📥 正在尝试下载 Wi-Fi fix，可选..."
    # wget -q -O firmware-sheng-wififix.deb "$WIFI_FIX_DEB_URL" || \
    #     echo "⚠️ Wi-Fi fix 下载失败或不存在，跳过。"

    cp ./*.deb rootdir/tmp/debs/ 2>/dev/null || true

    if ! ls rootdir/tmp/debs/*.deb >/dev/null 2>&1; then
        echo "❌ 没有找到任何 deb 包，无法注入设备驱动。"
        exit 1
    fi

    echo "将安装以下 deb 包："
    ls -lh rootdir/tmp/debs/*.deb

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libprotobuf-c1 \
        libqmi-glib5 \
        libmbim-glib4 \
        initramfs-tools"

    chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/debs/*.deb" || {
        echo "⚠️ 部分 .deb 安装失败，尝试修复依赖后继续。"
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get -f install -y"
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/debs/*.deb"
    }

    echo "🔧 正在启用设备相关服务..."

    chroot rootdir systemctl enable rmtfs || true
    chroot rootdir systemctl enable qrtr-ns || true
    chroot rootdir systemctl enable pd-mapper || true
    chroot rootdir systemctl enable iio-sensor-proxy || true
    chroot rootdir systemctl enable sheng-sensors || true
    chroot rootdir systemctl enable sheng-devauth || true
    chroot rootdir systemctl enable fastrpc || true
}

fix_alsa_ucm_links() {
    echo "🔊 正在修复 Xiaomi Pad 6S Pro ALSA UCM 入口链接..."

    mkdir -p rootdir/usr/share/alsa/ucm2/conf.d/sm8550

    if [ -f rootdir/usr/share/alsa/ucm2/Xiaomi/sheng/Xiaomi-Pad6SPro.conf ]; then
        rm -f rootdir/usr/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf
        ln -s ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf \
            rootdir/usr/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf
    else
        echo "⚠️ 未找到 Xiaomi/sheng/Xiaomi-Pad6SPro.conf，跳过 UCM 链接修复。"
    fi
}

install_cirrus_audio_firmware() {
    echo "🔊 正在安装 Cirrus CS35L43 音频固件..."

    mkdir -p rootdir/lib/firmware/cirrus

    if [ -d firmware/cirrus ]; then
        cp -a firmware/cirrus/* rootdir/lib/firmware/cirrus/
    else
        echo "⚠️ 当前仓库没有 firmware/cirrus 目录，跳过 Cirrus 固件复制。"
        echo "⚠️ 扬声器可能无法正常工作。"
        return 0
    fi

    (
        cd rootdir/lib/firmware/cirrus

        for pos in BLH BLL BRL TLH TLL TRL; do
            cp cs35l43-dsp1-spk-prot.wmfw "cs35l43-DSP1-spk-prot-(null)-${pos}.wmfw" 2>/dev/null || true
            cp cs35l43-dsp1-spk-prot.wmfw "cs35l43-DSP1-spk-prot--(null)-${pos}.wmfw" 2>/dev/null || true
            cp "${pos}-cs35l43-dsp1-spk-prot.bin" "cs35l43-DSP1-spk-prot-(null)-${pos}.bin" 2>/dev/null || true
            cp "${pos}-cs35l43-dsp1-spk-prot.bin" "cs35l43-DSP1-spk-prot--(null)-${pos}.bin" 2>/dev/null || true
        done

        chmod 0644 ./* 2>/dev/null || true
    )
}

configure_sheng_audio_init_service() {
    echo "🔊 正在配置 sheng-audio-init 服务..."

    mkdir -p rootdir/usr/local/sbin
    mkdir -p rootdir/etc/systemd/system

    cat > rootdir/usr/local/sbin/sheng-audio-init <<'EOF'
#!/bin/bash
set -e

systemctl start pd-mapper.service 2>/dev/null || true

sleep 2

amixer -c 0 cset name='SECONDARY_MI2S_RX Audio Mixer MultiMedia1' 1 2>/dev/null || true
amixer -c 0 sset 'stream0.vol_ctrl0 MultiMedia1 Playback Volu' 80% 2>/dev/null || true

alsactl store 0 2>/dev/null || true

exit 0
EOF

    chmod 0755 rootdir/usr/local/sbin/sheng-audio-init

    cat > rootdir/etc/systemd/system/sheng-audio-init.service <<'EOF'
[Unit]
Description=Initialize Xiaomi Sheng audio routing
After=sound.target pd-mapper.service
Wants=pd-mapper.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sheng-audio-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    chroot rootdir systemctl enable pd-mapper || true
    chroot rootdir systemctl enable sheng-audio-init.service || true
}

configure_mesa_env_for_gdm() {
    echo "🎮 正在为 Wayland/Xorg 会话配置 Mesa Freedreno 环境..."

    mkdir -p rootdir/etc/profile.d
    mkdir -p rootdir/etc/environment.d
    mkdir -p rootdir/etc/ld.so.conf.d

    cat > rootdir/etc/ld.so.conf.d/mesa-freedreno.conf <<EOF
/opt/mesa-freedreno/lib/aarch64-linux-gnu
EOF

    cat > rootdir/etc/environment.d/90-mesa-freedreno.conf <<EOF
MESA_HOME=/opt/mesa-freedreno
LIBGL_DRIVERS_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu/dri
GBM_BACKENDS_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu/gbm
__EGL_VENDOR_LIBRARY_DIRS=/opt/mesa-freedreno/share/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d
EOF

    cat > rootdir/etc/profile.d/mesa-freedreno-extra.sh <<'EOF'
if [ -d /opt/mesa-freedreno ]; then
    export MESA_HOME=/opt/mesa-freedreno
    export LD_LIBRARY_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}
    export LIBGL_DRIVERS_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu/dri
    export GBM_BACKENDS_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu/gbm
    export __EGL_VENDOR_LIBRARY_DIRS=/opt/mesa-freedreno/share/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d

    if [ -f /opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.aarch64.json ]; then
        export VK_ICD_FILENAMES=/opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.aarch64.json
    elif [ -f /opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.arm64.json ]; then
        export VK_ICD_FILENAMES=/opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.arm64.json
    fi
fi
EOF

    chmod 0644 rootdir/etc/profile.d/mesa-freedreno-extra.sh
}

configure_fstab() {
    echo "💽 正在配置 fstab: dual"

    echo "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
}

cleanup_chroot_before_pack() {
    echo "🧹 正在清理 chroot..."

    chroot rootdir apt-get clean || true
    chroot rootdir bash -c "rm -rf /var/lib/apt/lists/*" || true
    chroot rootdir bash -c "rm -rf /tmp/debs /tmp/*.deb /tmp/firefox.tar.xz" || true

    rm -f ./*.deb
}

echo ""
echo "======================================================"
echo "🔥 开始构建: Debian ${DEBIAN_SUITE} | 桌面: GNOME | 模式: dual"
echo "======================================================"

ROOTFS_IMG="${distro_type}_${DEBIAN_SUITE}_gnome_dual_${TIMESTAMP}.img"
SPARSE_IMG="sparse_${ROOTFS_IMG}"
ARCHIVE_NAME="${ROOTFS_IMG%.img}.7z"

cleanup_mounts
mkdir -p rootdir

echo "🧱 正在创建 ext4 镜像: ${ROOTFS_IMG}"
truncate -s "$IMAGE_SIZE" "$ROOTFS_IMG"
mkfs.ext4 -F -O ^metadata_csum "$ROOTFS_IMG"
mount -o loop "$ROOTFS_IMG" rootdir

echo "⬇️ 正在使用 debootstrap 从 Debian 官方 HTTP 源拉取基础系统..."
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
configure_hostname
create_user
install_ibus_rime
install_gnome_desktop

# xdg-user-dirs 包安装完成后，再覆盖英文目录配置
configure_system_english_user_dirs
configure_english_user_dirs

install_firefox_official
configure_flatpak
install_device_debs
fix_alsa_ucm_links
install_cirrus_audio_firmware
configure_sheng_audio_init_service

if [ -d rootdir/opt/mesa-freedreno ]; then
    configure_mesa_env_for_gdm
else
    echo "🎮 未检测到 /opt/mesa-freedreno，跳过 Mesa Freedreno 环境配置。"
fi

configure_fstab

# 所有软件安装完成后，再把最终系统 APT 源切换为中科大 HTTPS 源
write_final_debian_sources

cleanup_chroot_before_pack

cleanup_mounts

echo "🔧 正在设置文件系统 UUID..."
tune2fs -U "$FILESYSTEM_UUID" "$ROOTFS_IMG"

echo "🔄 正在转换 Sparse 镜像并压缩..."
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"

7z a "$ARCHIVE_NAME" "$SPARSE_IMG"

rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

trap - EXIT ERR INT TERM

echo "🎉 [GNOME - dual] 版本完成: ${ARCHIVE_NAME}"
echo "✅ Debian GNOME dual 镜像已打包完毕！"