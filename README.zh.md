<p align="center">
  <img src="docs/screenshots/icon.png" alt="Tutti app icon" width="128" height="128">
</p>

<h1 align="center">Tutti</h1>

<p align="center"><em>One sound, every speaker.</em></p>

<p align="center">macOS 菜单栏小工具，让任意几个输出设备同时播放同一份声音。</p>

<p align="center"><a href="README.md">English README</a></p>

<!-- TODO screenshots:
  docs/screenshots/menubar.png  - 菜单栏图标三态（待机 / 输出 / 静音）
  docs/screenshots/popover.png  - popover 打开，勾选 2 个以上设备，滑杆可见
  docs/screenshots/settings.png - Settings -> 许可 tab 激活状态（扇贝徽章 + key）
-->

## 功能

- **多设备同时输出**：在菜单栏勾选多个输出，自动创建聚合设备（Aggregate Device）并设为系统默认输出。
- **单设备直通**：只选一个时直接切换系统默认输出，不创建多余的虚拟设备。
- **主音量 / 单设备音量**：滑杆既能整体推拉，也能单独调每一台。
- **主静音 / 单设备静音**：把一台单独静音，其他的继续放。
- **三态状态指示**：区分「全部输出中」「部分静音」「全部静音」，文案与色点同步。
- **硬件音量键接管**（Pro）：键盘音量增减、静音键直接控制聚合输出，Shift+Option 细调步长与系统一致。需要「辅助功能」权限。
- **蓝牙耳机电量**：识别到的蓝牙输出在设备名旁边显示电量。
- **外部切换感知**：在系统设置或控制中心切走默认输出时，自动销毁聚合设备并同步选中状态。
- **孤儿设备清理**：启动时清掉上次崩溃残留的聚合设备，以及旧版 MultiOut 残留。
- **浅色 / 深色 / 跟随系统**主题切换。
- **开机自启** 与 **GitHub Releases 自动检查更新**。

## 场景

- **多人共听**：客厅音箱加蓝牙耳机一起放，朋友戴耳机你外放，互不影响。
- **直播 / 演示 / 录课**：自己用耳机预听，同时外放给观众或推到采集卡。
- **多房间播放**：一台 Mac 同时驱动客厅和卧室两套有线音箱。
- **协作监听**：和别人共用一台 Mac，两副耳机同时插上都能听。
- **教学**：老师耳机里听讲解和提示音，教室音箱放给学生。

## Tutti Pro

每次新安装会自动开启 **7 天 Pro 试用**，无需激活码。试用结束后所有免费功能照常使用。

Pro 解锁一个重度用户专属的便利特性：**硬件音量键接管**。Mac 自带键盘上的音量键（以及支持的外接键盘音量键）直接控制聚合输出，不用再一台一台调整滑杆。

- **$7.99 一次买断**，不订阅。
- **一码 2 台 Mac**，在 Settings -> 许可 里随时激活、停用。
- **未来所有 Pro 新功能免费升级**。

[获取 Tutti Pro 激活码](https://tutti.recents.com/buy)

## 多语言

支持 9 种语言：简体中文、繁体中文、English、日本語、한국어、Français、Deutsch、Italiano、Español。

## 系统要求

- macOS 13.0 或更高
- 仅在使用 Pro 的硬件音量键接管时，需要授予「辅助功能」权限

## 构建

```bash
brew install xcodegen
cd tutti
xcodegen generate
xcodebuild -project Tutti.xcodeproj -scheme Tutti build
```

## 许可

Tutti 采用「源码公开」（Source-Available）模式发布，基于 [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0) 协议。

任何人都可以免费下载、编译、使用 Tutti，前提是仅用于个人且非商业的场景。

> **对开发者**：可以克隆本仓库并自行编译。但根据 PolyForm 协议，不能将本代码或修改后的版本用于商业牟利，比如打包到应用商店售卖，或作为付费服务的一部分。
