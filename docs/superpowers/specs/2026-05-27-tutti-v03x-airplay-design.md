# Tutti v0.3.x — AirPlay 快捷入口

**日期**：2026-05-27
**状态**：设计批准，待 Phase 0 spike 验证
**作者**：Barry × Claude
**前置背景**：v0.3.0 蓝牙重连尝试 revert（系统自动重连已覆盖、Tutti 通过 Core Audio HAL 自动检测，手动入口冗余）。见 `2026-05-27-tutti-v031-bluetooth-design.md`（已 abandoned）

---

## Context

Tutti 的产品定位是「替代 macOS 系统音量图标」。当前缺口：

- 用户家有 HomePod / Apple TV / 其他 Mac 等 AirPlay 设备，想切到这些设备听音乐 / 看视频时，需要走 **Control Center → 声音 → 输出 → 找设备列表 → 点设备** 四步路径
- Tutti popover 是用户日常的音频集中入口，但目前完全不感知 AirPlay 设备

**用户痛点定位**（v0.3.x brainstorm 锁定）：**点击路径太长**，不是行为不智能。

这意味着 Tutti 提供的唯一价值是「缩短点击路径」。切换后的系统行为应该跟点击 Control Center HomePod **100% 一致**，不做任何"智能记忆 / 自动恢复"花活。

---

## 锁定决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 范围 | 纯快捷入口 + HAL 兜底 | 用户痛点是 "路径太长"，不是 "行为不智能"。多做的每一点价值边际为零、bug 面成本递增。蓝牙刚刚验证过反模式 |
| Pro gate | 无（全 Free） | "替代系统菜单" 是产品定位的延伸。gate 起来破坏定位 |
| 切换语义 | 跟系统菜单 100% 一致 | 点 HomePod → 系统默认输出切到 HomePod → 本地多输出聚合自然退出，不持久化任何状态 |
| 切回 | 用 DevicesCapsule 选本地设备 | 不需要专门的 "断开 AirPlay" 按钮 |
| 私有 API 容忍度 | 接受 ObjC runtime 反射调用 | 蓝牙的 bundled CLI 路径不适用 AirPlay。主进程直接调私有 API |
| Spike 失败兜底 | 接受 "只显示已激活 AirPlay" | HAL 解除过滤就能拿到，0.5 天交付兜底版 |

---

## 已知 Spike 结论（来自 v0.3.0 spec）

**已验证可用**：
- ✅ `AVOutputContext.defaultSharedOutputContext.setOutputDevice(_:options:)` — 2 参版本，能切换系统默认输出
- ✅ `NSClassFromString("AVOutputContext")` 在 macOS 26 上返回有效 class

**已知不通**：
- ❌ Path A: HAL 不暴露未激活的 AirPlay 设备
- ❌ Path C: `AVRoutePickerView` UX 严重妥协（picker 弹在 popover 下方、本地输出强制顶部、跟 Tutti 视觉冲突）
- ❌ `AVOutputContext.outputDevices` 只返回当前路由设备，不是候选列表

**未走完的 4 条候选**（Phase 0 spike 任务）：
1. `AVOutputDeviceDiscoverySession`（iOS 同名公开类，macOS 可能 hide 私有）
2. `AVOutputContext` 未扫完的 ~20 个 class methods
3. `NetServiceBrowser` + `_airplay._tcp` mDNS + 找方法映射回 `AVOutputDevice`
4. `MRMediaRemoteService` 私有 framework

---

## Phase 0 — Spike（命门）

**目标**：找到一条能枚举 LAN 内 AirPlay 设备（含未激活）+ 能把设备对象喂给 `setOutputDevice` 切换的 API 路径。

### 优先级排序（按"成功概率 × 实现成本"）

#### Path 1: `AVOutputDeviceDiscoverySession` 反射 — **首选**
- 30 分钟 spike 出结论
- iOS 上是公开 AirPlay discovery API
- 试探：`NSClassFromString("AVOutputDeviceDiscoverySession")` → 拿 class → 看 class methods / init / delegate protocol → 构造 session → set delegate → start discovery → delegate 回调拿 devices
- **概率**：高。Apple 内部 iOS/macOS 共享 AV stack，类大概率存在

#### Path 2: `AVOutputContext` 未扫完的 class methods
- 2-3 小时
- 重点扫包含 `discovery` / `candidate` / `available` / `browse` 关键字的 selector
- 拿到候选 method → 试 invoke → 看返回类型是不是 `[AVOutputDevice]`-like
- **概率**：中

#### Path 3: `NetServiceBrowser` + `_airplay._tcp` + `_raop._tcp` — 公开 + 映射
- 3-4 小时
- Bonjour 扫描是公开 API
- 难点：拿到 hostname 后用 `NSClassFromString("AVOutputDevice")` 反射构造 `+[AVOutputDevice deviceWithUID:]` 或类似工厂方法，把 endpoint 映射回 `AVOutputDevice` 实例
- **概率**：中低（映射步骤是最大不确定性）

#### Path 4: `MRMediaRemoteService` 私有 framework
- 4+ 小时
- 完全黑盒，没文档没社区调研
- Apple Music / 控制中心媒体控件用的 framework
- **概率**：低

### Spike 时序

```
day 0 (30 min): Path 1
  ├─ work → 锁路径，开始 Phase A
  └─ 不通 →

day 0 (1-2 hour): Path 2
  ├─ work → 锁路径，开始 Phase A
  └─ 不通 →

day 0 (2-3 hour): Path 3
  ├─ work → 锁路径，开始 Phase A
  └─ 不通 →

day 0.5-1 (4+ hour): Path 4
  ├─ work → 锁路径，开始 Phase A
  └─ 全失败 → 兜底 Phase B only (0.5 天)
```

### Spike 5 项验证清单（每条路径都要满足）

1. ✅ 能枚举家里的 HomePod 2/3、Apple TV、其他 Mac（至少 3 台不同类型）
2. ✅ 拿到的设备对象能传给 `AVOutputContext.setOutputDevice(_:options:)` 实际切换成功
3. ✅ 切换后系统默认输出在 Sound 系统菜单里也确认变了
4. ✅ 该设备**未在 macOS 控制中心激活过**也能被发现（关键 — 不能只是 HAL 兜底重复）
5. ✅ ObjC runtime 反射 + private API 调用通过 Hardened Runtime + notarize（Tutti 现行签名配置）

### Spike 期间 scope

- 不写生产代码
- 用 `scripts/airplay-spike.swift` 或 Xcode Playground 做反射试探
- 出结果立即决策继续 / abort

---

## 架构总览

```
┌──────────────────────────────────────────────────────┐
│                   MenuBarView                         │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │DevicesCapsule│  │AirPlayCapsule│  │ProfilesCap.│  │
│  │ (本地 + 已   │  │ (新增,LAN)   │  │            │  │
│  │  激活AirPlay)│  │              │  │            │  │
│  └──────┬───────┘  └──────┬───────┘  └────────────┘  │
└─────────┼──────────────────┼─────────────────────────┘
          │                  │
          ▼                  ▼
┌──────────────────┐  ┌──────────────────────────────┐
│AudioDeviceManager│  │      AirPlayBrowser          │
│  (Core Audio HAL)│  │  @Published devices          │
│                  │  │  func refresh() async        │
│  .swift:244      │  │  func startContinuousScan()  │
│  解除 AirPlay    │  │  func stopContinuousScan()   │
│  过滤,作兜底     │  └──────────┬───────────────────┘
└──────────────────┘             │
                                 ▼
                       ┌─────────────────────┐
                       │ Spike 后定形态：     │
                       │ - AVOutputDevice    │
                       │   DiscoverySession  │
                       │ - 或 AVOutputContext│
                       │   未扫完的 methods  │
                       │ - 或 NetService     │
                       │   Browser+mDNS      │
                       │ - 或 MRMediaRemote  │
                       └─────────┬───────────┘
                                 │
                                 ▼
                       ┌─────────────────────┐
                       │   AirPlaySwitcher   │
                       │ AVOutputContext     │
                       │  .defaultShared     │
                       │  .setOutputDevice() │
                       │ (已验证可用)        │
                       └─────────────────────┘
```

**关键 invariant**：
- `AirPlayBrowser` 跟 `AudioDeviceManager` **不互相调用**。两个完全独立的设备来源
- UI 层（`AirPlayCapsule`）主动去重：HAL 已经报告的 AirPlay 不在 AirPlayCapsule 显示
- 不持久化任何 AirPlay 状态
- 不缓存设备列表跨 app session
- 生命周期跟 popover 绑死（用户不开 popover 时不扫描，省电）

---

## 数据模型

```swift
struct AirPlayDevice: Identifiable, Equatable, Hashable {
    /// 来自发现 API 的稳定 ID（UID / hostname / uuid，spike 决定）
    let id: String
    /// 显示名，如 "Barry's HomePod 2"
    let name: String
    /// 是否当前为系统默认输出
    let isActive: Bool
    /// 用于 SF Symbol 选择
    let deviceType: AirPlayDeviceType
}

enum AirPlayDeviceType {
    case homepod
    case appleTV
    case mac
    case speaker
    case unknown
}
```

---

## 文件清单

| 文件 | 操作 | 大致行数 |
|---|---|---|
| `Tutti/AirPlayBrowser.swift` | 新建（发现，spike 后定具体形态） | ~120-180 |
| `Tutti/AirPlaySwitcher.swift` | 新建（切换） | ~40 |
| `Tutti/AudioDeviceManager.swift` | 解除 `:244` AirPlay 过滤 | -1 |
| `Tutti/MenuBarView.swift` | 新增 `AirPlayCapsule` + `AirPlayRow` + 插入 body | +120 |
| `Tutti/AppDelegate.swift` | 实例化 `AirPlayBrowser`、注入 environment、popover 生命周期 hook | +15 |
| `Tutti/Localizable.xcstrings` | 4 个新 key × 9 语言 | +36 entries |
| `scripts/airplay-spike.swift` | Phase 0 反射 spike 脚本（不进 .app bundle） | ~80-150 |
| `TuttiTests/AirPlaySwitcherTests.swift` | 单测（local-only） | ~40 |
| `TuttiTests/AirPlayBrowserTests.swift` | 单测（local-only） | ~80 |

---

## 发现层（AirPlayBrowser）

```swift
@MainActor
final class AirPlayBrowser: ObservableObject {
    @Published private(set) var devices: [AirPlayDevice] = []

    private var session: Any?  // spike 决定具体类型

    func refresh() async {
        // 实现 spike 后定
    }

    func startContinuousScan() {
        // popover open 时调，开启 discovery session
    }

    func stopContinuousScan() {
        // popover close 时调，关闭 discovery，省电
    }
}
```

**生命周期**：
- `AppDelegate.applicationDidFinishLaunching` 实例化，**不预热**（mDNS/discovery 不像蓝牙的 paired list 是持久信息，每次都要 LAN scan）
- `popover.onVisibilityChange(visible: true)` → `startContinuousScan()`
- `popover.onVisibilityChange(visible: false)` → `stopContinuousScan()`

**Brittleness 处理**：
- `NSClassFromString` 反射 wrap `guard let cls = ... else { devices = []; return }`
- 所有 selector invocation wrap `responds(to:)` 检查
- 单测覆盖 reflection 失败路径
- 失败时 `os_log` 一行到 subsystem `com.recents.tutti`, category `airplay`

---

## 切换层（AirPlaySwitcher）

```swift
enum AirPlaySwitcher {
    /// 同步切换系统默认输出到指定 AirPlay 设备。
    /// 返回 false 表示反射调用失败或 setOutputDevice 返回错误。
    static func switchTo(_ device: AirPlayDevice) -> Bool {
        guard let ctxClass = NSClassFromString("AVOutputContext") as? NSObject.Type else {
            return false
        }
        let defaultShared = ctxClass.perform(NSSelectorFromString("defaultSharedOutputContext"))?
            .takeUnretainedValue() as? NSObject
        guard let ctx = defaultShared else { return false }

        // spike 后确认 setOutputDevice 的 device 参数怎么构造
        // ...
        return false  // 占位
    }
}
```

**为什么是 struct/enum 不是 actor**：切换是同步、毫秒级、无重入的 ObjC call。

---

## UI 设计

### 位置

MenuBarView 主视图垂直顺序：

```
StatusCapsule
MasterCapsule          (if showMaster)
DevicesCapsule         (本地 + 已激活 AirPlay 兜底)
AirPlayCapsule         ← 新增，仅 spike 成功且有可发现设备时显示
ProfilesCapsule        (if showProfiles)
```

### 显示规则

- `airPlayCapsule.displayableDevices.isEmpty` → 整个 capsule `EmptyView()`（不占空间）
- spike 全失败 → 不写 `AirPlayBrowser.swift` / `AirPlaySwitcher.swift` / `AirPlayCapsule`。仓库里根本没有这块代码，发版完全靠 Phase B 的 HAL 解除过滤兜底
- 已激活 AirPlay → 跟随 HAL 走 DevicesCapsule，**不**在 AirPlayCapsule 重复出现

### 去重逻辑（关键）

```swift
struct AirPlayCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var browser: AirPlayBrowser

    var displayableDevices: [AirPlayDevice] {
        let halAirPlayUIDs = manager.devices
            .filter { $0.transportType == kAudioDeviceTransportTypeAirPlay }
            .map { $0.uid }
        return browser.devices.filter { !halAirPlayUIDs.contains($0.id) }
    }
    // ...
}
```

**好特性**：视觉上呈现"这个 AirPlay 当前是不是接入 macOS"。切到 HomePod 后，HomePod 从 AirPlayCapsule 移到 DevicesCapsule，UI 自洽。

### Row 视觉

```
┌─ AirPlay ────────────────────────────┐
│  ┌────────────────────────────────┐ │
│  │ 🔊  Barry's HomePod 2     ◯    │ │
│  └────────────────────────────────┘ │
│  ┌────────────────────────────────┐ │
│  │ 📺  Barry's TV            ◯    │ │
│  └────────────────────────────────┘ │
└──────────────────────────────────────┘
```

- 左侧 SF Symbol（按 `deviceType`）：
  - `homepod` → `homepod.fill`
  - `appleTV` → `appletv.fill`
  - `mac` → `desktopcomputer`
  - `speaker` → `hifispeaker.fill`
  - `unknown` → `airplayaudio`
- 中间：设备名
- 右侧：浅色 `airplayaudio` 图标（提示可点）

### 点击行为

- 点击行 → `AirPlaySwitcher.switchTo(device)` 立即同步调
- 切换成功 → 下次 `browser.refresh()` 触发，该设备从 AirPlayCapsule 消失 + 出现在 DevicesCapsule（HAL 接管后）
- 切换失败 → silent failure，不弹错误提示

### 没有的东西

- ❌ "切换中..." loading 态
- ❌ confirm 弹窗
- ❌ "断开 AirPlay" 按钮（用 DevicesCapsule 选本地设备即可）
- ❌ row state machine（不像蓝牙的 connecting/failed）
- ❌ fold/unfold 折叠（设备数通常 ≤5）
- ❌ "扫描中" 指示器（discovery 是后台连续）

### xcstrings 新 keys（4 × 9 语言）

| Key (zh-Hans source) | en | 用途 |
|---|---|---|
| `AirPlay` | `AirPlay` | SectionHead 标题（同名） |
| `当前` | `Current` | 已激活设备的右侧文字 |
| `切换到 %@` | `Switch to %@` | 行 accessibility label |
| `AirPlay 设备 · 当前激活` | `AirPlay device · currently active` | accessibility label，已激活行 |

### Accessibility

- 整行 `accessibilityLabel`：「Barry's HomePod 2，AirPlay 设备，双击切换」
- isActive 行 label 加「当前激活」

---

## 错误处理 + 边界 case

| 场景 | 行为 |
|---|---|
| spike 上线后 macOS 升级私有 API 改 | `browser.devices` 永远空 → capsule 隐藏。降级为兜底版（HAL 已激活 AirPlay 在 DevicesCapsule 显示）。不崩 |
| `NSClassFromString` 返回 nil | `browser.devices = []`，capsule 隐藏，不崩 |
| `setOutputDevice` ObjC selector 不存在 | `switchTo` 返回 false，行不变 selected 态，silent failure |
| LAN 0 个 AirPlay 设备（拔网线 / 关 Wi-Fi） | `devices = []` → capsule 隐藏 |
| 1 台 HomePod 已激活 + 1 台 Apple TV 未激活 | HomePod 在 DevicesCapsule（HAL 兜底），Apple TV 在 AirPlayCapsule |
| 切到 AirPlay 后再用 Tutti 加本地设备到聚合 | 系统层 AirPlay 已是默认输出，聚合操作可能 silent fail。**接受**（用户操作顺序问题不是 Tutti 责任，行为跟系统菜单一致） |
| popover open 时设备出现 / 消失 | `@Published devices` 触发 view 重渲染，行自然 enter/exit |
| 同 LAN 多个用户的 HomePod（朋友家） | 都显示。Tutti 不区分"我的 vs 别人的"（macOS 也不区分） |
| 同 LAN 100+ AirPlay（机场 / 办公室） | spike 后定排序策略（LRU 前 10？） |
| 设备名含特殊字符 | SwiftUI Text 自动转义，最大宽度限制防溢出 |
| `_airplay._tcp` 在企业防火墙被屏蔽 | capsule 隐藏，HAL 兜底（已激活设备仍可见） |

---

## 测试

### 单测（local-only TuttiTests/，gitignored）

| 测试 | Fixture | 期望 |
|---|---|---|
| `AirPlaySwitcherTests` | mock `NSClassFromString` 返回 nil | `switchTo` 返回 false，不崩 |
| `AirPlayBrowserTests` | mock discovery session 返回 3 个 fixture 设备 | `devices` 正确填充 |
| `AirPlayBrowserFailureTests` | 反射 class 不存在 | `devices = []`，不崩 |

UI / 集成测试通过 Phase E 手测脚本覆盖。

### 手测脚本（v0.3.x 发版前必跑）

1. **首启 HAL 兜底** — Tutti 启动 → DevicesCapsule 应该出现当前已激活的 AirPlay（如果系统当前路由到 HomePod）
2. **AirPlay 发现** — 关掉所有 AirPlay 路由 → 打开 popover → AirPlayCapsule 显示 LAN 内所有 HomePod / Apple TV / 其他 Mac
3. **点击切换** — 点 HomePod 行 → 系统默认输出立即切到 HomePod → 该行从 AirPlayCapsule 消失 → 出现在 DevicesCapsule
4. **设备类型图标** — HomePod 显示 `homepod.fill` / Apple TV 显示 `appletv.fill` / 其他 Mac 显示 `desktopcomputer`
5. **去重正确** — 切到 HomePod 后，HomePod 只在 DevicesCapsule，不在 AirPlayCapsule
6. **切回本地** — 在 DevicesCapsule 取消 HomePod 勾选 → 系统输出回到本地 → HomePod 从 DevicesCapsule 消失 → 重新出现在 AirPlayCapsule
7. **同名设备 / 朋友家 HomePod** — LAN 上有别人家的 HomePod，确认列表里有但不崩
8. **空 LAN** — 拔网线 / 关 Wi-Fi → AirPlayCapsule 隐藏
9. **macOS 升级模拟** — 注释反射调用 → AirPlayCapsule 隐藏，DevicesCapsule 兜底正常
10. **app 退出清理** — popover open 中 killall Tutti → 无残留进程 / discovery session leak

### 构建验收

- `xcodebuild build` 干净，无新 warning
- 13 既有单测 + 3 新单测全过
- `scripts/release.sh` 跑通：build → sign → notarize → staple
- `spctl --assess --verbose Tutti.app` 报 `accepted, source=Notarized Developer ID`

---

## 工期

| Phase | 工作 | 时间 |
|---|---|---|
| **Phase 0** | Spike 4 条发现 API 路径，定 winner | 0.5-1 天 |
| **Phase A** | AirPlayBrowser + Switcher + 数据模型 + 单测 | 0.5 天 |
| **Phase B** | AudioDeviceManager 解除 AirPlay 过滤 | 0.25 天 |
| **Phase C** | MenuBarView AirPlayCapsule + Row + 去重 + 插入 body | 0.5 天 |
| **Phase D** | xcstrings + accessibility 4 keys × 9 语言 | 0.25 天 |
| **Phase E** | 手测 + 修 bug | 0.5 天 |
| **Phase F** | release pipeline 版本号 + notarize + 发版 | 0.25 天 |
| **合计（spike 成功）** | | **~2.75 天** |
| **合计（spike 失败，仅 Phase B + 必要 polish）** | | **~0.5 天** |

---

## Phase 0 决策点

**必须在写一行生产代码前过这道门**：

- ✅ 至少一条发现路径在测试 LAN 通过 5 项验证清单 → 进 Phase A-F 完整路线
- ❌ 4 条全部失败 → 跳到 Phase B（只解除 HAL 过滤），v0.3.x 改成 minor "surface activated AirPlay in device list"，工期 0.5 天

---

## 风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 私有 API 路径全部失败 | 中 | 降级到兜底，价值减半 | spike 优先级排序好，控制 spike 时间在 1 天内 |
| 私有 API 在 macOS 27 改名/删除 | 中 | 用户升级后 AirPlayCapsule 消失，兜底接管 | 设计的 graceful degrade 路径正是为此准备 |
| 反射 API 调用过不了 notarize | 低 | 整条路径阻塞 | Phase A 完成后立刻跑 notarize 验证（不是发版前才发现） |
| ObjC runtime 调用 crash | 中 | 启动崩溃 | 反射调用全部 wrap `class != nil && responds(to:)` + 单测覆盖 |
| `setOutputDevice` macOS 26.x 行为改 | 低 | 切换 silent fail | 错误处理已说明 silent degrade，不崩 |
| LAN 上恶意 AirPlay 设备名 | 极低 | 文字溢出 | SwiftUI Text 自动转义 + 行最大宽度 |
| `_airplay._tcp` 企业网防火墙屏蔽 | 低 | 列表空 | capsule 隐藏，HAL 兜底 |
| 同 LAN 100+ AirPlay 设备 | 极低 | 列表过长 | spike 后定排序策略 |

---

## v0.3.x 范围外（未来）

- AirPlay 2 多房间同步
- 主动断开 AirPlay 路由（macOS 没有公开 API，跳过）
- "记住上次 AirPlay 选择" 自动恢复（违反 "纯快捷入口" 定位决策）
- AirPlay 设备分组 / 排序 / 收藏 / 重命名
- 与 Profile 系统集成（保存"切到 HomePod"作为一个 Profile）
