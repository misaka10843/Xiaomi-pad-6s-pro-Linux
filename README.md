## 当前修改内容

本仓库基于上游 [code002-2/Xiaomi-pad-6s-pro-Linux](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux) 进行定制，主要目标是构建适用于 Xiaomi Pad 6S Pro / SM8550 的 Debian 13 GNOME dual 双系统镜像。

请必须阅读上游仓库中的所有资料！！

### 安装步骤

与 [上游仓库wiki](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/%E5%AE%89%E8%A3%85%E6%8C%87%E5%8D%97) 一致，仅需将debian的镜像换为本仓库的即可

### 一些需要运行的内容

#### firefox提示不支持html5播放器

请运行下方的命令安装解码器

```bash
sudo apt update
sudo apt install -y ffmpeg libavcodec-extra libavformat61 libavutil59 libswresample5 libavfilter10 libavdevice61
```

#### 安装后重分配

重新分配空间 `sudo resize2fs /dev/sda30`

### 构建流程调整

- 修改Debian 13 的 GitHub Actions。
- 构建方式改为手动触发，不再 push 自动触发。
- 删除 KDE 构建逻辑，仅保留 GNOME 桌面环境。
- 删除 single 模式构建逻辑，仅保留 dual 双系统模式。
- kernel bundle 固定从上游仓库 `code002-2/Xiaomi-pad-6s-pro-Linux` 下载，避免 fork 仓库没有 Release 资产导致构建失败。
- 支持通过 `kernel_version` 参数选择内核版本，默认使用 `7.1`。
- 支持通过 `mesa_release_tag` 可选内置 Mesa Freedreno / Turnip 驱动包。
- Release 和 Artifact 只上传 GNOME dual 镜像产物。

### Debian RootFS 调整

- 发行版切换为 Debian 13 / trixie。
- APT 源切换为中科大 USTC 镜像源。
- APT 源格式改为 Deb822 `.sources` 新格式。
- 默认镜像大小调整为 `12G`，避免 GNOME、Firefox、Flatpak 和设备驱动安装后空间不足。
- 仅构建 `debian-desktop + gnome + dual` 组合。
- fstab 固定为 dual 模式：
  - `PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1`

### 用户和默认配置

- 默认普通用户改为 `misaka10843`。
- 默认普通用户密码改为 `misaka10843`。
- root 密码改为 `misaka10843`。
- 默认主机名改为 `debian-mi-pad`。
- 默认时区设置为 `Asia/Shanghai`。
- 默认语言环境设置为 `zh_CN.UTF-8`。
- 默认启用 GDM 自动登录到 `misaka10843`。
- 用户组补充 `render`、`plugdev` 等权限组，方便 GPU、输入设备和外设访问。

### 桌面环境调整

- 仅保留 GNOME。
- 保留 GNOME Software 商店。
- 保留 GNOME System Monitor 系统监控。
- 安装 GNOME Tweaks、Nautilus、GNOME Terminal 等基础桌面组件。
- 启用 `graphical.target`。
- 安装 Flatpak。
- 安装 `gnome-software-plugin-flatpak`，让 GNOME Software 支持 Flatpak 应用。
- Flathub 远程源改为中科大镜像地址。

### Firefox 调整

- 移除 `firefox-esr` apt 安装方式。
- 改为下载 Mozilla 官方 ARM64 Firefox tarball。
- 安装到 `/opt/firefox`。
- 创建 `/usr/bin/firefox` 和 `/usr/local/bin/firefox` 软链接。
- 创建系统 `.desktop` 启动器。
- 补充 `xz-utils`，确保可以解压官方 `tar.xz` 包。

### 输入法调整

- 移除 fcitx5 输入法方案。
- 改用 `ibus + ibus-rime`。
- 安装中文字体：
  - `fonts-noto-cjk`
  - `fonts-wqy-microhei`
  - `fonts-wqy-zenhei`
- 配置环境变量：
  - `GTK_IM_MODULE=ibus`
  - `QT_IM_MODULE=ibus`
  - `XMODIFIERS=@im=ibus`
  - `INPUT_METHOD=ibus`
- 为 GNOME 会话添加 IBus 自动启动项。

### 时间同步

- 内置 `chrony`。
- 禁用 `systemd-timesyncd`。
- 配置中国大陆低延迟 NTP 服务器：
  - `ntp.aliyun.com`
  - `time1.cloud.tencent.com`
  - `time2.cloud.tencent.com`
  - `ntp.ntsc.ac.cn`
  - `cn.pool.ntp.org`
- 默认启用 `chrony` 服务。

### 设备驱动和运行时服务

- 构建时下载并安装上游 `kernel-bundle-7.1` 中的所有 `.deb` 包。
- 当前已知 bundle 包包括：
  - `linux-xiaomi-sheng.deb`
  - `firmware-xiaomi-sheng.deb`
  - `alsa-xiaomi-sheng.deb`
  - `fastrpc_1.0.2-1_arm64.deb`
  - `libssc_0.4.2-1_arm64.deb`
  - `iio-sensor-proxy_99993.8-6_arm64.deb`
  - `sheng-sensors_20240917-1_arm64.deb`
  - `sheng-devauth.deb`
- 额外下载并安装 `xiaomi-mipps-auth_0.11_arm64.deb`。
- 不默认安装旧的 `firmware-sheng-wififix.deb`，因为当前上游系统测试 Wi-Fi 正常。
- RootFS 脚本负责安装当前目录下已有的 `.deb` 包。
- 启用设备相关服务：
  - `rmtfs`
  - `qrtr-ns`
  - `iio-sensor-proxy`
  - `sheng-sensors`
  - `sheng-devauth`
  - `fastrpc`
- 补充 Qualcomm/设备相关运行时包：
  - `qrtr-tools`
  - `rmtfs`
  - `tqftpserv` / `pd-mapper` 尝试安装，失败则跳过
- 不从 apt 安装 Debian 原版 `iio-sensor-proxy`，优先使用 kernel bundle 中的设备定制版本。

### 音频、蓝牙、电源和传感器

- 安装 PipeWire 音频栈：
  - `pipewire`
  - `pipewire-audio`
  - `pipewire-pulse`
  - `wireplumber`
- 安装 ALSA 工具：
  - `alsa-utils`
  - `pavucontrol`
- 启用全局用户服务：
  - `pipewire`
  - `pipewire-pulse`
  - `wireplumber`
- 安装蓝牙组件：
  - `bluez`
  - `blueman`
- 启用 `bluetooth` 服务。
- 安装电源和亮度相关组件：
  - `upower`
  - `power-profiles-daemon`
  - `brightnessctl`
- 启用 `power-profiles-daemon` 服务。
- 使用 bundle 中的 `iio-sensor-proxy` 和 `sheng-sensors` 处理传感器相关功能。

### GPU / Mesa Freedreno / Turnip

- 新增独立的 Mesa Freedreno / Turnip 构建 workflow。
- 默认 Mesa 版本改为 `25.2`。
- 支持手动指定 Mesa 分支、tag 或 commit。
- Freedreno KMD 默认配置为 `msm,kgsl`，适配 SM8550 / Android 内核场景。
- Mesa 安装路径改为 `/opt/mesa-freedreno`，避免直接覆盖 Debian 系统 Mesa 文件。
- Mesa deb 包名为 `mesa-freedreno-turnip-opt`。
- 通过 `/etc/profile.d/mesa-freedreno.sh` 配置运行时环境变量。
- 通过 `/etc/environment.d/90-mesa-freedreno.conf` 配置系统环境。
- 通过 `/etc/ld.so.conf.d/mesa-freedreno.conf` 添加 Mesa 库路径。
- 构建 Gallium 驱动：
  - `freedreno`
  - `zink`
  - `softpipe`
- 构建 Vulkan 驱动：
  - `freedreno`
- 禁用 LLVM，避免额外构建依赖。
- 移除旧配置中的 `swrast`，改用 `softpipe` 作为软件渲染兜底。
- Debian 镜像 workflow 可通过 `mesa_release_tag` 选择是否内置该 Mesa 驱动包。

### 系统工具补充

- 安装常用调试和硬件工具：
  - `pciutils`
  - `usbutils`
  - `kmod`
  - `mesa-utils`
  - `vulkan-tools`
- 安装图形运行时基础库：
  - `libdrm2`
  - `libglvnd0`
  - `libgl1`
  - `libegl1`
  - `libgles2`
  - `libgbm1`
  - `libvulkan1`

### 清理和打包

- 构建完成后清理 apt 缓存和临时 `.deb`。
- 使用固定 filesystem UUID：
  - `ee8d3593-59b1-480e-a3b6-4fefb17ee7d8`
- 使用 `img2simg` 转换 sparse 镜像。
- 使用 `7z` 压缩最终镜像。
- 输出文件格式示例：
  - `debian_trixie_gnome_dual_YYYYMMDD_HHMMSS.7z`