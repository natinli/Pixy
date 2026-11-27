//
//  AppDelegate+UpdateCheck.swift
//  FlowVision
//
//  应用菜单「检查更新…」：只在用户点击时调用 UpdateChecker 联网一次，结果用 NSAlert 呈现。
//  The "Check for Updates…" app-menu item: asks UpdateChecker (one network request) only when the
//  user clicks it, then shows the outcome in an NSAlert. Nothing here runs at launch or on a timer.
//

import Cocoa

extension AppDelegate {

    /// 菜单动作。检查进行中菜单项置灰（`validateMenuItem`），这里再兜底一次：不发第二个请求、不叠第二个对话框。
    /// Menu action. While a check is in flight the item is greyed out (`validateMenuItem`); the guard
    /// here is the backstop, so there is never a second request or a second dialog.
    @IBAction func checkForUpdates(_ sender: Any?) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        log("Check for updates: requested by user")
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        UpdateChecker.check(currentVersion: currentVersion, session: UpdateChecker.makeSession()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 标志保持到对话框关闭：对话框 runModal 期间即便动作被再次触发，也不会叠第二个请求或对话框
                // The flag stays set until the dialog is dismissed, so a re-trigger during runModal is ignored.
                defer { self.isCheckingForUpdates = false }
                self.presentUpdateCheckResult(result)
            }
        }
    }

    private func presentUpdateCheckResult(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        var releaseURL: URL?

        switch result {
        case .updateAvailable(let current, let latest, let url):
            log("Check for updates: \(latest) is available (running \(current))")
            releaseURL = url
            alert.alertStyle = .informational
            alert.messageText = String(
                format: NSLocalizedString("update-available-title", value: "Pixy %@ is available",
                                          comment: "检查更新：有新版。%@ 为新版本号"),
                latest.description)
            let intro = String(
                format: NSLocalizedString("update-available-message",
                                          value: "You are using version %@. If you installed Pixy with Homebrew, run this command in Terminal:",
                                          comment: "检查更新：有新版。%@ 为当前版本号，后面紧跟 brew 命令"),
                current.description)
            let hint = NSLocalizedString("update-available-hint",
                                         value: "You can also download the new version from the release page.",
                                         comment: "检查更新：有新版，提示也可从发布页下载")
            alert.informativeText = intro + "\n\n" + UpdateChecker.upgradeCommand + "\n\n" + hint
            alert.addButton(withTitle: NSLocalizedString("update-open-release-page", value: "Open Release Page",
                                                         comment: "检查更新：打开发布页按钮"))
            alert.addButton(withTitle: NSLocalizedString("update-copy-command", value: "Copy Command",
                                                         comment: "检查更新：复制 brew 命令按钮"))
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
            alert.buttons[2].keyEquivalent = "\u{1b}"

        case .upToDate(let current):
            log("Check for updates: up to date (\(current))")
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("update-up-to-date-title", value: "You’re up to date",
                                                  comment: "检查更新：已是最新版本，标题")
            alert.informativeText = String(
                format: NSLocalizedString("update-up-to-date-message", value: "Pixy %@ is the latest version.",
                                          comment: "检查更新：已是最新版本。%@ 为当前版本号"),
                current.description)
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))

        case .failed(let reason):
            // 界面上只给一条泛化提示；具体原因只进日志
            log("Check for updates: failed (\(reason))", level: .warn)
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("update-failed-title", value: "Unable to Check for Updates",
                                                  comment: "检查更新：失败（离线、超时、响应异常等），标题")
            alert.informativeText = NSLocalizedString("update-failed-message",
                                                      value: "Check your network connection and try again later.",
                                                      comment: "检查更新：失败，提示稍后重试")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        }

        // 与 showInformation / showConfirmation 一致：对话框期间暂停主窗口的键盘事件
        let storedKeyEventEnabled = getMainViewController()?.publicVar.isKeyEventEnabled
        getMainViewController()?.publicVar.isKeyEventEnabled = false
        let response = alert.runModal()
        getMainViewController()?.publicVar.isKeyEventEnabled = storedKeyEventEnabled ?? true

        guard let url = releaseURL else { return }
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(url)
        case .alertSecondButtonReturn:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(UpdateChecker.upgradeCommand, forType: .string)
        default:
            break
        }
    }
}
