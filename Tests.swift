import Foundation

@main struct Tests {
    static func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) { assert(condition, file: file, line: line) }
    static func main() throws {
        func response(_ used: Double, minutes: Int = 10080) -> [String: Any] {
            ["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 2, "windowDurationMins": 300],
                                                    "secondary": ["usedPercent": used, "windowDurationMins": minutes, "resetsAt": 1_800_000_000]]]]
        }
        let weekly = try Usage(response(96), workspace: "test")
        check(weekly.label == "4%")
        check(weekly.reset?.timeIntervalSince1970 == 1_800_000_000)
        check(weekly.resetCreditCount == nil && weekly.resetCreditLabel == "—")
        var credits = response(96)
        credits["rateLimitResetCredits"] = ["availableCount": 3, "credits": []] as [String: Any]
        check(try Usage(credits, workspace: "test").resetCreditLabel == "3")
        credits["rateLimitResetCredits"] = ["availableCount": 0, "credits": NSNull()] as [String: Any]
        check(try Usage(credits, workspace: "test").resetCreditLabel == "0")
        for invalid: Any in [-1, 1.5, true, "3", NSNull(), Double.infinity] {
            credits["rateLimitResetCredits"] = ["availableCount": invalid]
            check(try Usage(credits, workspace: "test").resetCreditCount == nil)
        }
        credits["rateLimitResetCredits"] = NSNull()
        check(try Usage(credits, workspace: "test").resetCreditLabel == "—")
        check(try Usage(response(100), workspace: "test").label == "0%")
        check(try Usage(response(99.5), workspace: "test").label == "<1%")
        check(try Usage(response(10, minutes: 300), workspace: "test").label == "—")
        check(try Usage(["rateLimitsByLimitId": ["other": [:]], "rateLimits": ["secondary": ["usedPercent": 1, "windowDurationMins": 10080]]], workspace: "test").label == "—")
        check(try Usage(response(120), workspace: "test").label == "0%")
        check(try Usage(response(-20), workspace: "test").label == "100%")
        var wrong = response(50); wrong["accountId"] = "different"
        do { _ = try Usage(wrong, workspace: "test"); fatalError("Account mismatch accepted") } catch {}
        let planNames = ["prolite": "Pro $100", "pro": "Pro $200", "plus": "Plus", "free": "Free", "go": "Go",
                         "team": "Business", "business": "Business", "self_serve_business_prolite": "Business",
                         "self_serve_business_usage_based": "Business", "enterprise": "Enterprise", "ent26": "Enterprise",
                         "enterprise_cbp_automation": "Enterprise", "enterprise_cbp_usage_based": "Enterprise",
                         "edu": "Edu", "edu_plus": "Edu", "edu_pro": "Edu", "unknown": "Codex", "future": "Future"]
        for (plan, name) in planNames { check(planLabel(plan) == name) }

        let claims: [String: Any] = ["sub": "test-user", "email": "dummy@example.invalid", "https://api.openai.com/auth": ["chatgpt_plan_type": "prolite"]]
        let base64 = try JSONSerialization.data(withJSONObject: claims).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let auth: [String: Any] = ["tokens": ["id_token": "test.\(base64).test", "access_token": "dummy", "refresh_token": "dummy", "account_id": "test-workspace"]]
        let data = try JSONSerialization.data(withJSONObject: auth)
        let credential = try Credentials(data)
        check(credential.identity == "test-user:test-workspace")
        check(credential.plan == "prolite")
        do { _ = try Credentials(Data("{}".utf8)); fatalError("Invalid auth accepted") } catch {}

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try privateDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("auth.json")
        try privateWrite(data, to: file)
        check(try Credentials.read(directory).identity == credential.identity)
        check((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try privateWrite(Data("replacement".utf8), to: file)
        check(try Data(contentsOf: file) == Data("replacement".utf8))
        check(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["auth.json"])
        print("Core checks passed: weekly windows, reset credits, unknown data, account matching, plan names, private atomic credential writes")
    }
}
