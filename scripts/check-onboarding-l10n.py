#!/usr/bin/env python3
"""Verify onboarding keys carry translations for the required locales.

Usage: python3 scripts/check-onboarding-l10n.py [comma,separated,locales]
Default locales: zh-Hant,en
"""
import json
import sys

KEYS = [
    "把一路音频同时送到多个设备。\n音箱、AirPods、HomePod —— 播放同一段声音。",
    "多设备同步", "同一音轨，零延迟", "菜单栏常驻", "随手切换输出", "开始",
    "开启辅助功能权限", "权限已开启",
    "现在你可以用键盘音量键直接控制 Tutti 的聚合输出。",
    "授权后，键盘音量键能直接控制 Tutti 的聚合输出。这是 Pro 特性。",
    "返回", "使用 F11 / F12 与音量键",
    "替代系统默认音频管理，使音量调节作用于聚合输出而不是单一设备。",
    "未授权", "稍后在设置中开启", "打开设置", "下一步",
    "点击「打开设置」会跳转到 `系统设置 › 隐私与安全性 › 辅助功能`，把 Tutti 的开关打开即可。",
    "点击「打开系统设置」会跳到 `控制中心`，把 `声音` 一栏的「在菜单栏中显示」改为「不显示」即可。",
]

required = sys.argv[1].split(",") if len(sys.argv) > 1 else ["zh-Hant", "en"]
with open("Tutti/Localizable.xcstrings", encoding="utf-8") as f:
    strings = json.load(f)["strings"]

bad = []
for k in KEYS:
    locs = strings.get(k, {}).get("localizations", {})
    for r in required:
        val = locs.get(r, {}).get("stringUnit", {}).get("value", "")
        if not val.strip():
            bad.append((r, k[:24]))

if bad:
    for r, k in bad:
        print(f"MISSING {r}: {k}")
    sys.exit(1)
print(f"OK: {len(KEYS)} keys x {required} all present")
