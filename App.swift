import AppKit
import ServiceManagement

@main
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let fm = FileManager.default
    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/oh-my-usage")
    private let codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    private let queue = DispatchQueue(label: "oh-my-usage", qos: .utility)
    private var accounts: [Account] = []
    private var usage: [String: Usage] = [:]
    private var errors: [String: String] = [:]
    private var item: NSStatusItem!
    private var timer: Timer?
    private var appearanceObservation: NSKeyValueObservation?
    private var busy = false
    private var message: String?
    private var loginSession: CodexRPC?
    private var switching = false

    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
    }
    private var binary: URL? {
        let candidates = [appURL?.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"),
                          appURL?.appendingPathComponent("Contents/Resources/codex"),
                          URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
                          fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex")]
        return candidates.compactMap { $0 }.first { fm.isExecutableFile(atPath: $0.path) }
    }
    private func home(_ account: Account) -> URL { root.appendingPathComponent(account.id) }
    private var current: Credentials? { try? Credentials.read(codexHome) }
    private func save() throws { try privateWrite(JSONEncoder().encode(accounts), to: root.appendingPathComponent("accounts.json")) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let config = (try? String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)) ?? ""
            if config.range(of: #"(?m)^\s*cli_auth_credentials_store\s*=\s*["'](?:keyring|auto)["']"#, options: .regularExpression) != nil {
                throw Failure.message("이 버전은 Codex의 파일 기반 인증만 지원합니다. 현재 자격 증명 설정을 변경하지 않았습니다.")
            }
            try privateDirectory(root)
            let file = root.appendingPathComponent("accounts.json")
            if fm.fileExists(atPath: file.path) {
                accounts = try JSONDecoder().decode([Account].self, from: Data(contentsOf: file))
                guard accounts.count <= 3, accounts.allSatisfy({ UUID(uuidString: $0.id) != nil }) else {
                    throw Failure.message("저장된 계정 목록이 올바르지 않습니다.")
                }
            }
        } catch { showError(error); NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.alphaValue = 0
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.render() }
        }
        render(); refresh()
        // The first appearance is provisional; keep the button blank until the menu bar is laid out.
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] startupTimer in
            guard let self else { startupTimer.invalidate(); return }
            guard let button = self.item.button, let window = button.window, window.frame.height > 0 else { return }
            self.render()
            button.alphaValue = 1
            startupTimer.invalidate()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if switching { return .terminateCancel }
        loginSession?.stop()
        return .terminateNow
    }

    @objc private func woke() { refresh() }
    @objc private func screenChanged() { render() }
    func menuWillOpen(_ menu: NSMenu) { render() }

    private func render() {
        let active = current?.identity
        let rows = accounts.map { a -> (String, Bool) in
            let mark = errors[a.id] == nil ? "" : "!"
            return ("\(usage[a.id]?.label ?? "—")\(mark) \(planLabel(a.plan))", a.identity == active)
        }
        if rows.isEmpty {
            item.length = NSStatusItem.variableLength
            item.button?.image = nil; item.button?.title = "Codex +"
        } else {
            item.button?.title = ""
            // The status window starts at zero height; the screen inset is available immediately.
            let window = item.button?.window
            let screen = window?.screen ?? NSScreen.main
            let barHeight = max(window?.frame.height ?? 0, screen?.safeAreaInsets.top ?? 0)
            let imageHeight: CGFloat = rows.count == 3 ? min(32, max(22, barHeight - 4)) : 22
            let height: CGFloat = rows.count == 3 ? floor(imageHeight / 3) : rows.count == 2 ? 10 : 16
            let size: CGFloat = rows.count == 3 ? min(9, height - 0.5) : rows.count == 2 ? 9 : 11
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
            let width = ceil(rows.map { ($0.0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 50) + 4
            let dark = item.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let image = NSImage(size: NSSize(width: width, height: imageHeight), flipped: false) { rect in
                for (i, row) in rows.enumerated() {
                    let y = (imageHeight - CGFloat(rows.count) * height) / 2 + CGFloat(rows.count - i - 1) * height
                    if row.1 {
                        NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1).setFill()
                        NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: width - 2, height: height), xRadius: 2, yRadius: 2).fill()
                    }
                    let color: NSColor = row.1 ? .black : (dark ? .white : .black)
                    let rowFont = row.1 ? NSFont.monospacedSystemFont(ofSize: size, weight: .bold) : font
                    (row.0 as NSString).draw(at: NSPoint(x: 2, y: y), withAttributes: [.font: rowFont, .foregroundColor: color])
                }
                return true
            }
            image.isTemplate = false; item.button?.image = image
            item.length = width + 2
        }
        item.button?.toolTip = "Codex 주간 잔여량 · 클릭하여 계정 전환"
        item.button?.setAccessibilityLabel(rows.map { $0.0 + ($0.1 ? ", 메인 계정" : "") }.joined(separator: ", "))
        guard let menu = item.menu else { return }
        menu.removeAllItems()
        add(menu, message ?? (busy ? "처리 중…" : "주간 남은 사용량"), enabled: false)
        for a in accounts {
            let title = "\(usage[a.id]?.label ?? "—")  \(planLabel(a.plan))  ·  \(a.email)  ·  ↻ \(usage[a.id]?.resetCreditLabel ?? "—")"
            let entry = add(menu, title, action: #selector(selectAccount(_:)), id: a.id, enabled: !busy)
            entry.state = a.identity == active ? .on : .off
            if a.identity == active { entry.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemBlue]) }
            var detail = errors[a.id] ?? ""
            if let snapshot = usage[a.id] {
                if let reset = snapshot.reset { detail += " 초기화: " + reset.formatted(date: .abbreviated, time: .shortened) }
                detail += " (갱신 " + snapshot.fetchedAt.formatted(date: .omitted, time: .shortened) + ")"
            }
            entry.toolTip = detail.isEmpty ? "이 계정을 Codex에서 사용" : detail
        }
        if !accounts.isEmpty { menu.addItem(.separator()) }
        add(menu, "현재 Codex 계정 추가", action: #selector(importCurrent), enabled: !busy && accounts.count < 3 && active != nil && !accounts.contains { $0.identity == active })
        add(menu, "다른 계정 추가…", action: #selector(addAccount), enabled: !busy && accounts.count < 3)
        if loginSession != nil { add(menu, "로그인 취소", action: #selector(cancelLogin)) }
        let remove = add(menu, "계정 삭제", enabled: !busy && !accounts.isEmpty)
        let submenu = NSMenu()
        for a in accounts { add(submenu, a.email, action: #selector(removeAccount(_:)), id: a.id, enabled: !busy) }
        remove.submenu = submenu
        menu.addItem(.separator())
        add(menu, "새로고침", action: #selector(refreshAction), enabled: !busy)
        let loginStatus = SMAppService.mainApp.status
        let login = add(menu, loginStatus == .requiresApproval ? "로그인 시 자동 실행 (승인 필요)" : "로그인 시 자동 실행",
                        action: #selector(toggleLaunchAtLogin), enabled: !switching)
        login.state = loginStatus == .enabled ? .on : .off
        add(menu, "계정 전환 시 Codex가 재시작됩니다", enabled: false)
        add(menu, "종료", action: #selector(quit), enabled: !switching)
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: String, action: Selector? = nil, id: String? = nil, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; entry.representedObject = id; entry.isEnabled = enabled
        menu.autoenablesItems = false; menu.addItem(entry); return entry
    }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "oh-my-usage"; alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    private func finish(_ error: Error? = nil) {
        busy = false; message = nil; render()
        if let error { showError(error) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func refreshAction() { refresh() }
    @objc private func cancelLogin() { loginSession?.stop() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch { showError(error) }
        render()
    }

    @objc private func importCurrent() {
        do {
            let credentials = try Credentials.read(codexHome)
            try register(credentials, id: UUID().uuidString)
            render(); refresh()
        } catch { showError(error) }
    }
    private func register(_ credentials: Credentials, id: String) throws {
        guard accounts.count < 3 else { throw Failure.message("최대 3개 계정을 등록할 수 있습니다.") }
        guard !accounts.contains(where: { $0.identity == credentials.identity }) else { throw Failure.message("이미 등록된 계정입니다.") }
        let account = Account(id: id, identity: credentials.identity, email: credentials.email, plan: credentials.plan)
        try privateDirectory(home(account))
        try privateWrite(credentials.data, to: home(account).appendingPathComponent("auth.json"))
        accounts.append(account)
        do { try save() } catch { accounts.removeLast(); throw error }
    }

    @objc private func addAccount() {
        guard !busy, accounts.count < 3 else { return }
        guard let binary else { showError(Failure.message("Codex 앱 또는 CLI를 찾을 수 없습니다.")); return }
        busy = true; message = "브라우저에서 다른 계정으로 로그인하세요"; render()
        let id = UUID().uuidString, directory = root.appendingPathComponent(UUID().uuidString)
        queue.async {
            do {
                try privateDirectory(directory)
                defer { try? self.fm.removeItem(at: directory) }
                let rpc = try CodexRPC(binary: binary, home: directory, seconds: 180)
                defer { rpc.stop() }
                DispatchQueue.main.async { self.loginSession = rpc; self.render() }
                try rpc.login { url in DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
                let credentials = try Credentials.read(directory)
                DispatchQueue.main.async {
                    self.loginSession = nil
                    do { try self.register(credentials, id: id); self.finish(); self.refresh() }
                    catch { self.finish(error) }
                }
            } catch { DispatchQueue.main.async { self.loginSession = nil; self.finish(error) } }
        }
    }

    @objc private func removeAccount(_ sender: NSMenuItem) {
        guard !busy, let id = sender.representedObject as? String, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let removed = accounts.remove(at: index)
        do { try save() }
        catch { accounts.insert(removed, at: index); showError(error); render(); return }
        do {
            try fm.removeItem(at: home(removed))
            usage[id] = nil; errors[id] = nil; render()
        } catch { showError(error); render() }
        // Removing a saved account never logs the desktop app out.
    }

    private func refresh() {
        guard !busy, !accounts.isEmpty else { return }
        guard let binary else { message = "Codex 앱 또는 CLI를 찾을 수 없습니다"; render(); return }
        busy = true; render()
        let snapshot = accounts
        queue.async {
            var updates: [String: Usage] = [:], failures: [String: String] = [:], plans: [String: String] = [:]
            for a in snapshot {
                do {
                    let active = try? Credentials.read(self.codexHome)
                    let directory = active?.identity == a.identity ? self.codexHome : self.home(a)
                    let before = try Credentials.read(directory)
                    guard before.identity == a.identity else { throw Failure.message("계정이 변경되었습니다. 다시 조회하세요.") }
                    let rpc = try CodexRPC(binary: binary, home: directory)
                    defer { rpc.stop() }
                    let result = try rpc.usage(workspace: before.workspace)
                    let after = try Credentials.read(directory)
                    guard after.identity == a.identity else { throw Failure.message("조회 중 계정이 변경되었습니다.") }
                    updates[a.id] = result; plans[a.id] = after.plan
                } catch { failures[a.id] = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self.usage.merge(updates) { _, new in new }; self.errors = failures
                for i in self.accounts.indices { if let p = plans[self.accounts[i].id] { self.accounts[i].plan = p } }
                do { try self.save(); self.finish() } catch { self.finish(error) }
            }
        }
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard !busy, let id = sender.representedObject as? String,
              let account = accounts.first(where: { $0.id == id }), account.identity != current?.identity else { return }
        guard let appURL, let binary else { showError(Failure.message("설치된 Codex 앱을 찾을 수 없습니다.")); return }
        busy = true; switching = true; message = "계정 전환 준비 중…"; render()
        queue.async {
            do {
                let target = try Credentials.read(self.home(account))
                guard target.identity == account.identity else { throw Failure.message("저장된 계정이 일치하지 않습니다.") }
                let rpc = try CodexRPC(binary: binary, home: self.home(account))
                defer { rpc.stop() }
                _ = try rpc.usage(workspace: target.workspace)
                let fresh = try Credentials.read(self.home(account))
                guard fresh.identity == account.identity else { throw Failure.message("전환 준비 중 계정이 변경되었습니다.") }
                DispatchQueue.main.async { self.restartCodex(using: fresh, appURL: appURL) }
            } catch { DispatchQueue.main.async { self.switching = false; self.finish(error) } }
        }
    }

    private func restartCodex(using target: Credentials, appURL: URL) {
        Task { @MainActor in
            var backup: Data?
            var replaced = false
            do {
                message = "Codex 정상 종료를 기다리는 중…"; render()
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
                for app in running where !app.terminate() { throw Failure.message("Codex가 종료를 거부했습니다. 작업을 마친 뒤 다시 전환하세요.") }
                let deadline = Date().addingTimeInterval(30)
                while running.contains(where: { !$0.isTerminated }) {
                    guard Date() < deadline else { throw Failure.message("Codex 종료가 완료되지 않아 계정을 바꾸지 않았습니다.") }
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                // Read AFTER termination to preserve any last token refresh.
                let authFile = codexHome.appendingPathComponent("auth.json")
                backup = try? Data(contentsOf: authFile)
                if let backup {
                    try privateWrite(backup, to: root.appendingPathComponent("switch-backup.json"))
                    if let old = try? Credentials(backup), let saved = accounts.first(where: { $0.identity == old.identity }) {
                        try privateWrite(old.data, to: home(saved).appendingPathComponent("auth.json"))
                    }
                }
                try privateDirectory(codexHome)
                try privateWrite(target.data, to: authFile); replaced = true
                message = "Codex 다시 여는 중…"; render()
                let configuration = NSWorkspace.OpenConfiguration()
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                try await Task.sleep(nanoseconds: 2_000_000_000)
                guard current?.identity == target.identity else { throw Failure.message("Codex가 다른 계정 정보를 복원했습니다. 전환을 확인할 수 없습니다.") }
                try? fm.removeItem(at: root.appendingPathComponent("switch-backup.json"))
                switching = false; finish(); refresh()
            } catch {
                if replaced {
                    // Never roll credentials back underneath a running desktop process.
                    let reopened = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
                    if reopened.isEmpty {
                        do {
                            let file = codexHome.appendingPathComponent("auth.json")
                            if let backup { try privateWrite(backup, to: file) }
                            else { try fm.removeItem(at: file) }
                            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
                        } catch { switching = false; finish(Failure.message("계정 복구에 실패했습니다. switch-backup.json을 보관했습니다.")); return }
                    }
                }
                switching = false; finish(error)
            }
        }
    }
}
