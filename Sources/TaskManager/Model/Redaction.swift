import Darwin
import Foundation

/// 隐私模式：截图或录屏分享时，把能指向具体某个人的信息挡掉。
///
/// 只做**遮蔽和过滤**，不伪造数据 —— 界面上显示的东西要么是真的，要么明显是被隐藏了。
/// 具体做三件事：
///   1. 真实登录用户名（uid ≥ 500）显示成 `user`
///   2. 主机名显示成 `mac`
///   3. 服务页与启动项页只列 `com.apple.*` 的系统作业，第三方的不显示
///
/// 进程名不动 —— 那是这个 App 的核心内容，遮掉就没意义了。要藏某个 App，
/// 退出它再截图即可。
enum Redaction {

    /// 环境变量给自动化截图用，UserDefaults 给菜单开关用。
    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["TM_REDACT"] != nil { return true }
        return UserDefaults.standard.bool(forKey: "privacyMode")
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "privacyMode")
    }

    /// 系统账号（root、_windowserver 之类）不算隐私，照常显示。
    static let firstRealUserID: uid_t = 500

    static func userName(_ name: String, uid: uid_t) -> String {
        guard isEnabled, uid >= firstRealUserID else { return name }
        return "user"
    }

    static func hostName(_ name: String) -> String {
        isEnabled ? "mac" : name
    }

    /// 第三方 launchd 作业会暴露装了什么软件。
    static func hidesThirdPartyJob(_ label: String) -> Bool {
        isEnabled && !label.hasPrefix("com.apple.")
    }
}
