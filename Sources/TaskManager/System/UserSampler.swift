import Darwin
import Foundation

struct LoginSession: Sendable, Identifiable {
    var id: String { "\(user)-\(line)-\(loginTime.timeIntervalSince1970)" }
    var user: String
    var line: String          // console / ttys000 …
    var host: String
    var pid: pid_t
    var loginTime: Date

    @MainActor
    var kind: String {
        if line == "console" { return L("本机登录") }
        if line.hasPrefix("tty") { return host.isEmpty ? L("终端") : L("远程（%@）", host) }
        return line
    }
}

/// 用户页的数据源：`utmpx` 里的登录会话。
enum UserSampler {

    static func sessions() -> [LoginSession] {
        var result: [LoginSession] = []
        setutxent()
        defer { endutxent() }

        while let entry = getutxent() {
            let record = entry.pointee
            guard record.ut_type == Int16(USER_PROCESS) else { continue }
            let user = String(cTuple: record.ut_user)
            guard !user.isEmpty else { continue }
            result.append(LoginSession(
                user: Redaction.userName(user, uid: Redaction.firstRealUserID),
                line: String(cTuple: record.ut_line),
                host: String(cTuple: record.ut_host),
                pid: record.ut_pid,
                loginTime: Date(timeIntervalSince1970: Double(record.ut_tv.tv_sec))
            ))
        }
        return result.sorted { $0.loginTime < $1.loginTime }
    }
}
