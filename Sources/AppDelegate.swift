import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let enabled = "enabled"
        static let nowPlayingOnly = "nowPlayingOnly"
    }

    private let defaults = UserDefaults.standard
    private let power = PowerController()
    private let monitor = MediaMonitor()
    private let loginItem = LoginItemManager()
    private let sleepBlockerMonitor = SleepBlockerMonitor()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var statusTitleItem: NSMenuItem!
    private var statusDetailItem: NSMenuItem!
    private var blockerHeaderItem: NSMenuItem!
    private var blockerItems: [NSMenuItem] = []
    private var enabledItem: NSMenuItem!
    private var nowPlayingOnlyItem: NSMenuItem!
    private var loginItemMenuItem: NSMenuItem!
    private var approvalItem: NSMenuItem!

    private var enabled = true
    private var nowPlayingOnly = true
    private var mediaState = MediaState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = NSImage(named: "AppIcon")

        if defaults.object(forKey: Keys.enabled) != nil {
            enabled = defaults.bool(forKey: Keys.enabled)
        } else {
            enabled = true
            defaults.set(true, forKey: Keys.enabled)
        }

        if defaults.object(forKey: Keys.nowPlayingOnly) != nil {
            nowPlayingOnly = defaults.bool(forKey: Keys.nowPlayingOnly)
        } else {
            nowPlayingOnly = true
            defaults.set(true, forKey: Keys.nowPlayingOnly)
        }
        monitor.nowPlayingOnly = nowPlayingOnly

        configureStatusItem()
        configureMenu()

        monitor.onUpdate = { [weak self] state in
            guard let self else { return }
            self.mediaState = state
            self.applyState()
        }
        monitor.start()
        applyState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        power.release()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Reflect changes made in System Settings while the app was idle.
        refreshMenu()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Left click toggles immediately. Right click (or Control-click) opens the
    /// settings menu, which also contains the same toggle for discoverability.
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let secondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if secondaryClick {
            refreshMenu()
            if let window = button.window {
                let buttonRect = button.convert(button.bounds, to: nil)
                let screenRect = window.convertToScreen(buttonRect)
                menu.popUp(
                    positioning: nil,
                    at: NSPoint(x: screenRect.minX, y: screenRect.minY - 4),
                    in: nil
                )
            }
        } else {
            toggleEnabled(nil)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let symbol = NSImage(
            systemSymbolName: "display",
            accessibilityDescription: "ScreenStay"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        )
        symbol?.isTemplate = true

        if enabled {
            button.image = symbol
        } else if let symbol {
            button.image = dimmed(symbol)
        }

        if let dotColor = statusDotColor {
            let dot = NSAttributedString(
                string: " ●",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: dotColor,
                    .baselineOffset: 1.0
                ]
            )
            button.attributedTitle = dot
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }

        button.toolTip = tooltipText
        button.setAccessibilityLabel(tooltipText)
    }

    private var statusDotColor: NSColor? {
        guard enabled else { return nil }
        guard mediaState.isPlaying else { return nil }
        return power.isHeld ? .systemGreen : .systemOrange
    }

    private func dimmed(_ image: NSImage) -> NSImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
            return true
        }
        result.isTemplate = true
        return result
    }

    private var tooltipText: String {
        let status: String
        if !enabled {
            status = "已关闭，不会阻止屏幕休眠"
        } else if mediaState.isPlaying {
            if power.isHeld {
                let source = mediaState.source ?? "媒体"
                status = "正在播放 \(source)，屏幕保持常亮"
            } else {
                status = "检测到媒体播放，但无法阻止屏幕休眠"
            }
        } else if nowPlayingOnly {
            status = monitor.isNowPlayingAvailable
                ? "等待系统播放列表中的媒体"
                : "系统播放列表不可用"
        } else {
            status = "等待音乐或视频播放"
        }
        return "ScreenStay：\(status)（单击开关，右键菜单）"
    }

    // MARK: - Menu

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        statusTitleItem = disabledItem()
        statusDetailItem = disabledItem()
        blockerHeaderItem = disabledItem()

        enabledItem = NSMenuItem(
            title: "保持屏幕常亮",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = self

        nowPlayingOnlyItem = NSMenuItem(
            title: "仅系统媒体播放时触发",
            action: #selector(toggleNowPlayingOnly(_:)),
            keyEquivalent: ""
        )
        nowPlayingOnlyItem.target = self
        nowPlayingOnlyItem.toolTip = "开启后只响应 macOS 右上角播放列表中的媒体，忽略提示音"

        loginItemMenuItem = NSMenuItem(
            title: "开机自动启动",
            action: #selector(toggleLoginItem(_:)),
            keyEquivalent: ""
        )
        loginItemMenuItem.target = self

        approvalItem = NSMenuItem(
            title: "在系统设置中批准开机自启…",
            action: #selector(openLoginItemSettings(_:)),
            keyEquivalent: ""
        )
        approvalItem.target = self

        let aboutItem = NSMenuItem(
            title: "关于 ScreenStay",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self

        let quitItem = NSMenuItem(
            title: "退出 ScreenStay",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.addItem(statusTitleItem)
        menu.addItem(statusDetailItem)
        menu.addItem(blockerHeaderItem)
        menu.addItem(.separator())
        menu.addItem(enabledItem)
        menu.addItem(nowPlayingOnlyItem)
        menu.addItem(loginItemMenuItem)
        menu.addItem(approvalItem)
        menu.addItem(.separator())
        menu.addItem(aboutItem)
        menu.addItem(quitItem)

        refreshMenu()
        updateStatusItem()
    }

    private func disabledItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func refreshMenu() {
        let title: String
        let detail: String

        if !enabled {
            title = "ScreenStay 已关闭"
            detail = mediaState.isPlaying
                ? "检测到媒体播放，但开关已关闭"
                : "不会阻止屏幕休眠"
        } else if mediaState.isPlaying {
            let source = mediaState.source ?? "媒体"
            title = "正在播放 · \(shortened(source))"
            if power.isHeld {
                detail = "屏幕保持常亮"
            } else if let error = power.lastError {
                detail = "无法阻止休眠：\(shortened(error, maxLength: 28))"
            } else {
                detail = "正在保持屏幕常亮…"
            }
        } else {
            title = "等待媒体播放"
            if nowPlayingOnly {
                detail = monitor.isNowPlayingAvailable
                    ? "仅响应系统播放列表中的媒体"
                    : "系统播放列表不可用，可关闭严格模式"
            } else {
                detail = "播放音乐或视频时自动保持亮屏"
            }
        }

        statusTitleItem.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        statusDetailItem.attributedTitle = NSAttributedString(
            string: detail,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        enabledItem.state = enabled ? .on : .off
        nowPlayingOnlyItem.state = nowPlayingOnly ? .on : .off

        let loginOn = loginItem.isOn
        loginItemMenuItem.state = loginOn ? .on : .off
        loginItemMenuItem.title = loginItem.status == .requiresApproval
            ? "开机自动启动（等待批准）"
            : "开机自动启动"
        approvalItem.isHidden = loginItem.status != .requiresApproval

        refreshBlockerItems()
        updateStatusItem()
    }

    /// Rebuilds the "other apps affecting display sleep" section. The list is
    /// refreshed whenever the menu opens or ScreenStay's media state changes.
    private func refreshBlockerItems() {
        for item in blockerItems {
            menu.removeItem(item)
        }
        blockerItems.removeAll()

        guard let blockers = sleepBlockerMonitor.currentBlockers() else {
            blockerHeaderItem.title = "无法读取影响熄屏的应用"
            return
        }

        if blockers.isEmpty {
            blockerHeaderItem.title = "没有其他应用影响熄屏"
            return
        }

        blockerHeaderItem.title = blockers.count == 1
            ? "其他影响熄屏的应用（1）"
            : "其他影响熄屏的应用（\(blockers.count)）"

        let headerIndex = menu.index(of: blockerHeaderItem)
        guard headerIndex >= 0 else { return }

        let maximumVisible = 6
        for (offset, blocker) in blockers.prefix(maximumVisible).enumerated() {
            let item = NSMenuItem(title: blocker.name, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            item.toolTip = blocker.detail
            menu.insertItem(item, at: headerIndex + 1 + offset)
            blockerItems.append(item)
        }

        if blockers.count > maximumVisible {
            let remaining = blockers.count - maximumVisible
            let more = NSMenuItem(
                title: "另有 \(remaining) 个应用…",
                action: nil,
                keyEquivalent: ""
            )
            more.isEnabled = false
            more.indentationLevel = 1
            menu.insertItem(more, at: headerIndex + 1 + maximumVisible)
            blockerItems.append(more)
        }
    }

    private func shortened(_ text: String, maxLength: Int = 18) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "…"
    }

    // MARK: - State

    private func applyState() {
        power.apply(shouldHold: enabled && mediaState.isPlaying)
        refreshMenu()
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        enabled.toggle()
        defaults.set(enabled, forKey: Keys.enabled)
        applyState()
    }

    @objc private func toggleNowPlayingOnly(_ sender: Any?) {
        nowPlayingOnly.toggle()
        defaults.set(nowPlayingOnly, forKey: Keys.nowPlayingOnly)
        monitor.nowPlayingOnly = nowPlayingOnly
        applyState()
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        let turnOn = !loginItem.isOn
        do {
            let needsApproval = try loginItem.setEnabled(turnOn)
            refreshMenu()
            if turnOn, needsApproval {
                showApprovalAlert()
            }
        } catch {
            refreshMenu()
            showLoginError(error)
        }
    }

    @objc private func openLoginItemSettings(_ sender: Any?) {
        loginItem.openLoginItemsSettings()
    }

    // MARK: - Alerts and About

    private func showApprovalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要批准开机自启"
        alert.informativeText = """
        macOS 已把 ScreenStay 加入登录项，但还需要你在“系统设置 → 通用 → 登录项”中允许它运行。

        批准后，下次登录时它会自动出现在菜单栏。
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            loginItem.openLoginItemsSettings()
        }
    }

    private func showLoginError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法设置开机自启"
        alert.informativeText = """
        \(error.localizedDescription)

        如果仍然失败，请先把 ScreenStay 拖到“应用程序”文件夹，再重新打开开关。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.2.3"
        let credits = NSAttributedString(
            string: "播放音乐或视频时自动阻止屏幕休眠。\n点击菜单栏图标即可随时开关。",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ScreenStay",
            .applicationVersion: version,
            .credits: credits
        ])
    }

    @objc private func quit(_ sender: Any?) {
        power.release()
        NSApp.terminate(nil)
    }
}
