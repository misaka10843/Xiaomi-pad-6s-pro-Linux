# misaka10843 自用构建说明

本分支基于上游 `code002-2/Xiaomi-pad-6s-pro-Linux` 的 `sheng` 分支同步，并在上游构建流程基础上加入了一些自用改动。主要目标是构建适合小米 Pad 6S Pro 的 Debian 13 KDE 双系统镜像。

上游项目地址：

```text
https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux
````

本分支当前重点不是重新维护一套完整发行版，而是在上游脚本的基础上补充中文环境、KDE 桌面、Flatpak、时间同步、可选显驱等内容。

---

## 当前做了哪些改动

### 1. Debian 13 KDE 镜像构建

默认推荐构建：

```text
Debian 13 Trixie
KDE Plasma
dual 双系统模式
```

也仍然保留上游的矩阵参数，可以选择：

```text
desktop_env: kde / gnome / all
boot_mode: dual / single / all
```

但自用建议优先选择：

```text
desktop_env: kde
boot_mode: dual
```

KDE 方案使用 `kde-plasma-desktop` 为基础，并加入常用组件：

```text
sddm
plasma-nm
bluedevil
powerdevil
dolphin
konsole
systemsettings
ark
spectacle
gwenview
okular
```

这样比完整 `kde-standard` 更轻一些，适合 8GB 内存设备。

---

### 2. 中文系统，但用户目录保持英文

系统默认语言为：

```text
zh_CN.UTF-8
```

时区为：

```text
Asia/Shanghai
```

但用户目录会强制保持英文：

```text
Desktop
Downloads
Documents
Pictures
Music
Videos
Templates
Public
```

这样可以避免中文目录在终端、脚本、Steam、Flatpak 或部分 Linux 程序里造成路径问题。

---

### 3. 输入法改为 fcitx5 + Rime

默认安装：

```text
fcitx5
fcitx5-chinese-addons
fcitx5-rime
fonts-noto-cjk
fonts-wqy-microhei
fonts-wqy-zenhei
```

同时写入输入法环境变量：

```text
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
INPUT_METHOD=fcitx
SDL_IM_MODULE=fcitx
```

KDE/Qt 环境下使用 fcitx5 通常比 ibus 更自然。

---

### 4. 使用 chrony 自动同步时间

加入并启用 `chrony`，用于自动同步时间。配置了国内常用 NTP 源：

```text
ntp.aliyun.com
time1.cloud.tencent.com
time2.cloud.tencent.com
ntp.ntsc.ac.cn
cn.pool.ntp.org
```

双系统切换、RTC 时间异常、首次联网后时间不准时，chrony 会比默认方案更稳一些。

---

### 5. Firefox 默认使用 Mozilla 官方 ARM64 版本

默认不安装 Debian `firefox-esr`，而是下载 Mozilla 官方 ARM64 tarball：

```text
https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=zh-CN
```

原因是大多数人更希望使用较新的 Firefox，而 ESR 大版本通常会落后正式版。

如果想用 Debian ESR，也可以在 GitHub Actions 里选择：

```text
firefox_channel: esr
```

---

### 6. 默认加入 Flatpak

默认安装 Flatpak 支持，方便安装 QQ 等软件：

```text
flatpak
xdg-desktop-portal
xdg-desktop-portal-kde
plasma-discover-backend-flatpak
```

并默认将 Flathub 切换到 USTC 镜像：

```text
https://mirrors.ustc.edu.cn/flathub
```

进系统后可以尝试：

```bash
flatpak install flathub com.qq.QQ
```

---

### 7. APT 源最终切换为 USTC

构建阶段使用 Debian 官方源，保证 GitHub Actions 构建稳定。

系统打包前会把最终系统内的 APT 源切换为中科大镜像：

```text
https://mirrors.ustc.edu.cn/debian
https://mirrors.ustc.edu.cn/debian-security
```

这样刷入后在国内更新软件会更快。

---

### 8. 额外驱动下载更严格

构建 RootFS 时会尝试下载额外上游 Release 包，默认只下载：

```text
sensor,MIPPS
```

其中 `sensor` Release 已经包含：

```text
fastrpc
iio-sensor-proxy
libssc
sheng-sensors
```

所以默认不会再额外下载：

```text
libssc
iio_sensor_patched
```

避免重复安装和旧包覆盖。

`sheng-devauth` 通常已经包含在 Kernel Bundle 里，所以默认也不额外下载。需要兜底时可以开启：

```text
download_devauth_fallback: true
```

---

### 9. Wi-Fi 修复包默认不安装

上游存在 Wi-Fi 修复包，但它属于故障修复用途，不适合默认覆盖正常固件。

默认：

```text
install_wifi_fix: false
```

如果刷入后 Wi-Fi 异常，再重新构建时开启：

```text
install_wifi_fix: true
```

---

### 10. Steam runtime 默认不安装

上游有 Steam ARM64 runtime / Proton 相关 Release，但这属于应用运行时，不是基础系统必需项。

默认：

```text
install_steam_runtime: false
```

建议系统能正常启动后，再按需手动安装或单独测试。

---

### 11. Mesa Freedreno / Turnip 显驱为可选注入

本分支恢复了显驱构建 workflow：

```text
.github/workflows/build-gpu-driver.yml
```

它会构建 Mesa Freedreno / Turnip，并打包为：

```text
mesa-freedreno-turnip-opt_*_arm64.deb
```

安装路径是：

```text
/opt/mesa-freedreno
```

它不会直接覆盖 Debian 系统 Mesa 文件。RootFS 构建时可以选择是否注入这个 deb。

默认：

```text
install_gpu_driver: false
```

第一次建议先不注入显驱，确认基础 KDE 镜像能正常启动后，再构建第二版并开启：

```text
install_gpu_driver: true
```

---

## 推荐构建流程

### 第一步：先构建基础 KDE 镜像

进入 GitHub Actions，运行：

```text
🌀 Build Debian 13 Desktop
```

推荐参数：

```text
kernel_version: 7.1
desktop_env: kde
boot_mode: dual
default_user: luser
default_pass: 自行填写
root_pass: 自行填写
firefox_channel: official
install_flatpak: true
install_gpu_driver: false
gpu_release_tag: mesa-freedreno-turnip-latest
image_size: 8G
extra_driver_tags: sensor,MIPPS
download_devauth_fallback: false
install_wifi_fix: false
install_steam_runtime: false
skip_release: false
```

第一次重点确认这些功能：

```text
系统能启动
KDE 能进入桌面
触摸正常
键盘/触摸板基本正常
Wi-Fi 正常
蓝牙正常
声音基本正常
自动旋转/传感器基本正常
```

---

### 第二步：可选构建 Mesa Freedreno / Turnip 显驱

如果基础系统正常，再运行：

```text
构建 Mesa Freedreno Turnip 驱动
```

推荐参数：

```text
mesa_ref: 25.2
build_type: release
freedreno_kmds: msm,kgsl
latest_release_tag: mesa-freedreno-turnip-latest
skip_release: false
```

构建成功后会创建或更新 Release：

```text
mesa-freedreno-turnip-latest
```

---

### 第三步：构建带显驱的 KDE 镜像

再次运行：

```text
🌀 Build Debian 13 Desktop
```

这次把：

```text
install_gpu_driver: true
```

其他参数保持一致即可。

如果显驱包不存在或安装失败，RootFS 构建不会中断，只会继续使用 Debian 默认 Mesa。

---

## 参数说明

### `desktop_env`

```text
kde    推荐，自用主目标
gnome  保留兼容
all    同时构建 GNOME 和 KDE，耗时更久
```

### `boot_mode`

```text
dual    推荐，双系统模式
single  单系统模式
all     同时构建 dual 和 single，耗时更久
```

### `extra_driver_tags`

默认：

```text
sensor,MIPPS
```

不建议默认加入：

```text
libssc
iio_sensor_patched
```

因为 `sensor` Release 已包含相关包。

### `download_devauth_fallback`

默认：

```text
false
```

Kernel Bundle 正常时不需要开启。只有怀疑缺少 `sheng-devauth` 时再开启。

### `install_wifi_fix`

默认：

```text
false
```

只有 Wi-Fi 异常时才建议开启。

### `install_steam_runtime`

默认：

```text
false
```

Steam runtime 不是基础系统组件，不建议默认进入镜像。

### `install_gpu_driver`

默认：

```text
false
```

建议先构建无显驱基础镜像，确认能正常启动后再开启。

---

## 刷写提醒

请先阅读上游 Wiki 和 README。刷写前确认：

```text
已解锁 bootloader
理解 dual / single 的区别
确认分区名和设备路径
确认 boot 镜像和 rootfs 镜像匹配
已备份数据
```

常见流程概览：

```text
1. 下载 rootfs 7z 和 boot 镜像
2. 解压 rootfs
3. 按上游教程分区
4. fastboot flash boot_b 对应 boot 镜像
5. fastboot flash linux 对应 sparse rootfs
6. 切换到对应 slot
7. 首次启动后扩容文件系统
```

首次进入系统后，如果是 dual 模式，一般需要按上游教程扩容：

```bash
sudo resize2fs /dev/sda30
```

具体设备路径请以上游教程和实际分区为准。

---

## 注意事项

本分支仍然属于实验性质。刷写、分区、替换 boot 镜像都有变砖风险。

建议先构建并测试：

```text
KDE + dual + install_gpu_driver=false
```

确认基础功能正常后，再尝试：

```text
install_gpu_driver=true
install_wifi_fix=true
install_steam_runtime=true
```

不要第一次就把所有可选项都打开。

# ⚠️ 警告 – 免责声明

**请仔细阅读此免责声明。**

我们不承担以下任何情况的责任：
- 设备变砖、恢复分区丢失
- 存储卡、电源管理芯片、内存、显示芯片、CPU 损坏
- 小米的任何意外操作
- 宠物或人员伤亡、核战争
- 因忘记切回 Android 导致闹钟未响而被解雇
- 地震海啸等任何自然灾害
- 刷机刷一半没吃饭饿死了
- 刷机刷一半没喝水渴死了
- 刷机刷一半忘记吸氧憋死了
- 因变砖引发任何疾病死了
- 因给我提Issues没有人回复气死了
- 等各种各样的原因

本仓库中的所有文件均由社区用户贡献。提供的指南及文件均为“按现状”提供，**请自行承担使用风险**，并严格遵循每一步骤。

我不会对您的设备因任何原因变砖负责，除非您愿意打钱：）

**如果您不熟悉平板改装、分区表操作或对设备变砖感到极度不安，请立即关闭此页面！您已经收到警告，任何后果自负！再次强调，您已收到警告！**

---

## 📊 功能状态（摘要）

|类别| 功能|状态| 备注|
|--------|------------|----------|--------------------------|
|核心|系统刷写|正常|仅限Debian|
|核心|屏幕/触摸|正常|含休眠/亮度/触摸|
|核心|键盘/触摸板|部分正常|官方键盘有概率无响应，需要重新与触点连接|
|连接|Wi-Fi|正常|部分地区需要设置wifi区域码才能正常使用5GHz Wifi|
|连接|蓝牙|正常||
|连接|Type-C|部分正常|Type-C与键盘触点冲突，官方键盘需要重新与触点连接才能正常检测|
|多媒体|音频/相机|正常|相机效果劣于Android|
|传感器|全部|正常|自动旋转/亮度/霍尔等|
|手写笔|测试|故障|只有笔充电可用，充电修复来自[xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status)|

> 完整功能状态表请查阅 [PostmarketOS wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6S_Pro_12.4_(xiaomi-sheng))

---

## 🔐 登录凭证

默认系统账户：

- **用户名**: `luser`
- **密码**: `luser`

---

## 📖 详细指南（Wiki）

所有安装、配置、切换系统的详细步骤均已移至 **Wiki**，请根据需求点击以下链接：

| 指南                                 | 说明                                     |
| ------------------------------------ | ---------------------------------------- |
| [📥 安装指南](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/安装指南) | 分区、刷写 rootfs 与 boot 镜像，首次扩容 |
| [🔄 切换操作系统](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/切换操作系统) | Android ↔ Linux 的无缝切换方法           |
| [⌨️ 官方键盘支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/官方键盘支持) | Pogo Pin 键盘认证服务配置                |
| [📡 传感器支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/传感器支持) | 加速度计、光线传感器等服务启用           |
| [🧩 推荐的 GNOME 扩展](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/推荐的GNOME扩展) | 提升平板触摸体验的扩展列表               |
| [steam安装教程](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/steam) | 适用于linux arm64的steam安装教程

---

## 🎥 软件测试视频

[小米pad6spro Debian启动！-哔哩哔哩](https://www.bilibili.com/video/BV1za5g6wEx8)

[小米pad6spro debian hangover wine+dxvk测试-哔哩哔哩](https://www.bilibili.com/video/BV1Be5y6ZEiK)

[小米pad6spro debian蓝牙手柄+vulkan小游戏测试-哔哩哔哩](https://www.bilibili.com/video/BV1rg516PEWt)

## 📝 快速预览（核心步骤）

如果你想快速了解安装流程，概览如下（详细操作请务必阅读 Wiki）：

1. 解锁 bootloader，确保仅有 Android 系统
2. 下载 `rootfs` 和 `boot` 镜像，以及 `parted` 工具
3. 通过 TWRP 和 `parted` 重分区（删除 userdata，新建 userdata + linux）
4. 刷写镜像到槽位 B：`fastboot flash boot_b` 和 `fastboot flash linux`
5. 激活槽位 B 并重启
6. 首次启动后执行 `sudo resize2fs /dev/sda30` 扩容

---

## ❤️ 致谢

感谢所有社区贡献者的测试与文件提供。
[@map220v](https://github.com/map220v) 主线内核开发，设备驱动等，
[@ianchb](https://github.com/ianchb) MIPPS快充补丁，触控笔充电，
[@alghiffaryfa19](https://github.com/alghiffaryfa19) 该设备项目的上游，
[@code002-2](https://github.com/code002-2) 二次开发改进

以及相关的贡献者

# 相关群组

[![Channel](https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram)](https://t.me/Pad_6S_Pro_Linux_Chat) [![QQ Group](https://img.shields.io/badge/Follow-QQ-12B7F5.svg?logo=qq&logoColor=white)](https://qun.qq.com/universal-share/share?ac=1&authKey=du2KyTQBUaKnU5ENPe5BD7r35s8t6m5qXuVHU656cEDmrpMVq0rTlUH1PuSLVN6n&busi_data=eyJncm91cENvZGUiOiIxMDkyMjc0NjU3IiwidG9rZW4iOiJQdDJqVnBGa1UzcFgyN0ZXSkxHYUhLbDhzZkN4N2g5d0ZoZFdFQkJyZVVMTzVkeitCTXArc2xKU1ZGRVpBd3VmIiwidWluIjoiMzQ5NzEzMDI2MSJ9&data=3eANpQ8g5VfxnuvZSz0QtAoD0D5o6yD7M9Gm8JQHbFs83icXp3G6bZYVVUHW47HKgL_Rq5ecivzzo8PNL8FCAQ&svctype=4&tempid=h5_group_info)

**谨慎操作 – 祝使用愉快！**
