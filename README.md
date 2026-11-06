# ScreenStay

> 一个常驻 macOS 菜单栏的小工具：音乐或视频播放时阻止屏幕休眠，暂停后自动释放。

[下载 DMG](dist/ScreenStay-1.2.3.dmg)

| 项目 | 内容 |
| --- | --- |
| 当前版本 | 1.2.3（Build 6） |
| 系统要求 | macOS 13 及以上 |
| 架构 | Apple Silicon + Intel 通用二进制 |
| 权限 | 无需辅助功能、屏幕录制、麦克风 |
| 网络 | 不联网，不上传数据 |
| 开源 | 源码与构建脚本均在本目录 |

## 目录

- [概览](#概览)
- [功能](#功能)
- [安装](#安装)
- [使用](#使用)
- [检测原理](#检测原理)
- [诊断](#诊断)
- [隐私与权限](#隐私与权限)
- [从源码构建](#从源码构建)
- [项目结构](#项目结构)
- [分发与公证](#分发与公证)
- [卸载](#卸载)
- [相关链接](#相关链接)

## 概览

ScreenStay 默认使用**严格模式**：只认可 macOS 右上角“正在播放”列表中的媒体。播放开始后，它创建防熄屏断言；暂停或结束后，断言自动释放。

它不模拟鼠标键盘，不修改系统节能设置，也不需要辅助功能或屏幕录制权限。

## 功能

- **只响应系统播放列表**：普通提示音、点击音效和后台声音不会触发。
- **暂停即释放**：读取真实的 Now Playing 播放状态，暂停后约 1–3 秒释放。
- **菜单栏开关**：单击图标开启/关闭；右键打开设置菜单。
- **影响熄屏的应用**：列出其他持有显示休眠断言的进程，便于排查。
- **开机自启**：通过 `SMAppService` 注册登录项。
- **电源断言**：按需创建 `PreventUserIdleDisplaySleep` 与 `PreventUserIdleSystemSleep`。
- **通用二进制**：同时支持 Apple Silicon 与 Intel。

严格模式关闭后，会回退到 `Core Audio + Now Playing` 兼容模式；任何持续约 2.5 秒以上的音频输出都可能触发。

## 安装

### 下载 DMG（推荐）

1. 双击 `dist/ScreenStay-1.2.3.dmg`。
2. 把 **ScreenStay** 拖入“应用程序”文件夹。
3. 打开 App，菜单栏会出现显示器图标。

也可以使用 ZIP：

- `dist/ScreenStay-1.2.3.zip`
- 或双击 `install.command`，脚本会安装到 `/Applications` 并打开。

> 首次打开如果被 Gatekeeper 拦截，请在「系统设置 → 隐私与安全性」中选择“仍要打开”，或执行：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/ScreenStay.app
> ```

## 使用

| 操作 | 效果 |
| --- | --- |
| 单击菜单栏图标 | 立即开启或关闭防熄屏 |
| 右键 / Control + 单击 | 打开设置菜单 |
| 菜单 → 保持屏幕常亮 | 总开关，与单击图标等价 |
| 菜单 → 仅系统媒体播放时触发 | 严格模式，默认开启 |
| 菜单 → 开机自启 | 注册或取消登录项 |

菜单结构示例：

```text
正在播放 · 网易云音乐
屏幕保持常亮
其他影响熄屏的应用（1）
  WorkBuddy
────────────
✓ 保持屏幕常亮
✓ 仅系统媒体播放时触发
  开机自动启动
  关于 ScreenStay
  退出 ScreenStay
```

- 图标右侧出现**绿点**：媒体正在播放，且已成功保持屏幕常亮。
- 图标变暗：总开关已关闭。
- 暂停媒体或退出 App：电源断言释放。

### 查看谁在阻止熄屏

右键菜单会列出持有 `NoDisplaySleepAssertion` 或 `PreventUserIdleDisplaySleep` 的其他应用。

如果列表为空，说明没有其他应用在阻止熄屏。若屏幕不按设定时间熄灭，可以先看这里。macOS 会汇总所有应用的电源断言，ScreenStay 无法取消其他应用的请求。

> ScreenStay 只阻止空闲熄屏和系统休眠。手动锁屏、合盖、低电量等情况仍按 macOS 自身策略执行。

## 检测原理

严格模式使用两层只读查询：

1. **系统 Perl 辅助器**
   - 通过 `/usr/bin/perl` 加载内置的极小 dylib。
   - 调用 `MRMediaRemoteGetNowPlayingApplicationIsPlaying`，读取真实的播放/暂停状态。
2. **JXA 辅助脚本**
   - 使用 `MRNowPlayingRequest` 读取应用名、标题、PID 和 Bundle ID，用于菜单展示。

如果 Perl 不可用，则回退到：

- `PlaybackRate`
- 播放器进程的 `kAudioProcessPropertyIsRunningOutput`
- 播放器元数据中的 `isCurrentlyPlaying`

确认播放后，App 创建两个 IOPM 电源断言：

- `PreventUserIdleDisplaySleep`
- `PreventUserIdleSystemSleep`

```bash
pmset -g assertions | grep ScreenStay
```

> macOS 15.4 之后，普通第三方 App 直接调用 MediaRemote C 接口或 `MRNowPlayingRequest` 类属性会返回过期的 `Paused`。ScreenStay 使用系统 Perl 作为受信任的读取进程，不申请辅助功能、屏幕录制或麦克风权限。

### 已知限制

- 如果播放器没有向系统登记 Now Playing，严格模式不会触发；可以关闭“仅系统媒体播放时触发”，回退到音频检测。
- 极少数情况下系统 Perl 不可用，会回退到组合判断，暂停释放可能稍晚。
- 完全静音且没有登记 Now Playing 的视频，仍可能识别不到。
- 移动 App 位置后，已注册的开机自启可能指向旧路径；关闭再打开一次“开机自启”即可。

## 诊断

```bash
# 观察 10 秒检测状态与电源断言
/Applications/ScreenStay.app/Contents/MacOS/ScreenStay --diagnose 10

# 查看当前影响熄屏的其他应用
/Applications/ScreenStay.app/Contents/MacOS/ScreenStay --blockers

# 查看当前 Now Playing 状态
/Applications/ScreenStay.app/Contents/MacOS/ScreenStay --nowplaying

# 查看 / 开启 / 关闭登录项
/Applications/ScreenStay.app/Contents/MacOS/ScreenStay --login-status
/Applications/ScreenStay.app/Contents/MacOS/ScreenStay --enable-login
/Applications/ScreenStay.app/Contents/MacOS/ScreenStay --disable-login
```

播放音乐时，`--nowplaying` 应显示：

```text
perlAvailable=true
perlIsPlaying=true
source=jxa
isPlaying=true
playbackRate=1.0
app=网易云音乐
title=歌曲名
```

`perlIsPlaying` 是最终判定；JXA 部分用于读取应用名和元数据。

## 隐私与权限

- 不联网、不上传播放记录或设备信息。
- 不需要辅助功能、屏幕录制或麦克风权限。
- 只读访问 macOS 播放状态和进程音频状态。
- 影响熄屏应用列表只在本机读取电源断言。
- 偏好设置保存在本机 `UserDefaults` 中。

## 从源码构建

要求：macOS 13+、Command Line Tools（`swiftc`、`clang`、`codesign`、`iconutil`）。

```bash
cd ScreenStay
./build.sh
open ScreenStay.app
```

构建脚本会：

- 分别编译 `arm64` 与 `x86_64`，并用 `lipo` 合并。
- 编译内置 Perl 辅助器与 Objective-C 桥接。
- 生成 `ScreenStay.app`，在 `/tmp` 完成 ad-hoc 签名。
- 校验签名与 `Info.plist`。

重新生成图标（可选，需要 Pillow）：

```bash
python3 scripts/make_icon.py
```

重新生成 ZIP / DMG：

```bash
./package.sh
```

## 项目结构

```text
ScreenStay/
├── README.md
├── CHANGELOG.md
├── build.sh
├── package.sh
├── install.command
├── ScreenStay.app
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MediaMonitor.swift
│   ├── AudioActivityDetector.swift
│   ├── AudioProcessActivityDetector.swift
│   ├── NowPlayingDetector.swift
│   ├── JXANowPlayingReader.swift
│   ├── PerlNowPlayingProbe.swift
│   ├── PerlNowPlayingProbe.m
│   ├── NowPlayingBridge.h
│   ├── NowPlayingBridge.m
│   ├── PowerController.swift
│   ├── LoginItemManager.swift
│   ├── SleepBlockerMonitor.swift
│   ├── Diagnostics.swift
│   └── nowplaying-probe.pl
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   ├── AppIcon-1024.png
└── scripts/make_icon.py
```

## 分发与公证

自己使用不需要额外准备。当前 DMG 使用 ad-hoc 签名。

如果要发给别人，需要：

1. Apple Developer Program 账号。
2. Developer ID Application 证书。
3. 使用 hardened runtime 签名 App，再用 `notarytool` 公证。
4. 对 DMG 签名并公证，最后用 `stapler` 装订票据。

否则 Gatekeeper 会提示“无法验证开发者”，对方需要右键打开或手动移除 quarantine。

```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" ScreenStay.app

ditto -c -k --keepParent ScreenStay.app /tmp/ScreenStay.zip
xcrun notarytool submit /tmp/ScreenStay.zip --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple ScreenStay.app
```

> 本 App 使用 MediaRemote 读取 Now Playing 信息，不适合提交 Mac App Store；通过 Developer ID 在 App Store 之外分发没有问题。

## 卸载

1. 右键菜单栏图标，取消“开机自启”。
2. 选择“退出 ScreenStay”。
3. 删除 `/Applications/ScreenStay.app`。
4. 可选：清理偏好设置。

```bash
defaults delete com.zzerfu.ScreenStay
```

## 相关链接

- [更新记录 Markdown](CHANGELOG.md)
- [下载 1.2.3 DMG](dist/ScreenStay-1.2.3.dmg)
