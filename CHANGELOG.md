# ScreenStay 更新记录

本文件记录 ScreenStay 从 1.0.0 到当前版本的变更。

[产品页](index.html) · [网页版使用说明](readme.html) · [网页版更新记录](changelog.html) · [下载 1.2.3](dist/ScreenStay-1.2.3.dmg)

| 项目 | 内容 |
| --- | --- |
| 当前版本 | **1.2.3**（Build 6） |
| 适用系统 | macOS 13 及以上 |
| 架构 | Apple Silicon（arm64）+ Intel（x86_64） |
| 最新变化 | 用系统 Perl 读取真实播放状态，修复暂停误判 |

> **建议：** 所有旧版本用户直接升级到 1.2.3。升级不会清除总开关、严格模式或登录项设置。

## 目录

- [版本总览](#版本总览)
- [1.2.3](#123---2026-11-04)
- [1.2.2](#122---2026-11-04)
- [1.2.1](#121---2026-11-04)
- [1.2.0](#120---2026-11-04)
- [1.1.0](#110---2026-11-03)
- [1.0.0](#100---2026-11-03)
- [版本规则](#版本规则)
- [相关链接](#相关链接)

## 版本总览

| 版本 | 日期 | 类型 | 摘要 |
| --- | --- | --- | --- |
| [1.2.3](#123---2026-11-04) | 2026-11-04 | 修复 | 改用系统 Perl 读取真实播放状态，修复暂停后仍显示播放 |
| [1.2.2](#122---2026-11-04) | 2026-11-04 | 修复 | 改用 JXA 读取真实 Now Playing 播放速率，修复严格模式不触发、绿点不出现 |
| [1.2.1](#121---2026-11-04) | 2026-11-04 | 过渡修复 | 改用 MRNowPlayingRequest，部分系统上状态仍为 Paused |
| [1.2.0](#120---2026-11-04) | 2026-11-04 | 功能 | 新增“仅系统媒体播放时触发”严格模式开关 |
| [1.1.0](#110---2026-11-03) | 2026-11-03 | 功能 | 右键菜单显示其他影响熄屏的应用 |
| [1.0.0](#100---2026-11-03) | 2026-11-03 | 首发 | 菜单栏开关、媒体播放检测、防熄屏、开机自启 |

---

## 1.2.3 - 2026-11-04

**版本号：** `CFBundleShortVersionString = 1.2.3`，`CFBundleVersion = 6`

### 修复

- 修复音乐暂停后，菜单栏仍显示为播放中、绿点不消失、电源断言继续持有的问题。
- 修复部分播放器暂停后 `kMRMediaRemoteNowPlayingInfoPlaybackRate` 仍停留在 `1` 的误判。

### 变更

- 新增内置 Perl 辅助器：
  - `nowplaying-probe.pl`
  - `libScreenStayNowPlaying.dylib`
  - 通过 `/usr/bin/perl` 调用 `MRMediaRemoteGetNowPlayingApplicationIsPlaying`，获得系统真实的播放/暂停状态。
- 严格模式改为以 Perl 读取的 `playing` 为最终判定；JXA 只负责读取应用名、标题、PID 和 Bundle ID。
- Perl 不可用时，回退到 `PlaybackRate + kAudioProcessPropertyIsRunningOutput + isCurrentlyPlaying` 组合判断。
- JXA 辅助脚本额外返回 `pid`、`bundleIdentifier`、`metadata.isCurrentlyPlaying`。
- 严格模式暂停释放延迟从 5 秒缩短为约 1–3 秒；Core Audio 兼容模式仍保持 5 秒防抖。
- `--nowplaying` 增加 `perlAvailable`、`perlIsPlaying`、`pid`、`bundle`、`metadataPlaying`、`processAudio` 输出。

### 验证

暂停状态下：

```text
perlAvailable=true
perlIsPlaying=false
source=jxa
isPlaying=false
playbackRate=0.0
app=网易云音乐
pid=29508
bundle=com.netease.163music
metadataPlaying=false
```

注意：某些播放器暂停后 `processAudio` 仍可能短暂为 true，但最终判定以 `perlIsPlaying` 为准。

播放状态下 `perlIsPlaying=true`，ScreenStay 正常创建电源断言和绿点；暂停后 1–3 秒内断言释放，绿点消失。

### 已知限制

- 极少数情况下系统 Perl 不可用，会回退到组合判断，暂停释放可能稍晚。
- 静音视频如果既没有进程音频输出、也没有 `isCurrentlyPlaying` 标记，仍可能识别不到。

---

## 1.2.2 - 2026-11-04

**版本号：** `CFBundleShortVersionString = 1.2.2`，`CFBundleVersion = 5`

### 修复

- 修复严格模式下“仅系统媒体播放时触发”无法识别实际播放状态的问题。
- 修复播放媒体时菜单栏图标右侧不出现绿点的问题。
- 修复 macOS 15.4 及以上系统中，旧的 MediaRemote 接口始终返回 `Paused`，导致电源断言不创建的问题。

### 变更

- 严格模式改用 `/usr/bin/osascript` 执行只读 JXA 辅助脚本，读取：
  - `MRNowPlayingRequest.localNowPlayingItem.nowPlayingInfo`
  - `kMRMediaRemoteNowPlayingInfoPlaybackRate`
- 以 `PlaybackRate > 0` 判断正在播放，不再依赖被系统拦截的 `localIsPlaying` / `localPlaybackState`。
- `--nowplaying` 诊断命令增加 `source=jxa`、`isPlaying`、`playbackRate`、`title` 输出。

### 验证

QQ 音乐实际播放时，诊断结果：

```text
source=jxa
isPlaying=true
playbackRate=1.0
app=QQ音乐
title=可能否 (新版)
```

同时成功创建：

```text
PreventUserIdleDisplaySleep named: "ScreenStay: media is playing"
PreventUserIdleSystemSleep named: "ScreenStay: media is playing"
```

菜单栏绿点已实机确认出现。

### 文档

- 新增本更新记录 `CHANGELOG.md`，覆盖 1.0.0 至 1.2.2。

### 已知限制

- 严格模式依赖系统 Now Playing 播放列表；没有登记到播放列表的播放器不会触发。
- 可通过关闭“仅系统媒体播放时触发”回退到 Core Audio 兼容模式。

---

## 1.2.1 - 2026-11-04

**版本号：** `CFBundleShortVersionString = 1.2.1`，`CFBundleVersion = 4`

### 尝试修复

- 旧 C 接口 `MRMediaRemoteGetNowPlayingApplicationIsPlaying` 在 macOS 15.4+ 被系统限制后，改用 Objective-C 桥接 `MRNowPlayingRequest`。
- 新增 `--nowplaying` 命令，用于查看当前播放应用、播放状态和 Bundle ID。
- 保留旧 C 接口作为兼容回退。

### 结果

- 能正确读取当前播放应用名称（例如 `QQ音乐`）。
- 但在 macOS 27 上，`MRNowPlayingRequest.localIsPlaying` 与 `localPlaybackState` 仍返回过期的 `Paused`。
- 该版本作为过渡版本保留记录，实际使用请升级到 **1.2.2**。

---

## 1.2.0 - 2026-11-04

**版本号：** `CFBundleShortVersionString = 1.2.0`，`CFBundleVersion = 3`

### 新增

- 右键菜单新增开关：**“仅系统媒体播放时触发”**，默认开启。
- 严格模式：
  - 只监听 macOS 右上角播放列表（Now Playing）。
  - 不再采样 Core Audio，普通提示音、点击音效、后台音频不会触发。
  - 播放开始后保持亮屏，暂停后约 5 秒释放。
- 关闭严格模式后，回退到 `Core Audio + Now Playing` 兼容模式，用于没有登记 Now Playing 的播放器。
- 开关状态持久化到 `UserDefaults`。

### 变更

- 菜单增加严格模式勾选状态。
- 菜单状态文案区分“仅响应系统播放列表”和“等待音乐或视频播放”。
- 诊断输出增加触发模式：`Now Playing only (strict)` 或 `audio + Now Playing`。

### 已知问题

- 受 macOS 15.4+ MediaRemote 权限限制，严格模式实际无法识别播放，绿点不出现；已在 **1.2.2** 修复。

---

## 1.1.0 - 2026-11-03

**版本号：** `CFBundleShortVersionString = 1.1.0`，`CFBundleVersion = 2`

### 新增

- 右键菜单新增 **“其他影响熄屏的应用”** 区域。
- 通过 `IOPMCopyAssertionsByProcess` 读取当前持有以下断言的进程：
  - `NoDisplaySleepAssertion`
  - `PreventUserIdleDisplaySleep`
- 自动排除 ScreenStay 自己。
- 显示应用名称，多个进程按应用合并。
- 鼠标悬停显示 PID 和断言类型。
- 最多平铺显示 6 个应用，更多显示“另有 N 个应用…”。
- 新增诊断命令：`--blockers`。

### 变更

- 打开右键菜单或媒体状态变化时刷新阻止熄屏应用列表。
- README 增加“查看谁在阻止熄屏”章节。

---

## 1.0.0 - 2026-11-03

**版本号：** `CFBundleShortVersionString = 1.0.0`，`CFBundleVersion = 1`

### 首次发布

- 原生 macOS 菜单栏应用，无 Dock 图标。
- 菜单栏图标：
  - 单击直接开启/关闭保护。
  - 右键（或 Control+单击）打开设置菜单。
  - 关闭时图标变暗，媒体播放时右侧显示绿点。
- 媒体检测：
  - Core Audio 输出设备活动。
  - 系统 Now Playing 状态。
  - 音频信号持续约 2.5 秒才触发，避免提示音误判。
  - 媒体停止后延迟约 5 秒释放。
- 防熄屏：
  - `PreventUserIdleDisplaySleep`
  - `PreventUserIdleSystemSleep`
- “保持屏幕常亮”总开关，关闭后立即释放电源断言。
- 开机自启：
  - 使用 `SMAppService.mainApp` 注册/注销登录项。
  - 支持 macOS 要求批准时的系统设置引导。
- 其他：
  - 菜单显示当前播放应用。
  - 关于面板与退出。
  - 无辅助功能、屏幕录制、麦克风权限。
  - 不联网、不上传数据。
  - 通用二进制、自定义图标、ad-hoc 签名。
  - 提供 DMG、ZIP 与一键安装脚本 `install.command`。

---

## 升级建议

- 从任意旧版本升级：请使用 **1.2.3**。
- 如果之前注册过开机自启，移动 App 到 `/Applications` 后，建议在右键菜单中关闭再重新打开一次“开机自动启动”。
- 升级不会清除已有偏好设置（总开关、严格模式、登录项状态）。

## 版本规则

版本号遵循 `主版本.次版本.修订号`：

- **次版本**（1.2.0）：新增功能或行为变化。
- **修订号**（1.2.3）：修复、兼容性改进，不改变主要交互。
- `CFBundleVersion` 每次发布递增，当前为 `6`。

## 相关链接

- [产品页](index.html)
- [网页版使用说明](readme.html)
- [网页版更新记录](changelog.html)
- [下载最新 DMG](dist/ScreenStay-1.2.3.dmg)
- [使用说明 Markdown](README.md)
