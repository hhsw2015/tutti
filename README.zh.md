<p align="center">
  <img src="docs/screenshots/icon.png" alt="Tutti app icon" width="128" height="128">
</p>

<h1 align="center">Tutti</h1>

<p align="center"><em>One sound, every speaker.</em></p>

<p align="center">macOS 菜单栏小工具：让任意几个输出设备同时播放同一份声音。</p>

## 功能

- **多设备同时输出**：在菜单栏勾选多个输出，自动创建聚合设备（Aggregate Device）并设为系统默认输出
- **单设备直通**：只选一个时直接切换系统默认输出，不创建多余的虚拟设备
- **主音量 / 单设备音量**：滑杆既能整体推拉，也能单独调每一台
- **主静音 / 单设备静音**：长按一台静音，留下其他的继续放
- **三态状态指示**：全部输出中 / 部分静音 / 全部静音，状态文案与色点同步
- **硬件音量键接管**：聚合设备会让系统音量键失效，Tutti 通过 CGEventTap 全局拦截音量增减 / 静音键，同步到每一台子设备，Shift+Option 细调步长与系统一致（需"辅助功能"权限）
- **蓝牙耳机电量**：通过 `system_profiler SPBluetoothDataType` 读取已配对蓝牙输出的电量并显示
- **外部切换感知**：在系统设置或控制中心切走默认输出时，自动销毁聚合设备并同步选中状态
- **孤儿设备清理**：启动时清掉上次崩溃残留的聚合设备（以及旧版 MultiOut 残留）
- **浅色 / 深色 / 跟随系统**主题切换
- **开机自启** + **GitHub Releases 自动检查更新**

## 场景

- **多人共听**：客厅音箱 + 蓝牙耳机一起放，朋友戴耳机你外放，互不影响
- **直播 / 演示 / 录课**：自己用耳机预听，同时外放给观众或推到采集卡
- **多房间播放**：客厅 + 卧室的两套有线音箱同时驱动，做穷人版 AirPlay 多房间
- **协作监听**：和别人共用一台 Mac 时，两副耳机同时插上都能听
- **教学**：老师耳机里听讲解 / 提示音，教室音箱放给学生

## 特色

- 纯原生 Swift + SwiftUI + CoreAudio，无任何第三方依赖
- LSUIElement 常驻菜单栏，不占 Dock
- 菜单栏图标为自绘的 Broadcast Dot 三态可视化（待机 / 输出 / 静音）
- 中文界面优先，UX 文案为了"诚实表达部分静音状态"专门设计
- 退出 / 崩溃 / 系统切换默认输出时都会自动清理聚合设备，不会污染音频环境

## 系统要求

- macOS 13.0+
- 首次使用需授予"辅助功能"权限（用于接管硬件音量键）

## 构建

```bash
brew install xcodegen
cd tutti
xcodegen generate
xcodebuild -project Tutti.xcodeproj -scheme Tutti build
```

## 许可与商业模式

Tutti 采用 **"源码公开" (Source-Available)** 模式发布，而非传统的开源 (Open Source)。我们希望保持代码的透明度，与社区分享 CoreAudio 的技术实践，同时也能维持项目的健康运转。

本项目基于 [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0) 协议。

### 免费版（个人非商业用途）

任何人都可以免费下载、编译并使用 Tutti，前提是仅用于**个人且非商业**的场景。

免费版已包含绝大多数核心功能，唯一限制是：**最多同时输出到 2 个设备**。对于日常的"音箱 + 耳机"或双人共享耳机场景，免费版完全够用。

### Tutti Pro

如果您需要同时串联 **3 个及以上的音频设备**，或者希望在商业环境中使用（例如：商业录音棚、付费直播、公司办公环境等），需要购买 Pro 激活码。

购买 Pro 不仅能解除设备数量限制，也是对独立开发者持续维护项目的最大支持。

[获取 Tutti Pro 激活码](https://tutti.recents.com/buy) — 单次购买，买断制，支持 2 台 Mac 设备绑定。

> **对开发者的提示**：作为技术爱好者，您完全可以克隆本仓库并自行编译。但请注意，根据 PolyForm 协议，您不能将本代码或修改后的版本用于商业牟利（例如：打包到应用商店售卖，或作为付费服务的一部分）。
