import Foundation
import CoreFoundation
import Darwin

enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

struct Account: Codable {
    let id: String
    let identity: String
    var email: String
    var plan: String
}

struct Credentials {
    let data: Data
    let identity: String
    let email: String
    let plan: String
    let workspace: String

    init(_ data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let mode = root?["auth_mode"] as? String, mode != "chatgpt" {
            throw Failure.message("ChatGPT 구독으로 로그인한 계정만 지원합니다.")
        }
        guard let tokens = root?["tokens"] as? [String: Any],
              let jwt = tokens["id_token"] as? String,
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
              let workspace = tokens["account_id"] as? String, !workspace.isEmpty else {
            throw Failure.message("ChatGPT로 로그인한 Codex 계정이 필요합니다.")
        }
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Failure.message("로그인 정보 형식을 읽을 수 없습니다.") }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let decoded = Data(base64Encoded: payload),
              let claims = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw Failure.message("계정 식별 정보를 읽을 수 없습니다.")
        }
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        self.data = data; self.workspace = workspace
        identity = subject + ":" + workspace
        email = claims["email"] as? String ?? "Codex 계정"
        plan = auth?["chatgpt_plan_type"] as? String ?? "unknown"
    }

    static func read(_ home: URL) throws -> Credentials {
        try Credentials(Data(contentsOf: home.appendingPathComponent("auth.json")))
    }
}

func planLabel(_ plan: String) -> String {
    switch plan {
    case "prolite": return "Pro x5"
    case "pro": return "Pro x20"
    case "plus": return "Plus"
    case "free": return "Free"
    case "unknown": return "Codex"
    default: return plan.capitalized
    }
}

struct Usage {
    let remaining: Double?
    let reset: Date?
    let resetCreditCount: Int?
    let fetchedAt: Date

    var label: String {
        guard let r = remaining else { return "—" }
        return r > 0 && r < 1 ? "<1%" : "\(Int(r.rounded(.down)))%"
    }

    var resetCreditLabel: String {
        resetCreditCount.map(String.init) ?? "—"
    }

    init(_ result: [String: Any], workspace: String) throws {
        if let id = result["accountId"] as? String, id != workspace {
            throw Failure.message("다른 계정의 사용량 응답을 받았습니다.")
        }
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        // A present multi-bucket response must contain the general Codex bucket.
        let bucket = buckets != nil ? buckets?["codex"] as? [String: Any] : result["rateLimits"] as? [String: Any]
        let week = ["primary", "secondary"].compactMap { bucket?[$0] as? [String: Any] }
            .first { ($0["windowDurationMins"] as? Int) == 10080 }
        if let number = week?["usedPercent"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
            let used = number.doubleValue
            remaining = min(100, max(0, 100 - used))
        } else { remaining = nil }
        reset = (week?["resetsAt"] as? NSNumber).flatMap {
            $0.doubleValue.isFinite && $0.doubleValue > 0 ? Date(timeIntervalSince1970: $0.doubleValue) : nil
        }
        let credits = result["rateLimitResetCredits"] as? [String: Any]
        if let number = credits?["availableCount"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           let count = Int(exactly: number.doubleValue), count >= 0 {
            resetCreditCount = count
        } else { resetCreditCount = nil }
        fetchedAt = Date()
    }
}

func privateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o700])
}

func privateWrite(_ data: Data, to url: URL) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
    guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                        attributes: [.posixPermissions: 0o600]) else {
        throw Failure.message("계정 파일을 저장할 수 없습니다.")
    }
    defer { try? FileManager.default.removeItem(at: temporary) }
    let handle = try FileHandle(forWritingTo: temporary)
    do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
    catch { try? handle.close(); throw error }
    guard rename(temporary.path, url.path) == 0 else {
        throw Failure.message("계정 파일 교체에 실패했습니다.")
    }
}

/// One short-lived official app-server process. Never starts a model turn.
final class CodexRPC {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffer = Data()
    private var timeout: DispatchWorkItem?
    private var loginResult: [String: Any]?
    private let shutdownLock = NSLock()

    init(binary: URL, home: URL, seconds: Double = 25) throws {
        process.executableURL = binary
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"file\"", "-c", "analytics.enabled=false"]
        var env: [String: String] = [:]
        for key in ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL"] { env[key] = ProcessInfo.processInfo.environment[key] }
        env["CODEX_HOME"] = home.path
        process.environment = env
        process.currentDirectoryURL = home
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { [weak self] in self?.stop() }
        timeout = deadline
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: deadline)
        do {
            _ = try request(0, "initialize", ["clientInfo": ["name": "oh_my_usage", "version": "0.1"], "capabilities": NSNull()])
            try send(["method": "initialized"])
        } catch { stop(); throw error }
    }

    func stop() {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }
        timeout?.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            // Only this helper, never the user's app or another Codex process.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func next() throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]; buffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["method"] as? String == "account/login/completed" { loginResult = object["params"] as? [String: Any] }
                return object
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw Failure.message("Codex 응답이 없거나 시간이 초과되었습니다.") }
            buffer.append(chunk)
            guard buffer.count < 4_000_000 else { throw Failure.message("Codex 응답 크기를 초과했습니다.") }
        }
    }

    func request(_ id: Int, _ method: String, _ params: [String: Any]? = nil) throws -> [String: Any] {
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)
        while true {
            let response = try next()
            guard response["id"] as? Int == id else { continue }
            if response["error"] != nil { throw Failure.message("Codex 요청 실패: \(method). 로그인을 다시 확인하세요.") }
            return response["result"] as? [String: Any] ?? [:]
        }
    }

    func login(open: (URL) -> Void) throws {
        let result = try request(1, "account/login/start", ["type": "chatgpt"])
        guard let text = result["authUrl"] as? String, let url = URL(string: text),
              url.scheme == "https", url.host == "auth.openai.com" else {
            throw Failure.message("OpenAI 로그인 주소를 확인할 수 없습니다.")
        }
        open(url)
        while loginResult == nil { _ = try next() }
        guard loginResult?["success"] as? Bool == true else { throw Failure.message("로그인이 취소되었거나 실패했습니다.") }
    }

    func usage(workspace: String) throws -> Usage {
        try Usage(request(2, "account/rateLimits/read"), workspace: workspace)
    }
}
