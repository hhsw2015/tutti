# Tutti v0.3.1 — 蓝牙发现 + 一键重连

**日期**：2026-05-27
**状态**：设计批准，待 Phase 1 spike 验证
**作者**：Barry × Claude
**前置背景**：v0.3.0 整体 park（AirPlay + 蓝牙都撞 macOS 26 限制），见 `TODO.md`

---

## Context

Tutti 的产品定位升级到「替代 macOS 系统音量图标」之后，设备列表必须追平系统声音菜单。当前缺口：

1. **已配对但未连接的蓝牙设备**（如猫王 OTR、未戴上的 AirPods）—— 系统菜单里直接列出且可一键连接，Tutti 看不到
2. **AirPlay 设备**（HomePod、Apple TV、其他 Mac）—— v0.3.2 处理

v0.3.0 时尝试用 IOBluetooth 直接 link 进 Tutti 主进程，macOS 26 TCC 在 `+[IOBluetoothCoreBluetoothCoordinator sharedInstance]` 触发 SIGABRT，即使有 `NSBluetoothAlwaysUsageDescription` plist key 也无效，结论是「主进程直接 link IOBluetooth + Hardened Runtime」路径死了。

本设计改走**主进程零 IOBluetooth 依赖 + bundled CLI subprocess** 的方案，绕开 TCC 主进程检查的同时保留完整重连能力。

---

## 锁定决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 范围 | 仅蓝牙；AirPlay 推 v0.3.2 | 蓝牙路径清晰（system_profiler + blueutil）能尽快交付；AirPlay 还要 spike |
| Pro gate | 无（全 Free） | 「替代系统菜单」是产品定位的基础能力，gate 起来会破坏定位 |
| 发现路径 | `system_profiler SPBluetoothDataType -json` subprocess | 项目已用（BluetoothBattery.swift），不触发 TCC，公开命令 |
| 重连路径 | bundled `blueutil` MIT binary，subprocess `--connect MAC` | Terminal.app sanity 验证：TCC 走「调用方 responsible process 授权」路径，弹标准系统弹窗后能用 |
| 超时 | 5s 主动 kill；3s failed 回退；0.5s 轮询 | 5s 够覆盖 AirPods（~1-2s）+ 外接耳机（~3-4s），实测后再调 |
| Core Audio 集成 | 重连成功 → 等 1.5s + 重试 1s → addToSelection | 不切换默认输出（不抢占当前路由） |
| Profile 兼容 | 零额外代码（降级体验） | profile apply 时未连蓝牙设备不进 selectedIDs（HAL 查不到 ID）；用户手动重连后通过 `handleBluetoothConnected` 加入当前聚合，独立于 profile 上下文 |

---

## Spike 前置验证（已完成 2026-05-27）

1. ✅ `brew install blueutil` 装上 v2.13.0（149KB universal）
2. ✅ `otool -L /opt/homebrew/bin/blueutil`：直接 link IOBluetooth.framework，adhoc 签名，无 Info.plist
3. ✅ Terminal.app 跑 `blueutil --paired`：macOS 弹「终端.app 想要使用蓝牙」标准授权弹窗 → 用户允许 → 干净返回完整 paired 列表（含猫王 OTR `f0-85-c1-a9-bd-e2`、AirPods Pro 1/2、HomePod 2/3、Apple TV 等）

**结论**：TCC 走「调用方 responsible process」路径。bundled 进 Tutti.app 后，首次 blueutil 调用应触发「Tutti 想要使用蓝牙」标准授权弹窗，授权后即可使用。

**Phase 1 还需 spike 的**：bundled blueutil（Developer ID 重签 + Hardened Runtime + notarized + bundled 进 .app）实际跑通 `--paired` 和 `--connect`。预计 0.5 天内拿结论。

---

## 架构总览

```
┌────────────────────────────────────────────────────────────┐
│                      MenuBarView                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │DevicesCapsule│  │BluetoothCapsule│ │ ProfilesCapsule │  │
│  │  (本地多选)  │  │ (已配对未连接) │  │                  │  │
│  └──────┬───────┘  └────────┬─────┘  └──────────────────┘  │
└─────────┼────────────────────┼──────────────────────────────┘
          │                    │
          ▼                    ▼
┌──────────────────┐   ┌──────────────────────────────┐
│AudioDeviceManager│◀──│   BluetoothDeviceMonitor     │
│  (Core Audio HAL)│   │   @Published pairedDevices   │
│                  │   │   @Published rowStates       │
│  onBluetoothConn │   │                              │
│  ected → 自动勾选│   │  ┌──────────┐  ┌──────────┐  │
└──────────────────┘   │  │ Discovery│  │ Reconnect│  │
                       │  │  Service │  │ Service  │  │
                       │  └────┬─────┘  └────┬─────┘  │
                       └───────┼─────────────┼────────┘
                               ▼             ▼
                  ┌────────────────────┐ ┌─────────────────┐
                  │ /usr/sbin/         │ │ <Bundle>/       │
                  │ system_profiler    │ │ Resources/bin/  │
                  │ SPBluetoothDataType│ │ blueutil        │
                  │ -json (subprocess) │ │ (subprocess)    │
                  └────────────────────┘ └─────────────────┘
```

**关键 invariant**：Tutti 主进程**完全不 link IOBluetooth.framework**。蓝牙能力只通过两个 subprocess 暴露。

---

## 文件清单

| 文件 | 操作 | 大致行数 |
|---|---|---|
| `Tutti/BluetoothDeviceMonitor.swift` | 新建（与 v0.3.0 同名不同实现，完全重写） | ~150 |
| `Tutti/BluetoothReconnector.swift` | 新建（blueutil subprocess actor） | ~80 |
| `Tutti/AudioDeviceManager.swift` | 加 `onBluetoothConnected(name:)` 钩子 + `handleBluetoothConnected` | +40 |
| `Tutti/MenuBarView.swift` | 新增 `BluetoothCapsule` / `BluetoothRow` struct | +120 |
| `Tutti/Localizable.xcstrings` | 新 4 个 keys × 9 语言 | +36 entries |
| `Tutti/Resources/bin/blueutil` | 新增（bundle 第三方 binary，universal） | ~150KB |
| `project.yml` | resources 加 `bin/blueutil`；`NSBluetoothAlwaysUsageDescription` | +6 行 |
| `scripts/release.sh` | bundle 前先签 blueutil + 验证签名 | +10 行 |
| `scripts/blueutil.version` | 新增（SHA256 + 版本号，供应链审计） | 2 行 |
| `TuttiTests/SystemProfilerParseTests.swift` | 新建 | ~80 |
| `TuttiTests/BluetoothRowStateTests.swift` | 新建 | ~60 |
| `TuttiTests/BluetoothMonitorReconnectTests.swift` | 新建 | ~120 |

---

## 数据模型

```swift
struct PairedBluetoothDevice: Identifiable, Equatable {
    let id: String          // normalized MAC，稳定 key
    let name: String        // 来自 system_profiler
    let macAddress: String  // 大小写格式（blueutil 传参用）
    let isConnected: Bool   // system_profiler 当前状态
    let batteryLevel: Int?  // 复用 BluetoothBattery
}

enum BluetoothRowState: Equatable {
    case idle
    case connecting(deadline: Date)   // now + 5s
    case failed(until: Date)          // failure 时刻 + 3s
}

@MainActor
final class BluetoothDeviceMonitor: ObservableObject {
    @Published private(set) var pairedDevices: [PairedBluetoothDevice] = []
    @Published private(set) var rowStates: [String: BluetoothRowState] = [:]  // key = MAC
    var onConnected: ((String) -> Void)?  // 注入 AudioDeviceManager.handleBluetoothConnected

    func warm() async                                       // app launch 预热
    func refresh() async                                    // popover open / reconnect 轮询
    func reconnect(_ device: PairedBluetoothDevice) async
    var displayableDevices: [PairedBluetoothDevice] {
        pairedDevices.filter { !$0.isConnected && !isInCoreAudio($0) }
    }
}

actor BluetoothReconnector {
    enum Result { case connected, timedOut, blueutilFailed(stderr: String) }
    func reconnect(macAddress: String, timeout: TimeInterval = 5) async -> Result
}
```

---

## 发现流程

**调用模型**（复用 `BluetoothBattery.swift` 模式）：

```swift
private func runSystemProfiler() async -> Data {
    // /usr/sbin/system_profiler SPBluetoothDataType -json
    // - stderr → /dev/null (避免 16KB pipe buffer 死锁)
    // - utility 优先级 detached Task
    // - 10s 上限（防 system_profiler 卡死，正常 1-2s）
}
```

**触发点**：

| 触发 | 时机 |
|---|---|
| App launch 预热 | `AppDelegate.applicationDidFinishLaunching` 调 `monitor.warm()` (非阻塞) |
| Popover 即将显示 | `StatusItemController` 弹出回调调 `monitor.refresh()` |
| Reconnect polling | `reconnect()` 内部 0.5s 一次 |

**不做后台轮询**：subprocess fork 开销大，会拖电池续航。

**JSON 解析 + 设备类型过滤**：

```swift
private static let audioMinorTypes: Set<String> = [
    "Headphones", "Headset", "Speakers", "Carkit", "AudioDevice"
    // 不要 Keyboard / Mouse / Trackpad / Phone / Computer / Watch / TV
]
```

**去重逻辑**：system_profiler 名字 vs Core Audio HAL 名字用 `BluetoothBattery.normalize`（小写 + 去空格 + 去标点）匹配。

---

## 重连流程

```swift
func reconnect(_ device: PairedBluetoothDevice) async {
    let mac = device.macAddress
    rowStates[mac] = .connecting(deadline: Date().addingTimeInterval(5))

    // 1. 启动 blueutil subprocess (并行)
    let reconnectTask = Task.detached(priority: .userInitiated) {
        await BluetoothReconnector().reconnect(macAddress: mac, timeout: 5)
    }

    // 2. 0.5s 轮询 system_profiler 看 device_connected
    let pollDeadline = Date().addingTimeInterval(5)
    while Date() < pollDeadline {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await refresh()
        if pairedDevices.first(where: { $0.macAddress == mac })?.isConnected == true {
            rowStates[mac] = .idle
            reconnectTask.cancel()
            await scheduleCoreAudioPickup(deviceName: device.name)
            return
        }
    }

    // 3. 5s 超时
    reconnectTask.cancel()
    rowStates[mac] = .failed(until: Date().addingTimeInterval(3))
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        rowStates[mac] = .idle
    }
}

private func scheduleCoreAudioPickup(deviceName: String) async {
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    onConnected?(deviceName)
}
```

**为什么轮询 system_profiler 而不是等 blueutil 返回**：blueutil `--connect` 是同步阻塞调用，连不上会等到自己的 ~10s 超时才退；用户体验差。轮询能让我们 5s 主动叫停。

**`AudioDeviceManager` 钩子**：

```swift
var onBluetoothConnected: ((String) -> Void)?

func handleBluetoothConnected(name: String) {
    refreshDevices()
    let normalized = BluetoothBattery.normalize(name)
    guard let match = devices.first(where: {
        BluetoothBattery.normalize($0.name) == normalized
    }) else {
        // 1.5s 还没到 HAL，等 1s 重试一次（最多一次）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            refreshDevices()
            if let retry = devices.first(where: {
                BluetoothBattery.normalize($0.name) == normalized
            }) {
                addToSelection(retry.id)
            }
        }
        return
    }
    addToSelection(match.id)
}

private func addToSelection(_ id: AudioDeviceID) {
    guard !selectedIDs.contains(id) else { return }
    selectedIDs.insert(id)
    updateAggregate()
}
```

---

## UI 设计

**位置**：MenuBarView 主视图垂直顺序：

```
Devices  (本地多选)
Bluetooth (已配对未连接)  ← 新增
Profiles (Pro)
```

**显示规则**：`displayableDevices.isEmpty` 时 capsule 整个隐藏。

**BluetoothCapsule 结构**：

```
┌─ 已配对蓝牙 ─────────────────────────────┐
│  ┌──────────────────────────────────┐   │
│  │ 🎧  猫王 OTR        🔋 65%  ◯    │   │  ← .idle
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ 🎧  AirPods Pro    连接中... ⟳   │   │  ← .connecting
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ 🎧  Sony WH-1000   连接失败  !   │   │  ← .failed (红字 3s)
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

**行视觉**（复用 `GlassDeviceRow` 模式 `MenuBarView.swift:764-868`）：
- 高度与 DevicesCapsule 行一致
- 左侧 SF Symbol：按 `device_minorType`
  - Headphones / Headset → `headphones`
  - Speakers → `hifispeaker.fill`
  - Carkit → `car.fill`
  - 兜底 → `dot.radiowaves.left.and.right`
- 中间：设备名
- 右侧：
  - `.idle`：电量 chip（如有）+ 圆形 idle 图标
  - `.connecting`：「连接中...」+ 旋转 `arrow.triangle.2.circlepath`
  - `.failed`：红色「连接失败」+ `exclamationmark.circle.fill`

**SectionHead**：复用 `SectionHead` (`MenuBarView.swift:388-391`)，标题「已配对蓝牙」/「Paired Bluetooth」。

**点击区**：整行 hit-target，`.connecting` 状态下整行可再点 = 取消。

**动画**：
- 行进入/退出：`.spring(response: 0.35)`
- `.connecting` → `.idle`：行直接消失（移到 DevicesCapsule 已勾选）
- `.failed`：红字 fade-in，3s 后 fade-out 回 `.idle` 图标

**xcstrings 新 keys**（9 语言）：

| Key (中文 source) | 用途 |
|---|---|
| `已配对蓝牙` | SectionHead |
| `连接中...` | .connecting |
| `连接失败` | .failed |
| `需要蓝牙权限` | TCC 拒绝兜底 |

英文：`Paired Bluetooth` / `Connecting…` / `Failed to connect` / `Bluetooth permission required`。

**Accessibility**：整行 `.accessibilityLabel`：「猫王 OTR，已配对未连接，电量 65%，双击连接」。`.connecting` 时 label 改成「连接中」。

---

## blueutil Bundling + 签名

**获取**：
- 从 https://github.com/toy/blueutil release 拿 universal binary（v2.13.0）
- 或从 `brew install blueutil` 拷出 `/opt/homebrew/bin/blueutil`
- SHA256 + 版本写到 `scripts/blueutil.version`（供应链审计）

**项目位置**：

```
tutti/
├── Tutti/
│   └── Resources/
│       └── bin/
│           └── blueutil              ← git tracked, executable
├── scripts/
│   ├── blueutil.version              ← SHA256 + 版本
│   └── release.sh                    ← 改动
└── project.yml                       ← 改动
```

**project.yml 改动**：

```yaml
targets:
  Tutti:
    info:
      properties:
        NSBluetoothAlwaysUsageDescription: "Tutti needs Bluetooth to reconnect your paired headphones and speakers."
    resources:
      - path: Tutti/Resources/bin/blueutil
        type: file
```

**Swift 调用**：

```swift
struct BlueutilLauncher {
    static var binaryURL: URL {
        guard let url = Bundle.main.url(
            forResource: "blueutil",
            withExtension: nil,
            subdirectory: "bin"
        ) else {
            fatalError("blueutil missing from bundle — release script broken")
        }
        return url
    }
}
```

**`scripts/release.sh` 改动**：

```bash
# 1. xcodebuild 之后、codesign 主 app 之前，先签 blueutil
codesign --force --sign "$IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements /dev/null \
  "$APP_PATH/Contents/Resources/bin/blueutil"

# 2. 验证 blueutil 签名链
codesign --verify --verbose "$APP_PATH/Contents/Resources/bin/blueutil"

# 3. 然后才签主 app（已有逻辑）
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" "$APP_PATH"

# 4. notarize 整个 .app（已有逻辑会自动 traverse nested binary）
xcrun notarytool submit "$ZIP" --keychain-profile "tutti-notary" --wait

# 5. stapler 整个 .app
xcrun stapler staple "$APP_PATH"
```

**关键点**：
- blueutil 用 `--options runtime`（Hardened Runtime） —— Notarization 要求
- `--entitlements /dev/null`：blueutil 不要自己的 entitlements，继承主 app 的 TCC 域
- Notarytool 会自动 traverse `Contents/Resources/` 内所有 mach-O；签错整个 app 都过不了 notarize

**Pre-flight 验证脚本** `scripts/verify-bluetooth.sh`：

```bash
#!/bin/zsh
# 在 build 完 .app 之后跑：
./build/Tutti.app/Contents/Resources/bin/blueutil --paired
# 期望：返回当前所有已配对设备列表，exit 0
# 失败：签名问题或 TCC 拦截，spike 路径要重评
```

---

## 错误处理 + 边界 case

| 场景 | 行为 |
|---|---|
| TCC 未授权（首次） | 主进程用 `CBCentralManager.authorization` 查状态。`.notDetermined` → 直接调 blueutil（触发系统弹窗）。`.denied` → 行内「需要蓝牙权限」+ 链接 `x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth` |
| 设备不在范围/没电 | blueutil 自身 ~10s 超时；Tutti 5s 主动 kill → `.failed(until: now+3s)` |
| MAC 地址错误 | exit code 非 0 → `.failed` |
| blueutil binary 缺失 | `fatalError("blueutil missing")` —— release 流程坏了 |
| 用户在 .connecting 中关 popover | 状态机继续跑（actor 隔离），下次开 popover 看结果 |
| 用户在 .connecting 中再次点同行 | 取消 subprocess + 设回 .idle |
| 用户在 .connecting 中点别的设备 | 串行：第二次点击 no-op 直到第一次完成 |
| system_profiler 在 polling 中失败 | 单次失败不致命，下次轮询重试 |
| blueutil --connect 卡死 | 5s 超时 `process.terminate()` 兜底 |
| Tutti app 被 kill -9 | blueutil 是 child，默认 process group 行为带走 |
| 重连成功但 Core Audio 未注册 | 1.5s + 重试 1s 仍无 → 放弃 onConnected；设备从 displayableDevices 消失，用户手动在 DevicesCapsule 勾选 |
| 用户无内建 BT（USB dongle 拔出） | `system_profiler` 输出空 `SPBluetoothDataType` → `pairedDevices = []` → capsule 隐藏 |
| macOS 26 蓝牙服务挂掉 | `bluetoothd` ~2s 重启期间 stale 数据，可接受 |
| 设备名含特殊字符（如「猫王·小王子 OTR」） | blueutil --connect 用 MAC 不用 name，规避 |
| system_profiler JSON schema 变化 | `if let` + 默认值 fallback；整组解析失败显示空列表，不崩 |

**`CBCentralManager.authorization` 是 CoreBluetooth 公开 API**，查询不触发 IOBluetooth TCC 检查。这是关键的「探测器」，让我们在调 blueutil 之前知道授权状态，精准 UX 引导。

---

## 测试

**单测**（新增到 `TuttiTests` target）：

| 测试 | Fixture | 期望 |
|---|---|---|
| `SystemProfilerParseTests` | `SPBluetoothDataType` JSON（含 connected/not_connected、AirPods 多 battery key、HomePod 非音频干扰） | 解析正确 `[PairedBluetoothDevice]`，过滤非音频类型 |
| `BluetoothRowStateTests` | 时间线 now / +0.5s / +5s / +5.5s / +8s / +8.5s | `.idle` → `.connecting` → `.failed` → `.idle` 转换 |
| `BluetoothMonitorReconnectTests` | mock subprocess + mock system_profiler | 5s 内连上：状态机 idle / 1.5s 等待 / onConnected 回调；超时：failed 3s → idle |
| `DeviceDeduplicationTests` | system_profiler "猫王·小王子 OTR" + HAL "猫王 OTR" 大小写不同 | normalize 后去重 |
| `AudioDeviceManagerHookTests` | mock `onBluetoothConnected(name:)` | 找到匹配 → addToSelection；没找到 → 1s 重试 1 次；仍无 → 放弃 |

**手测脚本**（v0.3.1 发版前必跑）：

1. **清状态**：`tccutil reset Bluetooth com.recents.tutti` → 启动 Tutti
2. **首启发现**：popover 打开 → 看到「已配对蓝牙」组列出当前未连接设备
3. **首次重连触发 TCC 弹窗**：点猫王 OTR（先断蓝牙）→ macOS 弹「Tutti 想要使用蓝牙」→ 允许 → 5s 内连上 → 行消失 → 自动加入聚合
4. **第二次重连无弹窗**：断 soundcore → 点重连 → 直接连上
5. **超时失败**：猫王离开蓝牙范围 → 点重连 → 5s 后红色「连接失败」→ 3s 自动回 idle
6. **取消**：点 AirPods Pro 1 → `.connecting` 中再点 → 立即取消
7. **TCC 拒绝路径**：`tccutil reset Bluetooth com.recents.tutti` → 重启 → 点未连设备 → 弹窗 → **拒绝** → 行内「需要蓝牙权限」+ 链接系统设置
8. **不切换默认输出**：默认输出 Mac 扬声器 → 重连猫王 → 猫王进聚合 + 内置仍是默认
9. **Profile 降级体验**：保存含猫王的 profile → 关猫王 → apply profile → 猫王不进当前 selectedIDs（HAL 找不到 ID） → 蓝牙 capsule 显示猫王为未连接 → 用户点重连 → 连上后通过 `handleBluetoothConnected` 加入聚合（独立于 profile，零额外代码）
10. **app 退出清理**：reconnect 中关 Tutti → `ps aux | grep blueutil` 无残留

**性能验收**：
- `system_profiler` 调用：utility 优先级 + 1-2s
- App launch 预热不阻塞 UI（detached Task）
- Popover 打开时 cache 已暖，列表瞬显（< 50ms）

**构建验收**：
- `xcodegen` 重新生成 pbxproj 通过
- `xcodebuild build` 干净，无新 warning
- `scripts/release.sh` 跑通：blueutil 签名 → 主 app 签名 → notarize → staple
- `codesign --verify --verbose --deep Tutti.app` 通过
- `spctl --assess --verbose Tutti.app` 报 `accepted, source=Notarized Developer ID`
- 装到 `/Applications` → 跑手测脚本

---

## 工期

| 阶段 | 工作 | 时间 |
|---|---|---|
| Phase 1 | bundled blueutil spike 验证（codesign + Hardened Runtime + plist + 实测） | 0.5 天 |
| Phase 2 | `BluetoothDeviceMonitor` + `BluetoothReconnector` 实现 + 单测 | 0.5 天 |
| Phase 3 | `AudioDeviceManager` 钩子 + `MenuBarView` BluetoothCapsule UI | 0.5 天 |
| Phase 4 | xcstrings 翻译 + plist NSBluetoothAlwaysUsageDescription + 9 语言 | 0.25 天 |
| Phase 5 | 联调 + 手测 + 修 bug | 0.25 天 |
| Phase 6 | release.sh 改动 + 完整签名 notarize 一次通 | 0.25 天 |
| **合计** | | **~2.5 天** |

---

## 风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| bundled blueutil + Hardened Runtime + Developer ID 重签后 TCC 仍拦 | 低（Terminal sanity 已通） | 阻塞 | Phase 1 spike 1 小时内拿结论；失败回退到 ObjC 私有 API 方向 |
| `NSBluetoothAlwaysUsageDescription` 中文 source 触发 plist 国际化 bug | 中（v0.2.1 已知 plist 翻译脆） | 仅影响弹窗文案 | source 用英文，弹窗仍清晰 |
| macOS 27 收紧 subprocess TCC 路径 | 未知 | 整方案重做 | 不可控；blueutil 路径至少撑到 macOS 27 GA |
| blueutil 项目停止维护 | 低 | 需自己 fork | 149KB 单源 ObjC，fork 容易 |
| 设备名含特殊字符 | 低 | 单设备无法重连 | blueutil --connect 用 MAC，规避 |
| system_profiler JSON schema 变化 | 低 | 解析失败 | `if let` fallback，整组解析失败显示空列表，不崩 |

---

## v0.3.1 范围外（v0.3.2+ 处理）

- AirPlay 设备发现 + 切换（HomePod / Apple TV / 其他 Mac）
- **副发现**：blueutil --paired 列表里包含 HomePod 2/3、Barry's TV 等 AirPlay 设备的 Bluetooth-paired 记录。这条信号可以作为 v0.3.2 AirPlay 发现的补充路径（比纯 mDNS 更可靠地知道「用户曾经配对过哪些 AirPlay 设备」）
- AirPlay 独占模式（`OutputMode` 状态机、`AggregateSnapshot` 持久化）
- Pro gate（v0.3.1 全 Free，未来若引入 AirPlay 多房间同步等增值功能再考虑）
