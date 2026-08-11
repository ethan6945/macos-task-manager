import Foundation

/// 单个端口的探测结果。
enum WebProbeResult: Sendable, Equatable {
    case probing
    /// 拿到了 HTTP 响应
    case web(scheme: String, status: Int, title: String?)
    /// 连上了，但对方不说 HTTP
    case notWeb
    case failed(String)

    @MainActor
    var text: String {
        switch self {
        case .probing: L("检测中…")
        case let .web(scheme, status, title):
            if let title, !title.isEmpty {
                L("%@ %d · %@", scheme.uppercased(), status, title)
            } else {
                L("%@ %d", scheme.uppercased(), status)
            }
        case .notWeb: L("不是 Web 服务")
        // 固定文案能查到英文，系统给的 localizedDescription 查不到就原样显示。
        case let .failed(reason): L(reason)
        }
    }

    var isWeb: Bool {
        if case .web = self { return true }
        return false
    }
}

/// 按需探测某个本机端口是不是 Web 服务。
///
/// 只在用户点「检测」时执行，从不自动扫描 —— 主动去连别人的服务是有副作用的事，
/// 得由用户自己发起。目标固定是 127.0.0.1，不碰局域网。
enum WebProbe {

    /// 只读响应体开头这么多字节来找 `<title>`，本地服务可能返回很大的页面。
    private static let titleScanLimit = 16 * 1024

    static func probe(port: Int) async -> WebProbeResult {
        let result = await request(scheme: "http", port: port)
        // 明文请求撞上 TLS 端口时，URLSession 报的是「连接被关闭/解析失败」这一类错误。
        if case let .failed(_, code) = result, Self.looksLikeTLS(code) {
            let secure = await request(scheme: "https", port: port)
            if case let .success(value) = secure { return value }
        }
        switch result {
        case let .success(value): return value
        case let .failed(message, _): return message
        }
    }

    private enum Attempt {
        case success(WebProbeResult)
        case failed(WebProbeResult, code: Int)
    }

    private static func request(scheme: String, port: Int) async -> Attempt {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/") else {
            return .failed(.failed("URL 无效"), code: 0)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        // 用 GET 而不是 HEAD：不少本地服务对 HEAD 直接回 405。
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, isRealHTTP(http) else {
                return .success(.notWeb)
            }
            return .success(.web(scheme: scheme, status: http.statusCode, title: htmlTitle(in: data)))
        } catch let error as URLError {
            return .failed(message(for: error), code: error.errorCode)
        } catch {
            return .failed(.failed(error.localizedDescription), code: 0)
        }
    }

    /// 对方没有状态行时，URLSession 会按 HTTP/0.9 处理，把随便什么欢迎横幅都算成 200
    /// —— sshd 的 `SSH-2.0-...` 就会被误判成 Web 服务。真正的 0.9 响应没有头部，
    /// URLSession 只会补上 Date / Max-Age，所以要求至少出现一个只可能来自真实头部块的字段。
    private static let realHTTPHeaders: Set<String> = [
        "content-type", "content-length", "server", "connection",
        "transfer-encoding", "location", "set-cookie", "cache-control",
        "www-authenticate", "etag", "content-encoding",
    ]

    private static func isRealHTTP(_ response: HTTPURLResponse) -> Bool {
        response.allHeaderFields.keys.contains { key in
            realHTTPHeaders.contains("\(key)".lowercased())
        }
    }

    /// 明文打到 TLS 端口上会掉进这几个错误码，值得再用 https 试一次。
    private static func looksLikeTLS(_ code: Int) -> Bool {
        [
            URLError.secureConnectionFailed.rawValue,
            URLError.cannotParseResponse.rawValue,
            URLError.badServerResponse.rawValue,
            URLError.networkConnectionLost.rawValue,
        ].contains(code)
    }

    private static func message(for error: URLError) -> WebProbeResult {
        switch error.code {
        // 端口在监听但不说 HTTP：连上了却读不出响应。
        case .cannotParseResponse, .badServerResponse, .zeroByteResource:
            .notWeb
        case .timedOut:
            .failed("超时")
        // 端口刚刚关掉了 —— 说「不是 Web 服务」会误导
        case .cannotConnectToHost, .cannotFindHost:
            .failed("无法连接")
        // 连上了又被对方掐断，通常是它根本不说 HTTP
        case .networkConnectionLost:
            .notWeb
        case .appTransportSecurityRequiresSecureConnection:
            .failed("被 App Transport Security 拦截")
        default:
            .failed(error.localizedDescription)
        }
    }

    /// 从 HTML 开头找 `<title>`。找不到就返回 nil，不猜。
    private static func htmlTitle(in data: Data) -> String? {
        let head = data.prefix(titleScanLimit)
        guard let text = String(data: head, encoding: .utf8) else { return nil }
        guard let open = text.range(of: "<title", options: .caseInsensitive),
              let openEnd = text.range(of: ">", range: open.upperBound..<text.endIndex),
              let close = text.range(of: "</title>", options: .caseInsensitive, range: openEnd.upperBound..<text.endIndex)
        else { return nil }

        let title = text[openEnd.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !title.isEmpty else { return nil }
        return title.count > 60 ? String(title.prefix(60)) + "…" : title
    }
}
